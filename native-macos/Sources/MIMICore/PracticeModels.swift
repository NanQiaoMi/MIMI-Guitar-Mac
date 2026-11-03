import Foundation

public enum PracticeStatus: String, Codable, CaseIterable, Sendable {
    case todo
    case practicing
    case mastered
    case archived
}

public struct PracticeItem: Codable, Hashable, Sendable {
    public var scoreId: String
    public var status: PracticeStatus
    public var note: String
    public var order: Double
    public var updatedAt: Double

    public init(scoreId: String, status: PracticeStatus = .todo, note: String = "", order: Double = 0, updatedAt: Double = Date().timeIntervalSince1970 * 1000) {
        self.scoreId = scoreId; self.status = status; self.note = note; self.order = order; self.updatedAt = updatedAt
    }
}

public struct PracticeFragmentSpeed: Codable, Hashable, Sendable {
    public var nativeAnchorBpm: Double
    public var startBpm: Double
    public var targetBpm: Double
    public var stepBpm: Double
    public var lapsPerLevel: Int

    public init(nativeAnchorBpm: Double, startBpm: Double, targetBpm: Double, stepBpm: Double, lapsPerLevel: Int) {
        self.nativeAnchorBpm = nativeAnchorBpm; self.startBpm = startBpm; self.targetBpm = targetBpm
        self.stepBpm = stepBpm; self.lapsPerLevel = lapsPerLevel
    }
}

public struct PracticeTickRange: Codable, Hashable, Sendable {
    public var startTick: Int
    public var endTick: Int

    public init(startTick: Int, endTick: Int) { self.startTick = startTick; self.endTick = endTick }
}

public struct PracticeFragment: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var scoreId: String
    public var scoreRevision: String
    public var name: String
    public var note: String
    public var range: PracticeTickRange
    public var speed: PracticeFragmentSpeed
    public var createdAt: Double
    public var updatedAt: Double
    public var deletedAt: Double?

    public init(id: String, scoreId: String, scoreRevision: String, name: String, note: String = "", range: PracticeTickRange, speed: PracticeFragmentSpeed, createdAt: Double, updatedAt: Double, deletedAt: Double? = nil) {
        self.id = id; self.scoreId = scoreId; self.scoreRevision = scoreRevision; self.name = name; self.note = note
        self.range = range; self.speed = speed; self.createdAt = createdAt; self.updatedAt = updatedAt; self.deletedAt = deletedAt
    }
}

public struct PlayerTrackMix: Codable, Hashable, Sendable {
    public var index: Int
    public var muted: Bool
    public var soloed: Bool
    public var volume: Double
    public var program: Int
    public var instrumentOverride: Bool?

    public init(index: Int, muted: Bool, soloed: Bool, volume: Double, program: Int, instrumentOverride: Bool? = nil) {
        self.index = index; self.muted = muted; self.soloed = soloed; self.volume = volume
        self.program = program; self.instrumentOverride = instrumentOverride
    }
}

public struct PlayerDisplaySettings: Codable, Hashable, Sendable {
    public var fontScale: Double
    public var chordMode: String
    public var scoreDisplayMode: String
    public var numberTab: Bool
    public var showFretboard: Bool

    public init(fontScale: Double, chordMode: String, scoreDisplayMode: String, numberTab: Bool, showFretboard: Bool) {
        self.fontScale = fontScale; self.chordMode = chordMode; self.scoreDisplayMode = scoreDisplayMode
        self.numberTab = numberTab; self.showFretboard = showFretboard
    }
}

public struct PlayerResume: Codable, Hashable, Sendable {
    public var scoreId: String
    public var scoreRevision: String
    public var tick: Double
    public var timeMs: Double
    public var speed: Double
    public var playbackRatio: Double?
    public var trackMix: [PlayerTrackMix]?
    public var display: PlayerDisplaySettings?
    public var capo: Int
    public var useSourceCapo: Bool?
    public var transpose: Int
    public var loop: PracticeTickRange?
    public var trackIndexes: [Int]
    public var metronome: Bool
    public var countIn: Bool
    public var updatedAt: Double

    private enum CodingKeys: String, CodingKey {
        case scoreId, scoreRevision, tick, timeMs, speed, playbackRatio, trackMix, display, capo
        case useSourceCapo, transpose, loop, trackIndexes, metronome, countIn, updatedAt
    }

    public init(scoreId: String, scoreRevision: String, tick: Double = 0, timeMs: Double = 0, speed: Double = 120, playbackRatio: Double? = nil, trackMix: [PlayerTrackMix]? = nil, display: PlayerDisplaySettings? = nil, capo: Int = 0, useSourceCapo: Bool? = nil, transpose: Int = 0, loop: PracticeTickRange? = nil, trackIndexes: [Int] = [], metronome: Bool = false, countIn: Bool = false, updatedAt: Double = Date().timeIntervalSince1970 * 1000) {
        self.scoreId = scoreId; self.scoreRevision = scoreRevision; self.tick = tick; self.timeMs = timeMs; self.speed = speed
        self.playbackRatio = playbackRatio; self.trackMix = trackMix; self.display = display; self.capo = capo
        self.useSourceCapo = useSourceCapo; self.transpose = transpose; self.loop = loop; self.trackIndexes = trackIndexes
        self.metronome = metronome; self.countIn = countIn; self.updatedAt = updatedAt
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(scoreId, forKey: .scoreId)
        try values.encode(scoreRevision, forKey: .scoreRevision)
        try values.encode(tick, forKey: .tick)
        try values.encode(timeMs, forKey: .timeMs)
        try values.encode(speed, forKey: .speed)
        try values.encodeIfPresent(playbackRatio, forKey: .playbackRatio)
        try values.encodeIfPresent(trackMix, forKey: .trackMix)
        try values.encodeIfPresent(display, forKey: .display)
        try values.encode(capo, forKey: .capo)
        try values.encodeIfPresent(useSourceCapo, forKey: .useSourceCapo)
        try values.encode(transpose, forKey: .transpose)
        // The website schema requires this key and represents an inactive
        // loop as JSON null; Optional's synthesized encoder would omit it.
        try values.encode(loop, forKey: .loop)
        try values.encode(trackIndexes, forKey: .trackIndexes)
        try values.encode(metronome, forKey: .metronome)
        try values.encode(countIn, forKey: .countIn)
        try values.encode(updatedAt, forKey: .updatedAt)
    }
}

public struct PracticeSlice: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var sequence: Double
    public var epoch: String
    public var startedAt: Double
    public var durationMs: Double

    public init(id: String, sequence: Double, epoch: String, startedAt: Double, durationMs: Double) {
        self.id = id; self.sequence = sequence; self.epoch = epoch; self.startedAt = startedAt; self.durationMs = durationMs
    }

    public init(id: String, sequence: Int, epoch: String, startedAt: Double, durationMs: Double) {
        self.init(id: id, sequence: Double(sequence), epoch: epoch, startedAt: startedAt, durationMs: durationMs)
    }
}

public struct PracticeSpeedPlan: Codable, Hashable, Sendable {
    public var revision: String
    public var nativeAnchorBpm: Double?
    public var loopRange: PracticeTickRange?
    public var startBpm: Double
    public var targetBpm: Double
    public var stepBpm: Double
    public var lapsPerLevel: Int
    public var currentBpm: Double
    public var completedLaps: Int

    public init(revision: String, nativeAnchorBpm: Double? = nil, loopRange: PracticeTickRange? = nil, startBpm: Double, targetBpm: Double, stepBpm: Double, lapsPerLevel: Int, currentBpm: Double, completedLaps: Int) {
        self.revision = revision; self.nativeAnchorBpm = nativeAnchorBpm; self.loopRange = loopRange
        self.startBpm = startBpm; self.targetBpm = targetBpm; self.stepBpm = stepBpm
        self.lapsPerLevel = lapsPerLevel; self.currentBpm = currentBpm; self.completedLaps = completedLaps
    }
}

public struct PracticeSession: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var scoreId: String
    public var scoreRevision: String
    public var state: String
    public var startedAt: Double
    public var updatedAt: Double
    public var endedAt: Double?
    public var timezone: String
    public var slices: [PracticeSlice]
    public var note: String
    public var speedPlan: PracticeSpeedPlan?

    public init(id: String, scoreId: String, scoreRevision: String, state: String = "active", startedAt: Double, updatedAt: Double, endedAt: Double? = nil, timezone: String = TimeZone.current.identifier, slices: [PracticeSlice] = [], note: String = "", speedPlan: PracticeSpeedPlan? = nil) {
        self.id = id; self.scoreId = scoreId; self.scoreRevision = scoreRevision; self.state = state
        self.startedAt = startedAt; self.updatedAt = updatedAt; self.endedAt = endedAt; self.timezone = timezone
        self.slices = slices; self.note = note; self.speedPlan = speedPlan
    }
}
