import Foundation
import MIMICore

/// Keeps the exact body accepted by the server available to the native reader.
/// The bundled catalog is read-only and cannot contain an article just published.
actor PublishedArticleCache {
    private struct Archive: Codable {
        var schemaVersion = 1
        var services: [String: [CatalogArticle]] = [:]
    }

    private let fileURL: URL
    private var archive: Archive?

    init(directory: URL) {
        fileURL = directory.appendingPathComponent("published-articles.json")
    }

    func articles(service: String) throws -> [CatalogArticle] {
        try readArchive().services[service] ?? []
    }

    func save(_ article: CatalogArticle, service: String) throws {
        var next = try readArchive()
        var rows = next.services[service] ?? []
        rows.removeAll { $0.id == article.id }
        rows.append(article)
        next.services[service] = rows
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let bytes = try encoder.encode(next)
        try bytes.write(to: fileURL, options: .atomic)
        archive = next
    }

    private func readArchive() throws -> Archive {
        if let archive { return archive }
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            let empty = Archive()
            archive = empty
            return empty
        }
        let bytes = try Data(contentsOf: fileURL, options: .mappedIfSafe)
        let decoded = try JSONDecoder().decode(Archive.self, from: bytes)
        guard decoded.schemaVersion == 1 else {
            throw CocoaError(.fileReadCorruptFile)
        }
        archive = decoded
        return decoded
    }
}
