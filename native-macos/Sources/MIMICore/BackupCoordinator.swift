import CryptoKit
import Foundation

private struct PersonalBackupVolumeHeader: Codable, Equatable {
    let format: String
    let formatVersion: Int
    let snapshotId: String
    let sequence: Int
    let totalVolumes: Int
    let payloadBytes: Int
    let payloadSha256: String
    let chunks: [PersonalBackupV2Chunk]
}

/// Implements the website-compatible v1 JSON and v2 MIMI2VOL formats.
/// Large v2 imports are checked one volume at a time and kept in SQLite's
/// temporary staging table until the final merge transaction succeeds.
public actor BackupCoordinator {
    private let store: PersonalStore

    public init(store: PersonalStore) { self.store = store }

    public func exportV1() async throws -> Data {
        let data = try await store.snapshot()
        try Self.validateExportSnapshot(data)
        let ids = requiredPersonalAssetIDs(data).sorted()
        guard ids.count <= PersonalBackupLimits.maximumAssetCount else { throw PersonalBackupError.invalid("附件数量超过 500 个上限；没有生成部分备份。") }
        let metadata = try await store.assetMetadata(ids: ids)
        let metadataByID = Dictionary(uniqueKeysWithValues: metadata.map { ($0.id, $0) })
        guard metadata.count == ids.count else { throw PersonalBackupError.invalid("个人资料引用的附件缺失；完整备份未生成。") }
        let totalAssetBytes = try Self.checkedAssetBytes(metadata)
        guard totalAssetBytes <= PersonalBackupLimits.maximumReferencedAssetBytes else { throw PersonalBackupError.invalid("附件总量超过 927 MiB 上限；没有生成部分备份。") }

        let dataObject = try personalJSONObject(data)
        let dataJSON = try Self.jsonData(dataObject)
        guard dataJSON.count <= PersonalBackupLimits.maximumDataJSONBytes else { throw PersonalBackupError.invalid("个人资料清单超过 60 MiB 上限；没有生成部分备份。") }

        // Reject an oversized v1 export from metadata alone. In particular,
        // do this before reading/encoding any attachment bytes: a valid v2
        // archive may refer to hundreds of MiB that cannot fit in v1 JSON.
        let generatedAt = Self.iso8601Now()
        let descriptors = metadata.sorted { $0.id < $1.id }.map { PersonalBackupAssetDescriptor(id: $0.id, mimeType: $0.mimeType, size: $0.size) }
        let preflightManifest = PersonalBackupV1Manifest(
            formatVersion: 1,
            schemaVersion: data.schemaVersion,
            revision: data.revision,
            generatedAt: generatedAt,
            counts: backupDataCounts(data, assetCount: metadata.count),
            assets: descriptors,
            payloadSha256: String(repeating: "0", count: 64),
            assetBytes: totalAssetBytes
        )
        let placeholders: [[String: Any]] = metadata.map { ["id": $0.id, "mimeType": $0.mimeType, "size": $0.size, "base64": ""] }
        let preflightEnvelope: [String: Any] = [
            "format": PersonalBackupFormat.v1,
            "manifest": try personalJSONObject(preflightManifest),
            "payload": ["data": dataObject, "assets": placeholders],
        ]
        var estimatedBytes = try Self.jsonData(preflightEnvelope).count
        for descriptor in metadata {
            let (base64Bytes, overflow) = ((descriptor.size + 2) / 3).multipliedReportingOverflow(by: 4)
            guard !overflow else { throw PersonalBackupError.invalid("JSON 备份大小溢出。") }
            let (sum, addOverflow) = estimatedBytes.addingReportingOverflow(base64Bytes)
            guard !addOverflow else { throw PersonalBackupError.invalid("JSON 备份大小溢出。") }
            estimatedBytes = sum
        }
        guard estimatedBytes <= PersonalBackupLimits.maximumV1BackupBytes else { throw PersonalBackupError.invalid("JSON 备份预估超过 64 MiB 上限；请使用多卷备份，没有读取或编码附件。") }

        var assetRecords: [[String: Any]] = []
        assetRecords.reserveCapacity(ids.count)
        for id in ids {
            try Task.checkCancellation()
            guard let asset = try await store.asset(id: id), let declared = metadataByID[id],
                  asset.bytes.count == declared.size, asset.mimeType == declared.mimeType,
                  PersonalStore.sha256(asset.bytes) == id else {
                throw PersonalBackupError.invalid("附件 \(id) 缺失或 SHA-256/MIME/长度校验失败；完整备份未生成。")
            }
            guard PersonalStore.isValidMIMEType(asset.mimeType), asset.bytes.count <= PersonalBackupLimits.maximumAssetBytes else {
                throw PersonalBackupError.invalid("附件 \(id) 的 MIME 类型或长度超出安全上限。")
            }
            assetRecords.append(["id": id, "mimeType": asset.mimeType, "size": asset.bytes.count, "base64": asset.bytes.base64EncodedString()])
        }
        let payload: [String: Any] = ["data": dataObject, "assets": assetRecords]
        let payloadDigest = PersonalStore.sha256(personalCanonicalData(payload))
        let manifest = PersonalBackupV1Manifest(
            formatVersion: preflightManifest.formatVersion,
            schemaVersion: preflightManifest.schemaVersion,
            revision: preflightManifest.revision,
            generatedAt: preflightManifest.generatedAt,
            counts: preflightManifest.counts,
            assets: preflightManifest.assets,
            payloadSha256: payloadDigest,
            assetBytes: preflightManifest.assetBytes
        )
        let manifestObject = try personalJSONObject(manifest)
        let envelope: [String: Any] = ["format": PersonalBackupFormat.v1, "manifest": manifestObject, "payload": payload]
        let result = try Self.jsonData(envelope)
        guard result.count <= PersonalBackupLimits.maximumV1BackupBytes else { throw PersonalBackupError.invalid("JSON 备份超过 64 MiB 上限；没有生成部分备份。") }
        let after = try await store.snapshot()
        guard after.revision == data.revision else { throw PersonalBackupError.invalid("导出期间个人资料发生变化，请重新导出。") }
        return result
    }

    public func previewV1(_ bytes: Data) async throws -> PersonalBackupV1Preview {
        guard !bytes.isEmpty, bytes.count <= PersonalBackupLimits.maximumV1BackupBytes else { throw PersonalBackupError.invalid("备份文件必须大于 0 且不超过 64 MiB。") }
        let root = try Self.parseObject(bytes, label: "JSON 备份")
        guard root["format"] as? String == PersonalBackupFormat.v1 else { throw PersonalBackupError.invalid("备份格式不匹配。") }
        guard let manifestObject = root["manifest"] as? [String: Any], let payload = root["payload"] as? [String: Any] else { throw PersonalBackupError.invalid("备份缺少 manifest 或 payload。") }

        // Hash the original JSON.parse-equivalent payload before decoding into
        // Codable models. This preserves the web format's number/key semantics.
        guard let savedPayloadHash = manifestObject["payloadSha256"] as? String,
              PersonalDataValidator.isSHA256(savedPayloadHash),
              PersonalStore.sha256(personalCanonicalData(payload)) == savedPayloadHash else {
            throw PersonalBackupError.invalid("备份 payload SHA-256 校验失败。")
        }
        guard Self.int(manifestObject["formatVersion"]) == 1 else { throw PersonalBackupError.invalid("不支持的 JSON 备份版本。") }
        guard let schemaVersion = Self.int(manifestObject["schemaVersion"]), [1, 2].contains(schemaVersion),
              let manifestRevision = Self.int(manifestObject["revision"]), manifestRevision >= 0,
              let generatedAt = manifestObject["generatedAt"] as? String, Self.parseISO8601(generatedAt) != nil,
              let assetBytes = Self.int(manifestObject["assetBytes"]), assetBytes >= 0, assetBytes <= PersonalBackupLimits.maximumReferencedAssetBytes,
              let dataRaw = payload["data"] as? [String: Any], let assetEntries = payload["assets"] as? [[String: Any]] else {
            throw PersonalBackupError.invalid("manifest 字段无效或超出安全上限。")
        }
        guard let dataSchema = Self.int(dataRaw["schemaVersion"]), let dataRevision = Self.int(dataRaw["revision"]),
              dataSchema == schemaVersion, dataRevision == manifestRevision else { throw PersonalBackupError.invalid("manifest 与资料版本不一致。") }
        let data = try Self.decodePersonalData(dataRaw)
        try Self.validateBackupData(data, raw: dataRaw)
        guard Self.entityCount(data) <= PersonalBackupLimits.maximumEntityCount else { throw PersonalBackupError.invalid("个人资料实体总数超过 10,000 个上限。") }
        guard assetEntries.count <= PersonalBackupLimits.maximumAssetCount else { throw PersonalBackupError.invalid("附件数量超过 500 个上限。") }

        var assets: [PersonalAsset] = []
        var seen = Set<String>()
        var actualBytes = 0
        for (index, entry) in assetEntries.enumerated() {
            try Task.checkCancellation()
            guard let id = entry["id"] as? String, PersonalDataValidator.isSHA256(id),
                  let mimeType = entry["mimeType"] as? String, PersonalStore.isValidMIMEType(mimeType),
                  let size = Self.int(entry["size"]), size >= 0, size <= PersonalBackupLimits.maximumAssetBytes,
                  let base64 = entry["base64"] as? String else { throw PersonalBackupError.invalid("assets[\(index)] 字段无效。") }
            guard seen.insert(id).inserted else { throw PersonalBackupError.invalid("备份附件重复：\(id)") }
            guard let bytes = Data(base64Encoded: base64), bytes.base64EncodedString() == base64 else { throw PersonalBackupError.invalid("附件 \(id) 不是规范的 Base64 数据。") }
            guard bytes.count == size, PersonalStore.sha256(bytes) == id else { throw PersonalBackupError.invalid("附件 \(id) 长度或 SHA-256 校验失败。") }
            let (sum, overflow) = actualBytes.addingReportingOverflow(bytes.count)
            guard !overflow, sum <= PersonalBackupLimits.maximumReferencedAssetBytes else { throw PersonalBackupError.invalid("manifest 附件总量超过 927 MiB 上限。") }
            actualBytes = sum
            assets.append(PersonalAsset(id: id, bytes: bytes, mimeType: mimeType))
        }
        guard actualBytes == assetBytes else { throw PersonalBackupError.invalid("manifest 附件总大小不一致。") }
        let requiredIDs = requiredPersonalAssetIDs(data).sorted()
        guard requiredIDs == seen.sorted() else { throw PersonalBackupError.invalid("备份没有完整包含资料引用的附件，无法安全恢复。") }
        let descriptors = try Self.v1AssetDescriptors(manifestObject["assets"])
        let actualDescriptors = assets.map { PersonalBackupAssetDescriptor(id: $0.id, mimeType: $0.mimeType, size: $0.bytes.count) }.sorted { $0.id < $1.id }
        guard descriptors == actualDescriptors else { throw PersonalBackupError.invalid("manifest 附件清单不一致。") }
        guard Self.countsMatch(manifestObject["counts"], expected: backupDataCounts(data, assetCount: assets.count)) else { throw PersonalBackupError.invalid("manifest 实体计数不一致。") }
        let manifest = try Self.decode(PersonalBackupV1Manifest.self, from: manifestObject)
        let current = try await store.snapshot()
        let dataFingerprint = PersonalStore.sha256(personalCanonicalData(try personalJSONObject(data)))
        return PersonalBackupV1Preview(
            manifest: manifest,
            data: data,
            assets: assets,
            fileSize: bytes.count,
            expectedRevision: current.revision,
            verifiedPayloadSha256: savedPayloadHash,
            verifiedDataFingerprint: dataFingerprint
        )
    }

    public func restoreV1(_ preview: PersonalBackupV1Preview, expectedRevision: Int) async throws -> PersonalData {
        guard preview.format == PersonalBackupFormat.v1, expectedRevision == preview.expectedRevision else { throw PersonalBackupError.invalid("JSON 备份预览已失效，请重新预览后再恢复。") }
        guard preview.manifest.schemaVersion == preview.data.schemaVersion, preview.manifest.revision == preview.data.revision,
              requiredPersonalAssetIDs(preview.data) == Set(preview.assets.map(\.id)),
              preview.assets.allSatisfy({ PersonalStore.isValidMIMEType($0.mimeType) && $0.bytes.count <= PersonalBackupLimits.maximumAssetBytes && PersonalStore.sha256($0.bytes) == $0.id }) else {
            throw PersonalBackupError.invalid("备份预览资料或附件已变化；请重新预览。")
        }
        let dataFingerprint = PersonalStore.sha256(personalCanonicalData(try personalJSONObject(preview.data)))
        let descriptors = preview.assets.map { PersonalBackupAssetDescriptor(id: $0.id, mimeType: $0.mimeType, size: $0.bytes.count) }.sorted { $0.id < $1.id }
        let manifestDescriptors = preview.manifest.assets.sorted { $0.id < $1.id }
        let assetBytes = preview.assets.reduce(0) { $0 + $1.bytes.count }
        guard preview.verifiedPayloadSha256 == preview.manifest.payloadSha256,
              preview.verifiedDataFingerprint == dataFingerprint,
              descriptors == manifestDescriptors,
              assetBytes == preview.manifest.assetBytes else {
            throw PersonalBackupError.invalid("预览资料或附件与已验证的原始备份不一致；请重新预览。")
        }
        do { return try await store.restore(preview.data, assets: preview.assets, expectedRevision: expectedRevision) }
        catch { throw error }
    }

    public func exportV2(to directory: URL) async throws -> PersonalBackupV2Export {
        let data = try await store.snapshot()
        try Self.validateExportSnapshot(data)
        let dataObject = try personalJSONObject(data)
        let encodedData = try Self.jsonData(dataObject)
        guard encodedData.count <= PersonalBackupLimits.maximumDataJSONBytes else { throw PersonalBackupError.invalid("个人资料清单超过 60 MiB 上限；没有生成部分备份。") }
        let ids = requiredPersonalAssetIDs(data).sorted()
        guard ids.count <= PersonalBackupLimits.maximumAssetCount else { throw PersonalBackupError.invalid("附件数量超过 500 个上限；没有生成部分备份。") }
        let metadata = try await store.assetMetadata(ids: ids)
        guard metadata.count == ids.count else { throw PersonalBackupError.invalid("个人资料引用的附件 metadata 缺失。") }
        let assetBytes = try Self.checkedAssetBytes(metadata)
        guard assetBytes <= PersonalBackupLimits.maximumReferencedAssetBytes else { throw PersonalBackupError.invalid("附件总量超过 927 MiB 上限；没有生成部分备份。") }
        let metadataByID = Dictionary(uniqueKeysWithValues: metadata.map { ($0.id, $0) })
        var assets: [PersonalBackupV2Asset] = []
        var chunkGroups: [[PersonalBackupV2Chunk]] = []
        var currentChunks: [PersonalBackupV2Chunk] = []
        var currentBytes = 0

        for id in ids {
            try Task.checkCancellation()
            guard let declared = metadataByID[id], declared.size >= 0,
                  declared.size <= PersonalBackupLimits.maximumAssetBytes,
                  PersonalStore.isValidMIMEType(declared.mimeType),
                  let asset = try await store.asset(id: id), asset.bytes.count == declared.size,
                  asset.mimeType == declared.mimeType, PersonalStore.sha256(asset.bytes) == id else {
                throw PersonalBackupError.invalid("附件 \(id) 缺失或 SHA-256/MIME/长度校验失败；没有生成部分备份。")
            }
            let chunkCount = declared.size == 0 ? 0 : (declared.size + PersonalBackupLimits.volumeBytes - 1) / PersonalBackupLimits.volumeBytes
            assets.append(PersonalBackupV2Asset(id: id, mimeType: declared.mimeType, size: declared.size, chunkCount: chunkCount))
            for chunkIndex in 0..<chunkCount {
                let start = chunkIndex * PersonalBackupLimits.volumeBytes
                let length = min(PersonalBackupLimits.volumeBytes, declared.size - start)
                if currentBytes > 0 && currentBytes + length > PersonalBackupLimits.volumeBytes {
                    chunkGroups.append(currentChunks)
                    currentChunks = []
                    currentBytes = 0
                }
                let bytes = asset.bytes.subdata(in: start..<(start + length))
                currentChunks.append(PersonalBackupV2Chunk(assetId: id, chunkIndex: chunkIndex, byteLength: length, sha256: PersonalStore.sha256(bytes)))
                currentBytes += length
                if currentBytes == PersonalBackupLimits.volumeBytes {
                    chunkGroups.append(currentChunks)
                    currentChunks = []
                    currentBytes = 0
                }
            }
        }
        if !currentChunks.isEmpty { chunkGroups.append(currentChunks) }
        guard chunkGroups.count <= PersonalBackupLimits.maximumVolumeCount else { throw PersonalBackupError.invalid("附件按 8 MiB 分卷后超过 128 卷上限。") }

        let snapshotID = UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "_")
        let generatedAt = Self.iso8601Now()
        let finalFolderName = "MIMI-Personal-Backup-\(snapshotID)"
        let parent = directory.standardizedFileURL
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let temporaryDirectory = parent.appendingPathComponent(".\(finalFolderName).partial", isDirectory: true)
        let finalDirectory = parent.appendingPathComponent(finalFolderName, isDirectory: true)
        guard !FileManager.default.fileExists(atPath: temporaryDirectory.path), !FileManager.default.fileExists(atPath: finalDirectory.path) else { throw PersonalBackupError.invalid("备份输出目录已存在；请重新选择位置。") }
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: false)
        var temporaryOwned = true
        defer { if temporaryOwned { try? FileManager.default.removeItem(at: temporaryDirectory) } }

        var volumeDescriptors: [PersonalBackupV2Volume] = []
        var temporaryVolumeURLs: [URL] = []
        for (index, chunks) in chunkGroups.enumerated() {
            try Task.checkCancellation()
            let body = try await Self.makeVolumeBody(chunks: chunks, store: store)
            let payloadBytes = chunks.reduce(0) { $0 + $1.byteLength }
            guard body.count == payloadBytes else { throw PersonalBackupError.invalid("分卷负载长度计算不一致。") }
            let payloadHash = PersonalStore.sha256(body)
            let sequence = index + 1
            let header = PersonalBackupVolumeHeader(format: PersonalBackupFormat.v2, formatVersion: 2, snapshotId: snapshotID, sequence: sequence, totalVolumes: chunkGroups.count, payloadBytes: payloadBytes, payloadSha256: payloadHash, chunks: chunks)
            let headerBytes = try Self.encodeHeader(header)
            let byteLength = PersonalBackupFormat.volumeMagic.count + 4 + headerBytes.count + body.count
            let descriptor = PersonalBackupV2Volume(sequence: sequence, payloadBytes: payloadBytes, payloadSha256: payloadHash, byteLength: byteLength, chunks: chunks)
            let fileBytes = Self.volumeFile(header: headerBytes, payload: body)
            let fileName = String(format: "MIMI2VOL-%03d-of-%03d.mimivol", sequence, chunkGroups.count)
            let url = temporaryDirectory.appendingPathComponent(fileName, isDirectory: false)
            try fileBytes.write(to: url, options: .atomic)
            volumeDescriptors.append(descriptor)
            temporaryVolumeURLs.append(url)
        }
        let afterVolumes = try await store.snapshot()
        guard afterVolumes.revision == data.revision else { throw PersonalBackupError.invalid("导出期间个人资料发生变化，请重新导出。") }

        let base: [String: Any] = [
            "formatVersion": 2,
            "snapshotId": snapshotID,
            "schemaVersion": data.schemaVersion,
            "revision": data.revision,
            "generatedAt": generatedAt,
            "counts": backupDataCounts(data, assetCount: assets.count),
            "assetBytes": assetBytes,
            "assets": try assets.map { try personalJSONObject($0) },
            "volumes": try volumeDescriptors.map { try personalJSONObject($0) },
            "data": dataObject,
        ]
        let snapshotHash = PersonalStore.sha256(personalCanonicalData(base))
        var complete = base
        complete["snapshotSha256"] = snapshotHash
        let wrapper: [String: Any] = ["format": PersonalBackupFormat.v2, "manifest": complete]
        let manifestBytes = try Self.jsonData(wrapper)
        guard manifestBytes.count <= PersonalBackupLimits.maximumManifestBytes else { throw PersonalBackupError.invalid("备份清单超过 64 MiB 上限；没有生成完整备份。") }
        var totalFileBytes = manifestBytes.count
        for volume in volumeDescriptors {
            let (sum, overflow) = totalFileBytes.addingReportingOverflow(volume.byteLength)
            guard !overflow, sum <= PersonalBackupLimits.maximumBackupBytes else { throw PersonalBackupError.invalid("完整备份超过 1 GiB 总文件上限。") }
            totalFileBytes = sum
        }
        let manifestURLInTemporary = temporaryDirectory.appendingPathComponent("manifest.json", isDirectory: false)
        try manifestBytes.write(to: manifestURLInTemporary, options: .atomic)
        let manifest = try Self.decode(PersonalBackupV2Manifest.self, from: complete)
        let finalState = try await store.snapshot()
        guard finalState.revision == data.revision else { throw PersonalBackupError.invalid("导出期间个人资料发生变化，请重新导出。") }
        try FileManager.default.moveItem(at: temporaryDirectory, to: finalDirectory)
        temporaryOwned = false
        let volumeURLs = temporaryVolumeURLs.map { finalDirectory.appendingPathComponent($0.lastPathComponent, isDirectory: false) }
        return PersonalBackupV2Export(
            manifestURL: finalDirectory.appendingPathComponent("manifest.json", isDirectory: false),
            volumeURLs: volumeURLs,
            manifest: manifest,
            totalFileBytes: totalFileBytes
        )
    }

    public func previewV2(manifest bytes: Data, volumeURLs: [URL]) async throws -> PersonalBackupV2Preview {
        guard !bytes.isEmpty, bytes.count <= PersonalBackupLimits.maximumManifestBytes else { throw PersonalBackupError.invalid("v2 manifest 必须大于 0 且不超过 64 MiB。") }
        let rawManifest = try Self.unwrapV2Manifest(Self.parseObject(bytes, label: "v2 backup envelope"))
        let manifest = try Self.decodeV2Manifest(rawManifest)
        try Self.validateV2Manifest(manifest, raw: rawManifest, manifestBytes: bytes.count)
        guard volumeURLs.count == manifest.volumes.count else { throw PersonalBackupError.invalid("所选分卷数量与 manifest 不一致。") }
        let stageID = UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "_")
        var stageStarted = false
        do {
            var totalBytes = bytes.count
            var urlsBySequence: [Int: URL] = [:]
            for url in volumeURLs {
                try Task.checkCancellation()
                let header = try Self.readVolumeHeader(url)
                guard header.format == PersonalBackupFormat.v2, header.formatVersion == 2,
                      header.snapshotId == manifest.snapshotId,
                      header.sequence >= 1, header.sequence <= manifest.volumes.count,
                      urlsBySequence[header.sequence] == nil else { throw PersonalBackupError.invalid("分卷标识、快照或序号重复/无效。") }
                urlsBySequence[header.sequence] = url
                let size = try Self.fileSize(url)
                let (sum, overflow) = totalBytes.addingReportingOverflow(size)
                guard !overflow, sum <= PersonalBackupLimits.maximumBackupBytes else { throw PersonalBackupError.invalid("完整备份超过 1 GiB 总文件上限。") }
                totalBytes = sum
            }
            guard urlsBySequence.count == manifest.volumes.count else { throw PersonalBackupError.invalid("缺少一个或多个分卷。") }
            var assetIndex = 0
            var assembling = Data()
            var consumedBytes = 0
            var reusableAssetIDs = Set<String>()
            func retainOrStage(_ descriptor: PersonalBackupV2Asset, bytes: Data) async throws {
                if let active = try await store.asset(id: descriptor.id) {
                    guard active.bytes.count == descriptor.size, PersonalStore.sha256(active.bytes) == descriptor.id else {
                        throw PersonalBackupError.invalid("本机已有附件 \(descriptor.id) 内容异常；没有覆盖任何资料。")
                    }
                    reusableAssetIDs.insert(descriptor.id)
                } else {
                    try await store.stageRestoreAsset(sessionID: stageID, asset: PersonalAsset(id: descriptor.id, bytes: bytes, mimeType: descriptor.mimeType))
                    stageStarted = true
                }
            }
            func stageEmptyAssets() async throws {
                while assetIndex < manifest.assets.count, manifest.assets[assetIndex].chunkCount == 0 {
                    let item = manifest.assets[assetIndex]
                    guard item.size == 0, PersonalStore.sha256(Data()) == item.id else { throw PersonalBackupError.invalid("零长度附件 \(item.id) 摘要无效。") }
                    try await retainOrStage(item, bytes: Data())
                    assetIndex += 1
                }
            }
            try await stageEmptyAssets()
            for descriptor in manifest.volumes {
                try Task.checkCancellation()
                guard let url = urlsBySequence[descriptor.sequence] else { throw PersonalBackupError.invalid("缺少分卷 \(descriptor.sequence)。") }
                let file = try Self.readVolumeFile(url, descriptor: descriptor, manifest: manifest)
                consumedBytes += descriptor.byteLength
                var payloadOffset = 0
                for chunk in descriptor.chunks {
                    guard assetIndex < manifest.assets.count else { throw PersonalBackupError.invalid("分卷包含 manifest 之外的附件。") }
                    let assetDescriptor = manifest.assets[assetIndex]
                    guard chunk.assetId == assetDescriptor.id, chunk.chunkIndex == Self.consumedBytesChunkIndex(assetDescriptor: assetDescriptor, accumulated: assembling.count),
                          payloadOffset + chunk.byteLength <= file.payload.count else { throw PersonalBackupError.invalid("附件分块顺序、长度或 ID 无效。") }
                    let end = payloadOffset + chunk.byteLength
                    let chunkBytes = file.payload.subdata(in: payloadOffset..<end)
                    guard PersonalStore.sha256(chunkBytes) == chunk.sha256 else { throw PersonalBackupError.invalid("附件 \(chunk.assetId) 分块 SHA-256 校验失败。") }
                    assembling.append(chunkBytes)
                    payloadOffset = end
                    if assembling.count == assetDescriptor.size {
                        guard PersonalStore.sha256(assembling) == assetDescriptor.id else { throw PersonalBackupError.invalid("附件 \(assetDescriptor.id) SHA-256 校验失败。") }
                        try await retainOrStage(assetDescriptor, bytes: assembling)
                        assembling = Data()
                        assetIndex += 1
                        try await stageEmptyAssets()
                    }
                }
                guard payloadOffset == file.payload.count else { throw PersonalBackupError.invalid("分卷 \(descriptor.sequence) 含未声明数据。") }
            }
            try await stageEmptyAssets()
            guard assetIndex == manifest.assets.count, assembling.isEmpty else { throw PersonalBackupError.invalid("一个或多个附件分块缺失。") }
            guard consumedBytes + bytes.count == totalBytes else { throw PersonalBackupError.invalid("备份文件总长度计算不一致。") }
            let staged = try await store.stagedAssetMetadata(sessionID: stageID)
            let expected = manifest.assets.filter { !reusableAssetIDs.contains($0.id) }.map { PersonalAssetMetadata(id: $0.id, size: $0.size, mimeType: $0.mimeType) }
            guard staged == expected else { throw PersonalBackupError.invalid("分卷暂存附件清单与 manifest 不一致。") }
            let current = try await store.snapshot()
            return PersonalBackupV2Preview(manifest: manifest, fileSize: totalBytes, expectedRevision: current.revision, stagingSessionID: stageID, rawManifest: bytes)
        } catch {
            if stageStarted {
                do { try await store.clearRestoreStage(sessionID: stageID) }
                catch { throw PersonalBackupError.invalid("\(error.localizedDescription)；临时附件暂存未能确认清理，请重新打开备份页面后重试。") }
            }
            if Task.isCancelled { throw PersonalBackupError.cancelled }
            throw error
        }
    }

    public func restoreV2(_ preview: PersonalBackupV2Preview, expectedRevision: Int) async throws -> PersonalData {
        guard preview.format == PersonalBackupFormat.v2, expectedRevision == preview.expectedRevision else {
            try? await store.clearRestoreStage(sessionID: preview.stagingSessionID)
            throw PersonalBackupError.invalid("v2 备份预览 revision 已失效；请重新校验。")
        }
        do {
            let raw = try Self.unwrapV2Manifest(Self.parseObject(preview.rawManifest, label: "v2 backup envelope"))
            let verified = try Self.decodeV2Manifest(raw)
            try Self.validateV2Manifest(verified, raw: raw, manifestBytes: preview.rawManifest.count)
            guard verified == preview.manifest, preview.data == verified.data,
                  PersonalStore.sha256(personalCanonicalData(Self.manifestDigestInput(raw))) == verified.snapshotSha256 else {
                throw PersonalBackupError.invalid("v2 预览资料或 manifest SHA-256 不匹配；请重新校验。")
            }
            let metadata = verified.assets.map { PersonalAssetMetadata(id: $0.id, size: $0.size, mimeType: $0.mimeType) }
            return try await store.restoreStaged(verified.data, sessionID: preview.stagingSessionID, expectedMetadata: metadata, expectedRevision: expectedRevision)
        } catch {
            do { try await store.clearRestoreStage(sessionID: preview.stagingSessionID) }
            catch { throw PersonalBackupError.invalid("\(error.localizedDescription)；恢复没有提交，临时附件暂存未能确认清理。") }
            if Task.isCancelled { throw PersonalBackupError.cancelled }
            throw error
        }
    }

    public func cancelV2Preview(_ preview: PersonalBackupV2Preview) async throws {
        guard preview.format == PersonalBackupFormat.v2 else { return }
        try await store.clearRestoreStage(sessionID: preview.stagingSessionID)
    }

    private static func validateExportSnapshot(_ data: PersonalData) throws {
        guard data.migrationCompleted else { throw PersonalBackupError.invalid("个人资料迁移状态未完成；完整备份未生成。") }
        guard entityCount(data) <= PersonalBackupLimits.maximumEntityCount else { throw PersonalBackupError.invalid("个人资料实体总数超过 10,000 个上限；没有生成部分备份。") }
        do { try PersonalDataValidator.validate(data, strictProjects: true, rawProjects: (try personalJSONObject(data) as? [String: Any])?["projects"] as? [Any]) }
        catch { throw PersonalBackupError.invalid(error.localizedDescription) }
    }

    private static func validateBackupData(_ data: PersonalData, raw: [String: Any]) throws {
        do {
            try PersonalDataValidator.validateBackupShape(raw)
            try PersonalDataValidator.validate(data, strictProjects: true, rawProjects: raw["projects"] as? [Any])
        }
        catch { throw PersonalBackupError.invalid(error.localizedDescription) }
    }

    private static func entityCount(_ data: PersonalData) -> Int {
        data.scores.count + data.favorites.count + data.practiceItems.count + data.practiceFragments.count + data.resumes.count + data.sessions.count + data.projects.count + data.originals.count + data.history.count
    }

    private static func checkedAssetBytes(_ metadata: [PersonalAssetMetadata]) throws -> Int {
        guard metadata.count <= PersonalBackupLimits.maximumAssetCount else { throw PersonalBackupError.invalid("附件数量超过 500 个上限。") }
        var total = 0
        var seen = Set<String>()
        for asset in metadata {
            guard seen.insert(asset.id).inserted, PersonalDataValidator.isSHA256(asset.id),
                  asset.size >= 0, asset.size <= PersonalBackupLimits.maximumAssetBytes,
                  PersonalStore.isValidMIMEType(asset.mimeType) else { throw PersonalBackupError.invalid("附件 metadata 无效：\(asset.id)") }
            let (sum, overflow) = total.addingReportingOverflow(asset.size)
            guard !overflow else { throw PersonalBackupError.invalid("附件总大小溢出。") }
            total = sum
        }
        return total
    }

    private static func parseObject(_ bytes: Data, label: String) throws -> [String: Any] {
        let value: Any
        do { value = try JSONSerialization.jsonObject(with: bytes, options: [.fragmentsAllowed]) }
        catch { throw PersonalBackupError.invalid("\(label) 不是有效的 JSON 文件。") }
        guard let object = value as? [String: Any] else { throw PersonalBackupError.invalid("\(label) 必须是 JSON 对象。") }
        return object
    }

    /// Website v2 backups wrap the hashed manifest in a format envelope.
    /// Accept the earlier native direct-manifest form as an import-only legacy
    /// compatibility path so backups already exported by this app remain usable.
    private static func unwrapV2Manifest(_ root: [String: Any]) throws -> [String: Any] {
        if let format = root["format"] {
            guard format as? String == PersonalBackupFormat.v2,
                  let manifest = root["manifest"] as? [String: Any] else {
                throw PersonalBackupError.invalid("分卷备份清单格式不匹配或缺少 manifest。")
            }
            return manifest
        }
        guard root["formatVersion"] != nil else { throw PersonalBackupError.invalid("分卷备份清单缺少格式标识。") }
        return root
    }

    private static func decode<T: Decodable>(_ type: T.Type, from value: Any) throws -> T {
        let data = Data(canonicalPersonalJSON(value).utf8)
        do { return try JSONDecoder().decode(type, from: data) }
        catch { throw PersonalBackupError.invalid("备份字段无法解码：\(error.localizedDescription)") }
    }

    private static func decodePersonalData(_ raw: [String: Any]) throws -> PersonalData {
        try decode(PersonalData.self, from: raw)
    }

    private static func jsonData(_ value: Any) throws -> Data {
        do { return try JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed, .withoutEscapingSlashes]) }
        catch { throw PersonalBackupError.invalid("备份无法编码为 JSON：\(error.localizedDescription)") }
    }

    private static func int(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let double = number.doubleValue
        guard double.isFinite, double.rounded(.towardZero) == double, abs(double) <= 9_007_199_254_740_991 else { return nil }
        return Int(double)
    }

    private static func countsMatch(_ value: Any?, expected: [String: Int]) -> Bool {
        guard let raw = value as? [String: Any], Set(raw.keys) == Set(expected.keys) else { return false }
        for (key, count) in expected where int(raw[key]) != count { return false }
        return true
    }

    private static func v1AssetDescriptors(_ value: Any?) throws -> [PersonalBackupAssetDescriptor] {
        guard let rows = value as? [[String: Any]], rows.count <= PersonalBackupLimits.maximumAssetCount else { throw PersonalBackupError.invalid("manifest 附件清单无效。") }
        var result: [PersonalBackupAssetDescriptor] = []
        var seen = Set<String>()
        for row in rows {
            guard let id = row["id"] as? String, PersonalDataValidator.isSHA256(id), seen.insert(id).inserted,
                  let mime = row["mimeType"] as? String, PersonalStore.isValidMIMEType(mime),
                  let size = int(row["size"]), size >= 0, size <= PersonalBackupLimits.maximumAssetBytes else { throw PersonalBackupError.invalid("manifest 附件条目无效。") }
            result.append(PersonalBackupAssetDescriptor(id: id, mimeType: mime, size: size))
        }
        return result.sorted { $0.id < $1.id }
    }

    private static func iso8601Now() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }

    private static func parseISO8601(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }

    private static func encodeHeader(_ header: PersonalBackupVolumeHeader) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        let bytes = try encoder.encode(header)
        guard !bytes.isEmpty, bytes.count <= 256 * 1_024 else { throw PersonalBackupError.invalid("分卷头信息超过 256 KiB 上限。") }
        return bytes
    }

    private static func volumeFile(header: Data, payload: Data) -> Data {
        var result = Data()
        result.reserveCapacity(PersonalBackupFormat.volumeMagic.count + 4 + header.count + payload.count)
        result.append(PersonalBackupFormat.volumeMagic)
        var length = UInt32(header.count).bigEndian
        withUnsafeBytes(of: &length) { result.append(contentsOf: $0) }
        result.append(header)
        result.append(payload)
        return result
    }

    private static func makeVolumeBody(chunks: [PersonalBackupV2Chunk], store: PersonalStore) async throws -> Data {
        var body = Data()
        let expectedBytes = chunks.reduce(0) { $0 + $1.byteLength }
        body.reserveCapacity(expectedBytes)
        var assetID: String?
        var currentAsset: PersonalAsset?
        for chunk in chunks {
            if assetID != chunk.assetId {
                guard let loaded = try await store.asset(id: chunk.assetId), PersonalStore.sha256(loaded.bytes) == loaded.id else { throw PersonalBackupError.invalid("导出期间附件缺失或摘要异常：\(chunk.assetId)") }
                assetID = chunk.assetId
                currentAsset = loaded
            }
            guard let asset = currentAsset else { throw PersonalBackupError.invalid("导出附件数据缺失：\(chunk.assetId)") }
            let start = chunk.chunkIndex * PersonalBackupLimits.volumeBytes
            let end = start + chunk.byteLength
            guard start >= 0, end <= asset.bytes.count else { throw PersonalBackupError.invalid("导出附件分块范围无效：\(chunk.assetId)") }
            let bytes = asset.bytes.subdata(in: start..<end)
            guard PersonalStore.sha256(bytes) == chunk.sha256 else { throw PersonalBackupError.invalid("导出附件分块摘要不一致：\(chunk.assetId)") }
            body.append(bytes)
        }
        return body
    }

    private static func decodeV2Manifest(_ raw: [String: Any]) throws -> PersonalBackupV2Manifest {
        guard let data = raw["data"] as? [String: Any] else { throw PersonalBackupError.invalid("v2 manifest 缺少资料。") }
        let typedData = try decodePersonalData(data)
        try validateBackupData(typedData, raw: data)
        var copy = raw
        copy["data"] = try personalJSONObject(typedData)
        let typed = try decode(PersonalBackupV2Manifest.self, from: copy)
        return PersonalBackupV2Manifest(
            formatVersion: typed.formatVersion,
            snapshotId: typed.snapshotId,
            schemaVersion: typed.schemaVersion,
            revision: typed.revision,
            generatedAt: typed.generatedAt,
            counts: typed.counts,
            assetBytes: typed.assetBytes,
            assets: typed.assets,
            volumes: typed.volumes,
            data: typedData,
            snapshotSha256: typed.snapshotSha256
        )
    }

    private static func manifestDigestInput(_ raw: [String: Any]) -> [String: Any] {
        var result = raw
        result.removeValue(forKey: "snapshotSha256")
        return result
    }

    private static func validateV2Manifest(_ manifest: PersonalBackupV2Manifest, raw: [String: Any], manifestBytes: Int) throws {
        guard manifestBytes > 0, manifestBytes <= PersonalBackupLimits.maximumManifestBytes,
              manifest.formatVersion == 2,
              manifest.snapshotId.range(of: "^[a-zA-Z0-9_-]{12,80}$", options: .regularExpression) != nil,
              [1, 2].contains(manifest.schemaVersion), manifest.revision >= 0,
              parseISO8601(manifest.generatedAt) != nil,
              PersonalDataValidator.isSHA256(manifest.snapshotSha256),
              manifest.data.schemaVersion == manifest.schemaVersion, manifest.data.revision == manifest.revision,
              PersonalStore.sha256(personalCanonicalData(manifestDigestInput(raw))) == manifest.snapshotSha256 else {
            throw PersonalBackupError.invalid("v2 manifest 版本、时间、SHA-256 或资料版本无效。")
        }
        guard entityCount(manifest.data) <= PersonalBackupLimits.maximumEntityCount else { throw PersonalBackupError.invalid("个人资料实体总数超过 10,000 个上限。") }
        guard manifest.assets.count <= PersonalBackupLimits.maximumAssetCount,
              manifest.volumes.count <= PersonalBackupLimits.maximumVolumeCount else { throw PersonalBackupError.invalid("附件或分卷数量超过上限。") }
        var assetTotal = 0
        var assetMap: [String: PersonalBackupV2Asset] = [:]
        var previousID: String?
        for asset in manifest.assets {
            guard PersonalDataValidator.isSHA256(asset.id), PersonalStore.isValidMIMEType(asset.mimeType),
                  asset.size >= 0, asset.size <= PersonalBackupLimits.maximumAssetBytes,
                  asset.chunkCount >= 0, asset.chunkCount == (asset.size == 0 ? 0 : (asset.size + PersonalBackupLimits.volumeBytes - 1) / PersonalBackupLimits.volumeBytes),
                  assetMap[asset.id] == nil, previousID == nil || previousID! < asset.id else { throw PersonalBackupError.invalid("v2 附件清单重复、未排序或字段无效。") }
            assetMap[asset.id] = asset
            previousID = asset.id
            let (sum, overflow) = assetTotal.addingReportingOverflow(asset.size)
            guard !overflow else { throw PersonalBackupError.invalid("附件总大小溢出。") }
            assetTotal = sum
        }
        guard assetTotal == manifest.assetBytes, assetTotal <= PersonalBackupLimits.maximumReferencedAssetBytes,
              Self.countsMatch(raw["counts"], expected: backupDataCounts(manifest.data, assetCount: manifest.assets.count)) else {
            throw PersonalBackupError.invalid("v2 manifest 附件总量或实体计数不一致。")
        }
        guard requiredPersonalAssetIDs(manifest.data).sorted() == manifest.assets.map(\.id) else { throw PersonalBackupError.invalid("备份没有完整包含个人资料引用的附件。") }
        let packed = packedVolumeCount(manifest.assets)
        guard packed == manifest.volumes.count else { throw PersonalBackupError.invalid("分卷数量与附件打包规则不一致。") }
        let hasChunks = manifest.assets.contains { $0.chunkCount > 0 }
        guard hasChunks == !manifest.volumes.isEmpty else { throw PersonalBackupError.invalid("附件数据与分卷数量不一致。") }

        var allChunks: [PersonalBackupV2Chunk] = []
        var declaredBytes = manifestBytes
        for (index, volume) in manifest.volumes.enumerated() {
            guard volume.sequence == index + 1, volume.payloadBytes > 0,
                  volume.payloadBytes <= PersonalBackupLimits.volumeBytes,
                  PersonalDataValidator.isSHA256(volume.payloadSha256),
                  volume.byteLength >= 12, volume.byteLength <= 12 + 256 * 1_024 + PersonalBackupLimits.volumeBytes,
                  !volume.chunks.isEmpty else { throw PersonalBackupError.invalid("分卷 \(index + 1) 描述字段无效。") }
            var chunkBytes = 0
            for chunk in volume.chunks {
                guard let asset = assetMap[chunk.assetId], chunk.chunkIndex >= 0, chunk.chunkIndex < asset.chunkCount,
                      chunk.byteLength > 0, chunk.byteLength <= PersonalBackupLimits.volumeBytes,
                      PersonalDataValidator.isSHA256(chunk.sha256) else { throw PersonalBackupError.invalid("分卷 \(volume.sequence) 含无效附件分块。") }
                let expectedLength = min(PersonalBackupLimits.volumeBytes, asset.size - chunk.chunkIndex * PersonalBackupLimits.volumeBytes)
                guard chunk.byteLength == expectedLength else { throw PersonalBackupError.invalid("附件 \(chunk.assetId) 分块长度无效。") }
                let (sum, overflow) = chunkBytes.addingReportingOverflow(chunk.byteLength)
                guard !overflow else { throw PersonalBackupError.invalid("分卷负载长度溢出。") }
                chunkBytes = sum
                allChunks.append(chunk)
            }
            guard chunkBytes == volume.payloadBytes else { throw PersonalBackupError.invalid("分卷 \(volume.sequence) 负载长度不一致。") }
            let header = PersonalBackupVolumeHeader(format: PersonalBackupFormat.v2, formatVersion: 2, snapshotId: manifest.snapshotId, sequence: volume.sequence, totalVolumes: manifest.volumes.count, payloadBytes: volume.payloadBytes, payloadSha256: volume.payloadSha256, chunks: volume.chunks)
            let headerBytes = try encodeHeader(header)
            guard volume.byteLength == 12 + headerBytes.count + volume.payloadBytes else { throw PersonalBackupError.invalid("分卷 \(volume.sequence) 声明长度不一致。") }
            let (sum, overflow) = declaredBytes.addingReportingOverflow(volume.byteLength)
            guard !overflow, sum <= PersonalBackupLimits.maximumBackupBytes else { throw PersonalBackupError.invalid("完整备份超过 1 GiB 总文件上限。") }
            declaredBytes = sum
        }
        var assetIndex = 0
        var expectedChunkIndex = 0
        for chunk in allChunks {
            while assetIndex < manifest.assets.count, manifest.assets[assetIndex].chunkCount == 0 { assetIndex += 1 }
            guard assetIndex < manifest.assets.count else { throw PersonalBackupError.invalid("分卷包含附件清单之外的数据。") }
            let expectedAsset = manifest.assets[assetIndex]
            guard chunk.assetId == expectedAsset.id, chunk.chunkIndex == expectedChunkIndex else { throw PersonalBackupError.invalid("附件分块重复、乱序或缺失。") }
            expectedChunkIndex += 1
            if expectedChunkIndex == expectedAsset.chunkCount { assetIndex += 1; expectedChunkIndex = 0 }
        }
        while assetIndex < manifest.assets.count, manifest.assets[assetIndex].chunkCount == 0 { assetIndex += 1 }
        guard assetIndex == manifest.assets.count else { throw PersonalBackupError.invalid("附件 \(manifest.assets[assetIndex].id) 分块缺失。") }
    }

    private static func packedVolumeCount(_ assets: [PersonalBackupV2Asset]) -> Int {
        var count = 0
        var payload = 0
        for asset in assets {
            var remaining = asset.size
            while remaining > 0 {
                let chunk = min(PersonalBackupLimits.volumeBytes, remaining)
                if payload > 0 && payload + chunk > PersonalBackupLimits.volumeBytes { count += 1; payload = 0 }
                payload += chunk
                remaining -= chunk
                if payload == PersonalBackupLimits.volumeBytes { count += 1; payload = 0 }
            }
        }
        if payload > 0 { count += 1 }
        return count
    }

    private static func consumedBytesChunkIndex(assetDescriptor: PersonalBackupV2Asset, accumulated: Int) -> Int {
        assetDescriptor.chunkCount == 0 ? -1 : accumulated / PersonalBackupLimits.volumeBytes
    }

    private static func readVolumeHeader(_ url: URL) throws -> PersonalBackupVolumeHeader {
        let startedAccess = url.startAccessingSecurityScopedResource()
        defer { if startedAccess { url.stopAccessingSecurityScopedResource() } }
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        guard let prefix = try file.read(upToCount: 12), prefix.count == 12,
              prefix.prefix(PersonalBackupFormat.volumeMagic.count) == PersonalBackupFormat.volumeMagic else { throw PersonalBackupError.invalid("分卷文件标识无效或文件太短。") }
        let lengthData = prefix.subdata(in: 8..<12)
        let headerLength = lengthData.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        guard headerLength > 0, headerLength <= 256 * 1_024,
              let bytes = try file.read(upToCount: Int(headerLength)), bytes.count == Int(headerLength) else { throw PersonalBackupError.invalid("分卷头长度无效。") }
        return try Self.decode(PersonalBackupVolumeHeader.self, from: JSONSerialization.jsonObject(with: bytes, options: [.fragmentsAllowed]))
    }

    private static func readVolumeFile(_ url: URL, descriptor: PersonalBackupV2Volume, manifest: PersonalBackupV2Manifest) throws -> (header: PersonalBackupVolumeHeader, payload: Data) {
        let startedAccess = url.startAccessingSecurityScopedResource()
        defer { if startedAccess { url.stopAccessingSecurityScopedResource() } }
        let size = try fileSize(url)
        guard size == descriptor.byteLength, size >= 12, size <= 12 + 256 * 1_024 + PersonalBackupLimits.volumeBytes else { throw PersonalBackupError.invalid("分卷 \(descriptor.sequence) 文件大小无效。") }
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        guard let prefix = try file.read(upToCount: 12), prefix.count == 12,
              prefix.prefix(PersonalBackupFormat.volumeMagic.count) == PersonalBackupFormat.volumeMagic else { throw PersonalBackupError.invalid("分卷 \(descriptor.sequence) 文件标识不匹配。") }
        let headerLength = Int(prefix[8..<12].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) })
        guard headerLength > 0, headerLength <= 256 * 1_024,
              let headerBytes = try file.read(upToCount: headerLength), headerBytes.count == headerLength,
              let payload = try file.read(upToCount: descriptor.payloadBytes), payload.count == descriptor.payloadBytes,
              try file.read(upToCount: 1)?.isEmpty != false else { throw PersonalBackupError.invalid("分卷 \(descriptor.sequence) 内容长度不一致。") }
        let header = try Self.decode(PersonalBackupVolumeHeader.self, from: JSONSerialization.jsonObject(with: headerBytes, options: [.fragmentsAllowed]))
        guard header.format == PersonalBackupFormat.v2, header.formatVersion == 2,
              header.snapshotId == manifest.snapshotId, header.sequence == descriptor.sequence,
              header.totalVolumes == manifest.volumes.count, header.payloadBytes == descriptor.payloadBytes,
              header.payloadSha256 == descriptor.payloadSha256, header.chunks == descriptor.chunks,
              PersonalStore.sha256(payload) == descriptor.payloadSha256 else { throw PersonalBackupError.invalid("分卷 \(descriptor.sequence) 头或 payload SHA-256 校验失败。") }
        return (header, payload)
    }

    private static func fileSize(_ url: URL) throws -> Int {
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true, let size = values.fileSize, size >= 0 else { throw PersonalBackupError.invalid("所选分卷不是普通文件。") }
        return size
    }
}

import CoreFoundation
