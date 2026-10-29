import Foundation

public enum AppPathError: Error, LocalizedError {
    case invalidReference
    case outsideContent

    public var errorDescription: String? {
        switch self {
        case .invalidReference: return "曲谱资源引用无效或不受支持。"
        case .outsideContent: return "曲谱资源引用超出了应用内容目录。"
        }
    }
}

public enum AppPaths {
    public static func contentRoot(bundle: Bundle = .main) -> URL? {
        if let configured = ProcessInfo.processInfo.environment["MIMI_CONTENT_ROOT"], !configured.isEmpty {
            let root = URL(fileURLWithPath: configured, isDirectory: true).standardizedFileURL
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                return nil
            }
            return root
        }

        guard let resourceURL = bundle.resourceURL else { return nil }
        let root = resourceURL.appendingPathComponent("Content", isDirectory: true).standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return nil
        }
        return root
    }

    public static func catalogURL(contentRoot: URL) -> URL {
        contentRoot.appendingPathComponent("catalog.sqlite", isDirectory: false)
    }

    public static func resolve(reference: String, contentRoot: URL) throws -> URL {
        guard !reference.isEmpty, !reference.contains("\0"), !reference.contains("\\"),
              !reference.contains("?"), !reference.contains("#"),
              let decoded = reference.removingPercentEncoding else {
            throw AppPathError.invalidReference
        }
        guard !decoded.contains("\0"), !decoded.contains("\\") else {
            throw AppPathError.invalidReference
        }

        let relative = decoded.hasPrefix("/") ? String(decoded.dropFirst()) : decoded
        guard !relative.hasPrefix("/") else { throw AppPathError.invalidReference }
        let components = relative.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard components.count >= 2,
              components[0] == "storage" || components[0] == "soundfonts",
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw AppPathError.invalidReference
        }

        let root = contentRoot.standardizedFileURL.resolvingSymlinksInPath().standardizedFileURL
        var candidate = root
        for component in components { candidate.appendPathComponent(component, isDirectory: false) }
        candidate = candidate.standardizedFileURL

        guard contains(candidate, inside: root) else { throw AppPathError.outsideContent }
        let allowedRoot = root.appendingPathComponent(components[0], isDirectory: true).standardizedFileURL
        guard contains(candidate, inside: allowedRoot) else { throw AppPathError.outsideContent }

        let resolvedRoot = allowedRoot.resolvingSymlinksInPath().standardizedFileURL
        let resolvedCandidate = candidate.resolvingSymlinksInPath().standardizedFileURL
        guard contains(resolvedRoot, inside: root),
              contains(resolvedCandidate, inside: resolvedRoot),
              contains(resolvedCandidate, inside: root) else {
            throw AppPathError.outsideContent
        }
        return candidate
    }

    public static func userDataDirectory() throws -> URL {
#if MIMI_RUNTIME_DIAGNOSTICS
        if let configured = ProcessInfo.processInfo.environment["MIMI_RUNTIME_DATA_ROOT"], !configured.isEmpty {
            let directory = URL(fileURLWithPath: configured, isDirectory: true).standardizedFileURL
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            return directory
        }
#endif
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = support.appendingPathComponent("com.mimi.guitar.mac", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func contains(_ candidate: URL, inside parent: URL) -> Bool {
        let candidatePath = candidate.standardizedFileURL.path
        let parentPath = parent.standardizedFileURL.path
        return candidatePath == parentPath || candidatePath.hasPrefix(parentPath.hasSuffix("/") ? parentPath : parentPath + "/")
    }
}
