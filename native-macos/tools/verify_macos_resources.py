#!/usr/bin/env python3
"""Verify copied app resources and emit a per-file size/SHA-256 manifest."""

from __future__ import annotations

import hashlib
import os
import sys
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import unquote, urlsplit


def file_record(path: Path) -> tuple[int, str]:
    digest = hashlib.sha256()
    size = 0
    with path.open("rb") as source:
        while chunk := source.read(1024 * 1024):
            digest.update(chunk)
            size += len(chunk)
    return size, digest.hexdigest()


def inventory(root: Path) -> dict[str, tuple[int, str]]:
    result: dict[str, tuple[int, str]] = {}
    for directory, subdirectories, filenames in os.walk(root):
        subdirectories.sort()
        filenames.sort()
        for filename in filenames:
            path = Path(directory) / filename
            if path.is_file():
                result[path.relative_to(root).as_posix()] = file_record(path)
    return result


def verify_file(source: Path, target: Path, label: str) -> None:
    if not source.is_file() or not target.is_file():
        raise SystemExit(f"missing file in resource copy ({label}): {source} -> {target}")
    if file_record(source) != file_record(target):
        raise SystemExit(f"resource copy differs ({label}): {source} -> {target}")


def verify_tree(source: Path, target: Path, label: str) -> None:
    source_records = inventory(source)
    target_records = inventory(target)
    if source_records != target_records:
        missing = sorted(set(source_records) - set(target_records))
        extra = sorted(set(target_records) - set(source_records))
        changed = sorted(key for key in source_records.keys() & target_records.keys() if source_records[key] != target_records[key])
        details = []
        if missing:
            details.append("missing=" + ",".join(missing[:8]))
        if extra:
            details.append("extra=" + ",".join(extra[:8]))
        if changed:
            details.append("changed=" + ",".join(changed[:8]))
        raise SystemExit(f"resource tree differs ({label}): " + "; ".join(details))
    size = sum(record[0] for record in source_records.values())
    print(f"Verified {label}: {len(source_records)} files, {size} bytes")


def write_manifest(root: Path) -> None:
    records = inventory(root)
    for relative in sorted(records):
        size, digest = records[relative]
        print(f"{digest}\t{size}\t{relative}")


class EntryReferences(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.references: list[str] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        values = dict(attrs)
        if tag == "script" and values.get("src"):
            self.references.append(values["src"] or "")
        if tag == "link" and "stylesheet" in (values.get("rel") or "").split() and values.get("href"):
            self.references.append(values["href"] or "")


def verify_runtime_entrypoints(player_root: Path, studio_root: Path) -> None:
    checked = 0
    for label, root in (("Player", player_root), ("Studio", studio_root)):
        parser = EntryReferences()
        parser.feed((root / "index.html").read_text(encoding="utf-8"))
        for reference in parser.references:
            parsed = urlsplit(reference)
            relative = Path(unquote(parsed.path).lstrip("/"))
            if parsed.scheme or parsed.netloc or parsed.query or parsed.fragment or ".." in relative.parts:
                raise SystemExit(f"unsupported runtime entry dependency ({label}): {reference}")
            # Studio uses the same local AlphaTab runtime and SoundFont preview code.
            shared_player_scripts = {"/alphaTab.js", "/ar.es.js", "/guitar-audio.bundle.js"}
            dependency_root = player_root if label == "Studio" and parsed.path in shared_player_scripts else root
            dependency = (dependency_root / relative).resolve()
            if not dependency.is_relative_to(dependency_root.resolve()) or not dependency.is_file():
                raise SystemExit(f"missing runtime entry dependency ({label}): {reference}")
            checked += 1
    print(f"Verified runtime HTML entry dependencies: {checked} local scripts/styles")


def main() -> None:
    if len(sys.argv) < 3:
        raise SystemExit("usage: verify_macos_resources.py compare-file SRC DST LABEL | compare-tree SRC DST LABEL | runtime-entrypoints PLAYER STUDIO | manifest ROOT")
    action = sys.argv[1]
    if action == "compare-file" and len(sys.argv) == 5:
        verify_file(Path(sys.argv[2]), Path(sys.argv[3]), sys.argv[4])
    elif action == "compare-tree" and len(sys.argv) == 5:
        verify_tree(Path(sys.argv[2]), Path(sys.argv[3]), sys.argv[4])
    elif action == "manifest" and len(sys.argv) == 3:
        write_manifest(Path(sys.argv[2]))
    elif action == "runtime-entrypoints" and len(sys.argv) == 4:
        verify_runtime_entrypoints(Path(sys.argv[2]), Path(sys.argv[3]))
    else:
        raise SystemExit("invalid verify_macos_resources.py arguments")


if __name__ == "__main__":
    main()
