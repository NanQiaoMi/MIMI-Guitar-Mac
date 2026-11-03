import Foundation
import MIMICore
import WebKit

final class PlayerResourceSchemeHandler: NSObject, WKURLSchemeHandler {
    private final class ActiveTask {
        let task: WKURLSchemeTask
        let fileHandle: FileHandle
        var cancelled = false
        var readPending = false

        init(task: WKURLSchemeTask, fileHandle: FileHandle) {
            self.task = task
            self.fileHandle = fileHandle
        }
    }

    private let playerRoot: URL
    private let contentRoot: URL
    private let source: NativePlayerSource
    private let soundFontURL: URL
    private let ukuleleSoundFontURL: URL?
    private let ioQueue = DispatchQueue(label: "com.mimi.guitar.player-resource-io", qos: .userInitiated, attributes: .concurrent)
    private var activeTasks: [ObjectIdentifier: ActiveTask] = [:]

    init(playerRoot: URL, contentRoot: URL, source: NativePlayerSource) throws {
        self.playerRoot = playerRoot.standardizedFileURL.resolvingSymlinksInPath().standardizedFileURL
        self.contentRoot = contentRoot.standardizedFileURL.resolvingSymlinksInPath().standardizedFileURL
        self.source = source
        soundFontURL = try AppPaths.resolve(reference: "/soundfonts/sonivox.sf2", contentRoot: contentRoot)
        ukuleleSoundFontURL = try? AppPaths.resolve(reference: "/storage/soundfonts/ukulele_fast.sf2", contentRoot: contentRoot)
        super.init()
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        let taskID = ObjectIdentifier(urlSchemeTask as AnyObject)
        onMainQueue {
            guard let url = urlSchemeTask.request.url,
                  let path = Self.safePath(for: url) else {
                urlSchemeTask.didFailWithError(PlayerResourceError.invalidRequest)
                return
            }
            do {
                let (fileURL, mimeType, textEncoding) = try self.resource(for: path)
                let values = try fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
                guard values.isRegularFile == true else { throw PlayerResourceError.fileMissing }
                let handle = try FileHandle(forReadingFrom: fileURL)
                let state = ActiveTask(task: urlSchemeTask, fileHandle: handle)
                self.activeTasks[taskID] = state
                let headers = [
                    "Content-Type": textEncoding.map { "\(mimeType); charset=\($0)" } ?? mimeType,
                    "Content-Length": String(values.fileSize ?? 0),
                    "Cache-Control": "no-store",
                ]
                // A custom-scheme URLResponse has no HTTP success status. fetch() can
                // therefore expose status 0 / ok=false even though the bytes arrived.
                // Preserve the strict mimiplayer://app allowlist while giving fetch a
                // standards-shaped successful response for each approved resource.
                let response = HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: headers
                )!
                urlSchemeTask.didReceive(response)
                self.readNext(taskID, state: state)
            } catch {
                urlSchemeTask.didFailWithError(error)
            }
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        let taskID = ObjectIdentifier(urlSchemeTask as AnyObject)
        onMainQueue {
            guard let state = activeTasks.removeValue(forKey: taskID) else { return }
            state.cancelled = true
            if !state.readPending { try? state.fileHandle.close() }
        }
    }

    private func resource(for path: String) throws -> (URL, String, String?) {
        if path == "/source/current" {
            try validateSource(source)
            return (source.url, Self.mimeType(for: source.url.pathExtension), nil)
        }
        if path == "/soundfont/main" {
            try validateContentFile(soundFontURL, rootName: "soundfonts")
            return (soundFontURL, "application/octet-stream", nil)
        }
        if path == "/soundfonts/sonivox.sf2" {
            try validateContentFile(soundFontURL, rootName: "soundfonts")
            return (soundFontURL, "application/octet-stream", nil)
        }
        if path == "/storage/soundfonts/ukulele_fast.sf2", let ukuleleSoundFontURL {
            try validateContentFile(ukuleleSoundFontURL, rootName: "storage")
            return (ukuleleSoundFontURL, "application/octet-stream", nil)
        }

        let assets: [String: (String, String, String?)] = [
            "/index.html": ("index.html", "text/html", "utf-8"),
            "/player.css": ("player.css", "text/css", "utf-8"),
            "/score-rendering.bundle.js": ("score-rendering.bundle.js", "text/javascript", "utf-8"),
            "/player.js": ("player.js", "text/javascript", "utf-8"),
            "/ibe.bundle.js": ("ibe.bundle.js", "text/javascript", "utf-8"),
            "/practice-runtime.bundle.js": ("practice-runtime.bundle.js", "text/javascript", "utf-8"),
            "/guitar-audio.bundle.js": ("guitar-audio.bundle.js", "text/javascript", "utf-8"),
            "/ar.es.js": ("ar.es.js", "text/javascript", "utf-8"),
            "/alphaTab.js": ("alphaTab.js", "text/javascript", "utf-8"),
            "/_astro/alphaTab.core.mjs": ("_astro/alphaTab.core.mjs", "text/javascript", "utf-8"),
            "/_astro/alphaTab.worker.mjs": ("_astro/alphaTab.worker.mjs", "text/javascript", "utf-8"),
            "/_astro/alphaTab.worklet.mjs": ("_astro/alphaTab.worklet.mjs", "text/javascript", "utf-8"),
            "/font/Bravura.eot": ("font/Bravura.eot", "application/vnd.ms-fontobject", nil),
            "/font/Bravura.otf": ("font/Bravura.otf", "font/otf", nil),
            "/font/Bravura.svg": ("font/Bravura.svg", "image/svg+xml", "utf-8"),
            "/font/Bravura.woff": ("font/Bravura.woff", "font/woff", nil),
            "/font/Bravura.woff2": ("font/Bravura.woff2", "font/woff2", nil),
            "/font/CascadiaCode.ttf": ("font/CascadiaCode.ttf", "font/ttf", nil),
            "/font/CascadiaCode.woff2": ("font/CascadiaCode.woff2", "font/woff2", nil),
            "/font/FZXiaoBiaoSong.TTF": ("font/FZXiaoBiaoSong.TTF", "font/ttf", nil),
            "/font/FZXiaoBiaoSong.woff2": ("font/FZXiaoBiaoSong.woff2", "font/woff2", nil),
        ]
        guard let asset = assets[path] else { throw PlayerResourceError.notWhitelisted }
        let url = playerRoot.appendingPathComponent(asset.0)
            .standardizedFileURL
            .resolvingSymlinksInPath()
            .standardizedFileURL
        guard Self.contains(url, inside: playerRoot), FileManager.default.fileExists(atPath: url.path) else {
            throw PlayerResourceError.assetMissing(asset.0)
        }
        return (url, asset.1, asset.2)
    }

    private func validateSource(_ source: NativePlayerSource) throws {
        let canonical = source.url.resolvingSymlinksInPath().standardizedFileURL
        if source.isImported {
            let importRoot = try AppPaths.userDataDirectory()
                .appendingPathComponent("Imports", isDirectory: true)
                .resolvingSymlinksInPath()
                .standardizedFileURL
            guard Self.contains(canonical, inside: importRoot) else { throw PlayerResourceError.outsideSourceRoot }
            let values = try canonical.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values.isRegularFile == true, let size = values.fileSize, size > 0, size <= 30 * 1024 * 1024 else {
                throw PlayerResourceError.invalidImportedFile
            }
        } else {
            try validateContentFile(canonical, rootName: "storage")
        }
    }

    private func validateContentFile(_ url: URL, rootName: String) throws {
        let root = contentRoot.appendingPathComponent(rootName, isDirectory: true)
            .resolvingSymlinksInPath()
            .standardizedFileURL
        let canonical = url.resolvingSymlinksInPath().standardizedFileURL
        guard Self.contains(canonical, inside: root) else { throw PlayerResourceError.outsideSourceRoot }
        let values = try canonical.resourceValues(forKeys: [.isRegularFileKey])
        guard values.isRegularFile == true else { throw PlayerResourceError.fileMissing }
    }

    private func readNext(_ id: ObjectIdentifier, state: ActiveTask) {
        guard activeTasks[id] === state, !state.cancelled else { return }
        state.readPending = true
        ioQueue.async { [weak self, state] in
            let result: Result<Data, Error>
            do {
                result = .success(try state.fileHandle.read(upToCount: 128 * 1024) ?? Data())
            } catch {
                result = .failure(error)
            }
            guard let self else {
                try? state.fileHandle.close()
                return
            }
            DispatchQueue.main.async {
                guard self.activeTasks[id] === state, !state.cancelled else {
                    try? state.fileHandle.close()
                    return
                }
                state.readPending = false
                switch result {
                case .failure(let error):
                    state.task.didFailWithError(error)
                    self.finish(id, state: state)
                case .success(let data) where data.isEmpty:
                    state.task.didFinish()
                    self.finish(id, state: state)
                case .success(let data):
                    state.task.didReceive(data)
                    self.readNext(id, state: state)
                }
            }
        }
    }

    private func finish(_ id: ObjectIdentifier, state: ActiveTask) {
        guard activeTasks[id] === state else { return }
        activeTasks.removeValue(forKey: id)
        try? state.fileHandle.close()
    }

    private func onMainQueue(_ action: () -> Void) {
        if Thread.isMainThread {
            action()
        } else {
            DispatchQueue.main.sync(execute: action)
        }
    }

    private static func safePath(for url: URL) -> String? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "mimiplayer",
              components.host == "app",
              components.percentEncodedQuery == nil,
              components.percentEncodedFragment == nil,
              !components.percentEncodedPath.contains("%"),
              !components.percentEncodedPath.contains("\\") else { return nil }
        let path = components.percentEncodedPath
        guard path.hasPrefix("/"), !path.split(separator: "/").contains("."), !path.split(separator: "/").contains("..") else {
            return nil
        }
        return path
    }

    private static func contains(_ candidate: URL, inside parent: URL) -> Bool {
        let candidatePath = candidate.standardizedFileURL.path
        let parentPath = parent.standardizedFileURL.path
        return candidatePath.hasPrefix(parentPath.hasSuffix("/") ? parentPath : parentPath + "/")
    }

    private static func mimeType(for extensionName: String) -> String {
        switch extensionName.lowercased() {
        case "ibe", "gp", "gp3", "gp4", "gp5", "gp6", "gp7", "gp8", "gpx", "musicxml", "xml", "xhe":
            return "application/octet-stream"
        default:
            return "application/octet-stream"
        }
    }
}

private enum PlayerResourceError: Error, LocalizedError {
    case invalidRequest
    case notWhitelisted
    case assetMissing(String)
    case outsideSourceRoot
    case invalidImportedFile
    case fileMissing

    var errorDescription: String? {
        switch self {
        case .invalidRequest: return "本地播放器收到无效资源请求。"
        case .notWhitelisted: return "本地播放器拒绝了未授权的资源路径。"
        case .assetMissing(let path): return "应用缺少播放器资源：\(path)"
        case .outsideSourceRoot: return "播放器拒绝了内容目录以外的文件。"
        case .invalidImportedFile: return "导入文件无效或超过 30 MiB。"
        case .fileMissing: return "本地播放器资源不存在或不是普通文件。"
        }
    }
}
