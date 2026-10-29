import Foundation
import WebKit

final class StudioResourceSchemeHandler: NSObject, WKURLSchemeHandler {
    private let studioRoot: URL
    private let playerRoot: URL
    private let contentRoot: URL
    private let workQueue = DispatchQueue(label: "com.mimi.guitar.studio-resources", qos: .userInitiated)
    private let lock = NSLock()
    private var cancelled = Set<ObjectIdentifier>()

    init(studioRoot: URL, playerRoot: URL, contentRoot: URL) {
        self.studioRoot = Self.canonical(studioRoot)
        self.playerRoot = Self.canonical(playerRoot)
        self.contentRoot = Self.canonical(contentRoot)
        super.init()
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        let id = ObjectIdentifier(urlSchemeTask as AnyObject)
        workQueue.async { [weak self] in
            guard let self else { return }
            do {
                guard let requestURL = urlSchemeTask.request.url,
                      let path = Self.safePath(requestURL),
                      let (file, mime, encoding) = self.resolve(path) else {
                    throw StudioResourceError.notWhitelisted
                }
                let values = try file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
                guard values.isRegularFile == true, let count = values.fileSize, count >= 0, count <= 64 * 1_024 * 1_024 else {
                    throw StudioResourceError.invalidFile
                }
                let bytes = try Data(contentsOf: file, options: .mappedIfSafe)
                guard bytes.count == count else { throw StudioResourceError.invalidFile }
                DispatchQueue.main.async {
                    guard !self.isCancelled(id) else { return }
                    var headers = ["Content-Type": encoding.map { "\(mime); charset=\($0)" } ?? mime,
                                   "Content-Length": String(bytes.count), "Cache-Control": "no-store"]
                    headers["X-Content-Type-Options"] = "nosniff"
                    let response = HTTPURLResponse(url: requestURL, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers)!
                    urlSchemeTask.didReceive(response)
                    urlSchemeTask.didReceive(bytes)
                    urlSchemeTask.didFinish()
                    self.forget(id)
                }
            } catch {
                DispatchQueue.main.async {
                    guard !self.isCancelled(id) else { return }
                    urlSchemeTask.didFailWithError(error)
                    self.forget(id)
                }
            }
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        lock.lock(); cancelled.insert(ObjectIdentifier(urlSchemeTask as AnyObject)); lock.unlock()
    }

    private func resolve(_ path: String) -> (URL, String, String?)? {
        let studioAssets: [String: (String, String, String?)] = [
            "/index.html": ("index.html", "text/html", "utf-8"),
            "/studio.css": ("studio.css", "text/css", "utf-8"),
            "/studio.js": ("studio.js", "text/javascript", "utf-8"),
            "/studio-runtime.bundle.js": ("studio-runtime.bundle.js", "text/javascript", "utf-8"),
        ]
        if let (name, mime, encoding) = studioAssets[path] {
            let url = Self.canonical(studioRoot.appendingPathComponent(name))
            guard Self.contains(url, within: studioRoot) else { return nil }
            return (url, mime, encoding)
        }
        let playerAssets: [String: (String, String, String?)] = [
            "/ar.es.js": ("ar.es.js", "text/javascript", "utf-8"),
            "/guitar-audio.bundle.js": ("guitar-audio.bundle.js", "text/javascript", "utf-8"),
            "/alphaTab.js": ("alphaTab.js", "text/javascript", "utf-8"),
            "/_astro/alphaTab.core.mjs": ("_astro/alphaTab.core.mjs", "text/javascript", "utf-8"),
            "/_astro/alphaTab.worker.mjs": ("_astro/alphaTab.worker.mjs", "text/javascript", "utf-8"),
            "/_astro/alphaTab.worklet.mjs": ("_astro/alphaTab.worklet.mjs", "text/javascript", "utf-8"),
            "/font/Bravura.woff2": ("font/Bravura.woff2", "font/woff2", nil),
            "/font/Bravura.woff": ("font/Bravura.woff", "font/woff", nil),
            "/font/CascadiaCode.woff2": ("font/CascadiaCode.woff2", "font/woff2", nil),
            "/font/CascadiaCode.ttf": ("font/CascadiaCode.ttf", "font/ttf", nil),
            "/font/FZXiaoBiaoSong.woff2": ("font/FZXiaoBiaoSong.woff2", "font/woff2", nil),
            "/font/FZXiaoBiaoSong.TTF": ("font/FZXiaoBiaoSong.TTF", "font/ttf", nil),
        ]
        if let (name, mime, encoding) = playerAssets[path] {
            let url = Self.canonical(playerRoot.appendingPathComponent(name))
            guard Self.contains(url, within: playerRoot) else { return nil }
            return (url, mime, encoding)
        }
        if path == "/soundfonts/sonivox.sf2" {
            let root = Self.canonical(contentRoot.appendingPathComponent("soundfonts", isDirectory: true))
            let file = Self.canonical(root.appendingPathComponent("sonivox.sf2"))
            guard Self.contains(root, within: contentRoot), Self.contains(file, within: root) else { return nil }
            return (file, "application/octet-stream", nil)
        }
        if path == "/storage/soundfonts/ukulele_fast.sf2" {
            let storageRoot = Self.canonical(contentRoot.appendingPathComponent("storage", isDirectory: true))
            let root = Self.canonical(storageRoot.appendingPathComponent("soundfonts", isDirectory: true))
            let file = Self.canonical(root.appendingPathComponent("ukulele_fast.sf2"))
            guard Self.contains(storageRoot, within: contentRoot),
                  Self.contains(root, within: storageRoot),
                  Self.contains(file, within: root) else { return nil }
            return (file, "application/octet-stream", nil)
        }
        if path == "/soundfont/main" {
            let root = Self.canonical(contentRoot.appendingPathComponent("soundfonts", isDirectory: true))
            let file = Self.canonical(root.appendingPathComponent("sonivox.sf2"))
            guard Self.contains(root, within: contentRoot), Self.contains(file, within: root) else { return nil }
            return (file, "application/octet-stream", nil)
        }
        return nil
    }

    private func isCancelled(_ id: ObjectIdentifier) -> Bool {
        lock.lock(); defer { lock.unlock() }; return cancelled.contains(id)
    }

    private func forget(_ id: ObjectIdentifier) {
        lock.lock(); cancelled.remove(id); lock.unlock()
    }

    private static func safePath(_ url: URL) -> String? {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme?.lowercased() == "mimistudio", parts.host?.lowercased() == "app",
              parts.query == nil, parts.fragment == nil,
              let path = parts.percentEncodedPath.removingPercentEncoding,
              !path.contains("\\"), !path.contains("\0"), !path.split(separator: "/", omittingEmptySubsequences: false).contains(where: { $0 == "." || $0 == ".." }) else { return nil }
        return path
    }

    private static func canonical(_ url: URL) -> URL { url.standardizedFileURL.resolvingSymlinksInPath().standardizedFileURL }
    private static func contains(_ url: URL, within root: URL) -> Bool {
        let value = canonical(url).path, base = canonical(root).path
        return value == base || value.hasPrefix(base.hasSuffix("/") ? base : base + "/")
    }
}

private enum StudioResourceError: Error, LocalizedError {
    case notWhitelisted, invalidFile
    var errorDescription: String? {
        switch self {
        case .notWhitelisted: return "工坊资源请求未通过本地白名单。"
        case .invalidFile: return "工坊资源不存在或文件大小无效。"
        }
    }
}
