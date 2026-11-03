import CoreFoundation
import CryptoKit
import Foundation
import JavaScriptCore

private let personalCanonicalContextKey = "MIMICore.PersonalBackup.JavaScriptCoreCanonicalizer"

public enum PersonalBackupFormat {
    public static let v1 = "mimi-personal-backup"
    public static let v2 = "mimi-personal-backup-volume"
    public static let volumeMIMEType = "application/vnd.mimi.personal-backup-volume"
    public static let volumeMagic = Data("MIMI2VOL".utf8)
}

public struct PersonalBackupAssetDescriptor: Codable, Hashable, Sendable {
    public let id: String
    public let mimeType: String
    public let size: Int

    public init(id: String, mimeType: String, size: Int) {
        self.id = id
        self.mimeType = mimeType
        self.size = size
    }
}

public struct PersonalBackupV1Manifest: Codable, Hashable, Sendable {
    public let formatVersion: Int
    public let schemaVersion: Int
    public let revision: Int
    public let generatedAt: String
    public let counts: [String: Int]
    public let assets: [PersonalBackupAssetDescriptor]
    public let payloadSha256: String
    public let assetBytes: Int

    public init(formatVersion: Int, schemaVersion: Int, revision: Int, generatedAt: String, counts: [String: Int], assets: [PersonalBackupAssetDescriptor], payloadSha256: String, assetBytes: Int) {
        self.formatVersion = formatVersion
        self.schemaVersion = schemaVersion
        self.revision = revision
        self.generatedAt = generatedAt
        self.counts = counts
        self.assets = assets
        self.payloadSha256 = payloadSha256
        self.assetBytes = assetBytes
    }
}

public struct PersonalBackupV1Preview: Sendable {
    public let format: String
    public let manifest: PersonalBackupV1Manifest
    public let data: PersonalData
    public let assets: [PersonalAsset]
    public let fileSize: Int
    public let expectedRevision: Int
    let verifiedPayloadSha256: String
    let verifiedDataFingerprint: String

    init(manifest: PersonalBackupV1Manifest, data: PersonalData, assets: [PersonalAsset], fileSize: Int, expectedRevision: Int, verifiedPayloadSha256: String, verifiedDataFingerprint: String) {
        self.format = PersonalBackupFormat.v1
        self.manifest = manifest
        self.data = data
        self.assets = assets
        self.fileSize = fileSize
        self.expectedRevision = expectedRevision
        self.verifiedPayloadSha256 = verifiedPayloadSha256
        self.verifiedDataFingerprint = verifiedDataFingerprint
    }
}

public struct PersonalBackupV2Chunk: Codable, Hashable, Sendable {
    public let assetId: String
    public let chunkIndex: Int
    public let byteLength: Int
    public let sha256: String

    public init(assetId: String, chunkIndex: Int, byteLength: Int, sha256: String) {
        self.assetId = assetId
        self.chunkIndex = chunkIndex
        self.byteLength = byteLength
        self.sha256 = sha256
    }
}

public struct PersonalBackupV2Asset: Codable, Hashable, Sendable {
    public let id: String
    public let mimeType: String
    public let size: Int
    public let chunkCount: Int

    public init(id: String, mimeType: String, size: Int, chunkCount: Int) {
        self.id = id
        self.mimeType = mimeType
        self.size = size
        self.chunkCount = chunkCount
    }
}

public struct PersonalBackupV2Volume: Codable, Hashable, Sendable {
    public let sequence: Int
    public let payloadBytes: Int
    public let payloadSha256: String
    public let byteLength: Int
    public let chunks: [PersonalBackupV2Chunk]

    public init(sequence: Int, payloadBytes: Int, payloadSha256: String, byteLength: Int, chunks: [PersonalBackupV2Chunk]) {
        self.sequence = sequence
        self.payloadBytes = payloadBytes
        self.payloadSha256 = payloadSha256
        self.byteLength = byteLength
        self.chunks = chunks
    }
}

public struct PersonalBackupV2Manifest: Codable, Hashable, Sendable {
    public let formatVersion: Int
    public let snapshotId: String
    public let schemaVersion: Int
    public let revision: Int
    public let generatedAt: String
    public let counts: [String: Int]
    public let assetBytes: Int
    public let assets: [PersonalBackupV2Asset]
    public let volumes: [PersonalBackupV2Volume]
    public let data: PersonalData
    public let snapshotSha256: String

    public init(formatVersion: Int, snapshotId: String, schemaVersion: Int, revision: Int, generatedAt: String, counts: [String: Int], assetBytes: Int, assets: [PersonalBackupV2Asset], volumes: [PersonalBackupV2Volume], data: PersonalData, snapshotSha256: String) {
        self.formatVersion = formatVersion
        self.snapshotId = snapshotId
        self.schemaVersion = schemaVersion
        self.revision = revision
        self.generatedAt = generatedAt
        self.counts = counts
        self.assetBytes = assetBytes
        self.assets = assets
        self.volumes = volumes
        self.data = data
        self.snapshotSha256 = snapshotSha256
    }
}

public struct PersonalBackupV2Preview: Sendable {
    public let format: String
    public let manifest: PersonalBackupV2Manifest
    public let data: PersonalData
    public let fileSize: Int
    public let volumeCount: Int
    public let assetBytes: Int
    public let assetCount: Int
    public let expectedRevision: Int
    public let stagingSessionID: String
    let rawManifest: Data

    init(manifest: PersonalBackupV2Manifest, fileSize: Int, expectedRevision: Int, stagingSessionID: String, rawManifest: Data) {
        self.format = PersonalBackupFormat.v2
        self.manifest = manifest
        self.data = manifest.data
        self.fileSize = fileSize
        self.volumeCount = manifest.volumes.count
        self.assetBytes = manifest.assetBytes
        self.assetCount = manifest.assets.count
        self.expectedRevision = expectedRevision
        self.stagingSessionID = stagingSessionID
        self.rawManifest = rawManifest
    }
}

public struct PersonalBackupV2Export: Sendable {
    public let manifestURL: URL
    public let volumeURLs: [URL]
    public let manifest: PersonalBackupV2Manifest
    public let totalFileBytes: Int

    public init(manifestURL: URL, volumeURLs: [URL], manifest: PersonalBackupV2Manifest, totalFileBytes: Int) {
        self.manifestURL = manifestURL
        self.volumeURLs = volumeURLs
        self.manifest = manifest
        self.totalFileBytes = totalFileBytes
    }
}

public enum PersonalBackupError: Error, LocalizedError, Sendable {
    case invalid(String)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .invalid(let detail): return detail
        case .cancelled: return "备份操作已取消；当前资料保持不变。"
        }
    }
}

func canonicalPersonalJSON(_ value: Any) -> String {
    // The web contract hashes JSON.parse(...) output using ECMAScript
    // JSON.stringify semantics. Run that same operation here so NSNumber
    // representations such as 1.0, exponent boundaries and negative zero do
    // not drift from JavaScript's Number serialization.
    let encoded: Data
    do { encoded = try JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed, .withoutEscapingSlashes]) }
    catch { preconditionFailure("Canonical JSON input is not a JSON value: \(error)") }
    guard let json = String(data: encoded, encoding: .utf8) else { preconditionFailure("JSONSerialization returned invalid UTF-8") }
    let context: JSContext
    if let cached = Thread.current.threadDictionary[personalCanonicalContextKey] as? JSContext {
        context = cached
    } else {
        guard let created = JSContext() else { preconditionFailure("Could not prepare the JavaScriptCore canonical JSON context") }
        context = created
        Thread.current.threadDictionary[personalCanonicalContextKey] = created
    }
    context.setObject(json as NSString, forKeyedSubscript: "__mimiCanonicalInput" as NSString)
    let script = """
    (function canonicalJson(value) {
      if (value === undefined) return 'null';
      if (value === null || typeof value !== 'object') return JSON.stringify(value);
      if (Array.isArray(value)) return '[' + value.map(canonicalJson).join(',') + ']';
      return '{' + Object.keys(value).filter(function (key) { return value[key] !== undefined; }).sort().map(function (key) {
        return JSON.stringify(key) + ':' + canonicalJson(value[key]);
      }).join(',') + '}';
    })(JSON.parse(__mimiCanonicalInput))
    """
    guard let result = context.evaluateScript(script), !result.isUndefined, let canonical = result.toString() else {
        preconditionFailure("JavaScriptCore failed to canonicalize a validated JSON value")
    }
    return canonical
}

func personalJSONObject<T: Encodable>(_ value: T) throws -> Any {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.withoutEscapingSlashes]
    let data = try encoder.encode(value)
    return try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
}

func personalCanonicalData(_ value: Any) -> Data {
    Data(canonicalPersonalJSON(value).utf8)
}

func backupDataCounts(_ data: PersonalData, assetCount: Int) -> [String: Int] {
    var result = [
        "scores": data.scores.count,
        "favorites": data.favorites.count,
        "practiceItems": data.practiceItems.count,
        "resumes": data.resumes.count,
        "sessions": data.sessions.count,
        "projects": data.projects.count,
        "originals": data.originals.count,
        "history": data.history.count,
        "assets": assetCount,
    ]
    if data.schemaVersion == 2 { result["practiceFragments"] = data.practiceFragments.count }
    return result
}

func requiredPersonalAssetIDs(_ data: PersonalData) -> Set<String> {
    var ids = Set<String>()
    for score in data.scores {
        if let assetId = score.assetId { ids.insert(assetId) }
        if let originalAssetId = score.originalAssetId { ids.insert(originalAssetId) }
    }
    for original in data.originals { ids.insert(original.assetId) }
    return ids
}

func mergePersonalBackupData(current: PersonalData, incomingData: PersonalData) throws -> PersonalData {
    var incoming = incomingData.currentSchema
    let encoded = try personalJSONObject(incoming)
    guard let root = encoded as? [String: Any] else { throw PersonalStoreError.validation("恢复资料无法读取") }
    try PersonalDataValidator.validate(incoming, strictProjects: true, rawProjects: root["projects"] as? [Any])

    var originals = Dictionary(uniqueKeysWithValues: current.originals.map { ($0.id, $0) })
    var originalOrder = current.originals.map(\.id)
    var originalIDMap: [String: String] = [:]
    for candidate in incoming.originals {
        guard let old = originals[candidate.id] else { originals[candidate.id] = candidate; originalOrder.append(candidate.id); continue }
        if old.assetId != candidate.assetId {
            let reusable = reusableConflictID(sourceID: candidate.id, candidate: candidate, existing: Array(originals.values), marker: "backup")
            let id: String
            if let reusable { id = reusable }
            else { id = conflictID(sourceID: candidate.id, serialized: try canonicalValue(candidate), existing: Set(originals.keys), marker: "backup") }
            originalIDMap[candidate.id] = id
            if reusable == nil {
                var copy = candidate
                copy.id = id
                originals[id] = copy
                originalOrder.append(id)
            }
        }
    }
    for index in incoming.projects.indices {
        if let source = incoming.projects[index].source, let mapped = originalIDMap[source.id] {
            var changed = source
            changed.id = mapped
            incoming.projects[index].source = changed
        }
    }

    var projects = Dictionary(uniqueKeysWithValues: current.projects.map { ($0.id, $0) })
    var projectOrder = current.projects.map(\.id)
    var projectIDMap: [String: String] = [:]
    for index in incoming.projects.indices {
        let candidate = incoming.projects[index]
        guard let old = projects[candidate.id] else { projects[candidate.id] = candidate; projectOrder.append(candidate.id); continue }
        if try canonicalValue(old) != canonicalValue(candidate) {
            let reusable = reusableConflictID(sourceID: candidate.id, candidate: candidate, existing: Array(projects.values), marker: "backup")
            let id: String
            if let reusable { id = reusable }
            else { id = conflictID(sourceID: candidate.id, serialized: try canonicalValue(candidate), existing: Set(projects.keys), marker: "backup") }
            projectIDMap[candidate.id] = id
            var copy = candidate
            copy.id = id
            incoming.projects[index] = copy
            if reusable == nil {
                projects[id] = copy
                projectOrder.append(id)
            }
        }
    }
    for index in incoming.scores.indices {
        if let projectID = incoming.scores[index].projectId, let mapped = projectIDMap[projectID] { incoming.scores[index].projectId = mapped }
    }

    var scores = Dictionary(uniqueKeysWithValues: current.scores.map { ($0.id, $0) })
    var scoreOrder = current.scores.map(\.id)
    var scoreIDMap: [String: String] = [:]
    for index in incoming.scores.indices {
        var candidate = incoming.scores[index]
        let sourceID = candidate.id
        if let old = scores[sourceID], old.revision != candidate.revision {
            let id = stableScoreConflictID(sourceID: sourceID, scoreRevision: candidate.revision, existing: scores)
            scoreIDMap[sourceID] = id
            candidate.id = id
            incoming.scores[index] = candidate
            if let previousCopy = scores[id] {
                if candidate.updatedAt >= previousCopy.updatedAt { scores[id] = candidate }
            } else { scores[id] = candidate; scoreOrder.append(id) }
        } else if let old = scores[sourceID] {
            if candidate.updatedAt >= old.updatedAt { scores[sourceID] = candidate }
        } else {
            scores[sourceID] = candidate
            scoreOrder.append(sourceID)
        }
    }
    let remapScoreID: (String) -> String = { scoreIDMap[$0] ?? $0 }
    for index in incoming.practiceItems.indices { incoming.practiceItems[index].scoreId = remapScoreID(incoming.practiceItems[index].scoreId) }
    for index in incoming.resumes.indices { incoming.resumes[index].scoreId = remapScoreID(incoming.resumes[index].scoreId) }
    for index in incoming.sessions.indices { incoming.sessions[index].scoreId = remapScoreID(incoming.sessions[index].scoreId) }
    incoming.favorites = incoming.favorites.map(remapScoreID)

    var favorites = current.favorites
    var favoriteSet = Set(favorites)
    for id in incoming.favorites where favoriteSet.insert(id).inserted { favorites.append(id) }
    let practiceItems = keyedMerge(current.practiceItems, incoming.practiceItems, key: { $0.scoreId }, timestamp: { $0.updatedAt })
    let resumes = keyedMerge(current.resumes, incoming.resumes, key: { $0.scoreId }, timestamp: { $0.updatedAt })
    let sessions = try mergeSessions(current.sessions, incoming.sessions)
    let fragments = mergePracticeFragments(current.practiceFragments, incoming.practiceFragments, scoreIDMap: scoreIDMap)
    var history = Dictionary<String, PersonalHistoryEntry>()
    var historyOrder: [String] = []
    for entry in current.history + incoming.history {
        let key = "\(entry.id)\0\(entry.url)\0\(entry.time)"
        if history[key] == nil { historyOrder.append(key) }
        history[key] = entry
    }
    var indexedHistory: [(index: Int, entry: PersonalHistoryEntry)] = []
    for (index, key) in historyOrder.enumerated() {
        if let entry = history[key] { indexedHistory.append((index: index, entry: entry)) }
    }
    indexedHistory.sort { lhs, rhs in
        if lhs.entry.time == rhs.entry.time { return lhs.index < rhs.index }
        return lhs.entry.time > rhs.entry.time
    }
    let orderedHistory = indexedHistory.map(\.entry)
    return PersonalData(
        schemaVersion: 2,
        revision: current.revision,
        scores: scoreOrder.compactMap { scores[$0] },
        favorites: favorites,
        practiceItems: practiceItems,
        practiceFragments: fragments,
        resumes: resumes,
        sessions: sessions,
        projects: projectOrder.compactMap { projects[$0] },
        originals: originalOrder.compactMap { originals[$0] },
        history: orderedHistory,
        settings: current.settings.merging(incoming.settings) { _, newer in newer },
        migrationCompleted: current.migrationCompleted && incoming.migrationCompleted
    )
}

private func mergeSessions(_ current: [PracticeSession], _ incoming: [PracticeSession]) throws -> [PracticeSession] {
    var result = Dictionary(uniqueKeysWithValues: current.map { ($0.id, $0) })
    var order = current.map(\.id)
    for candidate in incoming {
        guard let old = result[candidate.id] else { result[candidate.id] = candidate; order.append(candidate.id); continue }
        guard old.scoreId == candidate.scoreId, old.scoreRevision == candidate.scoreRevision else {
            throw PersonalStoreError.validation("练习会话 \(candidate.id) 在同一稳定 ID 下关联了不同曲谱版本；为避免重复计时，本次恢复已取消")
        }
        var byID = Dictionary(uniqueKeysWithValues: old.slices.map { ($0.id, $0) })
        for slice in candidate.slices {
            if let previous = byID[slice.id] {
                if slice.sequence > previous.sequence || (slice.sequence == previous.sequence && slice.durationMs > previous.durationMs) { byID[slice.id] = slice }
            } else { byID[slice.id] = slice }
        }
        var bySequence: [String: PracticeSlice] = [:]
        for slice in byID.values {
            let key = "\(slice.epoch)\0\(slice.sequence)"
            if let previous = bySequence[key] {
                if slice.durationMs > previous.durationMs { bySequence[key] = slice }
            } else { bySequence[key] = slice }
        }
        var latest = candidate.updatedAt >= old.updatedAt ? candidate : old
        latest.slices = bySequence.values.sorted { $0.epoch == $1.epoch ? $0.sequence < $1.sequence : $0.epoch < $1.epoch }
        result[candidate.id] = latest
    }
    return order.compactMap { result[$0] }
}

private func mergePracticeFragments(_ current: [PracticeFragment], _ incoming: [PracticeFragment], scoreIDMap: [String: String]) -> [PracticeFragment] {
    var result = Dictionary(uniqueKeysWithValues: current.map { ($0.id, $0) })
    for sourceCandidate in incoming {
        var candidate = sourceCandidate
        let originalScoreID = candidate.scoreId
        candidate.scoreId = scoreIDMap[originalScoreID] ?? originalScoreID
        if let source = result[candidate.id], source.scoreId == originalScoreID, source.scoreRevision == candidate.scoreRevision {
            guard practiceFragmentCandidateWins(candidate, over: source) else { continue }
            if candidate.scoreId == originalScoreID { result[candidate.id] = candidate }
            else {
                let id = stablePracticeFragmentConflictID(sourceID: candidate.id, scoreID: candidate.scoreId, scoreRevision: candidate.scoreRevision, existing: result)
                candidate.id = id
                if let branch = result[id], branch.scoreId == candidate.scoreId, branch.scoreRevision == candidate.scoreRevision {
                    if practiceFragmentCandidateWins(candidate, over: branch) { result[id] = candidate }
                } else { result[id] = candidate }
            }
            continue
        }
        if let old = result[candidate.id] {
            if old.scoreId == candidate.scoreId && old.scoreRevision == candidate.scoreRevision {
                if practiceFragmentCandidateWins(candidate, over: old) { result[candidate.id] = candidate }
            } else {
                let id = stablePracticeFragmentConflictID(sourceID: candidate.id, scoreID: candidate.scoreId, scoreRevision: candidate.scoreRevision, existing: result)
                candidate.id = id
                if let branch = result[id], branch.scoreId == candidate.scoreId, branch.scoreRevision == candidate.scoreRevision {
                    if practiceFragmentCandidateWins(candidate, over: branch) { result[id] = candidate }
                } else { result[id] = candidate }
            }
        } else { result[candidate.id] = candidate }
    }
    return result.values.sorted { $0.id < $1.id }
}

private func practiceFragmentCandidateWins(_ candidate: PracticeFragment, over old: PracticeFragment) -> Bool {
    if candidate.updatedAt != old.updatedAt { return candidate.updatedAt > old.updatedAt }
    if (candidate.deletedAt != nil) != (old.deletedAt != nil) { return candidate.deletedAt != nil }
    return ((try? canonicalValue(candidate)) ?? "") >= ((try? canonicalValue(old)) ?? "")
}

private func keyedMerge<T>(_ old: [T], _ new: [T], key: (T) -> String, timestamp: (T) -> Double) -> [T] {
    var result: [String: T] = [:]
    var order: [String] = []
    for entry in old {
        let entryKey = key(entry)
        if result[entryKey] == nil { order.append(entryKey) }
        result[entryKey] = entry
    }
    for candidate in new {
        let candidateKey = key(candidate)
        if let previous = result[candidateKey], timestamp(candidate) < timestamp(previous) { continue }
        if result[candidateKey] == nil { order.append(candidateKey) }
        result[candidateKey] = candidate
    }
    return order.compactMap { result[$0] }
}

private func reusableConflictID<T: Encodable & Identifiable>(sourceID: String, candidate: T, existing: [T], marker: String) -> String? where T.ID == String {
    guard let serialized = try? canonicalValue(candidate) else { return nil }
    let base = conflictID(sourceID: sourceID, serialized: serialized, existing: [], marker: marker)
    for item in existing where item.id == base || item.id.hasPrefix(base + "-") {
        guard let restored = try? personalJSONObject(item), var object = restored as? [String: Any] else { continue }
        object["id"] = sourceID
        if canonicalPersonalJSON(object) == serialized { return item.id }
    }
    return nil
}

private func conflictID(sourceID: String, serialized: String, existing: Set<String>, marker: String) -> String {
    var hash: UInt32 = 2_166_136_261
    for unit in serialized.utf16 { hash = (hash ^ UInt32(unit)) &* 16_777_619 }
    let suffix = String(format: "%08x", hash)
    let root = "\(sourceID)~\(marker)-\(suffix)"
    var candidate = root
    var serial = 2
    while existing.contains(candidate) { candidate = "\(root)-\(serial)"; serial += 1 }
    return candidate
}

private func stableIdentityHash(_ value: String) -> String {
    let seeds: [UInt32] = [0x811c9dc5, 0x9e3779b9, 0x85ebca6b, 0xc2b2ae35]
    return seeds.enumerated().map { slot, seed in
        var hash = seed
        let multiplier = UInt32(0x01000193 + slot * 2)
        for unit in value.utf16 { hash = (hash ^ (UInt32(unit) &+ UInt32(slot * 17))) &* multiplier }
        return String(format: "%08x", hash)
    }.joined()
}

private func stableScoreConflictID(sourceID: String, scoreRevision: String, existing: [String: PersonalScore]) -> String {
    let identity = canonicalPersonalJSON(["sourceId": sourceID, "scoreRevision": scoreRevision])
    let root = "\(sourceID)~backup-\(stableIdentityHash(identity))"
    var candidate = root
    var serial = 2
    while let present = existing[candidate], present.revision != scoreRevision { candidate = "\(root)-\(serial)"; serial += 1 }
    return candidate
}

private func stablePracticeFragmentConflictID(sourceID: String, scoreID: String, scoreRevision: String, existing: [String: PracticeFragment]) -> String {
    let identity = canonicalPersonalJSON(["scoreId": scoreID, "scoreRevision": scoreRevision])
    let root = "\(sourceID)~backup-\(stableIdentityHash(identity))"
    var candidate = root
    var serial = 2
    while let present = existing[candidate] {
        if present.scoreId == scoreID && present.scoreRevision == scoreRevision { return candidate }
        candidate = "\(root)-\(serial)"
        serial += 1
    }
    return candidate
}

private func canonicalValue<T: Encodable>(_ value: T) throws -> String {
    canonicalPersonalJSON(try personalJSONObject(value))
}
