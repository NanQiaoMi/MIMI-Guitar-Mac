import Foundation

enum StudioBundleAssets {
    private static let requiredFiles = ["index.html", "studio.css", "studio.js", "studio-runtime.bundle.js"]

    static func studioRootURL() -> URL? {
        guard let resourceURL = Bundle.main.resourceURL else { return nil }
        let root = resourceURL.appendingPathComponent("Studio", isDirectory: true)
            .standardizedFileURL.resolvingSymlinksInPath().standardizedFileURL
        guard requiredFiles.allSatisfy({ FileManager.default.fileExists(atPath: root.appendingPathComponent($0).path) }) else { return nil }
        return root
    }

    static func playerRootURL() -> URL? { PlayerBundleAssets.rootURL() }
}
