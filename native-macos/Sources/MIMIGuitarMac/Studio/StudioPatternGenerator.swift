import Foundation
import MIMICore

// MARK: - 吉他和弦把位定义 (Guitar Chord Voicing)

public struct GuitarChordVoicing: Identifiable, Hashable, Sendable {
    public var id: String { name }
    public let name: String
    public let displayName: String
    /// 从 1 弦到 6 弦的品位；nil 表示该弦不发音 (Mute/X)
    public let frets: [Int?]
    /// 根音所在弦 (1-6)，通常为 4、5 或 6 弦
    public let bassString: Int
    /// 该和弦在调性中的级数 (如 I, V, vi, IV)
    public let degree: String?

    public init(name: String, displayName: String, frets: [Int?], bassString: Int, degree: String? = nil) {
        self.name = name
        self.displayName = displayName
        self.frets = frets
        self.bassString = bassString
        self.degree = degree
    }

    /// 获取特定琴弦上的品位 (1-based: 1=高音E, 6=低音E)
    public func fret(forString stringNum: Int) -> Int? {
        guard stringNum >= 1 && stringNum <= 6, frets.indices.contains(stringNum - 1) else { return nil }
        return frets[stringNum - 1]
    }
}

// MARK: - 常用吉他和弦库 (Standard Guitar Chords Library)

public enum GuitarChordLibrary {
    public static let commonChords: [GuitarChordVoicing] = [
        // C 大调常用
        GuitarChordVoicing(name: "C", displayName: "C 大调主和弦", frets: [0, 1, 0, 2, 3, nil], bassString: 5, degree: "I"),
        GuitarChordVoicing(name: "G", displayName: "G 大三和弦", frets: [3, 0, 0, 0, 2, 3], bassString: 6, degree: "V"),
        GuitarChordVoicing(name: "Am", displayName: "A 小三和弦", frets: [0, 1, 2, 2, 0, nil], bassString: 5, degree: "vi"),
        GuitarChordVoicing(name: "Em", displayName: "E 小三和弦", frets: [0, 0, 0, 2, 2, 0], bassString: 6, degree: "iii"),
        GuitarChordVoicing(name: "F", displayName: "F 大三和弦 (简易/全横按)", frets: [1, 1, 2, 3, 3, 1], bassString: 6, degree: "IV"),
        GuitarChordVoicing(name: "Fmaj7", displayName: "F 大七和弦 (空灵清澈)", frets: [0, 1, 2, 3, nil, nil], bassString: 4, degree: "IV"),
        GuitarChordVoicing(name: "Dm", displayName: "D 小三和弦", frets: [1, 3, 2, 0, nil, nil], bassString: 4, degree: "ii"),
        GuitarChordVoicing(name: "G7", displayName: "G 属七和弦", frets: [1, 0, 0, 0, 2, 3], bassString: 6, degree: "V7"),

        // 现代流行色彩和弦
        GuitarChordVoicing(name: "Cadd9", displayName: "C 加九和弦 (现代流行声响)", frets: [3, 3, 0, 2, 3, nil], bassString: 5, degree: "I add9"),
        GuitarChordVoicing(name: "G/B", displayName: "G 转位和弦 (平滑低音走向)", frets: [3, 0, 0, 0, 2, nil], bassString: 5, degree: "V/3"),
        GuitarChordVoicing(name: "Am7", displayName: "A 小七和弦", frets: [0, 1, 0, 2, 0, nil], bassString: 5, degree: "vi7"),
        GuitarChordVoicing(name: "Em7", displayName: "E 小七和弦 (双三品指法)", frets: [3, 3, 0, 2, 2, 0], bassString: 6, degree: "iii7"),
        GuitarChordVoicing(name: "Dm7", displayName: "D 小七和弦", frets: [1, 1, 2, 0, nil, nil], bassString: 4, degree: "ii7"),
        GuitarChordVoicing(name: "Cmaj7", displayName: "C 大七和弦", frets: [0, 0, 0, 2, 3, nil], bassString: 5, degree: "I maj7"),

        // D/A/E 常用
        GuitarChordVoicing(name: "D", displayName: "D 大三和弦", frets: [2, 3, 2, 0, nil, nil], bassString: 4, degree: "I"),
        GuitarChordVoicing(name: "A", displayName: "A 大三和弦", frets: [0, 2, 2, 2, 0, nil], bassString: 5, degree: "I"),
        GuitarChordVoicing(name: "E", displayName: "E 大三和弦", frets: [0, 0, 1, 2, 2, 0], bassString: 6, degree: "I"),
        GuitarChordVoicing(name: "Bm", displayName: "B 小三和弦", frets: [2, 3, 4, 4, 2, nil], bassString: 5, degree: "ii"),
        GuitarChordVoicing(name: "Bm7", displayName: "B 小七和弦", frets: [2, 3, 2, 4, 2, nil], bassString: 5, degree: "ii7"),
        GuitarChordVoicing(name: "D7", displayName: "D 属七和弦", frets: [2, 1, 2, 0, nil, nil], bassString: 4, degree: "V7"),
        GuitarChordVoicing(name: "A7", displayName: "A 属七和弦", frets: [0, 2, 0, 2, 0, nil], bassString: 5, degree: "V7"),
        GuitarChordVoicing(name: "E7", displayName: "E 属七和弦", frets: [0, 0, 1, 0, 2, 0], bassString: 6, degree: "V7"),
    ]

    private static let chordMap: [String: GuitarChordVoicing] = Dictionary(uniqueKeysWithValues: commonChords.map { ($0.name, $0) })

    public static func find(_ name: String) -> GuitarChordVoicing? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let exact = chordMap[trimmed] { return exact }
        // 尝试大小写容错
        return commonChords.first { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }
    }
}

// MARK: - 经典和弦进行套路 (Common Chord Progressions)

public struct ChordProgressionPreset: Identifiable, Hashable, Sendable {
    public var id: String { name }
    public let name: String
    public let description: String
    public let chords: [String]

    public init(name: String, description: String, chords: [String]) {
        self.name = name
        self.description = description
        self.chords = chords
    }

    public static let presets: [ChordProgressionPreset] = [
        ChordProgressionPreset(name: "流行黄金律 (1-5-6-4)", description: "无数流行金曲通用神级和弦走向", chords: ["C", "G", "Am", "F"]),
        ChordProgressionPreset(name: "现代抓耳律 (4-5-3-6)", description: "日本流行与华语流行标配，副歌极强推动力", chords: ["Fmaj7", "G", "Em7", "Am7"]),
        ChordProgressionPreset(name: "卡农经典进行 (1-5-6-3-4-1-4-5)", description: "古典与民谣优雅循环，绵长动听", chords: ["C", "G", "Am", "Em", "F", "C", "F", "G"]),
        ChordProgressionPreset(name: "青春民谣走向 (1-6-4-5)", description: "50年代经典抒情摇滚，温暖治愈", chords: ["C", "Am", "F", "G"]),
        ChordProgressionPreset(name: "悲伤小调循环 (6-4-1-5)", description: "深沉内省、情绪爆发的抒情小调", chords: ["Am", "F", "C", "G"]),
        ChordProgressionPreset(name: "暖心陪伴律 (1-5/7-6-4)", description: "转位低音下行，平滑连贯", chords: ["C", "G/B", "Am", "F"]),
    ]
}

// MARK: - 伴奏织体模式 (Accompaniment Pattern Template)

public enum AccompanimentCategory: String, CaseIterable, Identifiable, Sendable {
    case fingerstyle = "指弹分解"
    case strumming = "民谣扫弦"
    case travis = "乡村交替"
    case ballad68 = "6/8摇摆"

    public var id: String { rawValue }
    public var symbol: String {
        switch self {
        case .fingerstyle: return "hand.point.up.left"
        case .strumming: return "waveform"
        case .travis: return "music.quarternote.3"
        case .ballad68: return "metronome"
        }
    }
}

public struct PatternStep: Hashable, Sendable {
    public enum Target: Hashable, Sendable {
        case bass                // 根音弦 (由和弦自动决定)
        case string(Int)         // 指定琴弦 (1-6)
        case pinch([Int])        // 多弦抓弦 (同时发声)
        case fullStrum(brush: String) // 全和弦扫弦 (brush: "down" 或 "up")
        case rest                // 休止拍
    }

    public let target: Target
    public let duration: StudioDuration // 4=四分, 8=八分, 16=十六分
    public let dot: Bool
    public let dead: Bool

    public init(target: Target, duration: StudioDuration = 8, dot: Bool = false, dead: Bool = false) {
        self.target = target
        self.duration = duration
        self.dot = dot
        self.dead = dead
    }
}

public struct StudioAccompanimentPattern: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let description: String
    public let category: AccompanimentCategory
    public let timeSignatureNumerator: Int
    public let timeSignatureDenominator: Int
    public let steps: [PatternStep]

    public init(id: String, name: String, description: String, category: AccompanimentCategory, timeSignatureNumerator: Int = 4, timeSignatureDenominator: Int = 4, steps: [PatternStep]) {
        self.id = id
        self.name = name
        self.description = description
        self.category = category
        self.timeSignatureNumerator = timeSignatureNumerator
        self.timeSignatureDenominator = timeSignatureDenominator
        self.steps = steps
    }

    // MARK: - 内置高频织体预设库

    public static let allPatterns: [StudioAccompanimentPattern] = [
        // 1. 经典流行八分分解 T-3-2-3-1-3-2-3
        StudioAccompanimentPattern(
            id: "pop_8th_t3231323",
            name: "流行八分分解",
            description: "最通用的经典 T-3-2-3-1-3-2-3 八分音符分解指法",
            category: .fingerstyle,
            steps: [
                PatternStep(target: .bass, duration: 8),
                PatternStep(target: .string(3), duration: 8),
                PatternStep(target: .string(2), duration: 8),
                PatternStep(target: .string(3), duration: 8),
                PatternStep(target: .string(1), duration: 8),
                PatternStep(target: .string(3), duration: 8),
                PatternStep(target: .string(2), duration: 8),
                PatternStep(target: .string(3), duration: 8),
            ]
        ),

        // 2. 温暖抒情抓弦分解 T-3-(12)-3
        StudioAccompanimentPattern(
            id: "ballad_pinch",
            name: "抒情双音抓弦",
            description: "低音随后抓拨高音双弦，干净温暖有质感",
            category: .fingerstyle,
            steps: [
                PatternStep(target: .bass, duration: 8),
                PatternStep(target: .string(3), duration: 8),
                PatternStep(target: .pinch([1, 2]), duration: 8),
                PatternStep(target: .string(3), duration: 8),
                PatternStep(target: .bass, duration: 8),
                PatternStep(target: .string(3), duration: 8),
                PatternStep(target: .pinch([1, 2]), duration: 8),
                PatternStep(target: .string(3), duration: 8),
            ]
        ),

        // 3. 民谣经典三音齐抓 T-(123)-3-(123)
        StudioAccompanimentPattern(
            id: "folk_pinch_t123",
            name: "民谣齐抓节奏",
            description: "根音 + 一二三弦同时抓弦，节拍感强",
            category: .fingerstyle,
            steps: [
                PatternStep(target: .bass, duration: 4),
                PatternStep(target: .pinch([1, 2, 3]), duration: 4),
                PatternStep(target: .string(3), duration: 4),
                PatternStep(target: .pinch([1, 2, 3]), duration: 4),
            ]
        ),

        // 4. 标准抒情摇滚扫弦 (下 - 下 - 下 - 上下)
        StudioAccompanimentPattern(
            id: "rock_ballad_strum",
            name: "抒情摇滚扫弦",
            description: "四分扫弦沉稳推进，末拍十六分切分回扫",
            category: .strumming,
            steps: [
                PatternStep(target: .fullStrum(brush: "down"), duration: 4),
                PatternStep(target: .fullStrum(brush: "down"), duration: 4),
                PatternStep(target: .fullStrum(brush: "down"), duration: 4),
                PatternStep(target: .fullStrum(brush: "down"), duration: 8),
                PatternStep(target: .fullStrum(brush: "up"), duration: 8),
            ]
        ),

        // 5. 民谣切分扫弦 (下 - 下上 - 上下上)
        StudioAccompanimentPattern(
            id: "folk_driving_strum",
            name: "民谣跃动扫弦",
            description: "带切分音的扫弦律动，适合中速欢快弹唱",
            category: .strumming,
            steps: [
                PatternStep(target: .fullStrum(brush: "down"), duration: 4),
                PatternStep(target: .fullStrum(brush: "down"), duration: 8),
                PatternStep(target: .fullStrum(brush: "up"), duration: 8),
                PatternStep(target: .fullStrum(brush: "up"), duration: 8),
                PatternStep(target: .fullStrum(brush: "down"), duration: 8),
                PatternStep(target: .fullStrum(brush: "up"), duration: 8),
            ]
        ),

        // 6. 乡村/指弹交替低音 Travis Picking
        StudioAccompanimentPattern(
            id: "travis_picking",
            name: "Travis 交替低音",
            description: "低音弦交替行走，高音清脆切分跳跃",
            category: .travis,
            steps: [
                PatternStep(target: .bass, duration: 8),
                PatternStep(target: .string(2), duration: 8),
                PatternStep(target: .string(4), duration: 8),
                PatternStep(target: .string(1), duration: 8),
                PatternStep(target: .bass, duration: 8),
                PatternStep(target: .string(3), duration: 8),
                PatternStep(target: .string(4), duration: 8),
                PatternStep(target: .string(2), duration: 8),
            ]
        ),

        // 7. 6/8 拍经典滚指摇摆 (T-3-2-1-2-3)
        StudioAccompanimentPattern(
            id: "ballad_68_rolling",
            name: "6/8 拍摇摆滚指",
            description: "华尔兹与6/8慢歌优雅滚指分解",
            category: .ballad68,
            timeSignatureNumerator: 6,
            timeSignatureDenominator: 8,
            steps: [
                PatternStep(target: .bass, duration: 8),
                PatternStep(target: .string(3), duration: 8),
                PatternStep(target: .string(2), duration: 8),
                PatternStep(target: .string(1), duration: 8),
                PatternStep(target: .string(2), duration: 8),
                PatternStep(target: .string(3), duration: 8),
            ]
        ),
    ]
}

// MARK: - 伴奏织体应用引擎 (Pattern Application Engine)

public enum StudioPatternGenerator {
    /// 将伴奏织体与和弦生成为单个小节的完整音符序列
    public static func generateBeats(
        forChord chord: GuitarChordVoicing,
        pattern: StudioAccompanimentPattern,
        capo: Int = 0
    ) -> [StudioBeat] {
        var result: [StudioBeat] = []

        for (stepIdx, step) in pattern.steps.enumerated() {
            let beatId = "beat_\(UUID().uuidString.prefix(8))"
            var notes: [StudioNote] = []
            var brush: String? = nil

            switch step.target {
            case .bass:
                let bassStr = chord.bassString
                if let fret = chord.fret(forString: bassStr) {
                    notes.append(StudioNote(string: bassStr, fret: fret + capo))
                }
            case .string(let strNum):
                if let fret = chord.fret(forString: strNum) {
                    notes.append(StudioNote(string: strNum, fret: fret + capo))
                }
            case .pinch(let strNums):
                for s in strNums {
                    if let fret = chord.fret(forString: s) {
                        notes.append(StudioNote(string: s, fret: fret + capo))
                    }
                }
            case .fullStrum(let b):
                brush = b
                // 采集该和弦所有可发声音符
                for s in 1...6 {
                    if let fret = chord.fret(forString: s) {
                        notes.append(StudioNote(string: s, fret: fret + capo, dead: step.dead))
                    }
                }
            case .rest:
                break
            }

            let isRest = notes.isEmpty
            // 第一拍携带和弦名称标记
            let chordNameOnBeat = stepIdx == 0 ? chord.name : nil

            result.append(StudioBeat(
                id: beatId,
                duration: step.duration,
                isRest: isRest,
                dot: step.dot,
                triplet: false,
                notes: notes,
                chordName: chordNameOnBeat,
                lyrics: nil,
                brush: brush
            ))
        }

        return result
    }

    /// 应用织体到工程中指定轨道和指定小节
    public static func applyPatternToBar(
        project: StudioProject,
        trackIndex: Int,
        barIndex: Int,
        chordName: String,
        pattern: StudioAccompanimentPattern
    ) -> StudioProject? {
        guard project.tracks.indices.contains(trackIndex),
              project.bars.indices.contains(barIndex),
              let chord = GuitarChordLibrary.find(chordName) else {
            return nil
        }

        var next = project
        let track = next.tracks[trackIndex]
        var bar = next.bars[barIndex]

        // 如果织体有专属拍号（如 6/8），更新小节拍号
        if bar.timeSignatureNumerator != pattern.timeSignatureNumerator ||
           bar.timeSignatureDenominator != pattern.timeSignatureDenominator {
            bar.timeSignatureNumerator = pattern.timeSignatureNumerator
            bar.timeSignatureDenominator = pattern.timeSignatureDenominator
        }

        let newBeats = generateBeats(forChord: chord, pattern: pattern, capo: track.capo)
        bar.trackBeats[track.id] = newBeats
        next.bars[barIndex] = bar
        return next
    }

    /// 批量应用和弦进行到一段小节中
    public static func applyProgression(
        project: StudioProject,
        trackIndex: Int,
        startBarIndex: Int,
        progression: ChordProgressionPreset,
        pattern: StudioAccompanimentPattern
    ) -> StudioProject? {
        guard project.tracks.indices.contains(trackIndex) else { return nil }
        var current = project
        let totalChords = progression.chords.count

        // 确保有足够的小节，不足时自动追加小节
        var neededBars = startBarIndex + totalChords
        while current.bars.count < neededBars {
            let lastIndex = current.bars.count
            let templateBar = current.bars.last ?? StudioBar(
                id: "bar_\(UUID().uuidString.prefix(8))",
                index: lastIndex,
                timeSignatureNumerator: pattern.timeSignatureNumerator,
                timeSignatureDenominator: pattern.timeSignatureDenominator,
                trackBeats: [:]
            )
            var newBar = templateBar
            newBar.id = "bar_\(UUID().uuidString.prefix(8))"
            newBar.index = lastIndex
            newBar.trackBeats = [:]
            for trk in current.tracks {
                newBar.trackBeats[trk.id] = [
                    StudioBeat(id: "beat_\(UUID().uuidString.prefix(8))", duration: 4, isRest: true, notes: []),
                    StudioBeat(id: "beat_\(UUID().uuidString.prefix(8))", duration: 4, isRest: true, notes: []),
                    StudioBeat(id: "beat_\(UUID().uuidString.prefix(8))", duration: 4, isRest: true, notes: []),
                    StudioBeat(id: "beat_\(UUID().uuidString.prefix(8))", duration: 4, isRest: true, notes: []),
                ]
            }
            current.bars.append(newBar)
        }

        for (idx, chordName) in progression.chords.enumerated() {
            let targetBar = startBarIndex + idx
            if let updated = applyPatternToBar(project: current, trackIndex: trackIndex, barIndex: targetBar, chordName: chordName, pattern: pattern) {
                current = updated
            }
        }

        return current
    }
}
