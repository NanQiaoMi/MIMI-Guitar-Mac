import Foundation

public struct PersonalDataValidationError: Error, LocalizedError, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

public enum PersonalDataValidator {
    private static let sha256Pattern = try! NSRegularExpression(pattern: "^[a-f0-9]{64}$")

    /// Checks source-level optional/null distinctions before Codable collapses
    /// an omitted key and an explicit JSON null into the same Swift Optional.
    public static func validateBackupShape(_ raw: [String: Any]) throws {
        guard let scores = raw["scores"] as? [[String: Any]],
              let resumes = raw["resumes"] as? [[String: Any]],
              let sessions = raw["sessions"] as? [[String: Any]],
              let projects = raw["projects"] as? [[String: Any]] else {
            throw PersonalDataValidationError("scores, resumes, sessions 或 projects 的 JSON 形状无效")
        }
        for (index, score) in scores.enumerated() {
            try rejectExplicitNull(score, keys: ["scoreUrl", "assetId", "originalAssetId", "projectId"], label: "scores[\(index)]")
        }
        for (index, resume) in resumes.enumerated() {
            guard resume.keys.contains("loop") else { throw PersonalDataValidationError("resumes[\(index)].loop 缺失") }
            try rejectExplicitNull(resume, keys: ["playbackRatio", "trackMix", "display", "useSourceCapo"], label: "resumes[\(index)]")
            if let mixes = resume["trackMix"] as? [[String: Any]] {
                for (mixIndex, mix) in mixes.enumerated() {
                    try rejectExplicitNull(mix, keys: ["instrumentOverride"], label: "resumes[\(index)].trackMix[\(mixIndex)]")
                }
            }
        }
        for (index, session) in sessions.enumerated() {
            try rejectExplicitNull(session, keys: ["endedAt", "speedPlan"], label: "sessions[\(index)]")
            if let plan = session["speedPlan"] as? [String: Any] {
                try rejectExplicitNull(plan, keys: ["nativeAnchorBpm", "loopRange"], label: "sessions[\(index)].speedPlan")
            }
        }
        if let fragments = raw["practiceFragments"] as? [[String: Any]] {
            for (index, fragment) in fragments.enumerated() {
                try rejectExplicitNull(fragment, keys: ["deletedAt"], label: "practiceFragments[\(index)]")
            }
        }
        for (index, project) in projects.enumerated() {
            try rejectExplicitNull(project, keys: ["schemaVersion", "album", "words", "music", "tabber", "source", "importWarnings"], label: "projects[\(index)]")
            if let source = project["source"] as? [String: Any] {
                try rejectExplicitNull(source, keys: ["title"], label: "projects[\(index)].source")
            }
        }
    }

    public static func validate(_ data: PersonalData, strictProjects: Bool = false, rawProjects: [Any]? = nil) throws {
        guard data.schemaVersion == 1 || data.schemaVersion == 2 else { throw PersonalDataValidationError("不支持的个人数据 schemaVersion：\(data.schemaVersion)") }
        if data.schemaVersion == 1, let rawProjects, rawProjects.count != data.projects.count {
            throw PersonalDataValidationError("schemaVersion 1 的工程数量无效")
        }
        guard data.revision >= 0 else { throw PersonalDataValidationError("revision 必须是非负整数") }

        var scoreIDs = Set<String>()
        for (index, score) in data.scores.enumerated() {
            try requireID(score.id, "scores[\(index)].id")
            guard scoreIDs.insert(score.id).inserted else { throw PersonalDataValidationError("scores 中存在重复 ID：\(score.id)") }
            try requireID(score.source, "scores[\(index)].source")
            try requireID(score.sourceId, "scores[\(index)].sourceId")
            try requireID(score.revision, "scores[\(index)].revision")
            try requireID(score.title, "scores[\(index)].title")
            guard score.title.count <= 500, score.artist.count <= 500 else { throw PersonalDataValidationError("scores[\(index)] 标题或艺术家名称超长") }
            guard ["catalog", "private", "project"].contains(score.source) else { throw PersonalDataValidationError("scores[\(index)].source 无效") }
            guard ["guitar", "ukulele", "bass"].contains(score.category) else { throw PersonalDataValidationError("scores[\(index)].category 无效") }
            guard ["ibe", "gp", "xhe", "project"].contains(score.format) else { throw PersonalDataValidationError("scores[\(index)].format 无效") }
            try requireFinite(score.createdAt, "scores[\(index)].createdAt", min: 0)
            try requireFinite(score.updatedAt, "scores[\(index)].updatedAt", min: 0)
            if let url = score.scoreUrl, !isSafeLocalPath(url) { throw PersonalDataValidationError("scores[\(index)].scoreUrl 必须是站点内的安全路径") }
            for (name, value) in [("assetId", score.assetId), ("originalAssetId", score.originalAssetId), ("projectId", score.projectId)] {
                if let value { try requireID(value, "scores[\(index)].\(name)") }
            }
        }

        var unique = Set<String>()
        for (index, id) in data.favorites.enumerated() {
            try requireID(id, "favorites[\(index)]")
            guard unique.insert(id).inserted else { throw PersonalDataValidationError("favorites 中存在重复 ID：\(id)") }
            guard scoreIDs.contains(id) else { throw PersonalDataValidationError("favorites[\(index)] 引用了不存在的曲谱：\(id)") }
        }

        unique.removeAll(keepingCapacity: true)
        for (index, item) in data.practiceItems.enumerated() {
            try requireID(item.scoreId, "practiceItems[\(index)].scoreId")
            guard unique.insert(item.scoreId).inserted else { throw PersonalDataValidationError("practiceItems 中存在重复曲谱：\(item.scoreId)") }
            guard scoreIDs.contains(item.scoreId) else { throw PersonalDataValidationError("practiceItems[\(index)] 引用了不存在的曲谱：\(item.scoreId)") }
            guard PracticeStatus.allCases.contains(item.status) else { throw PersonalDataValidationError("practiceItems[\(index)].status 无效") }
            guard item.note.count <= 5_000 else { throw PersonalDataValidationError("practiceItems[\(index)].note 必须是 5000 字符以内的字符串") }
            try requireFinite(item.order, "practiceItems[\(index)].order")
            try requireFinite(item.updatedAt, "practiceItems[\(index)].updatedAt", min: 0)
        }

        unique.removeAll(keepingCapacity: true)
        for (index, resume) in data.resumes.enumerated() {
            try requireID(resume.scoreId, "resumes[\(index)].scoreId")
            guard unique.insert(resume.scoreId).inserted else { throw PersonalDataValidationError("resumes 中存在重复曲谱：\(resume.scoreId)") }
            guard scoreIDs.contains(resume.scoreId) else { throw PersonalDataValidationError("resumes[\(index)] 引用了不存在的曲谱：\(resume.scoreId)") }
            try requireID(resume.scoreRevision, "resumes[\(index)].scoreRevision")
            try requireFinite(resume.tick, "resumes[\(index)].tick", min: 0)
            try requireFinite(resume.timeMs, "resumes[\(index)].timeMs", min: 0)
            try requireFinite(resume.speed, "resumes[\(index)].speed", min: 0)
            try requireFinite(Double(resume.capo), "resumes[\(index)].capo", min: -1)
            try requireFinite(Double(resume.transpose), "resumes[\(index)].transpose")
            try requireFinite(resume.updatedAt, "resumes[\(index)].updatedAt", min: 0)
            guard (20...300).contains(resume.speed) else { throw PersonalDataValidationError("resumes[\(index)].speed 超出 20–300 BPM 范围") }
            if let ratio = resume.playbackRatio, !ratio.isFinite || ratio < 0.125 || ratio > 8 { throw PersonalDataValidationError("resumes[\(index)].playbackRatio 超出 0.125–8 范围") }
            if let mixes = resume.trackMix {
                guard mixes.count <= 1024 else { throw PersonalDataValidationError("resumes[\(index)].trackMix 最多保存 1024 条音轨混音") }
                var mixIndexes = Set<Int>()
                for (mixIndex, mix) in mixes.enumerated() {
                    guard (0...1023).contains(mix.index), mixIndexes.insert(mix.index).inserted else { throw PersonalDataValidationError("resumes[\(index)].trackMix[\(mixIndex)].index 必须唯一且在 0–1023 范围") }
                    try requireFinite(mix.volume, "resumes[\(index)].trackMix[\(mixIndex)].volume", min: 0)
                    guard mix.volume <= 100, (0...127).contains(mix.program) else { throw PersonalDataValidationError("resumes[\(index)].trackMix[\(mixIndex)] 音量或乐器超出范围") }
                }
            }
            if let display = resume.display {
                guard display.fontScale.isFinite, (0.6...1.6).contains(display.fontScale) else { throw PersonalDataValidationError("resumes[\(index)].display.fontScale 超出 0.6–1.6 范围") }
                guard ["name", "diagram"].contains(display.chordMode), ["mixed", "tab"].contains(display.scoreDisplayMode) else { throw PersonalDataValidationError("resumes[\(index)].display 显示模式无效") }
            }
            guard (-1...24).contains(resume.capo), (-48...48).contains(resume.transpose) else { throw PersonalDataValidationError("resumes[\(index)] 的 capo 或 transpose 超出范围") }
            if let loop = resume.loop { try validateRange(loop, label: "resumes[\(index)].loop", integer: false) }
            guard resume.trackIndexes.allSatisfy({ $0 >= 0 && $0 <= 9_007_199_254_740_991 }) else { throw PersonalDataValidationError("resumes[\(index)].trackIndexes 必须是非负安全整数") }
        }

        unique.removeAll(keepingCapacity: true)
        for (index, session) in data.sessions.enumerated() {
            try requireID(session.id, "sessions[\(index)].id")
            guard unique.insert(session.id).inserted else { throw PersonalDataValidationError("sessions 中存在重复 ID：\(session.id)") }
            try requireID(session.scoreId, "sessions[\(index)].scoreId")
            guard scoreIDs.contains(session.scoreId) else { throw PersonalDataValidationError("sessions[\(index)] 引用了不存在的曲谱：\(session.scoreId)") }
            try requireID(session.scoreRevision, "sessions[\(index)].scoreRevision")
            guard ["active", "paused", "interrupted", "completed"].contains(session.state) else { throw PersonalDataValidationError("sessions[\(index)].state 无效") }
            try requireFinite(session.startedAt, "sessions[\(index)].startedAt", min: 0)
            try requireFinite(session.updatedAt, "sessions[\(index)].updatedAt", min: 0)
            try requireID(session.timezone, "sessions[\(index)].timezone")
            guard session.note.count <= 5000 else { throw PersonalDataValidationError("sessions[\(index)].note 必须是 5000 字以内的字符串") }
            if let endedAt = session.endedAt { try requireFinite(endedAt, "sessions[\(index)].endedAt", min: 0) }
            if let plan = session.speedPlan {
                try requireID(plan.revision, "sessions[\(index)].speedPlan.revision")
                for (name, value) in [("startBpm", plan.startBpm), ("targetBpm", plan.targetBpm), ("stepBpm", plan.stepBpm), ("currentBpm", plan.currentBpm)] {
                    try requireFinite(value, "sessions[\(index)].speedPlan.\(name)", min: 0)
                }
                guard [plan.startBpm, plan.targetBpm, plan.currentBpm].allSatisfy({ (20...300).contains($0) }), plan.stepBpm > 0, plan.lapsPerLevel >= 1, plan.completedLaps >= 0 else { throw PersonalDataValidationError("sessions[\(index)].speedPlan 参数超出范围") }
                if let native = plan.nativeAnchorBpm, !native.isFinite || native <= 0 || native > 1000 { throw PersonalDataValidationError("sessions[\(index)].speedPlan.nativeAnchorBpm 超出范围") }
                if let loop = plan.loopRange { try validateRange(loop, label: "sessions[\(index)].speedPlan.loopRange", integer: true) }
            }
            var sliceIDs = Set<String>()
            var sequences = Set<String>()
            for (sliceIndex, slice) in session.slices.enumerated() {
                try requireID(slice.id, "sessions[\(index)].slices[\(sliceIndex)].id")
                guard sliceIDs.insert(slice.id).inserted else { throw PersonalDataValidationError("sessions[\(index)] 存在重复 slice ID：\(slice.id)") }
                try requireID(slice.epoch, "sessions[\(index)].slices[\(sliceIndex)].epoch")
                try requireFinite(slice.sequence, "sessions[\(index)].slices[\(sliceIndex)].sequence", min: 0)
                try requireFinite(slice.startedAt, "sessions[\(index)].slices[\(sliceIndex)].startedAt", min: 0)
                try requireFinite(slice.durationMs, "sessions[\(index)].slices[\(sliceIndex)].durationMs", min: 0)
                guard sequences.insert("\(slice.epoch)\0\(slice.sequence)").inserted else { throw PersonalDataValidationError("sessions[\(index)] 存在重复检查点 sequence") }
            }
        }

        if data.schemaVersion == 2 {
            unique.removeAll(keepingCapacity: true)
            for (index, fragment) in data.practiceFragments.enumerated() {
                try requireID(fragment.id, "practiceFragments[\(index)].id")
                guard unique.insert(fragment.id).inserted else { throw PersonalDataValidationError("practiceFragments 中存在重复 ID：\(fragment.id)") }
                try requireID(fragment.scoreId, "practiceFragments[\(index)].scoreId")
                guard scoreIDs.contains(fragment.scoreId) else { throw PersonalDataValidationError("practiceFragments[\(index)] 引用了不存在的曲谱：\(fragment.scoreId)") }
                guard isSHA256(fragment.scoreRevision) else { throw PersonalDataValidationError("practiceFragments[\(index)].scoreRevision 必须是小写 SHA-256") }
                guard !fragment.name.isEmpty, fragment.name == fragment.name.trimmingCharacters(in: .whitespacesAndNewlines), fragment.name.count <= 120, !containsControl(fragment.name) else { throw PersonalDataValidationError("practiceFragments[\(index)].name 必须是 1–120 字符的有效名称") }
                guard fragment.note.count <= 5000 else { throw PersonalDataValidationError("practiceFragments[\(index)].note 超过 5000 字符") }
                try validateRange(fragment.range, label: "practiceFragments[\(index)].range", integer: true)
                let speed = fragment.speed
                for (name, value) in [("nativeAnchorBpm", speed.nativeAnchorBpm), ("startBpm", speed.startBpm), ("targetBpm", speed.targetBpm), ("stepBpm", speed.stepBpm)] {
                    try requireFinite(value, "practiceFragments[\(index)].speed.\(name)", min: 0)
                }
                guard (1...1000).contains(speed.nativeAnchorBpm), (20...300).contains(speed.startBpm), speed.targetBpm >= speed.startBpm, speed.targetBpm <= 300,
                      speed.stepBpm > 0, speed.lapsPerLevel >= 1,
                      speed.startBpm / speed.nativeAnchorBpm >= 0.125, speed.startBpm / speed.nativeAnchorBpm <= 8,
                      speed.targetBpm / speed.nativeAnchorBpm >= 0.125, speed.targetBpm / speed.nativeAnchorBpm <= 8 else { throw PersonalDataValidationError("practiceFragments[\(index)].speed 参数超出有效范围") }
                try requireFinite(fragment.createdAt, "practiceFragments[\(index)].createdAt", min: 0)
                try requireFinite(fragment.updatedAt, "practiceFragments[\(index)].updatedAt", min: 0)
                guard fragment.updatedAt >= fragment.createdAt else { throw PersonalDataValidationError("practiceFragments[\(index)].updatedAt 不能早于 createdAt") }
                if let deletedAt = fragment.deletedAt {
                    try requireFinite(deletedAt, "practiceFragments[\(index)].deletedAt", min: 0)
                    guard deletedAt <= fragment.updatedAt else { throw PersonalDataValidationError("practiceFragments[\(index)].deletedAt 不能晚于 updatedAt") }
                }
            }
        } else if !data.practiceFragments.isEmpty {
            throw PersonalDataValidationError("schemaVersion 1 不支持 practiceFragments")
        }

        unique.removeAll(keepingCapacity: true)
        for (index, project) in data.projects.enumerated() {
            try validate(project, index: index)
            guard unique.insert(project.id).inserted else { throw PersonalDataValidationError("projects 中存在重复 ID：\(project.id)") }
            if strictProjects, let rawProjects, index < rawProjects.count { try validateProjectKeys(rawProjects[index], label: "projects[\(index)]") }
        }

        unique.removeAll(keepingCapacity: true)
        for (index, original) in data.originals.enumerated() {
            try requireID(original.id, "originals[\(index)].id")
            guard unique.insert(original.id).inserted else { throw PersonalDataValidationError("originals 中存在重复 ID：\(original.id)") }
            try requireID(original.fileName, "originals[\(index)].fileName")
            try requireID(original.mimeType, "originals[\(index)].mimeType")
            try requireID(original.assetId, "originals[\(index)].assetId")
            try requireFinite(original.savedAt, "originals[\(index)].savedAt", min: 0)
        }
        for (key, value) in data.settings {
            guard !key.isEmpty else { throw PersonalDataValidationError("settings 的 key 不能为空") }
            if case .number(let number) = value, !number.isFinite { throw PersonalDataValidationError("settings.\(key) 必须是有限数值") }
        }
        guard data.migrationCompleted == true || data.migrationCompleted == false else { throw PersonalDataValidationError("migrationCompleted 必须是布尔值") }
        for (index, entry) in data.history.enumerated() {
            try requireID(entry.id, "history[\(index)].id")
            try requireID(entry.title, "history[\(index)].title")
            try requireID(entry.url, "history[\(index)].url")
            guard isSafeLocalPath(entry.url) else { throw PersonalDataValidationError("history[\(index)].url 必须是站点内的安全路径") }
            try requireFinite(entry.time, "history[\(index)].time", min: 0)
        }
    }

    public static func isSHA256(_ value: String) -> Bool {
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return sha256Pattern.firstMatch(in: value, range: range) != nil
    }

    public static func isSafeLocalPath(_ value: String) -> Bool {
        guard value.count <= 2048, value.hasPrefix("/"), !value.hasPrefix("//"), !value.contains("\\"), !containsControl(value),
              let decoded = value.removingPercentEncoding, !decoded.hasPrefix("//"), !decoded.contains("\\"), !containsControl(decoded) else { return false }
        return true
    }

    private static func validate(_ project: StudioProject, index: Int) throws {
        let label = "projects[\(index)]"
        if let schema = project.schemaVersion, schema != 1 { throw PersonalDataValidationError("\(label).schemaVersion 无效") }
        for (field, value) in [("id", project.id), ("title", project.title), ("artist", project.artist), ("key", project.key)] {
            try requireID(value, "\(label).\(field)")
            guard value.count <= 500 else { throw PersonalDataValidationError("\(label).\(field) 超长") }
        }
        for (field, value) in [("album", project.album), ("words", project.words), ("music", project.music), ("tabber", project.tabber)] {
            if let value, value.count > 5000 { throw PersonalDataValidationError("\(label).\(field) 超长") }
        }
        guard (20...400).contains(project.initialTempo), (1...32).contains(project.timeSignatureNumerator), (1...32).contains(project.timeSignatureDenominator), project.createdAt.isFinite, project.updatedAt.isFinite else { throw PersonalDataValidationError("\(label) 元数据超出范围") }
        guard project.tracks.count <= 64, project.bars.count <= 10_000 else { throw PersonalDataValidationError("\(label) 音轨或小节数量超过安全上限") }
        var trackIDs = Set<String>()
        for (trackIndex, track) in project.tracks.enumerated() {
            try requireID(track.id, "\(label).tracks[\(trackIndex)].id")
            guard trackIDs.insert(track.id).inserted, track.name.count <= 500, track.tuningName.count <= 500,
                  (0...127).contains(track.program), track.tuning.allSatisfy({ (0...127).contains($0) }), (0...24).contains(track.capo),
                  track.volume.isFinite, (0...1).contains(track.volume), track.pan.isFinite, (-1...1).contains(track.pan) else { throw PersonalDataValidationError("\(label).tracks[\(trackIndex)] 音轨字段无效") }
        }
        for (barIndex, bar) in project.bars.enumerated() {
            try requireID(bar.id, "\(label).bars[\(barIndex)].id")
            guard (1...32).contains(bar.timeSignatureNumerator), (1...32).contains(bar.timeSignatureDenominator),
                  bar.tempo == nil || (bar.tempo!.isFinite && bar.tempo! > 0), bar.section == nil || bar.section!.count <= 500,
                  bar.repeatCount == nil || (2...8).contains(bar.repeatCount!), bar.volta == nil || (1...8).contains(bar.volta!) else { throw PersonalDataValidationError("\(label).bars[\(barIndex)] 拍号或标记无效") }
            var beatCount = 0
            var noteCount = 0
            for (trackID, beats) in bar.trackBeats {
                guard trackIDs.contains(trackID) else { throw PersonalDataValidationError("\(label).bars[\(barIndex)] 引用了未知音轨") }
                beatCount += beats.count
                guard beatCount <= 100_000 else { throw PersonalDataValidationError("工程单小节拍数超过安全上限") }
                for (beatIndex, beat) in beats.enumerated() {
                    try requireID(beat.id, "\(label).bars[\(barIndex)].beats[\(beatIndex)].id")
                    guard [1, 2, 4, 8, 16, 32].contains(beat.duration), beatCount <= 100_000 else { throw PersonalDataValidationError("\(label).bars[\(barIndex)] 拍时值无效") }
                    noteCount += beat.notes.count
                    guard noteCount <= 100_000 else { throw PersonalDataValidationError("工程单小节音符数超过安全上限") }
                    for note in beat.notes {
                        guard (1...12).contains(note.string), (0...36).contains(note.fret), note.bendValue == nil || (0...48).contains(note.bendValue!) else { throw PersonalDataValidationError("\(label).bars[\(barIndex)] 音符字段无效") }
                    }
                }
            }
        }
        if let source = project.source {
            try requireID(source.id, "\(label).source.id")
            try requireID(source.fileName, "\(label).source.fileName")
            guard ["file", "library"].contains(source.kind), source.id.count <= 512, source.fileName.count <= 500, !containsControl(source.fileName), source.title == nil || source.title!.count <= 500 else { throw PersonalDataValidationError("\(label).source 字段无效") }
            let formats = Set(["ibe", "gp", "gp3", "gp4", "gp5", "gpx", "gp7", "gp8", "musicxml", "xml", "tex", "alphatex", "json", "unknown"])
            guard formats.contains(source.format.lowercased()) else { throw PersonalDataValidationError("\(label).source.format 无效") }
        }
    }

    private static func validateRange(_ range: PracticeTickRange, label: String, integer: Bool) throws {
        let start = Double(range.startTick), end = Double(range.endTick)
        guard start >= 0, end > start, (!integer || (range.startTick <= 9_007_199_254_740_991 && range.endTick <= 9_007_199_254_740_991)) else { throw PersonalDataValidationError("\(label) 必须是非负 tick 的半开区间") }
    }

    private static func requireID(_ value: String, _ label: String) throws {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, value.count <= 512 else { throw PersonalDataValidationError("\(label) 必须是非空字符串") }
    }

    private static func requireFinite(_ value: Double, _ label: String, min: Double = -9_007_199_254_740_991) throws {
        guard value.isFinite, value >= min else { throw PersonalDataValidationError("\(label) 必须是有效数值") }
    }

    private static func containsControl(_ value: String) -> Bool {
        value.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
    }

    private static func validateProjectKeys(_ value: Any, label: String) throws {
        let projectKeys: Set<String> = ["schemaVersion", "id", "title", "artist", "album", "words", "music", "tabber", "key", "initialTempo", "timeSignatureNumerator", "timeSignatureDenominator", "tracks", "bars", "source", "importWarnings", "createdAt", "updatedAt"]
        guard let project = value as? [String: Any] else { throw PersonalDataValidationError("\(label) 必须是对象") }
        try checkKeys(project, allowed: projectKeys, label: label)
        if let tracks = project["tracks"] as? [[String: Any]] {
            let allowed: Set<String> = ["id", "name", "program", "tuning", "tuningName", "capo", "volume", "pan", "mute", "solo"]
            for (index, track) in tracks.enumerated() { try checkKeys(track, allowed: allowed, label: "\(label).tracks[\(index)]") }
        }
        if let bars = project["bars"] as? [[String: Any]] {
            let barAllowed: Set<String> = ["id", "index", "timeSignatureNumerator", "timeSignatureDenominator", "tempo", "section", "repeatStart", "repeatEnd", "repeatCount", "volta", "trackBeats"]
            let beatAllowed: Set<String> = ["id", "duration", "isRest", "dot", "triplet", "notes", "chordName", "lyrics", "brush"]
            let noteAllowed: Set<String> = ["string", "fret", "tie", "hammerPull", "slide", "bend", "bendValue", "harmonic", "harmonicType", "palmMute", "dead", "vibrato", "accent", "ghost"]
            for (index, bar) in bars.enumerated() {
                try checkKeys(bar, allowed: barAllowed, label: "\(label).bars[\(index)]")
                if let trackBeats = bar["trackBeats"] as? [String: [[String: Any]]] {
                    for (trackID, beats) in trackBeats {
                        for (beatIndex, beat) in beats.enumerated() {
                            try checkKeys(beat, allowed: beatAllowed, label: "\(label).bars[\(index)].trackBeats[\(trackID)][\(beatIndex)]")
                            if let notes = beat["notes"] as? [[String: Any]] {
                                for (noteIndex, note) in notes.enumerated() { try checkKeys(note, allowed: noteAllowed, label: "\(label).bars[\(index)].notes[\(noteIndex)]") }
                            }
                        }
                    }
                }
            }
        }
        if let source = project["source"] as? [String: Any] {
            try checkKeys(source, allowed: ["kind", "id", "fileName", "format", "title"], label: "\(label).source")
        }
    }

    private static func checkKeys(_ value: [String: Any], allowed: Set<String>, label: String) throws {
        if let unexpected = value.keys.first(where: { !allowed.contains($0) }) { throw PersonalDataValidationError("\(label) 包含不支持的字段：\(unexpected)") }
    }

    private static func rejectExplicitNull(_ value: [String: Any], keys: [String], label: String) throws {
        for key in keys where value.keys.contains(key) {
            if value[key] is NSNull { throw PersonalDataValidationError("\(label).\(key) 不能是 null") }
        }
    }
}
