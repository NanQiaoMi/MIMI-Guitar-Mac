#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_ROOT="$(cd "$NATIVE_ROOT/.." && pwd)"
BUILD_SCRIPT="$SCRIPT_DIR/build_macos_app.sh"
VERIFY_SCRIPT="$SCRIPT_DIR/verify_macos_resources.py"
OUTPUT_ROOT_DEFAULT="$(cd "$PROJECT_ROOT/../.." && pwd)/Native-Mac-0.2.4"
OUTPUT_ROOT="${MIMI_MAC_OUTPUT_DIR:-$OUTPUT_ROOT_DEFAULT}"
APP_NAME="MIMI Guitar.app"
EXECUTABLE_NAME="MIMIGuitarMac"
MINIMUM_MACOS="13.0"
APP_VERSION="${MIMI_MAC_VERSION:-0.2.4}"
BUILD_NUMBER="${MIMI_MAC_BUILD_NUMBER:-$(date -u +%Y%m%d%H%M)}"
MAKE_DMG=1
ALLOW_REPLACE=0

usage() {
  cat <<'EOF'
Usage: tools/build_macos_universal_app.sh [--no-dmg] [--replace]

Build x86_64 and arm64 apps with the explicit local macOS SDK, combine the
executables into a Universal 2 app, verify its ad-hoc signature and optionally
create and verify a compressed DMG.

Options:
  --no-dmg   Build and verify the .app only.
  --replace  Replace only this script's named .app and DMG outputs if present.
  --help     Show this help.

Environment:
  MIMI_MAC_SDK          SDK directory; defaults to the local Command Line Tools SDK.
  MIMI_MAC_VERSION      CFBundleShortVersionString; defaults to 0.2.4.
  MIMI_MAC_BUILD_NUMBER CFBundleVersion; defaults to the current UTC minute.
  MIMI_MAC_OUTPUT_DIR   Output directory; defaults to outputs/Native-Mac-0.2.4.
EOF
}

while (($# > 0)); do
  case "$1" in
    --no-dmg) MAKE_DMG=0 ;;
    --replace) ALLOW_REPLACE=1 ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

SDK_DEFAULT="/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk"
SDK_PATH="${MIMI_MAC_SDK:-$SDK_DEFAULT}"
if [[ ! -d "$SDK_PATH" ]]; then
  printf 'macOS SDK not found at: %s\n' "$SDK_PATH" >&2
  exit 1
fi
for tool in bash ditto swiftc lipo codesign plutil shasum find xargs sqlite3 python3; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    printf 'Required build tool is missing: %s\n' "$tool" >&2
    exit 1
  fi
done
if ((MAKE_DMG)) && ! command -v hdiutil >/dev/null 2>&1; then
  printf 'hdiutil is required to create a DMG on this host.\n' >&2
  exit 1
fi

APP_OUTPUT="$OUTPUT_ROOT/$APP_NAME"
DMG_OUTPUT="$OUTPUT_ROOT/MIMI-Guitar-macOS-universal2.dmg"
if [[ -e "$APP_OUTPUT" || -e "$DMG_OUTPUT" ]]; then
  if ((ALLOW_REPLACE == 0)); then
    printf 'Package output already exists. Use --replace to replace only the named .app/DMG outputs.\n' >&2
    exit 1
  fi
fi

mkdir -p "$NATIVE_ROOT/.build"
WORK_ROOT="$(mktemp -d "$NATIVE_ROOT/.build/universal2.XXXXXX")"
trap 'rm -rf "$WORK_ROOT"' EXIT
X86_OUTPUT="$WORK_ROOT/x86_64"
ARM_OUTPUT="$WORK_ROOT/arm64"
ASSEMBLY="$WORK_ROOT/assembly"
mkdir -p "$ASSEMBLY"

printf 'Building x86_64 app slice\n'
MIMI_MAC_SDK="$SDK_PATH" MIMI_MAC_ARCH=x86_64 MIMI_MAC_VERSION="$APP_VERSION" \
  MIMI_MAC_BUILD_NUMBER="$BUILD_NUMBER" MIMI_MAC_OUTPUT_DIR="$X86_OUTPUT" \
  bash "$BUILD_SCRIPT" --no-dmg
printf 'Building arm64 app slice\n'
MIMI_MAC_SDK="$SDK_PATH" MIMI_MAC_ARCH=arm64 MIMI_MAC_VERSION="$APP_VERSION" \
  MIMI_MAC_BUILD_NUMBER="$BUILD_NUMBER" MIMI_MAC_OUTPUT_DIR="$ARM_OUTPUT" \
  bash "$BUILD_SCRIPT" --no-dmg

X86_APP="$X86_OUTPUT/$APP_NAME"
ARM_APP="$ARM_OUTPUT/$APP_NAME"
ASSEMBLED_APP="$ASSEMBLY/$APP_NAME"
ditto "$X86_APP" "$ASSEMBLED_APP"
X86_EXECUTABLE="$X86_APP/Contents/MacOS/$EXECUTABLE_NAME"
ARM_EXECUTABLE="$ARM_APP/Contents/MacOS/$EXECUTABLE_NAME"
FAT_EXECUTABLE="$ASSEMBLED_APP/Contents/MacOS/$EXECUTABLE_NAME"
lipo -create "$X86_EXECUTABLE" "$ARM_EXECUTABLE" -output "$FAT_EXECUTABLE.universal2"
mv "$FAT_EXECUTABLE.universal2" "$FAT_EXECUTABLE"
lipo "$FAT_EXECUTABLE" -verify_arch x86_64 arm64
ARCHITECTURES="$(lipo "$FAT_EXECUTABLE" -archs)"
if [[ "$ARCHITECTURES" != *x86_64* || "$ARCHITECTURES" != *arm64* ]]; then
  printf 'Universal executable is missing an architecture slice: %s\n' "$ARCHITECTURES" >&2
  exit 1
fi

printf 'Verifying resource tree after universal assembly\n'
python3 "$VERIFY_SCRIPT" compare-tree \
  "$X86_APP/Contents/Resources" "$ASSEMBLED_APP/Contents/Resources" \
  "x86_64 to universal2 bundle resources"

python3 - "$ASSEMBLED_APP/Contents/Resources/BUILD-MANIFEST.txt" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
manifest = path.read_text()
old_arch = "Architecture: x86_64\n"
old_target = "Target: x86_64-apple-macosx13.0\n"
if manifest.count(old_arch) != 1 or manifest.count(old_target) != 1:
    raise SystemExit("could not locate the single-architecture fields in the embedded manifest")
manifest = manifest.replace(old_arch, "Architecture: universal2 (x86_64, arm64)\n", 1)
manifest = manifest.replace(old_target, "Targets: x86_64-apple-macosx13.0, arm64-apple-macosx13.0\n", 1)
path.write_text(manifest)
PY

printf 'Signing Universal 2 app with an ad-hoc signature\n'
codesign --force --deep --sign - "$ASSEMBLED_APP"
codesign --verify --deep --strict --verbose=2 "$ASSEMBLED_APP"

DMG_TEMP=""
if ((MAKE_DMG)); then
  DMG_STAGE="$WORK_ROOT/dmg-stage"
  mkdir -p "$DMG_STAGE"
  ditto "$ASSEMBLED_APP" "$DMG_STAGE/$APP_NAME"
  ln -s /Applications "$DMG_STAGE/Applications"
  DMG_TEMP="$WORK_ROOT/MIMI-Guitar-macOS-universal2.dmg"
  hdiutil create -volname "MIMI Guitar" -srcfolder "$DMG_STAGE" -ov -format UDZO "$DMG_TEMP"
  hdiutil verify "$DMG_TEMP"
fi

mkdir -p "$OUTPUT_ROOT"
if ((ALLOW_REPLACE)); then
  rm -rf "$APP_OUTPUT"
  if ((MAKE_DMG)); then rm -f "$DMG_OUTPUT"; fi
fi
ditto "$ASSEMBLED_APP" "$APP_OUTPUT"
codesign --verify --deep --strict --verbose=2 "$APP_OUTPUT"
python3 "$VERIFY_SCRIPT" compare-tree \
  "$ASSEMBLED_APP/Contents/Resources" "$APP_OUTPUT/Contents/Resources" \
  "universal2 assembly to final app resources"
if ((MAKE_DMG)); then mv "$DMG_TEMP" "$DMG_OUTPUT"; fi

APP_BYTES="$(du -sk "$APP_OUTPUT" | awk '{print $1 * 1024}')"
SIGNED_EXECUTABLE_SHA256="$(shasum -a 256 "$APP_OUTPUT/Contents/MacOS/$EXECUTABLE_NAME" | awk '{print $1}')"
X86_EXECUTABLE_SHA256="$(shasum -a 256 "$X86_EXECUTABLE" | awk '{print $1}')"
ARM_EXECUTABLE_SHA256="$(shasum -a 256 "$ARM_EXECUTABLE" | awk '{print $1}')"
INFO_PLIST_SHA256="$(shasum -a 256 "$APP_OUTPUT/Contents/Info.plist" | awk '{print $1}')"
SIGNATURE_IDENTITY="$(codesign -dv --verbose=2 "$APP_OUTPUT" 2>&1 | sed -n 's/^Signature=//p' | head -n 1)"
if ((MAKE_DMG)); then
  DMG_BYTES="$(stat -f '%z' "$DMG_OUTPUT")"
  DMG_SHA256="$(shasum -a 256 "$DMG_OUTPUT" | awk '{print $1}')"
else
  DMG_BYTES="not built"
  DMG_SHA256="not built"
  DMG_OUTPUT="not built"
fi
{
  cat "$APP_OUTPUT/Contents/Resources/BUILD-MANIFEST.txt"
  printf '\nUniversal 2 package outputs:\n'
  printf 'Architectures: %s\n' "$ARCHITECTURES"
  printf 'x86_64 source executable SHA-256: %s\n' "$X86_EXECUTABLE_SHA256"
  printf 'arm64 source executable SHA-256: %s\n' "$ARM_EXECUTABLE_SHA256"
  printf 'Universal executable SHA-256: %s\n' "$SIGNED_EXECUTABLE_SHA256"
  printf 'Info.plist SHA-256: %s\n' "$INFO_PLIST_SHA256"
  printf 'App: %s\n' "$APP_OUTPUT"
  printf 'App bytes (du -sk estimate): %s\n' "$APP_BYTES"
  printf 'Code signature identity: %s\n' "${SIGNATURE_IDENTITY:-unknown}"
  printf 'DMG: %s\n' "$DMG_OUTPUT"
  printf 'DMG bytes: %s\n' "$DMG_BYTES"
  printf 'DMG SHA-256: %s\n' "$DMG_SHA256"
  printf 'Codesign verification: passed\n'
  printf 'Notarization: not performed\n'
} > "$OUTPUT_ROOT/BUILD-MANIFEST.txt"

printf 'Universal 2 build complete.\n'
printf 'App: %s\n' "$APP_OUTPUT"
if ((MAKE_DMG)); then printf 'DMG: %s\n' "$DMG_OUTPUT"; fi
printf 'Manifest: %s/BUILD-MANIFEST.txt\n' "$OUTPUT_ROOT"
