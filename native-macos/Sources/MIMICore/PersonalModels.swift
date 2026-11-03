import Foundation

public struct PersonalScore: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var source: String
    public var sourceId: String
    public var revision: String
    public var title: String
    public var artist: String
    public var category: String
    public var format: String
    public var scoreUrl: String?
    public var assetId: String?
    public var originalAssetId: String?
    public var projectId: String?
    public var warnings: [String]?
    public var createdAt: Double
    public var updatedAt: Double

    public init(id: String, source: String, sourceId: String, revision: String, title: String, artist: String, category: String, format: String, scoreUrl: String? = nil, assetId: String? = nil, originalAssetId: String? = nil, projectId: String? = nil, warnings: [String]? = nil, createdAt: Double, updatedAt: Double) {
        self.id = id; self.source = source; self.sourceId = sourceId; self.revision = revision; self.title = title
        self.artist = artist; self.category = category; self.format = format; self.scoreUrl = scoreUrl
        self.assetId = assetId; self.originalAssetId = originalAssetId; self.projectId = projectId
        self.warnings = warnings; self.createdAt = createdAt; self.updatedAt = updatedAt
    }
}

public struct PersonalHistoryEntry: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var artist: String?
    public var url: String
    public var time: Double
    public var category: String?

    public init(id: String, title: String, artist: String? = nil, url: String, time: Double, category: String? = nil) {
        self.id = id; self.title = title; self.artist = artist; self.url = url; self.time = time; self.category = category
    }
}

public struct OriginalReference: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var fileName: String
    public var mimeType: String
    public var assetId: String
    public var savedAt: Double

    public init(id: String, fileName: String, mimeType: String, assetId: String, savedAt: Double) {
        self.id = id; self.fileName = fileName; self.mimeType = mimeType; self.assetId = assetId; self.savedAt = savedAt
    }
}

public enum PersonalSettingValue: Codable, Hashable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)

    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if let boolean = try? value.decode(Bool.self) { self = .bool(boolean); return }
        if let number = try? value.decode(Double.self), number.isFinite { self = .number(number); return }
        if let string = try? value.decode(String.self) { self = .string(string); return }
        throw DecodingError.dataCorruptedError(in: value, debugDescription: "Personal setting must be a string, finite number, or boolean")
    }

    public func encode(to encoder: Encoder) throws {
        var value = encoder.singleValueContainer()
        switch self {
        case .string(let string): try value.encode(string)
        case .number(let number):
            guard number.isFinite else { throw EncodingError.invalidValue(number, .init(codingPath: encoder.codingPath, debugDescription: "Personal setting number must be finite")) }
            try value.encode(number)
        case .bool(let boolean): try value.encode(boolean)
        }
    }
}

/// JSON representation is shared with the website's PersonalData schema 2.
/// Schema-1 values remain decodable for backup verification and are upgraded in memory on import.
public struct PersonalData: Codable, Hashable, Sendable {
    public var schemaVersion: Int
    public var revision: Int
    public var scores: [PersonalScore]
    public var favorites: [String]
    public var practiceItems: [PracticeItem]
    public var practiceFragments: [PracticeFragment]
    public var resumes: [PlayerResume]
    public var sessions: [PracticeSession]
    public var projects: [StudioProject]
    public var originals: [OriginalReference]
    public var history: [PersonalHistoryEntry]
    public var settings: [String: PersonalSettingValue]
    public var migrationCompleted: Bool

    public init(schemaVersion: Int = 2, revision: Int = 0, scores: [PersonalScore] = [], favorites: [String] = [], practiceItems: [PracticeItem] = [], practiceFragments: [PracticeFragment] = [], resumes: [PlayerResume] = [], sessions: [PracticeSession] = [], projects: [StudioProject] = [], originals: [OriginalReference] = [], history: [PersonalHistoryEntry] = [], settings: [String: PersonalSettingValue] = [:], migrationCompleted: Bool = true) {
        self.schemaVersion = schemaVersion; self.revision = revision; self.scores = scores; self.favorites = favorites
        self.practiceItems = practiceItems; self.practiceFragments = practiceFragments; self.resumes = resumes
        self.sessions = sessions; self.projects = projects; self.originals = originals; self.history = history
        self.settings = settings; self.migrationCompleted = migrationCompleted
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, revision, scores, favorites, practiceItems, practiceFragments, resumes, sessions
        case projects, originals, history, settings, migrationCompleted
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        revision = try values.decode(Int.self, forKey: .revision)
        scores = try values.decode([PersonalScore].self, forKey: .scores)
        favorites = try values.decode([String].self, forKey: .favorites)
        practiceItems = try values.decode([PracticeItem].self, forKey: .practiceItems)
        if schemaVersion == 1 {
            guard !values.contains(.practiceFragments) else {
                throw DecodingError.dataCorruptedError(forKey: .practiceFragments, in: values, debugDescription: "Schema 1 does not define practiceFragments")
            }
            practiceFragments = []
        } else {
            practiceFragments = try values.decode([PracticeFragment].self, forKey: .practiceFragments)
        }
        resumes = try values.decode([PlayerResume].self, forKey: .resumes)
        sessions = try values.decode([PracticeSession].self, forKey: .sessions)
        projects = try values.decode([StudioProject].self, forKey: .projects)
        originals = try values.decode([OriginalReference].self, forKey: .originals)
        history = try values.decode([PersonalHistoryEntry].self, forKey: .history)
        settings = try values.decode([String: PersonalSettingValue].self, forKey: .settings)
        migrationCompleted = try values.decode(Bool.self, forKey: .migrationCompleted)
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(schemaVersion, forKey: .schemaVersion)
        try values.encode(revision, forKey: .revision)
        try values.encode(scores, forKey: .scores)
        try values.encode(favorites, forKey: .favorites)
        try values.encode(practiceItems, forKey: .practiceItems)
        if schemaVersion != 1 { try values.encode(practiceFragments, forKey: .practiceFragments) }
        try values.encode(resumes, forKey: .resumes)
        try values.encode(sessions, forKey: .sessions)
        try values.encode(projects, forKey: .projects)
        try values.encode(originals, forKey: .originals)
        try values.encode(history, forKey: .history)
        try values.encode(settings, forKey: .settings)
        try values.encode(migrationCompleted, forKey: .migrationCompleted)
    }

    public var currentSchema: PersonalData {
        var value = self
        value.schemaVersion = 2
        if schemaVersion == 1 { value.practiceFragments = [] }
        return value
    }
}

public typealias PersonalDataSnapshot = PersonalData

public struct PersonalAsset: Sendable, Equatable {
    public var id: String
    public var bytes: Data
    public var mimeType: String

    public init(id: String, bytes: Data, mimeType: String) {
        self.id = id; self.bytes = bytes; self.mimeType = mimeType
    }
}

public struct PersonalAssetMetadata: Codable, Hashable, Sendable {
    public var id: String
    public var size: Int
    public var mimeType: String

    public init(id: String, size: Int, mimeType: String) { self.id = id; self.size = size; self.mimeType = mimeType }
}
