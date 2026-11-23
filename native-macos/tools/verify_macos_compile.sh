#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SDK_DEFAULT="/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk"
MINIMUM_MACOS="13.0"
ARCH_MODE="universal"
BUILD_JOBS="${MIMI_MAC_BUILD_JOBS:-4}"

usage() {
  cat <<'EOF'
Usage: native-macos/tools/verify_macos_compile.sh [--arch x86_64|arm64|universal]

Verify that MIMICore and MIMIGuitarMac Swift sources compile and link cleanly
with swiftc without requiring unbundled offline catalog.sqlite or public/storage.

Options:
  --arch <arch>  Target architecture: x86_64, arm64, or universal (default: universal).
  --help, -h     Show this help.

Environment:
  MIMI_MAC_SDK         macOS SDK directory; defaults to xcrun --sdk macosx --show-sdk-path
                       (with fallback to Command Line Tools SDK).
  MIMI_MAC_BUILD_JOBS  Compiler parallel jobs; defaults to 4.
EOF
}

while (($# > 0)); do
  case "$1" in
    --arch)
      if (($# < 2)); then
        printf 'Missing value for --arch\n' >&2
        usage >&2
        exit 2
      fi
      ARCH_MODE="$2"
      shift
      ;;
    --arch=*)
      ARCH_MODE="${1#*=}"
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      printf 'Unknown option: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

case "$ARCH_MODE" in
  x86_64) ARCHES=("x86_64") ;;
  arm64) ARCHES=("arm64") ;;
  universal) ARCHES=("x86_64" "arm64") ;;
  *)
    printf 'Unsupported --arch value: %s (expected x86_64, arm64, or universal).\n' "$ARCH_MODE" >&2
    exit 2
    ;;
esac

if [[ ! "$BUILD_JOBS" =~ ^[1-9][0-9]*$ ]]; then
  printf 'MIMI_MAC_BUILD_JOBS must be a positive integer.\n' >&2
  exit 2
fi

if [[ -n "${MIMI_MAC_SDK:-}" ]]; then
  SDK_PATH="$MIMI_MAC_SDK"
else
  XCRUN_SDK="$(xcrun --sdk macosx --show-sdk-path 2>/dev/null || true)"
  if [[ -n "$XCRUN_SDK" && -d "$XCRUN_SDK" ]]; then
    SDK_PATH="$XCRUN_SDK"
  else
    SDK_PATH="$SDK_DEFAULT"
  fi
fi

if [[ -z "$SDK_PATH" || ! -d "$SDK_PATH" ]]; then
  printf 'macOS SDK not found (checked MIMI_MAC_SDK, xcrun, and %s).\n' "$SDK_DEFAULT" >&2
  exit 1
fi

for tool in swiftc file find mktemp; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    printf 'Required build tool is missing: %s\n' "$tool" >&2
    exit 1
  fi
done

CORE_SOURCES=()
while IFS= read -r source; do
  CORE_SOURCES[${#CORE_SOURCES[@]}]="$source"
done < <(find "$NATIVE_ROOT/Sources/MIMICore" -type f -name '*.swift' | LC_ALL=C sort)

APP_SOURCES=()
while IFS= read -r source; do
  APP_SOURCES[${#APP_SOURCES[@]}]="$source"
done < <(find "$NATIVE_ROOT/Sources/MIMIGuitarMac" -type f -name '*.swift' | LC_ALL=C sort)

if ((${#CORE_SOURCES[@]} == 0 || ${#APP_SOURCES[@]} == 0)); then
  printf 'No Swift sources found for MIMICore or MIMIGuitarMac.\n' >&2
  exit 1
fi

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/mimi-macos-compile.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

printf 'Using SDK: %s\n' "$SDK_PATH"
printf 'Core Swift files: %d, App Swift files: %d, Jobs: %s\n' \
  "${#CORE_SOURCES[@]}" "${#APP_SOURCES[@]}" "$BUILD_JOBS"

for ARCH in "${ARCHES[@]}"; do
  TARGET_TRIPLE="${ARCH}-apple-macosx${MINIMUM_MACOS}"
  ARCH_DIR="$WORK_DIR/$ARCH"
  mkdir -p "$ARCH_DIR"

  printf '==> Compiling MIMICore (%s)\n' "$TARGET_TRIPLE"
  swiftc \
    -j "$BUILD_JOBS" \
    -O \
    -static \
    -emit-library \
    -emit-module \
    -module-name MIMICore \
    -emit-module-path "$ARCH_DIR/MIMICore.swiftmodule" \
    -sdk "$SDK_PATH" \
    -target "$TARGET_TRIPLE" \
    -I "$NATIVE_ROOT/Sources/CSQLite" \
    "${CORE_SOURCES[@]}" \
    -lsqlite3 \
    -framework JavaScriptCore \
    -o "$ARCH_DIR/libMIMICore.a"

  printf '==> Compiling MIMIGuitarMac (%s)\n' "$TARGET_TRIPLE"
  swiftc \
    -j "$BUILD_JOBS" \
    -Osize \
    -parse-as-library \
    -module-name MIMIGuitarMac \
    -sdk "$SDK_PATH" \
    -target "$TARGET_TRIPLE" \
    -I "$ARCH_DIR" \
    -I "$NATIVE_ROOT/Sources/CSQLite" \
    "${APP_SOURCES[@]}" \
    "$ARCH_DIR/libMIMICore.a" \
    -lsqlite3 \
    -framework JavaScriptCore \
    -framework AppKit \
    -framework SwiftUI \
    -framework WebKit \
    -o "$ARCH_DIR/MIMIGuitarMac"

  file "$ARCH_DIR/libMIMICore.a" "$ARCH_DIR/MIMIGuitarMac"
done

printf 'Compile verification passed for: %s\n' "${ARCHES[*]}"
