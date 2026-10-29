import CSQLite
import CryptoKit
import Foundation

public struct PersonalState: Codable, Sendable {
    public var favoriteIDs: Set<String>
    public var queueIDs: [String]
    public var recentIDs: [String]

    public init() {
        favoriteIDs = []
        queueIDs = []
        recentIDs = []
    }
}

public enum PersonalBackupLimits {
    public static let maximumAssetBytes = 30 * 1_024 * 1_024
    public static let maximumAssetCount = 500
    public static let maximumEntityCount = 10_000
    public static let maximumManifestBytes = 64 * 1_024 * 1_024
    public static let volumeBytes = 8 * 1_024 * 1_024
    public static let maximumVolumeCount = 128
    public static let maximumBackupBytes = 1_024 * 1_024 * 1_024
    public static let maximumReferencedAssetBytes = 927 * 1_024 * 1_024
    public static let maximumDataJSONBytes = 60 * 1_024 * 1_024
    public static let maximumV1BackupBytes = 64 * 1_024 * 1_024
}

public enum PersonalStoreError: Error, LocalizedError, Sendable {
    case storage(String)
    case revisionConflict(expected: Int, actual: Int)
    case recordConflict(String)
    case validation(String)
    case assetMissing(String)
    case assetIntegrity(String)

    public var errorDescription: String? {
        switch self {
        case .storage(let detail): return "保存本地个人资料失败：\(detail)"
        case .revisionConflict(let expected, let actual): return "个人资料已更新（预期 revision \(expected)，当前为 \(actual)）；请重新读取后再保存。"
        case .recordConflict(let detail): return detail
        case .validation(let detail): return detail
        case .assetMissing(let id): return "个人资料引用的附件不存在：\(id)"
        case .assetIntegrity(let detail): return detail
        }
    }
}

/// User-owned data is stored in a separate writable database from the bundled catalog.
public actor PersonalStore {
    private var database: OpaquePointer?

    /// `directory` is the app's Application Support directory, not the catalog directory.
    public init(directory: URL) throws {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            throw PersonalStoreError.storage(error.localizedDescription)
        }

        let databaseURL = directory.appendingPathComponent("personal.sqlite", isDirectory: false)
        var opened: OpaquePointer?
        let result = sqlite3_open_v2(databaseURL.path, &opened, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil)
        guard result == SQLITE_OK, let opened else {
            let detail = opened.map { String(cString: sqlite3_errmsg($0)) } ?? "SQLite returned code \(result)"
            if let opened { sqlite3_close(opened) }
            throw PersonalStoreError.storage(detail)
        }
        database = opened
        sqlite3_busy_timeout(opened, 2_000)
        do {
            try Self.initializeSchema(database: opened)
            try Self.migrateLegacyCollections(database: opened)
            try Self.migrateCatalogScoreIDs(database: opened)
        } catch {
            sqlite3_close(opened)
            database = nil
            throw error
        }
    }

    deinit {
        if let database { sqlite3_close(database) }
    }

    /// Returns a normalized schema-2 snapshot. Schema-1 rows are upgraded in memory.
    public func snapshot() throws -> PersonalData {
        guard let database else { throw PersonalStoreError.storage("数据库连接已关闭") }
        return try Self.readSnapshot(database: database).currentSchema
    }

    /// Atomically replaces the personal snapshot and stages content-addressed assets.
    /// A supplied revision provides compare-and-swap protection against stale editors.
    @discardableResult
    public func commit(_ data: PersonalData, assets: [PersonalAsset] = [], expectedRevision: Int? = nil) throws -> PersonalData {
        guard let database else { throw PersonalStoreError.storage("数据库连接已关闭") }
        let preparedAssets = try Self.prepareAssets(assets)
        let expected = expectedRevision ?? data.revision
        return try Self.withTransaction(database: database) { database in
            let current = try Self.readSnapshot(database: database)
            guard current.revision == expected else {
                throw PersonalStoreError.revisionConflict(expected: expected, actual: current.revision)
            }
            var proposed = data.currentSchema
            return try Self.commitSnapshot(database: database, current: current, proposed: &proposed, incomingAssets: preparedAssets, removeStageSession: nil)
        }
    }

    /// Reads one immutable, content-addressed personal asset.
    public func asset(id: String) throws -> PersonalAsset? {
        guard let database else { throw PersonalStoreError.storage("数据库连接已关闭") }
        let normalized = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        return try Self.readAsset(database: database, id: normalized)
    }

    /// Returns the stored size and MIME type for the requested IDs that exist.
    public func assetMetadata(ids: [String]) throws -> [PersonalAssetMetadata] {
        guard let database else { throw PersonalStoreError.storage("数据库连接已关闭") }
        var seen = Set<String>()
        var result: [PersonalAssetMetadata] = []
        for id in ids where seen.insert(id).inserted {
            if let metadata = try Self.readAssetMetadata(database: database, id: id) { result.append(metadata) }
        }
        return result
    }

    /// Backward-compatible catalog collection snapshot used by the current shell.
    public func state() throws -> PersonalState {
        guard let database else { throw PersonalStoreError.storage("数据库连接已关闭") }
        var result = PersonalState()
        let data = try Self.readSnapshot(database: database).currentSchema
        result.favoriteIDs = Set(data.favorites.map(Self.legacyCatalogID))
        result.queueIDs = data.practiceItems.filter { $0.status != .archived }.sorted { $0.order == $1.order ? $0.scoreId < $1.scoreId : $0.order < $1.order }.map { Self.legacyCatalogID($0.scoreId) }
        result.recentIDs = Array(data.history.sorted { $0.time > $1.time }.prefix(500).map(\.id))
        return result
    }

    /// Adds a locally imported score and its original/playable bytes in one revision.
    @discardableResult
    public func importScore(
        originalFileName: String,
        originalBytes: Data,
        playableBytes: Data? = nil,
        title: String,
        artist: String = "",
        category: String = "guitar",
        format: String,
        warnings: [String] = [],
        expectedRevision: Int? = nil
    ) throws -> PersonalScore {
        guard !originalBytes.isEmpty else { throw PersonalStoreError.validation("文件为空，未保存任何个人资料") }
        guard originalBytes.count <= PersonalBackupLimits.maximumAssetBytes else { throw PersonalStoreError.validation("文件超过 30 MiB，未保存任何个人资料") }
        let resolvedFormat = Self.personalFormat(format)
        guard let resolvedFormat else { throw PersonalStoreError.validation("不支持保存此曲谱格式：\(format)") }
        let safeCategory = ["guitar", "ukulele", "bass"].contains(category) ? category : "guitar"
        let displayTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? URL(fileURLWithPath: originalFileName).deletingPathExtension().lastPathComponent : title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !displayTitle.isEmpty, displayTitle.count <= 500, artist.count <= 500 else { throw PersonalStoreError.validation("曲谱标题或演奏者名称无效") }
        let playable = playableBytes ?? originalBytes
        guard !playable.isEmpty, playable.count <= PersonalBackupLimits.maximumAssetBytes else { throw PersonalStoreError.validation("可播放曲谱内容为空或超过 30 MiB") }
        let originalID = Self.sha256(originalBytes)
        let playableID = Self.sha256(playable)
        let id = "private:\(UUID().uuidString.lowercased())"
        let originalRefID = "original:\(UUID().uuidString.lowercased())"
        let now = Date().timeIntervalSince1970 * 1_000
        let originalMime = Self.mimeType(for: originalFileName, format: format)
        let assets = [
            PersonalAsset(id: originalID, bytes: originalBytes, mimeType: originalMime),
            PersonalAsset(id: playableID, bytes: playable, mimeType: "application/octet-stream"),
        ].reduce(into: [String: PersonalAsset]()) { map, asset in
            if map[asset.id] == nil { map[asset.id] = asset }
        }.values.sorted { $0.id < $1.id }
        var current = try snapshot()
        if let expectedRevision, current.revision != expectedRevision {
            throw PersonalStoreError.revisionConflict(expected: expectedRevision, actual: current.revision)
        }
        let expected = expectedRevision ?? current.revision
        let score = PersonalScore(
            id: id, source: "private", sourceId: id, revision: playableID, title: displayTitle, artist: artist,
            category: safeCategory, format: resolvedFormat, assetId: playableID, originalAssetId: originalID,
            warnings: warnings.isEmpty ? nil : warnings, createdAt: now, updatedAt: now
        )
        current.scores.append(score)
        current.originals.append(OriginalReference(id: originalRefID, fileName: originalFileName, mimeType: originalMime, assetId: originalID, savedAt: now))
        _ = try commit(current, assets: assets, expectedRevision: expected)
        return score
    }

    /// Creates or updates a project with both global and per-project compare-and-swap checks.
    @discardableResult
    public func saveProject(_ project: StudioProject, expectedUpdatedAt: Double? = nil, expectedRevision: Int? = nil) throws -> PersonalData {
        var data = try snapshot()
        if let expectedRevision, data.revision != expectedRevision { throw PersonalStoreError.revisionConflict(expected: expectedRevision, actual: data.revision) }
        let existing = data.projects.first(where: { $0.id == project.id })
        if let expectedUpdatedAt, existing?.updatedAt != expectedUpdatedAt {
            throw PersonalStoreError.recordConflict("工坊工程“\(project.title)”已在其他页面更新；为避免覆盖，请重新载入后再保存。")
        }
        if let index = data.projects.firstIndex(where: { $0.id == project.id }) { data.projects[index] = project }
        else { data.projects.append(project) }
        return try commit(data, expectedRevision: data.revision)
    }

    /// Saves a project, its optional original, and its optional playable practice copy atomically.
    /// `expectedUpdatedAt == nil` means that this project ID is expected not to exist.
    @discardableResult
    public func saveStudioProject(
        _ project: StudioProject,
        expectedUpdatedAt: Double?,
        original: OriginalReference? = nil,
        originalAsset: PersonalAsset? = nil,
        practiceScore: PersonalScore? = nil,
        practiceAsset: PersonalAsset? = nil,
        addToPractice: Bool = false
    ) throws -> PersonalData {
        guard let database else { throw PersonalStoreError.storage("数据库连接已关闭") }
        guard (original == nil) == (originalAsset == nil), (practiceScore == nil) == (practiceAsset == nil) else {
            throw PersonalStoreError.validation("工程原件或练习谱的附件信息不完整")
        }
        if let original, let originalAsset, original.assetId != originalAsset.id {
            throw PersonalStoreError.validation("工程原件引用与附件 ID 不一致")
        }
        if let practiceScore, let practiceAsset {
            guard practiceScore.source == "project", practiceScore.sourceId == project.id, practiceScore.projectId == project.id,
                  practiceScore.assetId == practiceAsset.id, practiceScore.revision == practiceAsset.id else {
                throw PersonalStoreError.validation("工程练习谱与可播放附件身份不一致")
            }
        }

        var assetsByID: [String: PersonalAsset] = [:]
        if let originalAsset { assetsByID[originalAsset.id] = originalAsset }
        if let practiceAsset { assetsByID[practiceAsset.id] = practiceAsset }
        let preparedAssets = try Self.prepareAssets(Array(assetsByID.values))
        return try Self.withTransaction(database: database) { database in
            let current = try Self.readSnapshot(database: database)
            var draft = current.currentSchema
            let existingProject = draft.projects.first(where: { $0.id == project.id })
            guard existingProject?.updatedAt == expectedUpdatedAt else {
                throw PersonalStoreError.recordConflict("工坊工程“\(project.title)”已在其他页面更新；为避免覆盖，请重新载入后再保存。")
            }
            let canonicalPracticeScoreID = "project:\(project.id)"
            let existingPracticeIndex = draft.scores.firstIndex(where: { $0.id == canonicalPracticeScoreID })
                ?? draft.scores.firstIndex(where: { $0.source == "project" && $0.sourceId == project.id || $0.projectId == project.id })
            let practiceScoreID = existingPracticeIndex.map { draft.scores[$0].id } ?? canonicalPracticeScoreID
            guard !addToPractice || practiceScore != nil else {
                throw PersonalStoreError.validation("加入待练需要先生成对应的可播放版本。")
            }
            guard practiceScore == nil || existingPracticeIndex != nil || addToPractice else {
                throw PersonalStoreError.recordConflict("这份工程尚无练习副本；请通过加入待练操作创建。")
            }
            if let practiceScore {
                guard practiceScore.id == canonicalPracticeScoreID || practiceScore.id == practiceScoreID else {
                    throw PersonalStoreError.recordConflict("工程练习副本身份已变化；请重新载入后再保存。")
                }
            }

            if let projectIndex = draft.projects.firstIndex(where: { $0.id == project.id }) { draft.projects[projectIndex] = project }
            else { draft.projects.append(project) }

            if let original {
                if let index = draft.originals.firstIndex(where: { $0.id == original.id }) { draft.originals[index] = original }
                else { draft.originals.append(original) }
            }

            if var practiceScore {
                practiceScore.id = practiceScoreID
                if let existingPracticeIndex {
                    let oldScore = draft.scores[existingPracticeIndex]
                    practiceScore.createdAt = oldScore.createdAt
                    if practiceScore.originalAssetId == nil { practiceScore.originalAssetId = oldScore.originalAssetId }
                    if practiceScore.warnings == nil { practiceScore.warnings = oldScore.warnings }
                    draft.scores[existingPracticeIndex] = practiceScore
                } else {
                    draft.scores.append(practiceScore)
                }
                if addToPractice {
                    if let itemIndex = draft.practiceItems.firstIndex(where: { $0.scoreId == practiceScoreID }) {
                        if draft.practiceItems[itemIndex].status == .archived {
                            let activeCount = draft.practiceItems.filter { $0.status != .archived }.count
                            draft.practiceItems[itemIndex].status = .todo
                            draft.practiceItems[itemIndex].order = Double(activeCount)
                            draft.practiceItems[itemIndex].updatedAt = project.updatedAt
                            Self.normalizePracticeQueue(&draft.practiceItems)
                        }
                    } else {
                        let activeCount = draft.practiceItems.filter { $0.status != .archived }.count
                        draft.practiceItems.append(PracticeItem(scoreId: practiceScoreID, status: .todo, note: "", order: Double(activeCount), updatedAt: project.updatedAt))
                        Self.normalizePracticeQueue(&draft.practiceItems)
                    }
                }
            }
            return try Self.commitSnapshot(database: database, current: current, proposed: &draft, incomingAssets: preparedAssets, removeStageSession: nil)
        }
    }

    /// Updates the selected score and joins or restores its practice item in one transaction.
    @discardableResult
    public func joinPractice(_ score: PersonalScore, now: Double = Date().timeIntervalSince1970 * 1_000) throws -> PersonalData {
        guard let database else { throw PersonalStoreError.storage("数据库连接已关闭") }
        return try Self.withTransaction(database: database) { database in
            let current = try Self.readSnapshot(database: database)
            var draft = current.currentSchema
            if let scoreIndex = draft.scores.firstIndex(where: { $0.id == score.id }) {
                var refreshed = score
                refreshed.createdAt = draft.scores[scoreIndex].createdAt
                refreshed.updatedAt = now
                draft.scores[scoreIndex] = refreshed
            } else {
                var added = score
                if added.createdAt <= 0 { added.createdAt = now }
                added.updatedAt = now
                draft.scores.append(added)
            }

            if let itemIndex = draft.practiceItems.firstIndex(where: { $0.scoreId == score.id }) {
                if draft.practiceItems[itemIndex].status == .archived {
                    let activeCount = draft.practiceItems.filter { $0.status != .archived }.count
                    draft.practiceItems[itemIndex].status = .todo
                    draft.practiceItems[itemIndex].order = Double(activeCount)
                    draft.practiceItems[itemIndex].updatedAt = now
                    Self.normalizePracticeQueue(&draft.practiceItems)
                } else {
                    draft.practiceItems[itemIndex].updatedAt = now
                }
            } else {
                let activeCount = draft.practiceItems.filter { $0.status != .archived }.count
                draft.practiceItems.append(PracticeItem(scoreId: score.id, status: .todo, note: "", order: Double(activeCount), updatedAt: now))
                Self.normalizePracticeQueue(&draft.practiceItems)
            }
            return try Self.commitSnapshot(database: database, current: current, proposed: &draft, incomingAssets: [], removeStageSession: nil)
        }
    }

    /// Ensures a score reference exists and marks it as actively being practiced.
    /// A supplied catalog item uses its exact raw ID, including any `catalog:` prefix.
    @discardableResult
    public func preparePracticeScore(scoreID: String, catalogItem: CatalogItem? = nil, now: Double = Date().timeIntervalSince1970 * 1_000) throws -> PersonalData {
        guard let database else { throw PersonalStoreError.storage("数据库连接已关闭") }
        return try Self.withTransaction(database: database) { database in
            let current = try Self.readSnapshot(database: database)
            var draft = current.currentSchema
            let targetID: String
            if let catalogItem {
                let rawID = try Self.validRawCatalogID(catalogItem.id)
                let canonicalID = Self.catalogScoreID(rawID: rawID)
                guard scoreID == rawID || scoreID == canonicalID else { throw PersonalStoreError.validation("曲库曲谱编号与元数据不一致") }
                targetID = Self.ensureCatalogScore(id: rawID, metadata: catalogItem, in: &draft).id
            } else if let existing = draft.scores.first(where: { $0.id == scoreID }) {
                targetID = existing.id
            } else if scoreID.hasPrefix("catalog:") {
                let rawID = try Self.validRawCatalogID(String(scoreID.dropFirst("catalog:".count)))
                targetID = Self.ensureCatalogScore(id: rawID, metadata: nil, in: &draft).id
            } else if scoreID.hasPrefix("project:") || scoreID.hasPrefix("private:") {
                throw PersonalStoreError.recordConflict("曲谱已被移除或不存在，请重新载入后再试。")
            } else {
                let rawID = try Self.validRawCatalogID(scoreID)
                targetID = Self.ensureCatalogScore(id: rawID, metadata: nil, in: &draft).id
            }

            if let itemIndex = draft.practiceItems.firstIndex(where: { $0.scoreId == targetID }) {
                if draft.practiceItems[itemIndex].status == .archived {
                    let activeCount = draft.practiceItems.filter { $0.status != .archived }.count
                    draft.practiceItems[itemIndex].order = Double(activeCount)
                    draft.practiceItems[itemIndex].status = .practicing
                    draft.practiceItems[itemIndex].updatedAt = now
                    Self.normalizePracticeQueue(&draft.practiceItems)
                } else {
                    draft.practiceItems[itemIndex].status = .practicing
                    draft.practiceItems[itemIndex].updatedAt = now
                }
            } else {
                let activeCount = draft.practiceItems.filter { $0.status != .archived }.count
                draft.practiceItems.append(PracticeItem(scoreId: targetID, status: .practicing, note: "", order: Double(activeCount), updatedAt: now))
                Self.normalizePracticeQueue(&draft.practiceItems)
            }
            return try Self.commitSnapshot(database: database, current: current, proposed: &draft, incomingAssets: [], removeStageSession: nil)
        }
    }

    /// Deletes an unlinked project only when its loaded project revision still matches.
    @discardableResult
    public func deleteProject(id: String, expectedUpdatedAt: Double? = nil, expectedRevision: Int? = nil) throws -> PersonalData {
        var data = try snapshot()
        if let expectedRevision, data.revision != expectedRevision { throw PersonalStoreError.revisionConflict(expected: expectedRevision, actual: data.revision) }
        guard let project = data.projects.first(where: { $0.id == id }) else { throw PersonalStoreError.recordConflict("工坊工程已删除或不存在，请重新载入后再试。") }
        if let expectedUpdatedAt, project.updatedAt != expectedUpdatedAt { throw PersonalStoreError.recordConflict("工坊工程已在其他页面更新，请重新载入后再试。") }
        if data.scores.contains(where: { $0.projectId == id || ($0.source == "project" && $0.sourceId == id) }) {
            throw PersonalStoreError.recordConflict("这份工程已保存为练习谱，当前不支持删除关联工程。练习谱和原件会继续保留。")
        }
        data.projects.removeAll { $0.id == id }
        return try commit(data, expectedRevision: data.revision)
    }

    /// Saves an A/B fragment; an existing record requires an exact updatedAt token.
    @discardableResult
    public func savePracticeFragment(_ fragment: PracticeFragment, expectedUpdatedAt: Double? = nil, expectedRevision: Int? = nil, now: Double = Date().timeIntervalSince1970 * 1_000) throws -> PersonalData {
        guard now.isFinite, now >= 0 else { throw PersonalStoreError.validation("练习片段操作时间无效") }
        var data = try snapshot()
        if let expectedRevision, data.revision != expectedRevision { throw PersonalStoreError.revisionConflict(expected: expectedRevision, actual: data.revision) }
        if let index = data.practiceFragments.firstIndex(where: { $0.id == fragment.id }) {
            let existing = data.practiceFragments[index]
            guard existing.deletedAt == nil, expectedUpdatedAt == existing.updatedAt else { throw PersonalStoreError.recordConflict("练习片段已删除或在其他页面更新，请重新载入后再试。") }
            guard fragment.scoreId == existing.scoreId, fragment.scoreRevision == existing.scoreRevision,
                  fragment.range == existing.range, fragment.speed == existing.speed, fragment.createdAt == existing.createdAt,
                  fragment.deletedAt == nil else {
                throw PersonalStoreError.validation("练习片段只能修改名称和备注；区间、提速方案与曲谱版本保持不变。")
            }
            var updated = existing
            updated.name = fragment.name.trimmingCharacters(in: .whitespacesAndNewlines)
            updated.note = fragment.note
            updated.updatedAt = max(now, existing.updatedAt + 1)
            data.practiceFragments[index] = updated
        } else {
            guard expectedUpdatedAt == nil else { throw PersonalStoreError.recordConflict("练习片段已删除或不存在，请重新载入后再试。") }
            guard data.scores.contains(where: { $0.id == fragment.scoreId && $0.revision == fragment.scoreRevision }) else {
                throw PersonalStoreError.recordConflict("曲谱版本已变化或不在本机资料中；请重新载入曲谱后保存片段。")
            }
            guard fragment.deletedAt == nil else { throw PersonalStoreError.validation("新练习片段不能是已删除状态") }
            var created = fragment
            created.name = fragment.name.trimmingCharacters(in: .whitespacesAndNewlines)
            created.createdAt = now
            created.updatedAt = now
            data.practiceFragments.append(created)
        }
        return try commit(data, expectedRevision: data.revision)
    }

    /// Retains a fragment deletion as a timestamped tombstone for backup merge safety.
    @discardableResult
    public func deletePracticeFragment(id: String, expectedUpdatedAt: Double, now: Double = Date().timeIntervalSince1970 * 1_000, expectedRevision: Int? = nil) throws -> PersonalData {
        var data = try snapshot()
        if let expectedRevision, data.revision != expectedRevision { throw PersonalStoreError.revisionConflict(expected: expectedRevision, actual: data.revision) }
        guard let index = data.practiceFragments.firstIndex(where: { $0.id == id }), data.practiceFragments[index].deletedAt == nil,
              data.practiceFragments[index].updatedAt == expectedUpdatedAt else { throw PersonalStoreError.recordConflict("练习片段已删除或在其他页面更新，请重新载入后再试。") }
        let timestamp = max(now, data.practiceFragments[index].updatedAt + 1)
        data.practiceFragments[index].updatedAt = timestamp
        data.practiceFragments[index].deletedAt = timestamp
        return try commit(data, expectedRevision: data.revision)
    }

    /// Updates queue status, notes and position as one revision.
    @discardableResult
    public func setPracticeItem(_ item: PracticeItem, expectedRevision: Int? = nil) throws -> PersonalData {
        var data = try snapshot()
        if let expectedRevision, data.revision != expectedRevision { throw PersonalStoreError.revisionConflict(expected: expectedRevision, actual: data.revision) }
        if let index = data.practiceItems.firstIndex(where: { $0.scoreId == item.scoreId }) { data.practiceItems[index] = item }
        else { data.practiceItems.append(item) }
        return try commit(data, expectedRevision: data.revision)
    }

    /// Changes a queue status without replacing its note or other fields.
    /// Status transitions preserve active/archive group ordering and normalize order values.
    @discardableResult
    public func setPracticeStatus(scoreID: String, status: PracticeStatus, now: Double = Date().timeIntervalSince1970 * 1_000) throws -> PersonalData {
        guard now.isFinite, now >= 0 else { throw PersonalStoreError.validation("待练操作时间无效") }
        var data = try snapshot()
        guard let index = data.practiceItems.firstIndex(where: { $0.scoreId == scoreID }) else {
            throw PersonalStoreError.recordConflict("待练条目已被移除，请刷新后重试。")
        }
        let beforeStatus = data.practiceItems[index].status
        if beforeStatus != status {
            if beforeStatus == .archived, status != .archived {
                data.practiceItems[index].order = Double(data.practiceItems.filter { $0.status != .archived }.count)
            } else if beforeStatus != .archived, status == .archived {
                data.practiceItems[index].order = Double(data.practiceItems.count)
            }
            data.practiceItems[index].status = status
        }
        data.practiceItems[index].updatedAt = max(now, data.practiceItems[index].updatedAt + 1)
        Self.normalizePracticeQueue(&data.practiceItems)
        return try commit(data, expectedRevision: data.revision)
    }

    /// Compare-and-swap updates only a queue note, preserving its latest status and order.
    @discardableResult
    public func updatePracticeNote(scoreID: String, note: String, expectedNote: String, now: Double = Date().timeIntervalSince1970 * 1_000) throws -> PersonalData {
        guard now.isFinite, now >= 0 else { throw PersonalStoreError.validation("待练备注操作时间无效") }
        var data = try snapshot()
        guard let index = data.practiceItems.firstIndex(where: { $0.scoreId == scoreID }) else {
            throw PersonalStoreError.recordConflict("待练条目已被移除，请刷新后重试。")
        }
        guard data.practiceItems[index].note == expectedNote else {
            throw PersonalStoreError.recordConflict("待练备注已在其他页面更新，请重新载入后再试。")
        }
        data.practiceItems[index].note = note
        data.practiceItems[index].updatedAt = max(now, data.practiceItems[index].updatedAt + 1)
        return try commit(data, expectedRevision: data.revision)
    }

    /// Reorders active practice items, leaving archived entries and notes intact.
    @discardableResult
    public func movePracticeItem(scoreID: String, direction: Int, expectedRevision: Int? = nil) throws -> PersonalData {
        guard direction == -1 || direction == 1 else { throw PersonalStoreError.validation("待练曲谱的移动方向无效") }
        var data = try snapshot()
        if let expectedRevision, data.revision != expectedRevision { throw PersonalStoreError.revisionConflict(expected: expectedRevision, actual: data.revision) }
        var activeIndices = data.practiceItems.indices.filter { data.practiceItems[$0].status != .archived }
        activeIndices.sort { lhs, rhs in
            let left = data.practiceItems[lhs].order
            let right = data.practiceItems[rhs].order
            return left == right ? lhs < rhs : left < right
        }
        guard let index = activeIndices.firstIndex(where: { data.practiceItems[$0].scoreId == scoreID }) else { return data }
        let target = index + direction
        guard activeIndices.indices.contains(target) else { return data }
        activeIndices.swapAt(index, target)
        for (position, itemIndex) in activeIndices.enumerated() { data.practiceItems[itemIndex].order = Double(position) }
        Self.normalizePracticeQueue(&data.practiceItems)
        return try commit(data, expectedRevision: data.revision)
    }

    /// CAS-restores an already verified backup and merges it without replacing local assets.
    @discardableResult
    public func restore(_ incoming: PersonalData, assets: [PersonalAsset], expectedRevision: Int) throws -> PersonalData {
        guard let database else { throw PersonalStoreError.storage("数据库连接已关闭") }
        let preparedAssets = try Self.prepareAssets(assets)
        return try Self.withTransaction(database: database) { database in
            let current = try Self.readSnapshot(database: database)
            guard current.revision == expectedRevision else { throw PersonalStoreError.revisionConflict(expected: expectedRevision, actual: current.revision) }
            var merged = try mergePersonalBackupData(current: current, incomingData: incoming.currentSchema)
            return try Self.commitSnapshot(database: database, current: current, proposed: &merged, incomingAssets: preparedAssets, removeStageSession: nil)
        }
    }

    /// Stores a verified asset outside the active snapshot while a v2 backup is previewed.
    public func stageRestoreAsset(sessionID: String, asset: PersonalAsset) throws {
        guard let database else { throw PersonalStoreError.storage("数据库连接已关闭") }
        guard !sessionID.isEmpty, sessionID.count <= 128 else { throw PersonalStoreError.validation("恢复暂存会话 ID 无效") }
        let prepared = try Self.prepareAssets([asset])[0]
        try Self.withTransaction(database: database) { database in
            if let existing = try Self.readStagedAsset(database: database, sessionID: sessionID, id: prepared.id) {
                guard existing == prepared else { throw PersonalStoreError.assetIntegrity("同一恢复会话中的附件发生冲突：\(prepared.id)") }
                return
            }
            let createdAt = Int(Date().timeIntervalSince1970 * 1_000)
            try Self.execute(database: database, sql: "INSERT INTO restore_staging(session_id, asset_id, mime_type, size, bytes, created_at_ms) VALUES(?, ?, ?, ?, ?, ?)", values: [.text(sessionID), .text(prepared.id), .text(prepared.mimeType), .integer(prepared.bytes.count), .blob(prepared.bytes), .integer(createdAt)])
        }
    }

    public func clearRestoreStage(sessionID: String) throws {
        guard let database else { throw PersonalStoreError.storage("数据库连接已关闭") }
        try Self.execute(database: database, sql: "DELETE FROM restore_staging WHERE session_id = ?", values: [.text(sessionID)])
    }

    public func stagedAssetMetadata(sessionID: String) throws -> [PersonalAssetMetadata] {
        guard let database else { throw PersonalStoreError.storage("数据库连接已关闭") }
        return try Self.readStagedMetadata(database: database, sessionID: sessionID)
    }

    /// CAS-commits v2 preview assets, state and temporary-stage cleanup in one SQLite transaction.
    @discardableResult
    public func restoreStaged(_ incoming: PersonalData, sessionID: String, expectedMetadata: [PersonalAssetMetadata], expectedRevision: Int) throws -> PersonalData {
        guard let database else { throw PersonalStoreError.storage("数据库连接已关闭") }
        return try Self.withTransaction(database: database) { database in
            let current = try Self.readSnapshot(database: database)
            guard current.revision == expectedRevision else { throw PersonalStoreError.revisionConflict(expected: expectedRevision, actual: current.revision) }
            guard expectedMetadata.count <= PersonalBackupLimits.maximumAssetCount else { throw PersonalStoreError.validation("恢复附件 metadata 超过 500 份") }
            var descriptors: [String: PersonalAssetMetadata] = [:]
            for metadata in expectedMetadata {
                guard descriptors[metadata.id] == nil else { throw PersonalStoreError.validation("恢复附件 metadata 重复：\(metadata.id)") }
                descriptors[metadata.id] = metadata
            }
            let stagedMetadata = try Self.readStagedMetadata(database: database, sessionID: sessionID)
            guard stagedMetadata.allSatisfy({ descriptors[$0.id] != nil }) else { throw PersonalStoreError.validation("恢复暂存包含预览清单之外的附件") }
            let existingIDs = Set(try Self.readIDs(database: database, sql: "SELECT id FROM assets ORDER BY id"))
            for metadata in expectedMetadata {
                guard PersonalDataValidator.isSHA256(metadata.id), metadata.size >= 0, metadata.size <= PersonalBackupLimits.maximumAssetBytes, Self.isValidMIMEType(metadata.mimeType) else { throw PersonalStoreError.validation("恢复附件 metadata 无效：\(metadata.id)") }
                if existingIDs.contains(metadata.id) {
                    guard let existing = try Self.readAsset(database: database, id: metadata.id),
                          existing.bytes.count == metadata.size,
                          Self.sha256(existing.bytes) == metadata.id else {
                        throw PersonalStoreError.assetIntegrity("本机已有附件 \(metadata.id) 与备份内容不一致；没有覆盖任何资料")
                    }
                } else {
                    guard let stageMetadata = stagedMetadata.first(where: { $0.id == metadata.id }), stageMetadata.size == metadata.size, stageMetadata.mimeType == metadata.mimeType,
                          let stage = try Self.readStagedAsset(database: database, sessionID: sessionID, id: metadata.id),
                          stage.bytes.count == metadata.size, stage.mimeType == metadata.mimeType,
                          Self.sha256(stage.bytes) == metadata.id else {
                        throw PersonalStoreError.assetMissing(metadata.id)
                    }
                    try Self.insertAsset(database: database, asset: stage)
                }
            }
            var merged = try mergePersonalBackupData(current: current, incomingData: incoming.currentSchema)
            let result = try Self.commitSnapshot(database: database, current: current, proposed: &merged, incomingAssets: [], removeStageSession: sessionID)
            return result
        }
    }

    /// Backward-compatible toggle. A placeholder is used only until a catalog detail is supplied.
    public func toggleFavorite(_ id: String) throws {
        try mutateCatalogCollection(id: id, favorite: true, metadata: nil)
    }

    public func toggleFavorite(_ item: CatalogItem) throws {
        try mutateCatalogCollection(id: item.id, favorite: true, metadata: item, rawCatalogID: true)
    }

    /// Idempotently ensures a catalog score is saved as a favorite.
    /// This is intended for migrations; interactive controls should keep using `toggleFavorite`.
    public func ensureFavorite(_ item: CatalogItem) throws {
        try mutateCatalogCollection(id: item.id, favorite: true, metadata: item, toggleFavorite: false, rawCatalogID: true)
    }

    /// Backward-compatible queue toggle; archiving keeps status, order and note recoverable.
    public func toggleQueue(_ id: String) throws {
        try mutateCatalogCollection(id: id, favorite: false, metadata: nil)
    }

    public func toggleQueue(_ item: CatalogItem) throws {
        try mutateCatalogCollection(id: item.id, favorite: false, metadata: item, rawCatalogID: true)
    }

    public func recordRecent(_ id: String) throws {
        try recordRecent(id: id, metadata: nil, rawCatalogID: false)
    }

    /// Records the catalog's exact raw ID and metadata rather than a placeholder title.
    public func recordRecent(_ item: CatalogItem) throws {
        try recordRecent(id: item.id, metadata: item, rawCatalogID: true)
    }

    private func recordRecent(id: String, metadata: CatalogItem?, rawCatalogID: Bool) throws {
        guard let database else { throw PersonalStoreError.storage("数据库连接已关闭") }
        let normalized = try rawCatalogID ? Self.validRawCatalogID(id) : Self.normalizedID(id)
        guard !normalized.isEmpty else { return }
        try Self.withTransaction(database: database) { database in
            let current = try Self.readSnapshot(database: database)
            var draft = current.currentSchema
            let score = Self.ensureCatalogScore(id: normalized, metadata: metadata, in: &draft)
            let route = Self.catalogRoute(normalized)
            draft.history.removeAll { $0.id == normalized && $0.url == route }
            draft.history.append(PersonalHistoryEntry(id: normalized, title: score.title, artist: score.artist, url: route, time: Date().timeIntervalSince1970 * 1_000, category: score.category))
            draft.history.sort { $0.time > $1.time }
            if draft.history.count > 500 { draft.history = Array(draft.history.prefix(500)) }
            _ = try Self.commitSnapshot(database: database, current: current, proposed: &draft, incomingAssets: [], removeStageSession: nil)
        }
    }

    private func mutateCatalogCollection(id: String, favorite: Bool, metadata: CatalogItem?, toggleFavorite: Bool = true, rawCatalogID: Bool = false) throws {
        guard let database else { throw PersonalStoreError.storage("数据库连接已关闭") }
        let normalized = try rawCatalogID ? Self.validRawCatalogID(id) : Self.normalizedID(id)
        guard !normalized.isEmpty else { return }
        let catalogID = Self.catalogScoreID(rawID: normalized)
        try Self.withTransaction(database: database) { database in
            let current = try Self.readSnapshot(database: database)
            var draft = current.currentSchema
            let score = Self.ensureCatalogScore(id: normalized, metadata: metadata, in: &draft)
            let now = Date().timeIntervalSince1970 * 1_000
            if favorite {
                if toggleFavorite, let index = draft.favorites.firstIndex(of: catalogID) { draft.favorites.remove(at: index) }
                else if !draft.favorites.contains(catalogID) { draft.favorites.append(catalogID) }
            } else if let index = draft.practiceItems.firstIndex(where: { $0.scoreId == catalogID }) {
                if draft.practiceItems[index].status == .archived {
                    let activeCount = draft.practiceItems.filter { $0.status != .archived }.count
                    draft.practiceItems[index].status = .todo
                    draft.practiceItems[index].order = Double(activeCount)
                    draft.practiceItems[index].updatedAt = max(now, draft.practiceItems[index].updatedAt + 1)
                } else {
                    draft.practiceItems[index].status = .archived
                    draft.practiceItems[index].order = Double(draft.practiceItems.count)
                    draft.practiceItems[index].updatedAt = max(now, draft.practiceItems[index].updatedAt + 1)
                }
                Self.normalizePracticeQueue(&draft.practiceItems)
            } else {
                let activeCount = draft.practiceItems.filter { $0.status != .archived }.count
                draft.practiceItems.append(PracticeItem(scoreId: score.id, status: .todo, note: "", order: Double(activeCount), updatedAt: now))
                Self.normalizePracticeQueue(&draft.practiceItems)
            }
            _ = try Self.commitSnapshot(database: database, current: current, proposed: &draft, incomingAssets: [], removeStageSession: nil)
        }
    }

    private static func initializeSchema(database: OpaquePointer) throws {
        let version = try scalarOptionalInt(database: database, sql: "PRAGMA user_version", values: []) ?? 0
        guard (0...2).contains(version) else { throw PersonalStoreError.storage("个人资料数据库版本 \(version) 不受此版本支持；当前支持版本为 2。") }
        try execute(database: database, sql: "BEGIN IMMEDIATE")
        do {
            try execute(database: database, sql: """
            CREATE TABLE IF NOT EXISTS favorites (id TEXT PRIMARY KEY NOT NULL, created_at INTEGER NOT NULL);
            CREATE TABLE IF NOT EXISTS queue (id TEXT PRIMARY KEY NOT NULL, position INTEGER NOT NULL);
            CREATE INDEX IF NOT EXISTS queue_position_idx ON queue(position);
            CREATE TABLE IF NOT EXISTS recents (id TEXT PRIMARY KEY NOT NULL, position INTEGER NOT NULL);
            CREATE INDEX IF NOT EXISTS recents_position_idx ON recents(position);
            CREATE TABLE IF NOT EXISTS personal_state (key TEXT PRIMARY KEY NOT NULL, data_json TEXT NOT NULL);
            CREATE TABLE IF NOT EXISTS assets (id TEXT PRIMARY KEY NOT NULL, mime_type TEXT NOT NULL, size INTEGER NOT NULL, bytes BLOB NOT NULL);
            CREATE TABLE IF NOT EXISTS asset_metadata (id TEXT PRIMARY KEY NOT NULL, size INTEGER NOT NULL, mime_type TEXT NOT NULL);
            CREATE TABLE IF NOT EXISTS restore_staging (session_id TEXT NOT NULL, asset_id TEXT NOT NULL, mime_type TEXT NOT NULL, size INTEGER NOT NULL, bytes BLOB NOT NULL, created_at_ms INTEGER NOT NULL DEFAULT 0, PRIMARY KEY(session_id, asset_id));
            CREATE INDEX IF NOT EXISTS restore_staging_session_idx ON restore_staging(session_id);
            INSERT OR IGNORE INTO asset_metadata(id, size, mime_type) SELECT id, size, mime_type FROM assets;
            PRAGMA user_version = 2;
            """)
            let hasStageTimestamp = try tableHasColumn(database: database, table: "restore_staging", column: "created_at_ms")
            if !hasStageTimestamp {
                try execute(database: database, sql: "ALTER TABLE restore_staging ADD COLUMN created_at_ms INTEGER NOT NULL DEFAULT 0")
            }
            let now = Int(Date().timeIntervalSince1970 * 1_000)
            // Existing staging rows predate the timestamp column. Give them a
            // fresh grace period instead of deleting an active preview on upgrade.
            try execute(database: database, sql: "UPDATE restore_staging SET created_at_ms = ? WHERE created_at_ms <= 0", values: [.integer(now)])
            let expiredBefore = now - 7 * 24 * 60 * 60 * 1_000
            try execute(database: database, sql: "DELETE FROM restore_staging WHERE created_at_ms < ?", values: [.integer(expiredBefore)])
            try execute(database: database, sql: "COMMIT")
        } catch {
            try? execute(database: database, sql: "ROLLBACK")
            throw error
        }
        try validateSchema(database: database)
        try execute(database: database, sql: "PRAGMA journal_mode = WAL")
        try execute(database: database, sql: "PRAGMA synchronous = FULL")
    }

    private static func validateSchema(database: OpaquePointer) throws {
        for sql in [
            "SELECT id, created_at FROM favorites LIMIT 0",
            "SELECT id, position FROM queue LIMIT 0",
            "SELECT id, position FROM recents LIMIT 0",
            "SELECT key, data_json FROM personal_state LIMIT 0",
            "SELECT id, mime_type, size, bytes FROM assets LIMIT 0",
            "SELECT id, size, mime_type FROM asset_metadata LIMIT 0",
            "SELECT session_id, asset_id, mime_type, size, bytes, created_at_ms FROM restore_staging LIMIT 0",
        ] {
            let statement = try prepare(database: database, sql: sql)
            sqlite3_finalize(statement)
        }
    }

    private static func tableHasColumn(database: OpaquePointer, table: String, column: String) throws -> Bool {
        let statement = try prepare(database: database, sql: "PRAGMA table_info(\(table))")
        defer { sqlite3_finalize(statement) }
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { return false }
            guard step == SQLITE_ROW, let name = sqlite3_column_text(statement, 1) else { throw sqliteError(database: database) }
            if String(cString: name) == column { return true }
        }
    }

    private static func migrateLegacyCollections(database: OpaquePointer) throws {
        guard try scalarInt(database: database, sql: "SELECT COUNT(*) FROM personal_state WHERE key = 'current'", values: []) == 0 else { return }
        let favoriteIDs = try readIDs(database: database, sql: "SELECT id FROM favorites ORDER BY id")
        let queueIDs = try readIDs(database: database, sql: "SELECT id FROM queue ORDER BY position ASC, id ASC")
        let recentIDs = try readIDs(database: database, sql: "SELECT id FROM recents ORDER BY position ASC, id ASC")
        guard !favoriteIDs.isEmpty || !queueIDs.isEmpty || !recentIDs.isEmpty else { return }
        var data = PersonalData()
        for id in favoriteIDs + queueIDs + recentIDs where data.scores.first(where: { $0.id == catalogScoreID(rawID: id) }) == nil {
            guard !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, id.count <= 512 else { continue }
            _ = ensureCatalogScore(id: id, metadata: nil, in: &data)
        }
        data.favorites = favoriteIDs.map(catalogScoreID(rawID:)).filter { id in data.scores.contains(where: { $0.id == id }) }
        let now = Date().timeIntervalSince1970 * 1_000
        data.practiceItems = queueIDs.enumerated().compactMap { position, id in
            let scoreID = catalogScoreID(rawID: id)
            guard data.scores.contains(where: { $0.id == scoreID }) else { return nil }
            return PracticeItem(scoreId: scoreID, status: .todo, note: "", order: Double(position), updatedAt: now)
        }
        data.history = recentIDs.enumerated().compactMap { position, id in
            guard let score = data.scores.first(where: { $0.id == catalogScoreID(rawID: id) }) else { return nil }
            return PersonalHistoryEntry(id: id, title: score.title, artist: score.artist, url: catalogRoute(id), time: max(0, now - Double(position)), category: score.category)
        }
        try validate(data)
        try writeSnapshot(database: database, data: data)
    }

    /// Converts the 0.1 native prototype's raw catalog IDs to the website's
    /// stable `catalog:<id>` PersonalData identity without changing localState IDs.
    private static func migrateCatalogScoreIDs(database: OpaquePointer) throws {
        let current = try readSnapshot(database: database).currentSchema
        let candidates = current.scores.filter { $0.source == "catalog" && $0.id != catalogScoreID(rawID: $0.sourceId) }
        guard !candidates.isEmpty else { return }
        try withTransaction(database: database) { database in
            let live = try readSnapshot(database: database)
            var proposed = live.currentSchema
            var scoreMap: [String: String] = [:]
            var scoresByID = Dictionary(uniqueKeysWithValues: proposed.scores.map { ($0.id, $0) })
            for candidate in candidates {
                guard scoresByID[candidate.id] != nil else { continue }
                let canonicalID = catalogScoreID(rawID: candidate.sourceId)
                if let existing = scoresByID[canonicalID], existing.id != candidate.id {
                    if existing.source == "catalog", existing.sourceId == candidate.sourceId {
                        scoreMap[candidate.id] = canonicalID
                        if candidate.updatedAt > existing.updatedAt || (candidate.updatedAt == existing.updatedAt && candidate.id < existing.id) {
                            var updated = candidate
                            updated.id = canonicalID
                            scoresByID[canonicalID] = updated
                        }
                        scoresByID.removeValue(forKey: candidate.id)
                    } else {
                        let identity = "legacy-catalog\0\(candidate.sourceId)\0\(candidate.revision)"
                        let suffix = String(sha256(Data(identity.utf8)).prefix(16))
                        var conflictID = "\(canonicalID)~legacy-\(suffix)"
                        var ordinal = 2
                        while scoresByID[conflictID] != nil {
                            conflictID = "\(canonicalID)~legacy-\(suffix)-\(ordinal)"
                            ordinal += 1
                        }
                        scoreMap[candidate.id] = conflictID
                        var updated = candidate
                        updated.id = conflictID
                        scoresByID.removeValue(forKey: candidate.id)
                        scoresByID[conflictID] = updated
                    }
                } else {
                    scoreMap[candidate.id] = canonicalID
                    var updated = candidate
                    updated.id = canonicalID
                    scoresByID.removeValue(forKey: candidate.id)
                    scoresByID[canonicalID] = updated
                }
            }
            for index in proposed.favorites.indices { proposed.favorites[index] = scoreMap[proposed.favorites[index]] ?? proposed.favorites[index] }
            for index in proposed.practiceItems.indices { proposed.practiceItems[index].scoreId = scoreMap[proposed.practiceItems[index].scoreId] ?? proposed.practiceItems[index].scoreId }
            for index in proposed.resumes.indices { proposed.resumes[index].scoreId = scoreMap[proposed.resumes[index].scoreId] ?? proposed.resumes[index].scoreId }
            for index in proposed.sessions.indices { proposed.sessions[index].scoreId = scoreMap[proposed.sessions[index].scoreId] ?? proposed.sessions[index].scoreId }
            for index in proposed.practiceFragments.indices { proposed.practiceFragments[index].scoreId = scoreMap[proposed.practiceFragments[index].scoreId] ?? proposed.practiceFragments[index].scoreId }
            proposed.scores = scoresByID.values.sorted { $0.id < $1.id }
            _ = try commitSnapshot(database: database, current: live, proposed: &proposed, incomingAssets: [], removeStageSession: nil)
        }
    }

    private static func commitSnapshot(database: OpaquePointer, current: PersonalData, proposed: inout PersonalData, incomingAssets: [PersonalAsset], removeStageSession: String?) throws -> PersonalData {
        guard current.revision < Int.max else { throw PersonalStoreError.validation("个人资料 revision 已达到安全上限") }
        proposed.schemaVersion = 2
        proposed.revision = current.revision + 1
        proposed.sessions = try mergeSessionCheckpoints(previous: current.sessions, proposed: proposed.sessions)
        try validate(proposed)
        try enforceEntityAndJSONBudget(current: current, proposed: proposed)

        let references = assetReferences(proposed)
        let currentReferences = assetReferences(current)
        var incomingByID: [String: PersonalAsset] = [:]
        for asset in incomingAssets {
            guard references.contains(asset.id) else { throw PersonalStoreError.validation("新附件 \(asset.id) 没有被个人资料引用；个人资料没有保存") }
            incomingByID[asset.id] = asset
        }
        var existingMetadata: [String: PersonalAssetMetadata] = [:]
        for id in Set(currentReferences).union(references) {
            if let metadata = try readAssetMetadata(database: database, id: id) { existingMetadata[id] = metadata }
        }
        for id in references where existingMetadata[id] == nil && incomingByID[id] == nil { throw PersonalStoreError.assetMissing(id) }

        let currentMetadata = try currentReferences.map { id -> PersonalAssetMetadata in
            guard let metadata = existingMetadata[id], isValidMIMEType(metadata.mimeType), metadata.size >= 0 else { throw PersonalStoreError.assetIntegrity("附件 \(id) 的预算 metadata 缺失或无效") }
            return metadata
        }
        let proposedMetadata = try references.map { id -> PersonalAssetMetadata in
            if let metadata = existingMetadata[id] { return metadata }
            guard let asset = incomingByID[id] else { throw PersonalStoreError.assetMissing(id) }
            return PersonalAssetMetadata(id: id, size: asset.bytes.count, mimeType: asset.mimeType)
        }
        if currentReferences != references {
            try enforceAssetBudget(current: current, proposed: proposed, currentAssets: currentMetadata, proposedAssets: proposedMetadata)
        }

        for asset in incomingAssets where existingMetadata[asset.id] == nil {
            try insertAsset(database: database, asset: asset)
        }
        try writeSnapshot(database: database, data: proposed)
        try syncCollections(database: database, data: proposed)
        if let removeStageSession { try execute(database: database, sql: "DELETE FROM restore_staging WHERE session_id = ?", values: [.text(removeStageSession)]) }
        return proposed
    }

    private static func mergeSessionCheckpoints(previous: [PracticeSession], proposed: [PracticeSession]) throws -> [PracticeSession] {
        var merged = Dictionary(uniqueKeysWithValues: proposed.map { ($0.id, $0) })
        for old in previous {
            guard var next = merged[old.id] else { merged[old.id] = old; continue }
            guard old.scoreId == next.scoreId, old.scoreRevision == next.scoreRevision else { throw PersonalStoreError.recordConflict("练习记录 \(old.id) 已关联不同曲谱版本，不能覆盖；请另存为独立会话。") }
            var byID = Dictionary(uniqueKeysWithValues: old.slices.map { ($0.id, $0) })
            for slice in next.slices {
                if let before = byID[slice.id] {
                    if slice.sequence > before.sequence || (slice.sequence == before.sequence && slice.durationMs > before.durationMs) { byID[slice.id] = slice }
                } else { byID[slice.id] = slice }
            }
            var bySequence: [String: PracticeSlice] = [:]
            for slice in byID.values {
                let key = "\(slice.epoch)\0\(slice.sequence)"
                if let before = bySequence[key] {
                    if slice.durationMs > before.durationMs { bySequence[key] = slice }
                } else { bySequence[key] = slice }
            }
            if old.updatedAt > next.updatedAt { next = old }
            next.slices = bySequence.values.sorted { $0.epoch == $1.epoch ? $0.sequence < $1.sequence : $0.epoch < $1.epoch }
            merged[old.id] = next
        }
        return merged.values.sorted { $0.id < $1.id }
    }

    private static func enforceEntityAndJSONBudget(current: PersonalData, proposed: PersonalData) throws {
        let currentEntities = entityCount(current)
        let proposedEntities = entityCount(proposed)
        if proposedEntities > PersonalBackupLimits.maximumEntityCount && proposedEntities > currentEntities {
            throw PersonalStoreError.validation("个人资料超过完整备份的 10,000 个实体预算；请先整理条目，本次新增未保存。")
        }
        let currentRefs = assetReferences(current).count
        let proposedRefs = assetReferences(proposed).count
        if proposedRefs > PersonalBackupLimits.maximumAssetCount && proposedRefs > currentRefs {
            throw PersonalStoreError.validation("个人资料超过完整备份的 500 份附件预算；请先整理引用，本次新增未保存。")
        }
        let oldBytes = try encodedSnapshot(current).count
        let newBytes = try encodedSnapshot(proposed).count
        if newBytes > PersonalBackupLimits.maximumDataJSONBytes && newBytes > oldBytes {
            throw PersonalStoreError.validation("个人资料清单超过 60 MiB 写入预算；请先整理资料，本次新增未保存。")
        }
    }

    private static func enforceAssetBudget(current: PersonalData, proposed: PersonalData, currentAssets: [PersonalAssetMetadata], proposedAssets: [PersonalAssetMetadata]) throws {
        for list in [currentAssets, proposedAssets] {
            for asset in list where asset.size < 0 || asset.size > PersonalBackupLimits.maximumAssetBytes || !isValidMIMEType(asset.mimeType) {
                throw PersonalStoreError.validation("附件预算 metadata 无效：\(asset.id)")
            }
        }
        let currentBytes = currentAssets.reduce(0) { $0 + $1.size }
        let proposedBytes = proposedAssets.reduce(0) { $0 + $1.size }
        let currentVolumes = packedVolumeCount(currentAssets)
        let proposedVolumes = packedVolumeCount(proposedAssets)
        let proposedDataBytes = try encodedSnapshot(proposed).count
        let proposedOver = proposedBytes > PersonalBackupLimits.maximumReferencedAssetBytes || proposedAssets.count > PersonalBackupLimits.maximumAssetCount || proposedVolumes > PersonalBackupLimits.maximumVolumeCount || entityCount(proposed) > PersonalBackupLimits.maximumEntityCount || proposedDataBytes > PersonalBackupLimits.maximumDataJSONBytes
        if proposedBytes > PersonalBackupLimits.maximumReferencedAssetBytes && proposedBytes > currentBytes { throw PersonalStoreError.validation("被引用附件总量超过完整备份的 927 MiB 预算；请先整理引用。") }
        if proposedAssets.count > PersonalBackupLimits.maximumAssetCount && proposedAssets.count > currentAssets.count { throw PersonalStoreError.validation("个人资料超过完整备份的 500 份附件预算；请先整理引用。") }
        if proposedVolumes > PersonalBackupLimits.maximumVolumeCount && proposedVolumes > currentVolumes { throw PersonalStoreError.validation("附件按 8 MiB 分卷后超过 128 卷预算；请先整理引用。") }
        if proposedOver && proposedBytes > currentBytes { throw PersonalStoreError.validation("个人资料仍超过完整备份预算，不能增加被引用附件总量。") }
        if proposedOver && proposedAssets.count > currentAssets.count { throw PersonalStoreError.validation("个人资料仍超过完整备份预算，不能增加被引用附件数量。") }
        _ = current
    }

    private static func packedVolumeCount(_ assets: [PersonalAssetMetadata]) -> Int {
        var volumes = 0
        var payload = 0
        for asset in assets.sorted(by: { $0.id < $1.id }) {
            var remaining = asset.size
            while remaining > 0 {
                let chunk = min(PersonalBackupLimits.volumeBytes, remaining)
                if payload > 0 && payload + chunk > PersonalBackupLimits.volumeBytes { volumes += 1; payload = 0 }
                payload += chunk
                remaining -= chunk
                if payload == PersonalBackupLimits.volumeBytes { volumes += 1; payload = 0 }
            }
        }
        if payload > 0 { volumes += 1 }
        return volumes
    }

    private static func validate(_ data: PersonalData) throws {
        do { try PersonalDataValidator.validate(data) }
        catch let error as PersonalDataValidationError { throw PersonalStoreError.validation(error.message) }
        let mimeTypes = data.originals.map(\.mimeType)
        for mime in mimeTypes where !isValidMIMEType(mime) { throw PersonalStoreError.validation("原件 MIME 类型无效：\(mime)") }
    }

    private static func assetReferences(_ data: PersonalData) -> Set<String> {
        var ids = Set<String>()
        for score in data.scores {
            if let id = score.assetId { ids.insert(id) }
            if let id = score.originalAssetId { ids.insert(id) }
        }
        for original in data.originals { ids.insert(original.assetId) }
        return ids
    }

    private static func entityCount(_ data: PersonalData) -> Int {
        data.scores.count + data.favorites.count + data.practiceItems.count + data.practiceFragments.count + data.resumes.count + data.sessions.count + data.projects.count + data.originals.count + data.history.count
    }

    private static func prepareAssets(_ assets: [PersonalAsset]) throws -> [PersonalAsset] {
        guard assets.count <= PersonalBackupLimits.maximumAssetCount else { throw PersonalStoreError.validation("单次保存附件最多 500 份；个人资料没有保存") }
        var ids = Set<String>()
        var result: [PersonalAsset] = []
        for asset in assets {
            guard PersonalDataValidator.isSHA256(asset.id), isValidMIMEType(asset.mimeType), asset.bytes.count <= PersonalBackupLimits.maximumAssetBytes else { throw PersonalStoreError.validation("附件格式无效或超过 30 MiB；个人资料没有保存") }
            guard ids.insert(asset.id).inserted else { throw PersonalStoreError.validation("附件 ID 重复：\(asset.id)") }
            guard sha256(asset.bytes) == asset.id else { throw PersonalStoreError.assetIntegrity("附件 SHA-256 不匹配：\(asset.id)") }
            result.append(PersonalAsset(id: asset.id, bytes: asset.bytes, mimeType: asset.mimeType))
        }
        return result
    }

    public static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    public static func isValidMIMEType(_ value: String) -> Bool {
        guard value.count <= 256, !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { return false }
        let pattern = "^[!#$%&'*+.^_`|~0-9A-Za-z-]+/[!#$%&'*+.^_`|~0-9A-Za-z-]+(?:\\s*;\\s*[!#$%&'*+.^_`|~0-9A-Za-z-]+(?:\\s*=\\s*(?:[!#$%&'*+.^_`|~0-9A-Za-z-]+|\"[^\"]*\"))?)*$"
        return value.range(of: pattern, options: .regularExpression) != nil
    }

    private static func personalFormat(_ input: String) -> String? {
        switch input.lowercased() {
        case "ibe": return "ibe"
        case "gp", "gp3", "gp4", "gp5", "gp6", "gp7", "gp8", "gpx": return "gp"
        case "xhe": return "xhe"
        case "project": return "project"
        default: return nil
        }
    }

    private static func mimeType(for fileName: String, format: String) -> String {
        switch URL(fileURLWithPath: fileName).pathExtension.lowercased() {
        case "xml", "musicxml": return "application/xml"
        case "json": return "application/json"
        case "tex", "alphatex": return "text/plain"
        default: return format.lowercased() == "xhe" ? "text/plain" : "application/octet-stream"
        }
    }

    private static func ensureCatalogScore(id: String, metadata: CatalogItem?, in data: inout PersonalData) -> PersonalScore {
        let catalogID = catalogScoreID(rawID: id)
        if let index = data.scores.firstIndex(where: { $0.id == catalogID }) {
            if let metadata {
                let existing = data.scores[index]
                var refreshed = catalogScore(id: id, item: metadata, createdAt: existing.createdAt)
                refreshed.revision = existing.revision
                refreshed.assetId = existing.assetId
                refreshed.originalAssetId = existing.originalAssetId
                refreshed.projectId = existing.projectId
                refreshed.warnings = existing.warnings
                data.scores[index] = refreshed
            }
            return data.scores[index]
        }
        let score = catalogScore(id: id, item: metadata, createdAt: Date().timeIntervalSince1970 * 1_000)
        data.scores.append(score)
        return score
    }

    private static func catalogScore(id: String, item: CatalogItem?, createdAt: Double) -> PersonalScore {
        let catalogFormat = item?.format.lowercased()
        let format = catalogFormat.map { ["gp", "xhe", "project"].contains($0) ? $0 : "ibe" } ?? "gp"
        let category = ["guitar", "ukulele", "bass"].contains(item?.category ?? "") ? item!.category : "guitar"
        let path = item?.scoreURL.flatMap { PersonalDataValidator.isSafeLocalPath($0) ? $0 : nil }
        let trimmedTitle = item?.title.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let revision = "unverified"
        return PersonalScore(
            id: catalogScoreID(rawID: id), source: "catalog", sourceId: id, revision: revision, title: trimmedTitle.isEmpty ? id : trimmedTitle,
            artist: item?.artist?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "", category: category, format: format, scoreUrl: path,
            createdAt: createdAt, updatedAt: Date().timeIntervalSince1970 * 1_000
        )
    }

    private static func catalogScoreID(rawID: String) -> String { "catalog:\(rawID)" }

    private static func legacyCatalogID(_ id: String) -> String {
        guard let score = id.hasPrefix("catalog:") ? String(id.dropFirst("catalog:".count)) : nil else { return id }
        return score
    }

    private static func catalogRoute(_ id: String) -> String {
        let allowed = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/?#%"))
        let encoded = id.addingPercentEncoding(withAllowedCharacters: allowed) ?? id.replacingOccurrences(of: "/", with: "%2F")
        return "/tabs/\(encoded)"
    }

    private static func normalizedID(_ id: String) throws -> String {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmed.hasPrefix("catalog:") ? String(trimmed.dropFirst("catalog:".count)) : trimmed
        guard normalized.count <= 512 else { throw PersonalStoreError.validation("曲谱编号超过 512 个字符") }
        return normalized
    }

    private static func validRawCatalogID(_ id: String) throws -> String {
        guard !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, id.count <= 512 else { throw PersonalStoreError.validation("曲谱编号无效或超过 512 个字符") }
        return id
    }

    private static func encodedSnapshot(_ data: PersonalData) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        do { return try encoder.encode(data) }
        catch { throw PersonalStoreError.validation("个人资料无法序列化为 JSON：\(error.localizedDescription)") }
    }

    private static func writeSnapshot(database: OpaquePointer, data: PersonalData) throws {
        let bytes = try encodedSnapshot(data)
        guard let json = String(data: bytes, encoding: .utf8) else { throw PersonalStoreError.validation("个人资料 JSON 编码不是有效 UTF-8") }
        try execute(database: database, sql: "INSERT INTO personal_state(key, data_json) VALUES('current', ?) ON CONFLICT(key) DO UPDATE SET data_json = excluded.data_json", values: [.text(json)])
    }

    private static func readSnapshot(database: OpaquePointer) throws -> PersonalData {
        let statement = try prepare(database: database, sql: "SELECT data_json FROM personal_state WHERE key = 'current' LIMIT 1")
        defer { sqlite3_finalize(statement) }
        let step = sqlite3_step(statement)
        if step == SQLITE_DONE { return PersonalData() }
        guard step == SQLITE_ROW, let value = sqlite3_column_text(statement, 0) else { throw sqliteError(database: database) }
        let json = String(cString: UnsafeRawPointer(value).assumingMemoryBound(to: CChar.self))
        do {
            let data = try JSONDecoder().decode(PersonalData.self, from: Data(json.utf8)).currentSchema
            try validate(data)
            return data
        } catch let error as PersonalStoreError { throw error }
        catch { throw PersonalStoreError.storage("个人资料 JSON 无法读取：\(error.localizedDescription)") }
    }

    private static func syncCollections(database: OpaquePointer, data: PersonalData) throws {
        try execute(database: database, sql: "DELETE FROM favorites")
        for id in data.favorites { try execute(database: database, sql: "INSERT INTO favorites(id, created_at) VALUES(?, ?)", values: [.text(id), .integer(Int(Date().timeIntervalSince1970))]) }
        try execute(database: database, sql: "DELETE FROM queue")
        let queue = data.practiceItems.filter { $0.status != .archived }.sorted { $0.order == $1.order ? $0.scoreId < $1.scoreId : $0.order < $1.order }
        for (position, item) in queue.enumerated() { try execute(database: database, sql: "INSERT INTO queue(id, position) VALUES(?, ?)", values: [.text(item.scoreId), .integer(position)]) }
        try execute(database: database, sql: "DELETE FROM recents")
        var recentIDs = Set<String>()
        let recents = data.history.sorted { $0.time == $1.time ? $0.id < $1.id : $0.time > $1.time }.filter { recentIDs.insert($0.id).inserted }.prefix(500)
        for (position, entry) in recents.enumerated() { try execute(database: database, sql: "INSERT INTO recents(id, position) VALUES(?, ?)", values: [.text(entry.id), .integer(position)]) }
    }

    private static func normalizePracticeQueue(_ items: inout [PracticeItem]) {
        let orderedIndices = items.indices.sorted { lhs, rhs in
            let left = items[lhs]
            let right = items[rhs]
            let leftArchived = left.status == .archived
            let rightArchived = right.status == .archived
            if leftArchived != rightArchived { return !leftArchived }
            if left.order != right.order { return left.order < right.order }
            return lhs < rhs
        }
        var normalized = orderedIndices.map { items[$0] }
        for position in normalized.indices { normalized[position].order = Double(position) }
        items = normalized
    }

    private static func insertAsset(database: OpaquePointer, asset: PersonalAsset) throws {
        try execute(database: database, sql: "INSERT INTO assets(id, mime_type, size, bytes) VALUES(?, ?, ?, ?)", values: [.text(asset.id), .text(asset.mimeType), .integer(asset.bytes.count), .blob(asset.bytes)])
        try execute(database: database, sql: "INSERT INTO asset_metadata(id, size, mime_type) VALUES(?, ?, ?) ON CONFLICT(id) DO UPDATE SET size = excluded.size, mime_type = excluded.mime_type", values: [.text(asset.id), .integer(asset.bytes.count), .text(asset.mimeType)])
    }

    private static func readAsset(database: OpaquePointer, id: String) throws -> PersonalAsset? {
        let statement = try prepare(database: database, sql: "SELECT mime_type, size, bytes FROM assets WHERE id = ? LIMIT 1")
        defer { sqlite3_finalize(statement) }
        try bind([.text(id)], to: statement, database: database)
        let result = sqlite3_step(statement)
        if result == SQLITE_DONE { return nil }
        guard result == SQLITE_ROW, let mime = columnText(statement, 0) else { throw sqliteError(database: database) }
        let size = Int(sqlite3_column_int64(statement, 1))
        guard size >= 0, sqlite3_column_bytes(statement, 2) == Int32(size) else { throw PersonalStoreError.assetIntegrity("附件 \(id) 的存储长度无效") }
        let bytes: Data
        if size == 0 { bytes = Data() }
        else if let raw = sqlite3_column_blob(statement, 2) { bytes = Data(bytes: raw, count: size) }
        else { throw PersonalStoreError.assetIntegrity("附件 \(id) 的内容缺失") }
        return PersonalAsset(id: id, bytes: bytes, mimeType: mime)
    }

    private static func readAssetMetadata(database: OpaquePointer, id: String) throws -> PersonalAssetMetadata? {
        let statement = try prepare(database: database, sql: "SELECT size, mime_type FROM asset_metadata WHERE id = ? LIMIT 1")
        defer { sqlite3_finalize(statement) }
        try bind([.text(id)], to: statement, database: database)
        let result = sqlite3_step(statement)
        if result == SQLITE_DONE { return nil }
        guard result == SQLITE_ROW, let mime = columnText(statement, 1) else { throw sqliteError(database: database) }
        return PersonalAssetMetadata(id: id, size: Int(sqlite3_column_int64(statement, 0)), mimeType: mime)
    }

    private static func readStagedAsset(database: OpaquePointer, sessionID: String, id: String) throws -> PersonalAsset? {
        let statement = try prepare(database: database, sql: "SELECT mime_type, size, bytes FROM restore_staging WHERE session_id = ? AND asset_id = ? LIMIT 1")
        defer { sqlite3_finalize(statement) }
        try bind([.text(sessionID), .text(id)], to: statement, database: database)
        let step = sqlite3_step(statement)
        if step == SQLITE_DONE { return nil }
        guard step == SQLITE_ROW, let mime = columnText(statement, 0) else { throw sqliteError(database: database) }
        let count = Int(sqlite3_column_int64(statement, 1))
        if count == 0 { return PersonalAsset(id: id, bytes: Data(), mimeType: mime) }
        guard count > 0, sqlite3_column_bytes(statement, 2) == Int32(count), let raw = sqlite3_column_blob(statement, 2) else { throw PersonalStoreError.assetIntegrity("恢复暂存附件长度无效：\(id)") }
        return PersonalAsset(id: id, bytes: Data(bytes: raw, count: count), mimeType: mime)
    }

    private static func readStagedAssets(database: OpaquePointer, sessionID: String) throws -> [PersonalAsset] {
        let statement = try prepare(database: database, sql: "SELECT asset_id, mime_type, size, bytes FROM restore_staging WHERE session_id = ? ORDER BY asset_id")
        defer { sqlite3_finalize(statement) }
        try bind([.text(sessionID)], to: statement, database: database)
        var assets: [PersonalAsset] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { return assets }
            guard step == SQLITE_ROW, let id = columnText(statement, 0), let mime = columnText(statement, 1) else { throw sqliteError(database: database) }
            let size = Int(sqlite3_column_int64(statement, 2))
            guard size >= 0, size <= PersonalBackupLimits.maximumAssetBytes, sqlite3_column_bytes(statement, 3) == Int32(size) else { throw PersonalStoreError.assetIntegrity("恢复暂存附件大小无效：\(id)") }
            let bytes: Data
            if size == 0 { bytes = Data() }
            else if let raw = sqlite3_column_blob(statement, 3) { bytes = Data(bytes: raw, count: size) }
            else { throw PersonalStoreError.assetIntegrity("恢复暂存附件内容缺失：\(id)") }
            assets.append(PersonalAsset(id: id, bytes: bytes, mimeType: mime))
        }
    }

    private static func readStagedMetadata(database: OpaquePointer, sessionID: String) throws -> [PersonalAssetMetadata] {
        let statement = try prepare(database: database, sql: "SELECT asset_id, size, mime_type FROM restore_staging WHERE session_id = ? ORDER BY asset_id")
        defer { sqlite3_finalize(statement) }
        try bind([.text(sessionID)], to: statement, database: database)
        var result: [PersonalAssetMetadata] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { return result }
            guard step == SQLITE_ROW, let id = columnText(statement, 0), let mime = columnText(statement, 2) else { throw sqliteError(database: database) }
            result.append(PersonalAssetMetadata(id: id, size: Int(sqlite3_column_int64(statement, 1)), mimeType: mime))
        }
    }

    private static func withTransaction<T>(database: OpaquePointer, operation: (OpaquePointer) throws -> T) throws -> T {
        try execute(database: database, sql: "BEGIN IMMEDIATE")
        do {
            let value = try operation(database)
            try execute(database: database, sql: "COMMIT")
            return value
        } catch {
            try? execute(database: database, sql: "ROLLBACK")
            throw error
        }
    }

    private static func readIDs(database: OpaquePointer, sql: String) throws -> [String] {
        let statement = try prepare(database: database, sql: sql)
        defer { sqlite3_finalize(statement) }
        var result: [String] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { return result }
            guard step == SQLITE_ROW, let text = columnText(statement, 0) else { throw sqliteError(database: database) }
            result.append(text)
        }
    }

    private static func scalarOptionalInt(database: OpaquePointer, sql: String, values: [SQLValue]) throws -> Int? {
        let statement = try prepare(database: database, sql: sql)
        defer { sqlite3_finalize(statement) }
        try bind(values, to: statement, database: database)
        let result = sqlite3_step(statement)
        if result == SQLITE_DONE || sqlite3_column_type(statement, 0) == SQLITE_NULL { return nil }
        guard result == SQLITE_ROW else { throw sqliteError(database: database) }
        return Int(sqlite3_column_int64(statement, 0))
    }

    private static func scalarInt(database: OpaquePointer, sql: String, values: [SQLValue]) throws -> Int {
        try scalarOptionalInt(database: database, sql: sql, values: values) ?? 0
    }

    private static func execute(database: OpaquePointer, sql: String, values: [SQLValue] = []) throws {
        if values.isEmpty {
            let result = sqlite3_exec(database, sql, nil, nil, nil)
            guard result == SQLITE_OK else { throw sqliteError(database: database) }
            return
        }
        let statement = try prepare(database: database, sql: sql)
        defer { sqlite3_finalize(statement) }
        try bind(values, to: statement, database: database)
        let result = sqlite3_step(statement)
        guard result == SQLITE_DONE else { throw sqliteError(database: database) }
    }

    private static func prepare(database: OpaquePointer, sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        let result = sqlite3_prepare_v2(database, sql, -1, &statement, nil)
        guard result == SQLITE_OK, let statement else { throw sqliteError(database: database) }
        return statement
    }

    private static func bind(_ values: [SQLValue], to statement: OpaquePointer, database: OpaquePointer) throws {
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (offset, value) in values.enumerated() {
            let index = Int32(offset + 1)
            let result: Int32
            switch value {
            case .text(let string): result = string.withCString { sqlite3_bind_text(statement, index, $0, -1, transient) }
            case .integer(let number): result = sqlite3_bind_int64(statement, index, sqlite3_int64(number))
            case .blob(let data):
                if data.isEmpty { result = sqlite3_bind_zeroblob(statement, index, 0) }
                else { result = data.withUnsafeBytes { buffer in sqlite3_bind_blob(statement, index, buffer.baseAddress, Int32(buffer.count), transient) } }
            }
            guard result == SQLITE_OK else { throw sqliteError(database: database) }
        }
    }

    private static func columnText(_ statement: OpaquePointer, _ index: Int32) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL, let value = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: UnsafeRawPointer(value).assumingMemoryBound(to: CChar.self))
    }

    private static func sqliteError(database: OpaquePointer) -> PersonalStoreError {
        .storage(String(cString: sqlite3_errmsg(database)))
    }
}

private enum SQLValue { case text(String); case integer(Int); case blob(Data) }
