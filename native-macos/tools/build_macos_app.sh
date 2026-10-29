#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERIFY_SCRIPT="$SCRIPT_DIR/verify_macos_resources.py"
NATIVE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_ROOT="$(cd "$NATIVE_ROOT/.." && pwd)"
OUTPUT_ROOT_DEFAULT="$(cd "$PROJECT_ROOT/../.." && pwd)/Native-Mac-0.2.4"
OUTPUT_ROOT="${MIMI_MAC_OUTPUT_DIR:-$OUTPUT_ROOT_DEFAULT}"
BUILD_ROOT="$NATIVE_ROOT/.build/package"
SDK_DEFAULT="/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk"
APP_NAME="MIMI Guitar.app"
EXECUTABLE_NAME="MIMIGuitarMac"
BUNDLE_ID="com.mimi.guitar.mac"
MINIMUM_MACOS="13.0"
APP_VERSION="${MIMI_MAC_VERSION:-0.2.4}"
BUILD_NUMBER="${MIMI_MAC_BUILD_NUMBER:-$(date -u +%Y%m%d%H%M)}"
ARCH="${MIMI_MAC_ARCH:-$(uname -m)}"
BUILD_JOBS="${MIMI_MAC_BUILD_JOBS:-1}"
MAKE_DMG=1
ALLOW_REPLACE=0

usage() {
  cat <<'EOF'
Usage: tools/build_macos_app.sh [--no-dmg] [--replace]

Build a native MIMI Guitar .app with an explicit macOS SDK, a static MIMICore
archive, bundled offline content, and an ad-hoc code signature. By default it
also creates a compressed DMG. Output defaults to ../../Native-Mac-0.2.4 relative to
the project; set MIMI_MAC_OUTPUT_DIR to choose another output directory.

Options:
  --no-dmg   Build and verify the .app only.
  --replace  Replace only this script's named .app and DMG outputs if present.
  --help     Show this help.

Environment:
  MIMI_MAC_SDK         SDK directory; defaults to the local Command Line Tools SDK.
  MIMI_MAC_ARCH        x86_64 or arm64; defaults to the current host architecture.
  MIMI_MAC_VERSION     CFBundleShortVersionString; defaults to 0.2.4.
  MIMI_MAC_BUILD_NUMBER CFBundleVersion; defaults to the current UTC minute.
  MIMI_MAC_OUTPUT_DIR  Output directory; defaults to outputs/Native-Mac-0.2.4.
  MIMI_MAC_BUILD_JOBS  Compiler parallel jobs; defaults to 1.
EOF
}

while (($# > 0)); do
  case "$1" in
    --no-dmg)
      MAKE_DMG=0
      ;;
    --replace)
      ALLOW_REPLACE=1
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

case "$ARCH" in
  x86_64|arm64) ;;
  *)
    printf 'Unsupported architecture: %s (use x86_64 or arm64).\n' "$ARCH" >&2
    exit 2
    ;;
esac
if [[ ! "$BUILD_JOBS" =~ ^[1-9][0-9]*$ ]]; then
  printf 'MIMI_MAC_BUILD_JOBS must be a positive integer.\n' >&2
  exit 2
fi

TARGET_TRIPLE="$ARCH-apple-macosx$MINIMUM_MACOS"
SDK_PATH="${MIMI_MAC_SDK:-$SDK_DEFAULT}"
if [[ ! -d "$SDK_PATH" ]]; then
  printf 'macOS SDK not found at: %s\n' "$SDK_PATH" >&2
  printf 'Set MIMI_MAC_SDK to an installed macOS SDK directory.\n' >&2
  exit 1
fi

for tool in swiftc ditto codesign plutil shasum find xargs sqlite3 python3; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    printf 'Required build tool is missing: %s\n' "$tool" >&2
    exit 1
  fi
done

if ((MAKE_DMG)) && ! command -v hdiutil >/dev/null 2>&1; then
  printf 'hdiutil is required to create a DMG on this host.\n' >&2
  exit 1
fi

CONTENT_SOURCE="$PROJECT_ROOT/public"
CATALOG_SOURCE="$NATIVE_ROOT/Data/catalog.sqlite"
PLAYER_SOURCE="$NATIVE_ROOT/Resources/Player"
STUDIO_SOURCE="$NATIVE_ROOT/Resources/Studio"
DESIGN_SOURCE="$NATIVE_ROOT/Resources/Design"
ICON_SOURCE="$NATIVE_ROOT/Resources/AppIcon.icns"
AR_SOURCE="$PROJECT_ROOT/src/lib/vendor/ar.es.js"
APP_OUTPUT="$OUTPUT_ROOT/$APP_NAME"
DMG_OUTPUT="$OUTPUT_ROOT/MIMI-Guitar-macOS-$ARCH.dmg"

required_files=(
  "$ICON_SOURCE"
  "$CATALOG_SOURCE"
  "$CONTENT_SOURCE/soundfonts/sonivox.sf2"
  "$CONTENT_SOURCE/alphaTab.js"
  "$CONTENT_SOURCE/_astro/alphaTab.core.mjs"
  "$CONTENT_SOURCE/_astro/alphaTab.worker.mjs"
  "$CONTENT_SOURCE/_astro/alphaTab.worklet.mjs"
  "$AR_SOURCE"
  "$PLAYER_SOURCE/index.html"
  "$PLAYER_SOURCE/player.css"
  "$PLAYER_SOURCE/player.js"
  "$PLAYER_SOURCE/ibe.bundle.js"
  "$PLAYER_SOURCE/ibe-entry.ts"
  "$PLAYER_SOURCE/practice-runtime-entry.ts"
  "$PLAYER_SOURCE/practice-runtime.bundle.js"
  "$PLAYER_SOURCE/guitar-audio-entry.ts"
  "$PLAYER_SOURCE/guitar-audio.bundle.js"
  "$PLAYER_SOURCE/score-rendering-entry.ts"
  "$PLAYER_SOURCE/score-rendering.bundle.js"
  "$PLAYER_SOURCE/third-party/alphaTab-MPL-2.0.txt"
  "$PLAYER_SOURCE/third-party/alphaTab-integrated-libraries.txt"
  "$STUDIO_SOURCE/index.html"
  "$STUDIO_SOURCE/studio.css"
  "$STUDIO_SOURCE/studio.js"
  "$STUDIO_SOURCE/studio-runtime-entry.ts"
  "$STUDIO_SOURCE/studio-runtime.bundle.js"
  "$DESIGN_SOURCE/chords.ts"
  "$DESIGN_SOURCE/paper-texture.svg"
  "$PROJECT_ROOT/docs/third-party/sonivox-soundfont/LICENSE.txt"
  "$PROJECT_ROOT/docs/third-party/sonivox-soundfont/NOTICE.md"
  "$PROJECT_ROOT/docs/third-party/sonivox-soundfont/README-source.md"
  "$DESIGN_SOURCE/Fonts/Fraunces-400.ttf"
  "$DESIGN_SOURCE/Fonts/Fraunces-500.ttf"
  "$DESIGN_SOURCE/Fonts/Inter-400.ttf"
  "$DESIGN_SOURCE/Fonts/Inter-500.ttf"
  "$DESIGN_SOURCE/Fonts/Inter-600.ttf"
  "$DESIGN_SOURCE/Fonts/Inter-700.ttf"
  "$DESIGN_SOURCE/Fonts/OFL-Fraunces.txt"
  "$DESIGN_SOURCE/Fonts/OFL-Inter.txt"
)

for required_file in "${required_files[@]}"; do
  if [[ ! -f "$required_file" ]]; then
    printf 'Required package input is missing: %s\n' "$required_file" >&2
    exit 1
  fi
done

if [[ ! -d "$CONTENT_SOURCE/storage" || ! -d "$CONTENT_SOURCE/font" ]]; then
  printf 'Required public/storage or public/font resource directory is missing.\n' >&2
  exit 1
fi

if [[ ! -d "$STUDIO_SOURCE" ]]; then
  printf 'Required Studio resources directory is missing: %s\n' "$STUDIO_SOURCE" >&2
  exit 1
fi

font_files=(
  Bravura.eot Bravura.otf Bravura.svg Bravura.woff Bravura.woff2
  CascadiaCode.ttf CascadiaCode.woff2 FZXiaoBiaoSong.TTF FZXiaoBiaoSong.woff2
)
for font_file in "${font_files[@]}"; do
  if [[ ! -f "$CONTENT_SOURCE/font/$font_file" ]]; then
    printf 'Required player font is missing: %s\n' "$CONTENT_SOURCE/font/$font_file" >&2
    exit 1
  fi
done

if [[ -e "$APP_OUTPUT" || ( $MAKE_DMG -eq 1 && -e "$DMG_OUTPUT" ) ]]; then
  if ((ALLOW_REPLACE == 0)); then
    printf 'Package output already exists. Use --replace to replace only the named .app/DMG outputs.\n' >&2
    exit 1
  fi
  rm -rf "$APP_OUTPUT"
  if ((MAKE_DMG)); then rm -f "$DMG_OUTPUT"; fi
fi

mkdir -p "$OUTPUT_ROOT"
rm -rf "$BUILD_ROOT"
mkdir -p "$BUILD_ROOT/core" "$BUILD_ROOT/staging"

DB_INTEGRITY="$(sqlite3 -readonly "$CATALOG_SOURCE" 'PRAGMA integrity_check;')"
if [[ "$DB_INTEGRITY" != "ok" ]]; then
  printf 'Catalog SQLite integrity check failed: %s\n' "$DB_INTEGRITY" >&2
  exit 1
fi
CATALOG_COUNT="$(sqlite3 -readonly "$CATALOG_SOURCE" 'SELECT count(*) FROM catalog;')"
ARTICLE_COUNT="$(sqlite3 -readonly "$CATALOG_SOURCE" 'SELECT count(*) FROM articles;')"
CATALOG_SCHEMA_VERSION="$(sqlite3 -readonly "$CATALOG_SOURCE" "SELECT value FROM export_metadata WHERE key='schema_version';")"
if [[ "$CATALOG_SCHEMA_VERSION" != "2" || "$CATALOG_COUNT" != "16233" || "$ARTICLE_COUNT" != "8" ]]; then
  printf 'Catalog export is incomplete: expected schema 2 with 16,233 tabs and 8 articles; got schema %s, tabs %s, articles %s.\n' \
    "$CATALOG_SCHEMA_VERSION" "$CATALOG_COUNT" "$ARTICLE_COUNT" >&2
  exit 1
fi
EXPORT_TIME="$(sqlite3 -readonly "$CATALOG_SOURCE" "SELECT value FROM export_metadata WHERE key='exported_at_utc';")"
SOURCE_REVISION="$(sqlite3 -readonly "$CATALOG_SOURCE" "SELECT value FROM export_metadata WHERE key='source_revision';")"
TAB_ROWS_SHA256="$(sqlite3 -readonly "$CATALOG_SOURCE" "SELECT value FROM export_metadata WHERE key='tab_rows_sha256';")"
ARTICLE_ROWS_SHA256="$(sqlite3 -readonly "$CATALOG_SOURCE" "SELECT value FROM export_metadata WHERE key='article_rows_sha256';")"
RESOURCE_REFS_CHECKED="$(sqlite3 -readonly "$CATALOG_SOURCE" "SELECT value FROM export_metadata WHERE key='resource_refs_checked';")"
RESOURCE_REFS_MISSING="$(sqlite3 -readonly "$CATALOG_SOURCE" "SELECT value FROM export_metadata WHERE key='resource_refs_missing';")"
RESOURCE_REFS_INVALID="$(sqlite3 -readonly "$CATALOG_SOURCE" "SELECT value FROM export_metadata WHERE key='resource_refs_invalid';")"
if [[ "$RESOURCE_REFS_CHECKED" != "32453" || "$RESOURCE_REFS_MISSING" != "0" || "$RESOURCE_REFS_INVALID" != "0" ]]; then
  printf 'Catalog storage references are incomplete or invalid: checked/missing/invalid=%s/%s/%s.\n' \
    "$RESOURCE_REFS_CHECKED" "$RESOURCE_REFS_MISSING" "$RESOURCE_REFS_INVALID" >&2
  exit 1
fi

verify_file_copy() {
  python3 "$SCRIPT_DIR/verify_macos_resources.py" compare-file "$1" "$2" "$3"
}
verify_tree_copy() {
  python3 "$SCRIPT_DIR/verify_macos_resources.py" compare-tree "$1" "$2" "$3"
}

CORE_SOURCES=()
while IFS= read -r source; do CORE_SOURCES[${#CORE_SOURCES[@]}]="$source"; done < <(find "$NATIVE_ROOT/Sources/MIMICore" -type f -name '*.swift' | LC_ALL=C sort)
APP_SOURCES=()
while IFS= read -r source; do APP_SOURCES[${#APP_SOURCES[@]}]="$source"; done < <(find "$NATIVE_ROOT/Sources/MIMIGuitarMac" -type f -name '*.swift' | LC_ALL=C sort)

if ((${#CORE_SOURCES[@]} == 0 || ${#APP_SOURCES[@]} == 0)); then
  printf 'No Swift sources found for MIMICore or MIMIGuitarMac.\n' >&2
  exit 1
fi

for source in "${CORE_SOURCES[@]}" "${APP_SOURCES[@]}"; do
  if [[ ! -f "$source" ]]; then
    printf 'Swift source is missing: %s\n' "$source" >&2
    exit 1
  fi
done

printf 'Building static MIMICore for %s using SDK %s\n' "$TARGET_TRIPLE" "$SDK_PATH"
swiftc \
  -j "$BUILD_JOBS" \
  -O \
  -static \
  -emit-library \
  -emit-module \
  -module-name MIMICore \
  -emit-module-path "$BUILD_ROOT/core/MIMICore.swiftmodule" \
  -sdk "$SDK_PATH" \
  -target "$TARGET_TRIPLE" \
  -I "$NATIVE_ROOT/Sources/CSQLite" \
  "${CORE_SOURCES[@]}" \
  -lsqlite3 \
  -framework JavaScriptCore \
  -o "$BUILD_ROOT/core/libMIMICore.a"

APP_STAGE="$BUILD_ROOT/staging/$APP_NAME"
APP_CONTENTS="$APP_STAGE/Contents"
APP_RESOURCES="$APP_CONTENTS/Resources"
PLAYER_STAGE="$APP_RESOURCES/Player"
CONTENT_STAGE="$APP_RESOURCES/Content"
STUDIO_STAGE="$APP_RESOURCES/Studio"
DESIGN_STAGE="$APP_RESOURCES/Design"
mkdir -p "$APP_CONTENTS/MacOS" "$PLAYER_STAGE/_astro" "$PLAYER_STAGE/font" \
  "$PLAYER_STAGE/third-party" "$CONTENT_STAGE/soundfonts" "$APP_RESOURCES/Licenses/SONiVOX" \
  "$STUDIO_STAGE" "$DESIGN_STAGE"

printf 'Compiling native application sources\n'
swiftc \
  -j "$BUILD_JOBS" \
  -Osize \
  -parse-as-library \
  -module-name MIMIGuitarMac \
  -sdk "$SDK_PATH" \
  -target "$TARGET_TRIPLE" \
  -I "$BUILD_ROOT/core" \
  -I "$NATIVE_ROOT/Sources/CSQLite" \
  "${APP_SOURCES[@]}" \
  "$BUILD_ROOT/core/libMIMICore.a" \
  -lsqlite3 \
  -framework JavaScriptCore \
  -framework AppKit \
  -framework SwiftUI \
  -framework WebKit \
  -o "$APP_CONTENTS/MacOS/$EXECUTABLE_NAME"

printf 'Bundling offline data and player resources\n'
ditto "$ICON_SOURCE" "$APP_RESOURCES/AppIcon.icns"
verify_file_copy "$ICON_SOURCE" "$APP_RESOURCES/AppIcon.icns" "AppIcon.icns"
ditto "$CATALOG_SOURCE" "$CONTENT_STAGE/catalog.sqlite"
verify_file_copy "$CATALOG_SOURCE" "$CONTENT_STAGE/catalog.sqlite" "catalog.sqlite"
ditto "$CONTENT_SOURCE/storage" "$CONTENT_STAGE/storage"
verify_tree_copy "$CONTENT_SOURCE/storage" "$CONTENT_STAGE/storage" "public/storage"
ditto "$CONTENT_SOURCE/soundfonts" "$CONTENT_STAGE/soundfonts"
verify_tree_copy "$CONTENT_SOURCE/soundfonts" "$CONTENT_STAGE/soundfonts" "public/soundfonts"
ditto "$CONTENT_SOURCE/alphaTab.js" "$PLAYER_STAGE/alphaTab.js"
verify_file_copy "$CONTENT_SOURCE/alphaTab.js" "$PLAYER_STAGE/alphaTab.js" "alphaTab.js"
ditto "$CONTENT_SOURCE/_astro/alphaTab.core.mjs" "$PLAYER_STAGE/_astro/alphaTab.core.mjs"
verify_file_copy "$CONTENT_SOURCE/_astro/alphaTab.core.mjs" "$PLAYER_STAGE/_astro/alphaTab.core.mjs" "alphaTab core"
ditto "$CONTENT_SOURCE/_astro/alphaTab.worker.mjs" "$PLAYER_STAGE/_astro/alphaTab.worker.mjs"
verify_file_copy "$CONTENT_SOURCE/_astro/alphaTab.worker.mjs" "$PLAYER_STAGE/_astro/alphaTab.worker.mjs" "alphaTab worker"
ditto "$CONTENT_SOURCE/_astro/alphaTab.worklet.mjs" "$PLAYER_STAGE/_astro/alphaTab.worklet.mjs"
verify_file_copy "$CONTENT_SOURCE/_astro/alphaTab.worklet.mjs" "$PLAYER_STAGE/_astro/alphaTab.worklet.mjs" "alphaTab worklet"
ditto "$AR_SOURCE" "$PLAYER_STAGE/ar.es.js"
verify_file_copy "$AR_SOURCE" "$PLAYER_STAGE/ar.es.js" "audio worklet"
for player_file in index.html player.css player.js ibe.bundle.js guitar-audio.bundle.js guitar-audio-entry.ts score-rendering.bundle.js score-rendering-entry.ts; do
  ditto "$PLAYER_SOURCE/$player_file" "$PLAYER_STAGE/$player_file"
  verify_file_copy "$PLAYER_SOURCE/$player_file" "$PLAYER_STAGE/$player_file" "Player/$player_file"
done
ditto "$PLAYER_SOURCE/third-party" "$PLAYER_STAGE/third-party"
verify_tree_copy "$PLAYER_SOURCE/third-party" "$PLAYER_STAGE/third-party" "Player/third-party"
ditto "$PLAYER_SOURCE/ibe-entry.ts" "$PLAYER_STAGE/ibe-entry.ts"
verify_file_copy "$PLAYER_SOURCE/ibe-entry.ts" "$PLAYER_STAGE/ibe-entry.ts" "Player/ibe-entry.ts"
ditto "$PLAYER_SOURCE/practice-runtime-entry.ts" "$PLAYER_STAGE/practice-runtime-entry.ts"
verify_file_copy "$PLAYER_SOURCE/practice-runtime-entry.ts" "$PLAYER_STAGE/practice-runtime-entry.ts" "Player/practice-runtime-entry.ts"
ditto "$PLAYER_SOURCE/practice-runtime.bundle.js" "$PLAYER_STAGE/practice-runtime.bundle.js"
verify_file_copy "$PLAYER_SOURCE/practice-runtime.bundle.js" "$PLAYER_STAGE/practice-runtime.bundle.js" "Player/practice-runtime.bundle.js"
ditto "$STUDIO_SOURCE" "$STUDIO_STAGE"
verify_tree_copy "$STUDIO_SOURCE" "$STUDIO_STAGE" "Studio"
ditto "$DESIGN_SOURCE" "$DESIGN_STAGE"
verify_tree_copy "$DESIGN_SOURCE" "$DESIGN_STAGE" "Design"
python3 "$VERIFY_SCRIPT" runtime-entrypoints "$PLAYER_STAGE" "$STUDIO_STAGE"
for font_file in "${font_files[@]}"; do
  ditto "$CONTENT_SOURCE/font/$font_file" "$PLAYER_STAGE/font/$font_file"
  verify_file_copy "$CONTENT_SOURCE/font/$font_file" "$PLAYER_STAGE/font/$font_file" "Player/font/$font_file"
done
ditto "$PROJECT_ROOT/docs/third-party/sonivox-soundfont/LICENSE.txt" \
  "$APP_RESOURCES/Licenses/SONiVOX/LICENSE.txt"
verify_file_copy "$PROJECT_ROOT/docs/third-party/sonivox-soundfont/LICENSE.txt" "$APP_RESOURCES/Licenses/SONiVOX/LICENSE.txt" "SONiVOX LICENSE"
ditto "$PROJECT_ROOT/docs/third-party/sonivox-soundfont/NOTICE.md" \
  "$APP_RESOURCES/Licenses/SONiVOX/NOTICE.md"
verify_file_copy "$PROJECT_ROOT/docs/third-party/sonivox-soundfont/NOTICE.md" "$APP_RESOURCES/Licenses/SONiVOX/NOTICE.md" "SONiVOX NOTICE"
ditto "$PROJECT_ROOT/docs/third-party/sonivox-soundfont/README-source.md" \
  "$APP_RESOURCES/Licenses/SONiVOX/README-source.md"
verify_file_copy "$PROJECT_ROOT/docs/third-party/sonivox-soundfont/README-source.md" "$APP_RESOURCES/Licenses/SONiVOX/README-source.md" "SONiVOX source notes"

cat > "$APP_CONTENTS/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>zh_CN</string>
  <key>CFBundleExecutable</key><string>$EXECUTABLE_NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>MIMI Guitar</string>
  <key>CFBundleDisplayName</key><string>MIMI Guitar</string>
  <key>CFBundleIconFile</key><string>AppIcon.icns</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$APP_VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
  <key>LSMinimumSystemVersion</key><string>$MINIMUM_MACOS</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.music</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>UTImportedTypeDeclarations</key>
  <array>
    <dict>
      <key>UTTypeIdentifier</key><string>com.mimi.guitar.ibe-score</string>
      <key>UTTypeDescription</key><string>MIMI IBE Score</string>
      <key>UTTypeConformsTo</key><array><string>public.data</string></array>
      <key>UTTypeTagSpecification</key><dict><key>public.filename-extension</key><array><string>ibe</string></array></dict>
    </dict>
    <dict>
      <key>UTTypeIdentifier</key><string>com.mimi.guitar.xhe-score</string>
      <key>UTTypeDescription</key><string>MIMI XHE Score</string>
      <key>UTTypeConformsTo</key><array><string>public.plain-text</string></array>
      <key>UTTypeTagSpecification</key><dict><key>public.filename-extension</key><array><string>xhe</string></array></dict>
    </dict>
    <dict>
      <key>UTTypeIdentifier</key><string>com.mimi.guitar.guitarpro-score</string>
      <key>UTTypeDescription</key><string>Guitar Pro Score</string>
      <key>UTTypeConformsTo</key><array><string>public.data</string></array>
      <key>UTTypeTagSpecification</key><dict><key>public.filename-extension</key><array>
        <string>gp</string><string>gp3</string><string>gp4</string><string>gp5</string>
        <string>gp6</string><string>gp7</string><string>gp8</string><string>gpx</string>
      </array></dict>
    </dict>
    <dict>
      <key>UTTypeIdentifier</key><string>org.musicxml.musicxml</string>
      <key>UTTypeDescription</key><string>MusicXML Score</string>
      <key>UTTypeConformsTo</key><array><string>public.xml</string></array>
      <key>UTTypeTagSpecification</key>
      <dict>
        <key>public.filename-extension</key><array><string>musicxml</string><string>xml</string></array>
        <key>public.mime-type</key><string>application/vnd.recordare.musicxml+xml</string>
      </dict>
    </dict>
    <dict>
      <key>UTTypeIdentifier</key><string>com.mimi.guitar.alphatex</string>
      <key>UTTypeDescription</key><string>AlphaTex Score</string>
      <key>UTTypeConformsTo</key><array><string>public.plain-text</string></array>
      <key>UTTypeTagSpecification</key><dict><key>public.filename-extension</key><array><string>tex</string><string>alphatex</string></array></dict>
    </dict>
  </array>
  <key>CFBundleDocumentTypes</key>
  <array>
    <dict>
      <key>CFBundleTypeName</key><string>MIMI Guitar Score</string>
      <key>CFBundleTypeRole</key><string>Editor</string>
      <key>LSHandlerRank</key><string>Alternate</string>
      <key>CFBundleTypeExtensions</key>
      <array>
        <string>ibe</string><string>xhe</string><string>gp</string><string>gp3</string>
        <string>gp4</string><string>gp5</string><string>gp6</string><string>gp7</string>
        <string>gp8</string><string>gpx</string><string>musicxml</string><string>xml</string>
        <string>tex</string><string>alphatex</string><string>json</string>
      </array>
      <key>LSItemContentTypes</key>
      <array>
        <string>com.mimi.guitar.ibe-score</string><string>com.mimi.guitar.xhe-score</string>
        <string>com.mimi.guitar.guitarpro-score</string><string>org.musicxml.musicxml</string>
        <string>com.mimi.guitar.alphatex</string><string>public.json</string>
      </array>
    </dict>
  </array>
</dict>
</plist>
EOF

plutil -lint "$APP_CONTENTS/Info.plist"

RESOURCE_FILE_COUNT="$(find "$APP_RESOURCES" -type f | wc -l | tr -d ' ')"
RESOURCE_BYTES="$(find "$APP_RESOURCES" -type f -exec stat -f '%z' {} + | awk '{sum += $1} END {printf "%.0f", sum}')"
STORAGE_FILE_COUNT="$(find "$CONTENT_STAGE/storage" -type f | wc -l | tr -d ' ')"
FONT_FILE_COUNT="$(find "$PLAYER_STAGE/font" -type f | wc -l | tr -d ' ')"
STORAGE_BYTES="$(find "$CONTENT_STAGE/storage" -type f -exec stat -f '%z' {} + | awk '{sum += $1} END {printf "%.0f", sum}')"
SOUNDFONT_BYTES="$(find "$CONTENT_STAGE/soundfonts" -type f -exec stat -f '%z' {} + | awk '{sum += $1} END {printf "%.0f", sum}')"
FONT_BYTES="$(find "$PLAYER_STAGE/font" -type f -exec stat -f '%z' {} + | awk '{sum += $1} END {printf "%.0f", sum}')"
CONTENT_FILE_COUNT="$(find "$CONTENT_STAGE" -type f | wc -l | tr -d ' ')"
CONTENT_BYTES="$(find "$CONTENT_STAGE" -type f -exec stat -f '%z' {} + | awk '{sum += $1} END {printf "%.0f", sum}')"
STUDIO_FILE_COUNT="$(find "$STUDIO_STAGE" -type f | wc -l | tr -d ' ')"
DESIGN_FILE_COUNT="$(find "$DESIGN_STAGE" -type f | wc -l | tr -d ' ')"
CATALOG_BYTES="$(stat -f '%z' "$CONTENT_STAGE/catalog.sqlite")"
BUILD_UTC="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
BUNDLE_MANIFEST="$APP_RESOURCES/BUILD-MANIFEST.txt"

{
  printf 'MIMI Guitar Native macOS Build Manifest\n'
  printf 'Built UTC: %s\n' "$BUILD_UTC"
  printf 'Version: %s (%s)\n' "$APP_VERSION" "$BUILD_NUMBER"
  printf 'Architecture: %s\n' "$ARCH"
  printf 'Target: %s\n' "$TARGET_TRIPLE"
  printf 'Minimum macOS: %s\n' "$MINIMUM_MACOS"
  printf 'Core linkage: static MIMICore archive; SQLite links to the system libsqlite3\n'
  printf 'Product compiler optimization: MIMICore -O; MIMIGuitarMac -Osize\n'
  printf 'Diagnostic macro MIMI_RUNTIME_DIAGNOSTICS: not defined for product build\n'
  printf 'Catalog tabs: %s\n' "$CATALOG_COUNT"
  printf 'Articles: %s\n' "$ARTICLE_COUNT"
  printf 'Catalog export schema: %s\n' "$CATALOG_SCHEMA_VERSION"
  printf 'Catalog integrity: %s\n' "$DB_INTEGRITY"
  printf 'Catalog export UTC: %s\n' "$EXPORT_TIME"
  printf 'Catalog source revision: %s\n' "$SOURCE_REVISION"
  printf 'Tab rows SHA-256: %s\n' "$TAB_ROWS_SHA256"
  printf 'Article rows SHA-256: %s\n' "$ARTICLE_ROWS_SHA256"
  printf 'Resource references checked/missing/invalid: %s/%s/%s\n' \
    "$RESOURCE_REFS_CHECKED" "$RESOURCE_REFS_MISSING" "$RESOURCE_REFS_INVALID"
  printf 'Bundled resource files before this manifest: %s\n' "$RESOURCE_FILE_COUNT"
  printf 'Bundled resource bytes before this manifest: %s\n' "$RESOURCE_BYTES"
  printf 'Storage files: %s\n' "$STORAGE_FILE_COUNT"
  printf 'Storage bytes (sum of exact file sizes): %s\n' "$STORAGE_BYTES"
  printf 'SoundFont bytes (sum of exact file sizes): %s\n' "$SOUNDFONT_BYTES"
  printf 'Player font files: %s\n' "$FONT_FILE_COUNT"
  printf 'Player font bytes (sum of exact file sizes): %s\n' "$FONT_BYTES"
  printf 'Font redistribution status: see Design/Fonts/NOTICE-Fonts.zh-CN.md; Founder font authorization is not verified.\n'
  printf 'Offline content files: %s\n' "$CONTENT_FILE_COUNT"
  printf 'Offline content bytes (sum of exact file sizes): %s\n' "$CONTENT_BYTES"
  printf 'Studio resource files: %s\n' "$STUDIO_FILE_COUNT"
  printf 'Design resource files: %s\n' "$DESIGN_FILE_COUNT"
  printf 'Catalog SQLite bytes: %s\n' "$CATALOG_BYTES"
  printf 'Signature: ad-hoc (not Developer ID signed or notarized)\n'
  printf '\nInfo.plist SHA-256:\n'
  (cd "$APP_STAGE" && shasum -a 256 Contents/Info.plist)
  printf '\nEvery bundled resource file SHA-256, exact byte size and relative path\n'
  printf '(BUILD-MANIFEST.txt is excluded from its own listing):\n'
  python3 "$SCRIPT_DIR/verify_macos_resources.py" manifest "$APP_RESOURCES"
} > "$BUILD_ROOT/BUILD-MANIFEST.txt"
ditto "$BUILD_ROOT/BUILD-MANIFEST.txt" "$BUNDLE_MANIFEST"

printf 'Signing app with an ad-hoc signature\n'
codesign --force --deep --sign - "$APP_STAGE"
codesign --verify --deep --strict --verbose=2 "$APP_STAGE"

if ((MAKE_DMG)); then
  DMG_STAGE="$BUILD_ROOT/dmg-stage"
  mkdir -p "$DMG_STAGE"
  ditto "$APP_STAGE" "$DMG_STAGE/$APP_NAME"
  ln -s /Applications "$DMG_STAGE/Applications"
  DMG_TEMP="$BUILD_ROOT/MIMI-Guitar-macOS-$ARCH.dmg"
  hdiutil create -volname "MIMI Guitar" -srcfolder "$DMG_STAGE" -ov -format UDZO "$DMG_TEMP"
  hdiutil verify "$DMG_TEMP"
fi

ditto "$APP_STAGE" "$APP_OUTPUT"
codesign --verify --deep --strict --verbose=2 "$APP_OUTPUT"
if ((MAKE_DMG)); then
  mv "$DMG_TEMP" "$DMG_OUTPUT"
fi

APP_BYTES="$(du -sk "$APP_OUTPUT" | awk '{print $1 * 1024}')"
SIGNED_EXECUTABLE_SHA256="$(shasum -a 256 "$APP_OUTPUT/Contents/MacOS/$EXECUTABLE_NAME" | awk '{print $1}')"
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
  cat "$BUILD_ROOT/BUILD-MANIFEST.txt"
  printf '\nPackage outputs:\n'
  printf 'App: %s\n' "$APP_OUTPUT"
  printf 'App bytes (du -sk estimate): %s\n' "$APP_BYTES"
  printf 'Signed executable SHA-256: %s\n' "$SIGNED_EXECUTABLE_SHA256"
  printf 'Info.plist SHA-256: %s\n' "$INFO_PLIST_SHA256"
  printf 'Code signature identity: %s\n' "${SIGNATURE_IDENTITY:-unknown}"
  printf 'DMG: %s\n' "$DMG_OUTPUT"
  printf 'DMG bytes: %s\n' "$DMG_BYTES"
  printf 'DMG SHA-256: %s\n' "$DMG_SHA256"
  printf 'Codesign verification: passed\n'
  printf 'Notarization: not performed\n'
} > "$OUTPUT_ROOT/BUILD-MANIFEST.txt"

printf 'Build complete.\n'
printf 'App: %s\n' "$APP_OUTPUT"
if ((MAKE_DMG)); then printf 'DMG: %s\n' "$DMG_OUTPUT"; fi
printf 'Manifest: %s/BUILD-MANIFEST.txt\n' "$OUTPUT_ROOT"
