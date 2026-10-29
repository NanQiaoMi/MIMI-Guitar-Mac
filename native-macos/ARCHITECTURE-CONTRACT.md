# Native macOS implementation contract — full migration

Owner: primary agent. Implementation workers: GPT-6-Luna, reasoning=max.

## Active 0.2.4 player UX implementation ownership

The user started the approved PLAYER-UX-OPTIMIZATION-PLAN on 2026-10-25. This allocation supersedes historical owner names below for this change only; existing work remains in place.

- `audit_playhead_fullscreen_plan`: Resources/Player/**, original score rendering/configuration adapter, cursor and playback bridge. New `score-rendering-entry.ts` reuses the web configuration in the same AlphaTab module instance used by the native API. Primary builds `score-rendering.bundle.js` after handoff.
- `native_player_ui`: Player/** Swift files and Views/ScoreDetailView.swift. Stable player identity, native controls/settings, progress interpolation, resource whitelist. NativePlayerPane adds trailing default parameters `isFocused: Bool = false, viewportHeight: CGFloat? = nil, onToggleFocus: (() -> Void)? = nil`; prior and diagnostic initializers remain compatible.
- `audit_navigation_motion_plan`: AppModel, MIMICommands, MainWindowView, DesignSystem, SettingsView, shell helpers, and only the PracticeView block in FullParityViews.swift. AppModel exposes `isScoreFocused`, `toggleScoreFullscreen()` and `exitScoreFullscreen()`. DesignSystem exposes MIMIMotionPolicy full/gentle/off, `resolve(preference:reduceMotion:)`, page/panel/control animation properties and allowsSpatialMotion.
- Primary owns integration, build/bundle scripts, diagnostic drivers and evidence, plan/status documents and packaging. No concurrent compiler runs. No new test suite, commits, pushes or external publication. New version output is Native-Mac-0.2.4; preserve 0.2.3 artifacts.

Playback position fields are additive: retain currentTime/endTime/tick/endTick/isSeek/beat and add timeMs/durationMs/speedRatio/originalTempo/modifiedTempo/isPlaying/sampledAtMonotonicMs. Audio time values are milliseconds; Swift anchors received samples to its own monotonic clock rather than mixing JavaScript and Swift clock epochs. The engine cursor remains driven by the audio clock, not the throttled bridge.

Score rendering must match the original web project, including fonts, notation content, geometry, line breaks, lyrics/chords, display modes and score-page decoration. See section 3.5/U16 in the approved plan. The simplified planning mockup is not an accepted score renderer or visual baseline.

## Current scope override

The user explicitly requires every existing interface detail and functional flow to migrate, not a framework or first-slice delivery. M0/M1 notes below describe the historical foundation. Full parity is the current task; see FULL-PARITY-MATRIX.zh-CN.md. Existing disabled public submissions stay disabled as in the source; working local features must not be replaced with unavailable placeholders. Native UI is SwiftUI/AppKit, with WebKit scoped to notation/synthesis and controlled domain adapters. Preserve the existing paper design and route/interaction coverage.

Current owners are full_core (Core/models/SQLite/backup/catalog/tools/build), full_shell (App/** and Views/**), full_player (Player/**, Studio/**, Resources/Player/**, Resources/Studio/**). Primary owns plans, this contract, parity matrix, source visual specification and integration review. Previous owner names refer to the earlier implementation session. Each owner reads and extends existing files; never discard prior work.

Full-store API: PersonalStore.snapshot() -> PersonalData; commit(_: PersonalData, assets: [PersonalAsset] = [], expectedRevision: Int? = nil) -> PersonalData; asset(id: String) -> PersonalAsset?; assetMetadata(ids: [String]) -> [PersonalAssetMetadata]. These actor methods throw. Old state/toggle/recent methods remain compatible. Core owns canonical Personal/Practice/Studio Codable models matching source fields and milliseconds, not independently designed UI models.

UI integration signatures:

```swift
NativePlayerPane(item: CatalogItem?, personalScore: PersonalScore? = nil,
    contentRoot: URL, personalStore: PersonalStore,
    importedFileURL: URL? = nil, mode: NativePlayerMode = .player,
    onPersonalDataChanged: @escaping () -> Void = {})
// NativePlayerMode: player, practice
NativeStudioPane(contentRoot: URL, personalStore: PersonalStore,
    onOpenPractice: @escaping (String) -> Void,
    onPersonalDataChanged: @escaping () -> Void = {})
```

Shell owns routing/AppModel and exposes the shared stores/snapshot. Player owns audition host/controller and a single audio coordinator so home previews, full player, practice and studio do not overlap. Coordinate the audition API directly before implementation. Working online account/article/favorites endpoints remain real HTTP operations on a configured origin; never simulate registration, publication, recovery or sound. API coding is authorized; no agent registration, publication or cloud mutations are authorized by this task.

This contract fixes module boundaries for the first native vertical slice. The detailed migration plan distinguishes this slice from full feature parity. Preserve the running website, its existing package.json change, Docker data and all browser data. No commits, publishing, resets, or automatic data restoration.

## Platform and build

- Current host: Intel, macOS 13.7.8, Swift 5.8.1, Command Line Tools; no xcodebuild.
- Minimum macOS 13. Use SwiftUI/AppKit/WebKit, ObservableObject and async actors. Avoid SwiftData, @Observable, macOS 14/15-only APIs and external Swift package dependencies.
- SwiftPM executable target MIMIGuitarMac; library MIMICore; system library CSQLite. Package.swift belongs to core worker. SwiftPM currently fails on CLT PlatformPath metadata before source compilation; use an explicit-SDK swiftc static-library fallback for this host. Packaging belongs to core worker after the coordinated handoff.
- Sources live here. User-facing compiled app/DMG go to the task outputs directory. Scratch/build files belong in .build or work, never in the home folder.
- The native app must open the catalog and play supported bundled scores without PostgreSQL, Docker, Node, network, or a localhost web server at runtime. The existing Docker app remains available for comparison.

## Ownership

- core worker: Package.swift, .gitignore, Sources/CSQLite/**, Sources/MIMICore/**, tools/export_catalog.py, Data/**, tools/build_macos_app.sh and build notes. May export the existing restored catalog read-only. Must not restore or mutate PostgreSQL. Owns full compilation and app/DMG packaging after the confirmed handoff.
- shell worker: Sources/MIMIGuitarMac/App/** and Sources/MIMIGuitarMac/Views/**. Native app lifecycle, app model, sidebar, catalog list, inspector, search, menus, settings, file import.
- player worker: Sources/MIMIGuitarMac/Player/**, Resources/Player/** and player notes. Local AlphaTab adapter, native transport and resource safety. Supplies resource layout and compilation fixes to core worker. Do not edit Package.swift, build script or shell views.
- primary: this contract, MIGRATION-PLAN.zh-CN.md and integration/review notes. Coordinate API changes before edits in another owner's files.

## Public MIMICore API

Core worker must expose the following public names with public initializers; notify others promptly if a signature must change.

```swift
public struct CatalogItem: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let artist: String?
    public let category: String
    public let difficulty: Int
    public let key: String?
    public let bpm: Int?
    public let scoreURL: String?
    public let xheURL: String?
    public let screenshotURL: String?
    public let format: String
    public let heat: Int
    public let sheetForm: Int
    // initializer defaults for all fields except id/title
}
public enum CatalogSort: String, CaseIterable, Sendable { case popular, title, providedOrder }
public struct CatalogQuery: Sendable {
    // public init(text: String = "", category: String? = nil,
    // ids: [String]? = nil, sort: CatalogSort = .popular,
    // limit: Int = 120, offset: Int = 0)
}
public struct CatalogPage: Sendable {
    public let items: [CatalogItem]
    public let total: Int
}
public actor CatalogStore {
    public init(databaseURL: URL) throws
    public func search(_ query: CatalogQuery) throws -> CatalogPage
    public func item(id: String) throws -> CatalogItem?
    public func count() throws -> Int
}
public struct PersonalState: Codable, Sendable {
    public var favoriteIDs: Set<String>
    public var queueIDs: [String]
    public var recentIDs: [String]
    public init() // empty
}
public actor PersonalStore {
    public init(directory: URL) throws
    public func state() throws -> PersonalState
    public func toggleFavorite(_ id: String) throws
    public func toggleQueue(_ id: String) throws
    public func recordRecent(_ id: String) throws
}
public enum AppPaths {
    public static func contentRoot(bundle: Bundle = .main) -> URL?
    public static func catalogURL(contentRoot: URL) -> URL
    public static func resolve(reference: String, contentRoot: URL) throws -> URL
    public static func userDataDirectory() throws -> URL
}
```

User data is separate from bundled read-only catalog; use a SQLite user database under Application Support/com.mimi.guitar.mac. This is new native data: do not claim browser IndexedDB has migrated. Current Core code implements v1/v2 backup import/export, including the website v2 envelope and earlier native direct-manifest compatibility. Actual browser-data migration still requires an explicitly selected valid backup and separate runtime acceptance.

## Resources and player interface

App bundle resource layout:

```text
Contents/Resources/
  Content/catalog.sqlite
  Content/storage/...      # stable project public/storage
  Content/soundfonts/...   # stable project public/soundfonts
  Player/...               # local viewer and vendor runtime, licenses
  Player/font/...          # nine bundled font files, separately whitelisted
```

contentRoot() may use MIMI_CONTENT_ROOT for development, then Bundle.main.resourceURL/Content. Never hardcode this user's absolute path into product source.
resolve() accepts only validated local storage/soundfonts references, decodes URL paths once, denies traversal/symlink escape and arbitrary remote URLs. App-selected imported files are copied to the app's own Imports directory before use; single-file import cap is 30 MiB. No network bridge, no arbitrary filesystem bridge, no eval/command bridge from web content.

Player worker exposes this SwiftUI type to the shell:

```swift
struct NativePlayerPane: View {
    init(item: CatalogItem, contentRoot: URL, importedFileURL: URL? = nil)
}
```

Use a WKWebView only for notation rendering/score synthesis and reuse stable IBE decode/AlphaTab modules with license notices. All chrome, library, search, transport, dialogs and app commands are native. A custom local scheme is allowed with strict resource whitelisting; block remote navigation. Prefer local binary resource loading over large repeated base64 transfers. Handle missing/corrupt score and unsupported XHE explicitly. Sound or loading progress must reflect real engine events. No autoplay on load or resume.

Native playback commands are Notification.Name("MIMI.TogglePlayback") and Notification.Name("MIMI.StopPlayback"). Shell menus may publish these; player handles them. Use Command-Return for global play/pause and Space only when score view owns keyboard focus, so text input remains usable.

## First slice scope and checks

- Native sidebar, searchable paged catalog (16233 rows in source), guitar/ukulele/favorites/queue/recent, detail view, native toolbar and menu commands, Settings, import via NSOpenPanel and drop if practical.
- Native favorites/queue/recent survive restart. Async searches cancel or ignore stale results and never perform database IO on the UI thread. Honor Reduce Motion.
- At least the IBE/GP score path loads through the bundled engine and offers transport/tempo/zoom. Unsupported formats clearly report their boundary. Do not claim complete practice/studio/backup parity.
- Compile/package checks are required to make the delivered app reviewable. No new test suite or swift test run. Report exact build failures and unverified runtime/audio/arm64/notarization status. Local ad-hoc signing may be used; Developer ID/notarization is a later release gate requiring the user's credentials.

## Communication

Report changed file list, API changes, build commands/results and current limitations to primary. Coordinate directly with other workers for shared contracts; each worker edits only its owned files. Keep private env values out of logs and generated documents.


## 0.2.1 integration amendments

The source declarations are authoritative for the current full API; the first-slice signatures above remain historical context. Final implementation owners were `finish_core_parity`, `finish_shell_parity`, and `final_player_compile` (GPT-6-Luna / max); primary integrated AppModel, routes, packaging and documentation.

- `PersonalStore.ensureFavorite(_ item:)` is idempotent; `recordRecent(_ item:)` preserves real catalog metadata. Raw catalog IDs and `catalog:<raw>` personal references have different roles and must not be mixed in badges, lookup or navigation.
- `joinPractice(_:)` atomically saves the score reference and joins/restores its queue item. `preparePracticeScore(scoreID:catalogItem:now:)` explicitly starts practice. Active item notes/status/relative order survive repeated joins; archive restoration appends at the active tail. Queue normalization matches `src/lib/personal/practiceQueue.ts`.
- `setPracticeStatus(scoreID:status:now:)` changes only status/order/timestamp. `updatePracticeNote(scoreID:note:expectedNote:now:)` compares the previous note and changes only note/timestamp. Missing or concurrently changed records fail without recreating removed queue items. UI callbacks preserve input typed while a save is pending.
- `saveStudioProject(_:expectedUpdatedAt:original:originalAsset:practiceScore:practiceAsset:addToPractice:)` commits the project, optional original and optional playable copy in one transaction. A nil expected project version means the ID must not exist. Project-specific CAS is independent of unrelated global personal revisions. Existing legacy project-linked private score IDs are retained.
- Studio edit/undo/redo/manual saves share a serial queue. Each successful edit has an increasing stored project timestamp. Linked IBE is generated from the same project snapshot and committed atomically; saving only the timestamp must not trigger another canvas layout. Switching projects invalidates pending editor callbacks.
- `CatalogQuery.includeMetadata` defaults to false; command suggestions opt in for title/artist/tags/key search. `searchArticles(_:including:)` replaces bundled rows by ID with successful publication records before sorting/counting/pagination.
- Successful publication content is cached per configured service origin in `published-articles.json`. Only actual POST success supplies an ID; cache-write failure is distinct from publication failure. Account/service switches invalidate old responses.
- v2 export uses `{format, manifest}`. Import additionally accepts earlier native direct manifests. Restore staging timestamps migrate without clearing active previews; only expired sessions are cleaned on store open.
- Player/Studio PDF and PNG export reuse the website detached full-score renderer in `printScore.ts`. Native PDF composition uses A4 media boxes and complete JPEG page images; PNG preserves website canvas limits. Studio flushes queued edits and exports an explicit current project snapshot. XHE retains original/print actions and does not claim digital-score PDF/PNG capability.
- Packaging requires `guitar-audio.bundle.js`, all runtime HTML script/style entries, the complete content tree and the favicon-derived multi-size `AppIcon.icns`. The Universal 2 build uses two explicit-SDK compilations, resource hashes, signatures and DMG verification. Those checks do not establish native visual/audio/performance acceptance.
