import Foundation

public typealias StudioDuration = Int

public struct StudioNote: Codable, Hashable, Sendable {
    public var string: Int
    public var fret: Int
    public var tie: Bool?
    public var hammerPull: Bool?
    public var slide: Bool?
    public var bend: Bool?
    public var bendValue: Int?
    public var harmonic: Bool?
    public var harmonicType: String?
    public var palmMute: Bool?
    public var dead: Bool?
    public var vibrato: Bool?
    public var accent: Bool?
    public var ghost: Bool?

    public init(string: Int, fret: Int, tie: Bool? = nil, hammerPull: Bool? = nil, slide: Bool? = nil, bend: Bool? = nil, bendValue: Int? = nil, harmonic: Bool? = nil, harmonicType: String? = nil, palmMute: Bool? = nil, dead: Bool? = nil, vibrato: Bool? = nil, accent: Bool? = nil, ghost: Bool? = nil) {
        self.string = string; self.fret = fret; self.tie = tie; self.hammerPull = hammerPull; self.slide = slide
        self.bend = bend; self.bendValue = bendValue; self.harmonic = harmonic; self.harmonicType = harmonicType
        self.palmMute = palmMute; self.dead = dead; self.vibrato = vibrato; self.accent = accent; self.ghost = ghost
    }
}

public struct StudioBeat: Codable, Hashable, Sendable {
    public var id: String
    public var duration: StudioDuration
    public var isRest: Bool
    public var dot: Bool
    public var triplet: Bool
    public var notes: [StudioNote]
    public var chordName: String?
    public var lyrics: String?
    public var brush: String?

    public init(id: String, duration: StudioDuration, isRest: Bool, dot: Bool = false, triplet: Bool = false, notes: [StudioNote] = [], chordName: String? = nil, lyrics: String? = nil, brush: String? = nil) {
        self.id = id; self.duration = duration; self.isRest = isRest; self.dot = dot; self.triplet = triplet
        self.notes = notes; self.chordName = chordName; self.lyrics = lyrics; self.brush = brush
    }
}

public struct StudioBar: Codable, Hashable, Sendable {
    public var id: String
    public var index: Int
    public var timeSignatureNumerator: Int
    public var timeSignatureDenominator: Int
    public var tempo: Double?
    public var section: String?
    public var repeatStart: Bool?
    public var repeatEnd: Bool?
    public var repeatCount: Int?
    public var volta: Int?
    public var trackBeats: [String: [StudioBeat]]

    public init(id: String, index: Int, timeSignatureNumerator: Int, timeSignatureDenominator: Int, tempo: Double? = nil, section: String? = nil, repeatStart: Bool? = nil, repeatEnd: Bool? = nil, repeatCount: Int? = nil, volta: Int? = nil, trackBeats: [String: [StudioBeat]]) {
        self.id = id; self.index = index; self.timeSignatureNumerator = timeSignatureNumerator
        self.timeSignatureDenominator = timeSignatureDenominator; self.tempo = tempo; self.section = section
        self.repeatStart = repeatStart; self.repeatEnd = repeatEnd; self.repeatCount = repeatCount; self.volta = volta
        self.trackBeats = trackBeats
    }
}

public struct StudioTrack: Codable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var program: Int
    public var tuning: [Int]
    public var tuningName: String
    public var capo: Int
    public var volume: Double
    public var pan: Double
    public var mute: Bool
    public var solo: Bool

    public init(id: String, name: String, program: Int, tuning: [Int], tuningName: String, capo: Int = 0, volume: Double = 1, pan: Double = 0, mute: Bool = false, solo: Bool = false) {
        self.id = id; self.name = name; self.program = program; self.tuning = tuning; self.tuningName = tuningName
        self.capo = capo; self.volume = volume; self.pan = pan; self.mute = mute; self.solo = solo
    }
}

public struct StudioSource: Codable, Hashable, Sendable {
    public var kind: String
    public var id: String
    public var fileName: String
    public var format: String
    public var title: String?

    public init(kind: String, id: String, fileName: String, format: String, title: String? = nil) {
        self.kind = kind; self.id = id; self.fileName = fileName; self.format = format; self.title = title
    }
}

public struct StudioProject: Codable, Hashable, Identifiable, Sendable {
    public var schemaVersion: Int?
    public var id: String
    public var title: String
    public var artist: String
    public var album: String?
    public var words: String?
    public var music: String?
    public var tabber: String?
    public var key: String
    public var initialTempo: Int
    public var timeSignatureNumerator: Int
    public var timeSignatureDenominator: Int
    public var tracks: [StudioTrack]
    public var bars: [StudioBar]
    public var source: StudioSource?
    public var importWarnings: [String]?
    public var createdAt: Double
    public var updatedAt: Double

    public init(schemaVersion: Int? = 1, id: String, title: String, artist: String, album: String? = nil, words: String? = nil, music: String? = nil, tabber: String? = nil, key: String, initialTempo: Int, timeSignatureNumerator: Int, timeSignatureDenominator: Int, tracks: [StudioTrack], bars: [StudioBar], source: StudioSource? = nil, importWarnings: [String]? = nil, createdAt: Double, updatedAt: Double) {
        self.schemaVersion = schemaVersion; self.id = id; self.title = title; self.artist = artist; self.album = album
        self.words = words; self.music = music; self.tabber = tabber; self.key = key; self.initialTempo = initialTempo
        self.timeSignatureNumerator = timeSignatureNumerator; self.timeSignatureDenominator = timeSignatureDenominator
        self.tracks = tracks; self.bars = bars; self.source = source; self.importWarnings = importWarnings
        self.createdAt = createdAt; self.updatedAt = updatedAt
    }
}

public struct StudioCursorPosition: Codable, Hashable, Sendable {
    public var trackIndex: Int
    public var barIndex: Int
    public var beatIndex: Int
    public var stringIndex: Int

    public init(trackIndex: Int, barIndex: Int, beatIndex: Int, stringIndex: Int) {
        self.trackIndex = trackIndex; self.barIndex = barIndex; self.beatIndex = beatIndex; self.stringIndex = stringIndex
    }
}
