import Foundation
import SwiftUI
import MIMICore

// MARK: - 乐器分轨预设 (Instrument Track Presets)

public struct StudioTrackPreset: Identifiable, Hashable, Sendable {
    public var id: String { name }
    public let name: String
    public let iconName: String
    public let program: Int
    public let tuning: [Int]
    public let tuningName: String
    public let defaultVolume: Double
    public let defaultPan: Double

    public init(name: String, iconName: String, program: Int, tuning: [Int], tuningName: String, defaultVolume: Double = 0.9, defaultPan: Double = 0) {
        self.name = name
        self.iconName = iconName
        self.program = program
        self.tuning = tuning
        self.tuningName = tuningName
        self.defaultVolume = defaultVolume
        self.defaultPan = defaultPan
    }

    public static let standardPresets: [StudioTrackPreset] = [
        StudioTrackPreset(name: "民谣木吉他", iconName: "guitars", program: 25, tuning: [64, 59, 55, 50, 45, 40], tuningName: "标准吉他调弦", defaultVolume: 1.0, defaultPan: -0.2),
        StudioTrackPreset(name: "清音电吉他", iconName: "bolt", program: 27, tuning: [64, 59, 55, 50, 45, 40], tuningName: "标准吉他调弦", defaultVolume: 0.9, defaultPan: 0.2),
        StudioTrackPreset(name: "主音摇滚电吉他", iconName: "flame", program: 29, tuning: [64, 59, 55, 50, 45, 40], tuningName: "标准吉他调弦", defaultVolume: 0.95, defaultPan: 0.0),
        StudioTrackPreset(name: "指弹电贝斯", iconName: "waveform.path", program: 33, tuning: [43, 38, 33, 28], tuningName: "标准贝斯调弦", defaultVolume: 1.0, defaultPan: 0.0),
        StudioTrackPreset(name: "尤克里里", iconName: "music.quarternote.3", program: 24, tuning: [69, 64, 60, 67], tuningName: "标准尤克里里调弦", defaultVolume: 0.85, defaultPan: 0.3),
    ]
}

// MARK: - 多轨配器业务逻辑 (Track Arranging Logic)

public enum StudioArrangerLogic {
    /// 新增音轨并将各小节的静音小节初始化
    public static func addTrack(
        project: StudioProject,
        preset: StudioTrackPreset
    ) -> StudioProject {
        var next = project
        let newTrackId = "trk_\(UUID().uuidString.prefix(8))"
        let newTrack = StudioTrack(
            id: newTrackId,
            name: "\(preset.name) \(next.tracks.count + 1)",
            program: preset.program,
            tuning: preset.tuning,
            tuningName: preset.tuningName,
            capo: 0,
            volume: preset.defaultVolume,
            pan: preset.defaultPan,
            mute: false,
            solo: false
        )

        next.tracks.append(newTrack)

        // 为所有现有小节填补新轨道的默认休止拍
        for idx in next.bars.indices {
            var bar = next.bars[idx]
            let num = bar.timeSignatureNumerator
            let den = bar.timeSignatureDenominator
            var beats: [StudioBeat] = []
            for _ in 0..<num {
                beats.append(StudioBeat(
                    id: "beat_\(UUID().uuidString.prefix(8))",
                    duration: den,
                    isRest: true,
                    notes: []
                ))
            }
            bar.trackBeats[newTrackId] = beats
            next.bars[idx] = bar
        }

        return next
    }

    /// 复制指定音轨及其在全谱的所有音符
    public static func duplicateTrack(
        project: StudioProject,
        trackIndex: Int
    ) -> StudioProject? {
        guard project.tracks.indices.contains(trackIndex) else { return nil }
        var next = project
        let sourceTrack = next.tracks[trackIndex]
        let newTrackId = "trk_\(UUID().uuidString.prefix(8))"
        let newTrack = StudioTrack(
            id: newTrackId,
            name: "\(sourceTrack.name) (副本)",
            program: sourceTrack.program,
            tuning: sourceTrack.tuning,
            tuningName: sourceTrack.tuningName,
            capo: sourceTrack.capo,
            volume: sourceTrack.volume,
            pan: min(1.0, max(-1.0, -sourceTrack.pan)), // 自动立体声声像对称反向
            mute: sourceTrack.mute,
            solo: false
        )

        next.tracks.append(newTrack)

        for idx in next.bars.indices {
            var bar = next.bars[idx]
            let sourceBeats = bar.trackBeats[sourceTrack.id] ?? []
            let clonedBeats = sourceBeats.map { b in
                var nb = b
                nb.id = "beat_\(UUID().uuidString.prefix(8))"
                return nb
            }
            bar.trackBeats[newTrackId] = clonedBeats
            next.bars[idx] = bar
        }

        return next
    }

    /// 删除指定音轨（保留至少 1 轨）
    public static func removeTrack(
        project: StudioProject,
        trackIndex: Int
    ) -> StudioProject? {
        guard project.tracks.count > 1, project.tracks.indices.contains(trackIndex) else { return nil }
        var next = project
        let trackToRemove = next.tracks[trackIndex]
        next.tracks.remove(at: trackIndex)

        for idx in next.bars.indices {
            next.bars[idx].trackBeats.removeValue(forKey: trackToRemove.id)
        }

        return next
    }

    /// 更新音轨混音参数
    public static func updateTrack(
        project: StudioProject,
        trackIndex: Int,
        volume: Double? = nil,
        pan: Double? = nil,
        mute: Bool? = nil,
        solo: Bool? = nil,
        capo: Int? = nil,
        name: String? = nil
    ) -> StudioProject {
        guard project.tracks.indices.contains(trackIndex) else { return project }
        var next = project
        var track = next.tracks[trackIndex]

        if let volume { track.volume = max(0.0, min(1.5, volume)) }
        if let pan { track.pan = max(-1.0, min(1.0, pan)) }
        if let mute { track.mute = mute }
        if let solo { track.solo = solo }
        if let capo { track.capo = max(0, min(12, capo)) }
        if let name, !name.trimmingCharacters(in: .whitespaces).isEmpty { track.name = name }

        next.tracks[trackIndex] = track
        return next
    }
}
