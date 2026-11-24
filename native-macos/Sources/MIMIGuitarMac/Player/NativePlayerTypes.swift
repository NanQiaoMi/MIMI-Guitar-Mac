import Combine
import Foundation
import MIMICore
import SwiftUI

enum NativePlayerMode: String {
    case player
    case practice
}

struct NativePlaybackPositionSample: Equatable {
    let timeMs: Double
    let durationMs: Double
    let speedRatio: Double
    let isPlaying: Bool
    let receivedAtUptime: TimeInterval
    let tick: Double?
    let bar: Int?
    let beat: Int?
    let transportRevision: Int

    func time(at uptime: TimeInterval) -> Double {
        let elapsedMs = isPlaying ? max(0, uptime - receivedAtUptime) * 1_000 : 0
        let upperBound = durationMs > 0 ? durationMs : .greatestFiniteMagnitude
        return min(upperBound, max(0, timeMs + elapsedMs))
    }
}

@MainActor
final class NativePlayerPositionState: ObservableObject {
    @Published private(set) var sample: NativePlaybackPositionSample?
    private var transportRevision = 0

    func reanchor(
        timeMs: Double,
        durationMs: Double,
        speedRatio: Double,
        isPlaying: Bool,
        tick: Double? = nil,
        bar: Int? = nil,
        beat: Int? = nil,
        receivedAtUptime: TimeInterval = ProcessInfo.processInfo.systemUptime,
        resetAnimation: Bool = false
    ) {
        guard timeMs.isFinite, durationMs.isFinite, speedRatio.isFinite else { return }
        if resetAnimation { transportRevision &+= 1 }
        sample = NativePlaybackPositionSample(
            timeMs: max(0, timeMs),
            durationMs: max(0, durationMs),
            speedRatio: max(0, speedRatio),
            isPlaying: isPlaying,
            receivedAtUptime: receivedAtUptime,
            tick: tick,
            bar: bar,
            beat: beat,
            transportRevision: transportRevision
        )
    }

    func interpolatedTime(at uptime: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Double {
        sample?.time(at: uptime) ?? 0
    }

    func updateBeat(bar: Int?, beat: Int?, replacingUnknowns: Bool = false) {
        guard let sample else { return }
        self.sample = NativePlaybackPositionSample(
            timeMs: sample.timeMs,
            durationMs: sample.durationMs,
            speedRatio: sample.speedRatio,
            isPlaying: sample.isPlaying,
            receivedAtUptime: sample.receivedAtUptime,
            tick: sample.tick,
            bar: bar ?? (replacingUnknowns ? nil : sample.bar),
            beat: beat ?? (replacingUnknowns ? nil : sample.beat),
            transportRevision: sample.transportRevision
        )
    }

    func clear() {
        transportRevision &+= 1
        sample = nil
    }

    var playbackPositionChanges: AnyPublisher<Void, Never> {
        $sample.map { _ in () }.eraseToAnyPublisher()
    }
}

struct NativePlayerTrack: Identifiable, Hashable {
    var id: Int { index }
    var index: Int
    var name: String
    var program: Int
    var sourceProgram: Int
    var sourceCapo: Int
    var percussion: Bool
    var show: Bool
    var muted: Bool
    var soloed: Bool
    var volume: Double
    var instrumentOverride: Bool
    var tuning: [Int]
    /// 原谱音源类别（gm / ukulele）。由播放器按曲目 category、调弦与 program 判定。
    var sourceFlavor: String = "gm"
    /// 播放器给出的原谱音色文案（例如“原谱 · 尤克里里（钢弦）”）。
    var sourceName: String = ""

    var instrumentFlavor: String { instrumentOverride ? "gm" : sourceFlavor }

    /// 面板展示用的原谱音色名称；优先使用播放器的本地化文案。
    var sourceInstrumentLabel: String {
        if !sourceName.isEmpty { return sourceName }
        if percussion { return "原谱 · 打击乐" }
        if sourceFlavor == "ukulele" { return "原谱 · 尤克里里" }
        return "原谱 · MIDI \(sourceProgram + 1)"
    }
}

struct NativeFretNote: Identifiable, Hashable {
    var id: String { "\(string):\(fret)" }
    var string: Int
    var fret: Int
    var midi: Int
    var finger: Int? = nil
}

struct NativeGMInstrument: Identifiable, Hashable {
    var id: Int { program }
    var program: Int
    var name: String
}


enum NativePlayerSourceKind: String {
    case ibe
    case guitarPro = "gp"
    case musicXML = "musicxml"
    case json
    case xhe
}

struct NativePlayerLoopDetails: Equatable {
    let startTick: Int
    let endTick: Int
    let startBar: Int?
    let endBar: Int?
    let startRatio: Double?
    let endRatio: Double?
    let lapCount: Int
}

struct NativePlayerPointADetails: Equatable {
    let tick: Int
    let bar: Int?
    let beat: Int?
    let timeMs: Double?
    let ratio: Double?
}

struct NativePlayerSource {
    let url: URL
    let kind: NativePlayerSourceKind
    let isImported: Bool
}


#if MIMI_RUNTIME_DIAGNOSTICS
@MainActor
private final class RuntimePlayerPaneDiagnosticsRegistry {
    static let shared = RuntimePlayerPaneDiagnosticsRegistry()
    weak var activeModel: NativePlayerModel?
}

@MainActor
enum RuntimePlayerPaneDiagnostics {
    static var activeModel: NativePlayerModel? { RuntimePlayerPaneDiagnosticsRegistry.shared.activeModel }

    static func register(_ model: NativePlayerModel) {
        RuntimePlayerPaneDiagnosticsRegistry.shared.activeModel = model
    }

    static func clear(_ model: NativePlayerModel) {
        if activeModel === model { RuntimePlayerPaneDiagnosticsRegistry.shared.activeModel = nil }
    }
}
#endif

enum NativePlayerError: LocalizedError {
    case noScore
    case catalogScoreMissing
    case assetMissing(String)
    case assetRevisionMismatch
    case importMissing
    case importOutsideSandbox
    case importSizeLimit
    case unsupportedFormat(String)

    var errorDescription: String? {
        switch self {
        case .noScore:
            return "此曲目没有可用的本地谱面。"
        case .catalogScoreMissing:
            return "本地谱面文件不存在或无法读取。"
        case .assetMissing(let id):
            return "缺少本地谱面附件：\(id)"
        case .assetRevisionMismatch:
            return "本地谱面内容与保存的摘要不一致；请重新导入或重新链接原件。"
        case .importMissing:
            return "导入谱面没有保存在应用的 Imports 目录中。"
        case .importOutsideSandbox:
            return "导入谱面路径无效，必须先复制到应用的 Imports 目录。"
        case .importSizeLimit:
            return "导入谱面为空或超过 30 MiB 限制。"
        case .unsupportedFormat(let ext):
            return "支持 IBE、Guitar Pro 3–8、MusicXML 和 XHE 文本谱；当前文件格式“\(ext.isEmpty ? "未知" : ext)”不在支持范围内。MIDI 暂不支持。"
        }
    }
}
