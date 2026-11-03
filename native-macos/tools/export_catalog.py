#!/usr/bin/env python3
"""Export only the public Tab and Article catalog rows from the local dev DB.

The exporter uses psql inside the already-running development container and
writes a standalone SQLite file. It never updates or restores PostgreSQL.
"""

from __future__ import annotations

import argparse
import csv
from datetime import datetime, timezone
import hashlib
import io
import json
import os
from pathlib import Path
import sqlite3
import subprocess
import sys
import tempfile
from urllib.parse import unquote


DEFAULT_CONTAINER = "mimi-guitar-mac-dev-db"
PROJECT_ROOT = Path(__file__).resolve().parents[2]
SNAPSHOT_SQL = r'''BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY;
COPY (
  SELECT source_kind, row_payload
  FROM (
    SELECT 'tab'::text AS source_kind, row_to_json(row)::text AS row_payload
    FROM (
      SELECT id, title, artist, category, difficulty, style, "key" AS key,
             tuning, "sheetForm" AS sheet_form, bpm, "timeSig" AS time_sig,
             capo, "tuningText" AS tuning_text, heat, uploader,
             "publishDate" AS publish_date, format, "scoreUrl" AS score_url,
             "xheUrl" AS xhe_url, "screenshotUrl" AS screenshot_url,
             description, tags, "createdAt" AS created_at, "updatedAt" AS updated_at
      FROM "Tab"
    ) AS row
    UNION ALL
    SELECT 'article'::text AS source_kind, row_to_json(row)::text AS row_payload
    FROM (
      SELECT id, title, content, category, views, "createdAt" AS created_at
      FROM "Article"
    ) AS row
  ) AS rows
) TO STDOUT WITH (FORMAT CSV);
COMMIT;'''


def read_catalog_snapshot(container: str) -> tuple[list[dict[str, object]], list[dict[str, object]]]:
    command = [
        "docker", "exec", "-i", container, "sh", "-c",
        'exec psql -X -q -A -t -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB"',
    ]
    process = subprocess.run(command, input=SNAPSHOT_SQL + "\n", text=True, capture_output=True, check=False)
    if process.returncode != 0:
        detail = process.stderr.strip().splitlines()
        summary = detail[-1] if detail else f"docker/psql exited with {process.returncode}"
        raise RuntimeError(f"Could not read catalog rows from the selected container: {summary}")

    tabs: list[dict[str, object]] = []
    articles: list[dict[str, object]] = []
    for cells in csv.reader(io.StringIO(process.stdout)):
        if not cells:
            continue
        if len(cells) != 2 or cells[0] not in {"tab", "article"}:
            raise RuntimeError("psql returned a catalog row with an unexpected CSV shape")
        try:
            row = json.loads(cells[1])
        except (IndexError, json.JSONDecodeError) as exc:
            raise RuntimeError("psql returned a row that was not valid CSV JSON") from exc
        if not isinstance(row, dict):
            raise RuntimeError("psql returned a catalog row with an unexpected shape")
        (tabs if cells[0] == "tab" else articles).append(row)
    return tabs, articles


def create_database(
    path: Path,
    tabs: list[dict[str, object]],
    articles: list[dict[str, object]],
    source_revision: str,
    exported_at_utc: str,
    resource_summary: dict[str, int],
) -> tuple[int, int]:
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(prefix=".catalog-", suffix=".sqlite.tmp", dir=path.parent)
    os.close(descriptor)
    temporary_path = Path(temporary_name)
    try:
        os.chmod(temporary_path, 0o644)
        database = sqlite3.connect(temporary_path)
        try:
            database.executescript(
                """
                PRAGMA journal_mode = DELETE;
                PRAGMA synchronous = FULL;
                BEGIN IMMEDIATE;
                CREATE TABLE catalog (
                    id TEXT PRIMARY KEY NOT NULL,
                    title TEXT NOT NULL,
                    artist TEXT,
                    category TEXT NOT NULL DEFAULT 'guitar',
                    difficulty INTEGER NOT NULL DEFAULT 0,
                    style INTEGER,
                    key TEXT,
                    tuning TEXT,
                    sheet_form INTEGER NOT NULL DEFAULT 0,
                    bpm INTEGER,
                    time_sig TEXT,
                    capo INTEGER NOT NULL DEFAULT 0,
                    tuning_text TEXT,
                    heat INTEGER NOT NULL DEFAULT 0,
                    uploader TEXT,
                    publish_date TEXT,
                    format TEXT NOT NULL DEFAULT 'gp',
                    score_url TEXT,
                    xhe_url TEXT,
                    screenshot_url TEXT,
                    description TEXT,
                    tags TEXT NOT NULL DEFAULT '[]',
                    created_at TEXT,
                    updated_at TEXT
                );
                CREATE INDEX catalog_heat_idx ON catalog(heat DESC, title COLLATE NOCASE);
                CREATE INDEX catalog_title_idx ON catalog(title COLLATE NOCASE, id);
                CREATE INDEX catalog_category_heat_idx ON catalog(category, heat DESC);
                CREATE INDEX catalog_artist_idx ON catalog(artist COLLATE NOCASE);
                CREATE INDEX catalog_difficulty_idx ON catalog(difficulty DESC, heat DESC);
                CREATE INDEX catalog_publish_date_idx ON catalog(publish_date DESC, title COLLATE NOCASE);
                CREATE INDEX catalog_style_idx ON catalog(style);
                CREATE INDEX catalog_key_idx ON catalog(key);
                CREATE INDEX catalog_tuning_idx ON catalog(tuning);
                CREATE INDEX catalog_sheet_form_idx ON catalog(sheet_form);
                CREATE TABLE articles (
                    id TEXT PRIMARY KEY NOT NULL,
                    title TEXT NOT NULL,
                    content TEXT NOT NULL,
                    category TEXT,
                    views INTEGER NOT NULL DEFAULT 0,
                    created_at TEXT
                );
                CREATE TABLE export_metadata (
                    key TEXT PRIMARY KEY NOT NULL,
                    value TEXT NOT NULL
                );
                """
            )
            database.executemany(
                """INSERT INTO catalog(
                    id, title, artist, category, difficulty, style, key, tuning,
                    sheet_form, bpm, time_sig, capo, tuning_text, heat, uploader,
                    publish_date, format, score_url, xhe_url, screenshot_url,
                    description, tags, created_at, updated_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
                [
                    (
                        str(row.get("id") or ""),
                        str(row.get("title") or ""),
                        row.get("artist"),
                        str(row.get("category") or "guitar"),
                        int(row.get("difficulty") or 0),
                        row.get("style"),
                        row.get("key"),
                        row.get("tuning"),
                        int(row.get("sheet_form") or 0),
                        row.get("bpm"),
                        row.get("time_sig"),
                        int(row.get("capo") or 0),
                        row.get("tuning_text"),
                        int(row.get("heat") or 0),
                        row.get("uploader"),
                        row.get("publish_date"),
                        str(row.get("format") or "gp"),
                        row.get("score_url"),
                        row.get("xhe_url"),
                        row.get("screenshot_url"),
                        row.get("description"),
                        str(row.get("tags") or "[]"),
                        row.get("created_at"),
                        row.get("updated_at"),
                    )
                    for row in sorted(tabs, key=lambda item: str(item.get("id") or ""))
                ],
            )
            database.executemany(
                "INSERT INTO articles(id, title, content, category, views, created_at) VALUES (?, ?, ?, ?, ?, ?)",
                [
                    (
                        str(row.get("id") or ""),
                        str(row.get("title") or ""),
                        str(row.get("content") or ""),
                        row.get("category"),
                        int(row.get("views") or 0),
                        row.get("created_at"),
                    )
                    for row in sorted(articles, key=lambda item: str(item.get("id") or ""))
                ],
            )
            tab_digest = digest_rows(tabs)
            article_digest = digest_rows(articles)
            database.executemany(
                "INSERT INTO export_metadata(key, value) VALUES (?, ?)",
                [
                    ("schema_version", "2"),
                    ("exported_at_utc", exported_at_utc),
                    ("source_revision", source_revision),
                    ("tab_count", str(len(tabs))),
                    ("article_count", str(len(articles))),
                    ("tab_rows_sha256", tab_digest),
                    ("article_rows_sha256", article_digest),
                    *[(key, str(value)) for key, value in resource_summary.items()],
                ],
            )
            database.commit()
            tab_count = int(database.execute("SELECT COUNT(*) FROM catalog").fetchone()[0])
            article_count = int(database.execute("SELECT COUNT(*) FROM articles").fetchone()[0])
        except Exception:
            database.rollback()
            raise
        finally:
            database.close()
        temporary_path.replace(path)
        return tab_count, article_count
    finally:
        temporary_path.unlink(missing_ok=True)


def digest_rows(rows: list[dict[str, object]]) -> str:
    digest = hashlib.sha256()
    for row in sorted(rows, key=lambda item: str(item.get("id") or "")):
        canonical = json.dumps(row, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
        digest.update(canonical.encode("utf-8"))
        digest.update(b"\n")
    return digest.hexdigest()


def read_source_revision(project_root: Path) -> str:
    revision_path = project_root / "source-revision.json"
    try:
        revision = json.loads(revision_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return "unknown"
    baseline = revision.get("applicationBaseline")
    handoff = revision.get("handoffSourceCommit")
    identifiers = [
        f"applicationBaseline:{baseline}" if isinstance(baseline, str) and baseline else "",
        f"handoffSourceCommit:{handoff}" if isinstance(handoff, str) and handoff else "",
    ]
    result = ";".join(item for item in identifiers if item)
    return result or "unknown"


def check_resource_references(tabs: list[dict[str, object]], project_root: Path) -> dict[str, int]:
    public_root = (project_root / "public").resolve()
    allowed_roots = {
        name: (public_root / name).resolve()
        for name in ("storage", "soundfonts")
    }
    result = {
        "resource_refs_checked": 0,
        "resource_refs_missing": 0,
        "resource_refs_invalid": 0,
    }
    for field in ("score_url", "xhe_url", "screenshot_url"):
        result[f"resource_{field}_count"] = 0
        result[f"resource_{field}_missing"] = 0
        result[f"resource_{field}_invalid"] = 0

    for tab in tabs:
        for field in ("score_url", "xhe_url", "screenshot_url"):
            reference = tab.get(field)
            if not isinstance(reference, str) or not reference:
                continue
            result["resource_refs_checked"] += 1
            result[f"resource_{field}_count"] += 1
            try:
                decoded = unquote(reference, errors="strict")
                if "\0" in decoded or "\\" in decoded or "?" in decoded or "#" in decoded:
                    raise ValueError("unsupported path character")
                relative = decoded[1:] if decoded.startswith("/") else decoded
                parts = relative.split("/")
                if len(parts) < 2 or parts[0] not in allowed_roots or any(part in {"", ".", ".."} for part in parts):
                    raise ValueError("reference is outside the resource whitelist")
                allowed_root = allowed_roots[parts[0]]
                if os.path.commonpath((str(allowed_root), str(public_root))) != str(public_root):
                    raise ValueError("resource whitelist root escapes public content")
                candidate = (public_root / Path(*parts)).resolve(strict=False)
                if os.path.commonpath((str(candidate), str(allowed_root))) != str(allowed_root):
                    raise ValueError("reference resolves outside the resource whitelist")
            except (UnicodeDecodeError, ValueError, OSError):
                result["resource_refs_invalid"] += 1
                result[f"resource_{field}_invalid"] += 1
                continue
            if not candidate.is_file():
                result["resource_refs_missing"] += 1
                result[f"resource_{field}_missing"] += 1
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--container",
        default=DEFAULT_CONTAINER,
        help=f"running local PostgreSQL container (default: {DEFAULT_CONTAINER})",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=Path(__file__).resolve().parents[1] / "Data" / "catalog.sqlite",
        help="SQLite output path (default: Data/catalog.sqlite)",
    )
    args = parser.parse_args()

    try:
        tabs, articles = read_catalog_snapshot(args.container)
        exported_at_utc = datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")
        source_revision = read_source_revision(PROJECT_ROOT)
        resource_summary = check_resource_references(tabs, PROJECT_ROOT)
        tab_count, article_count = create_database(
            args.output.resolve(), tabs, articles, source_revision, exported_at_utc, resource_summary
        )
    except (OSError, RuntimeError, sqlite3.Error) as exc:
        print(f"Catalog export failed: {exc}", file=sys.stderr)
        return 1

    print(f"Exported {tab_count} catalog tabs and {article_count} articles to {args.output.resolve()}")
    print("PostgreSQL was read in one REPEATABLE READ, READ ONLY snapshot; no users, favorites, uploads, or browser data were exported.")
    print(
        f"Resource references checked: {resource_summary['resource_refs_checked']}; "
        f"missing: {resource_summary['resource_refs_missing']}; "
        f"invalid: {resource_summary['resource_refs_invalid']}"
    )
    print(f"Source revision: {source_revision}; export time UTC: {exported_at_utc}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
