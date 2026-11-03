# Shell/UI migration work log

## Scope

Native macOS shell, routes, pages, and UI parity. The migration target is `native-macos`; shared Core and Player implementation belongs to their respective agents. Existing package configuration and other worktree changes are preserved. No tests, commits, pushes, PRs, publication, or external account mutations were performed by this agent.

## Implemented in the current working tree

- Added native route state for catalog query round-tripping, article search, safe local auth return paths, Studio clones from catalog/personal scores, and reopening a specific Studio project.
- Added route history restoration for selected library section, catalog search/filter/sort/page, and article search/sort/page state.
- Tightened Account API loopback validation to accept only `localhost`, `::1`, or a valid four-octet IPv4 address in `127.0.0.0/8`; cross-origin redirects remain rejected.
- Wired Finder, drag/drop, and open-panel imports through player or Studio according to IBE, XHE, Guitar Pro, MusicXML/XML, AlphaTex/TeX, and JSON formats. Studio receives the selected project, clone source, and imported file where applicable.
- Added catalog and personal score detail actions, metadata, screenshot, descriptions, tags, related scores, favorite/queue, share/download, audition, practice, and Studio entry points.
- Added archived-practice navigation that opens the archived list, and added real progress seeking and tempo-rate cycling in the Showcase playback demonstration.
- Showcase now has nine individually operable sections: navigation/search, holographic card, cinematic paper opening, fretboard lab, score-card grid, blur-up/particles, favorite/share/download controls, filter bar, and difficulty matrix. Motion follows the stored setting and Reduce Motion; unknown settings behave as off.
- Removed `.presentationBackground(.clear)` usage that is unavailable on the macOS 13 deployment target. Corrected font-family selection to use the packaged Fraunces/Inter faces with system Chinese fallbacks.
- Repaired the missing switch-closing brace in `Views/MainWindowView.swift`; `swiftc -frontend -parse` passed for that file.
- Rebuilt Home Hero data as the source-ordered nine-song collection, including each title, artist, key, level, tempo, chord set, and four exact TAB note columns. Hero now starts on a random record, cycles forward across all nine, and plays the full source score without the capped preview timer.
- Added a separate four-record Masterpiece Stage dataset with its own descriptions, key/form labels, chord sets, exact heading/subtitle, popular-catalog link, `NO.` identifiers, static TAB example, and full-score auditions. The fixed Bento example still resolves independently to 晴天.
- Replaced unrelated screenshot thumbnails in both Home showcase cards with native vector TAB graphics. The Hero staff follows the selected source record and audition playhead; the Stage mini-score matches the fixed source illustration.
- Added the six source search placeholders with the 750 ms start, 75 ms typing, 30 ms deletion, 2.6 s hold, and 400 ms transition timings. Focus, view visibility, app activity, Reduce Motion, or a non-system motion preference stop and reset the animation.
- Added pointer-following Hero spotlight and source-style 3D tilt/shine for the Hero and four Stage cards; spatial effects are disabled for gentle/off/Reduce Motion.
- Added keyboard-focusable, click-pinnable chord preview popovers with source chord fingering data and the source fallback for unsupported chord names.

## Source file freeze

`Views/FullParityViews.swift` was recovered from its exact pre-delete session snapshot by the parent agent; the parent applied focused archived-list and Showcase patches. It remains frozen. No changes were made to it during this Home pass.

## Not verified

- `swiftc -frontend -parse Sources/MIMIGuitarMac/Views/HomeView.swift Sources/MIMIGuitarMac/Views/HomeSourceData.swift Sources/MIMIGuitarMac/Views/HomeChordPreview.swift` passed.
- `swift build` could not start because the installed Command Line Tools cannot resolve the macOS SDK PlatformPath (`xcrun --sdk macosx --show-sdk-platform-path`); the parent/Core integrated compile is needed for type-check and API-availability diagnostics.
- No test suite or automated UI/audio verification was run. Native UI automation was unavailable, so visual fidelity and live audio remain unverified.
- No test suite or automated UI/audio verification was run. Native UI automation was unavailable, so visual fidelity and live audio remain unverified.

## Remaining review items

- Home Hero and Stage data/interaction pass is implemented from the source components, but remains pending integrated type-check and visual/audio verification. Confirm local score availability for all curated IDs and actual popover/3D behavior in the built app.
- The Showcase grid currently uses the loaded Home featured set; confirm whether the source grid should draw from a broader catalog result set.
- The license page should disclose the included Bravura and Cascadia Code OFL files and the `FZXiaoBiaoSong.TTF` licensing status exactly as `Resources/Design/NOTICE-Fonts.zh-CN.md` states; do not describe that font as OFL or licensed.
- Route, file-type dispatch, full-page copy, and macOS 13 API compatibility still require integrated compile/review. Do not report UI/audio acceptance without device verification.
