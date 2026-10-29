# Core migration work log

Date: 2026-10-24

## Scope and constraints

- Branch: `feature/macos-native`; keep the existing `package.json` worktree change.
- Core ownership: `Sources/MIMICore/**`, `Sources/CSQLite/**`, `Data/**`, `Package.swift`, `tools/**`, `BUILDING.zh-CN.md`, and `Resources/Design/**`.
- Never restore, drop, or mutate the website database. No tests, commits, pushes, PRs, or deployment.
- Website personal-data contract: preserve schema-1/2 payload fields, raw backup digests, source IDs, attachment bytes and milliseconds; store catalog personal IDs as `catalog:<raw id>` and keep `sourceId` raw with revision `unverified`.
- Public storage API remains `snapshot()`, `commit(_:assets:expectedRevision:)`, `asset(id:)`, and `assetMetadata(ids:)`, with legacy collection methods maintained.

## 2026-10-24 recovery checkpoint

- Read `ARCHITECTURE-CONTRACT.md`, `FULL-PARITY-MATRIX.zh-CN.md`, `MIGRATION-PLAN.zh-CN.md`, and `SOURCE-DESIGN-SPEC.zh-CN.md` before editing.
- Confirmed no relevant prior project note in the memory registry; repository state is on `feature/macos-native`. Existing `package.json` diff is untouched.
- Sent the Store API and catalog ID contract to both Shell and Player workers.
- First explicit-SDK Core compilation exposed existing source errors. Fixed the malformed project-conflict string, missing `Self.` qualification, throwing nil-coalescing expressions, invalid `for` binding syntax, stale merge parameter labels, throwing budget expression, and `Int` revision validation.
- Replaced backup canonicalization with JavaScriptCore `JSON.stringify` semantics and cached the context per thread. Core/Package now links JavaScriptCore.
- v1 preview stores the digest verified against the original parsed payload and a typed-data fingerprint. Restore checks the saved digest/fingerprint plus asset descriptors instead of rebuilding and sorting a lossy Codable payload.
- v1 export estimates the complete envelope from metadata and empty-base64 placeholders before reading any attachment bytes; this rejects >64 MiB exports without loading their large assets.
- Legacy favorites, queue and recents resolve catalog models through `catalog:<raw id>` while history IDs/URLs retain raw source values. `recordRecent`, compatibility state and SQLite recents now retain 500 rows. Legacy catalog ID migration writes its final score set from the selected canonical map, avoiding stale duplicate records.
- Core compiles successfully with explicit SDK and JavaScriptCore:
  `swiftc -parse-as-library -emit-module -emit-library -module-name MIMICore -emit-module-path native-macos/.build/core-check/MIMICore.swiftmodule -sdk /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk -target x86_64-apple-macosx13.0 -I native-macos/Sources/CSQLite native-macos/Sources/MIMICore/*.swift -lsqlite3 -framework JavaScriptCore -o native-macos/.build/core-check/libMIMICore.dylib`
- `bash -n native-macos/tools/build_macos_app.sh` passes after changing it to collect every app/Core Swift file, package Player/Studio/Design trees, and link JavaScriptCore. It defaults to a new `Native-Mac-Full` output and version 0.2.0, leaving the prior Native-Mac 0.1 output untouched.
- Copied the six requested Fraunces/Inter latin font subsets and full OFL licenses from the running app container's `@fontsource` packages. Converted WOFF2 to TTF with a temporary build-only fontTools installation under ignored `.build/`; no runtime conversion dependency was added.
- Preserved the source `src/lib/chords.ts` byte-for-byte at `Resources/Design/chords.ts` and extracted the paper grain SVG to `Resources/Design/paper-texture.svg`.
- Confirmed the app bundle will carry SONiVOX `LICENSE.txt`, `NOTICE.md` and `README-source.md` under `Contents/Resources/Licenses/SONiVOX`.

## Integrated packaging work in progress

- Added `tools/verify_macos_resources.py` to compare source and staged file trees using every relative path, SHA-256 and exact byte size. The main build embeds a complete per-file resource inventory, checks the whole `public/storage` and Studio/Design trees, and rechecks the packaged resource tree.
- Added `tools/build_macos_universal_app.sh`: sequential x86_64/arm64 builds, `lipo` slice verification, a universal2 ad-hoc signature, optional compressed DMG creation and `hdiutil verify`. It writes only to `Native-Mac-Full`; the older `Native-Mac` output is kept intact.
- Explicit-SDK Core compilation passed for both x86_64 and arm64. A first integrated app compile exposed an incomplete Shell view; after that repair, compilation progressed into current Player work. Latest compile errors are recorded in the parent/Player task messages; do not start final packaging until Player and Shell signal frozen sources.
- Added complete Bravura and Cascadia Code OFL texts plus `Resources/Design/Fonts/NOTICE-Fonts.zh-CN.md`. The notice identifies that the source project ships Founder Corporation's FZXiaoBiaoSong without a license file, does not claim authorization, and links to Foundertype's rights information. The build manifest will repeat this licensing boundary.
- No test suite was added or run. Full app, DMG and final manifest checks are pending source freeze and integrated compile.

## Remaining Core work

- Complete the remaining Core review of model validation, catalog fields/filtering/rankings, v2 staging and merge behavior.
- Wait for Player's Studio resource bundle and then compile every MIMICore/app source with the integrated build script. Hash/count/size verification must cover the complete Content tree, including every existing `public/storage` file.
- Check the final app/DMG and manifest after the integrated package is built; do not claim UI/audio runtime validation because native CUA screenshots are unavailable.
