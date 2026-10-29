import Foundation

enum PlayerBundleAssets {
    private static let requiredFiles = [
        "index.html",
        "player.css",
        "score-rendering.bundle.js",
        "player.js",
        "ibe.bundle.js",
        "practice-runtime.bundle.js",
        "guitar-audio.bundle.js",
        "ar.es.js",
        "alphaTab.js",
        "_astro/alphaTab.core.mjs",
        "_astro/alphaTab.worker.mjs",
        "_astro/alphaTab.worklet.mjs",
        "font/Bravura.eot",
        "font/Bravura.otf",
        "font/Bravura.svg",
        "font/Bravura.woff",
        "font/Bravura.woff2",
        "font/CascadiaCode.ttf",
        "font/CascadiaCode.woff2",
        "font/FZXiaoBiaoSong.TTF",
        "font/FZXiaoBiaoSong.woff2",
    ]

    static func rootURL() -> URL? {
        var candidates: [URL] = []
        if let configured = ProcessInfo.processInfo.environment["MIMI_PLAYER_ROOT"], !configured.isEmpty {
            candidates.append(URL(fileURLWithPath: configured, isDirectory: true))
        }
        if let resourceURL = Bundle.main.resourceURL {
            candidates.append(resourceURL.appendingPathComponent("Player", isDirectory: true))
        }

        for candidate in candidates {
            let root = candidate.standardizedFileURL.resolvingSymlinksInPath().standardizedFileURL
            guard requiredFiles.allSatisfy({
                FileManager.default.fileExists(atPath: root.appendingPathComponent($0).path)
            }) else { continue }
            return root
        }
        return nil
    }
}
