import Foundation
import SwiftUI
import MIMICore

// MARK: - 曲式段落定义 (Song Form Section Definition)

public struct StudioSongSection: Identifiable, Hashable, Sendable {
    public var id: String { "\(name)_\(startBar)_\(endBar)" }
    public let name: String
    public let startBar: Int
    public let endBar: Int
    public var barCount: Int { max(1, endBar - startBar + 1) }

    public init(name: String, startBar: Int, endBar: Int) {
        self.name = name
        self.startBar = startBar
        self.endBar = endBar
    }

    /// 段落主题色调
    public var themeColor: Color {
        let lower = name.lowercased()
        if lower.contains("前奏") || lower.contains("intro") {
            return Color(red: 0.22, green: 0.45, blue: 0.85) // 宁静蓝
        } else if lower.contains("主歌") || lower.contains("verse") {
            return Color(red: 0.18, green: 0.62, blue: 0.45) // 沉稳翠绿
        } else if lower.contains("预副歌") || lower.contains("pre") {
            return Color(red: 0.85, green: 0.62, blue: 0.18) // 跃动琥珀
        } else if lower.contains("副歌") || lower.contains("chorus") {
            return Color(red: 0.88, green: 0.35, blue: 0.22) // 热烈赤土陶/暖红
        } else if lower.contains("间奏") || lower.contains("interlude") {
            return Color(red: 0.58, green: 0.32, blue: 0.78) // 雅致浅紫
        } else if lower.contains("独奏") || lower.contains("solo") {
            return Color(red: 0.82, green: 0.24, blue: 0.56) // 激昂品红
        } else if lower.contains("桥段") || lower.contains("bridge") {
            return Color(red: 0.35, green: 0.42, blue: 0.75) // 连贯靛蓝
        } else if lower.contains("尾奏") || lower.contains("outro") {
            return Color(red: 0.45, green: 0.48, blue: 0.52) // 沉淀石灰
        }
        return Color(red: 0.55, green: 0.45, blue: 0.35)
    }

    public var badgeLabel: String {
        "\(name) (\(startBar + 1)-\(endBar + 1)小节)"
    }
}

// MARK: - 段落管理与曲式算法 (Section Blueprint Logic)

public enum StudioSectionBlueprint {
    /// 预置标准段落名称
    public static let standardSectionNames: [String] = [
        "前奏 Intro",
        "主歌 Verse",
        "预副歌 Pre-Chorus",
        "副歌 Chorus",
        "间奏 Interlude",
        "吉他独奏 Solo",
        "桥段 Bridge",
        "尾奏 Outro",
    ]

    /// 从当前工程中提取所有连续段落
    public static func extractSections(from project: StudioProject) -> [StudioSongSection] {
        guard !project.bars.isEmpty else { return [] }
        var result: [StudioSongSection] = []

        var currentName = project.bars[0].section ?? "前奏 Intro"
        var currentStart = 0

        for (idx, bar) in project.bars.enumerated() {
            if let barSection = bar.section, !barSection.trimmingCharacters(in: .whitespaces).isEmpty {
                if idx > currentStart {
                    result.append(StudioSongSection(name: currentName, startBar: currentStart, endBar: idx - 1))
                }
                currentName = barSection
                currentStart = idx
            }
        }

        result.append(StudioSongSection(name: currentName, startBar: currentStart, endBar: project.bars.count - 1))
        return result
    }

    /// 在指定小节标记/修改段落名
    public static func markBarAsSection(
        project: StudioProject,
        barIndex: Int,
        sectionName: String?
    ) -> StudioProject {
        guard project.bars.indices.contains(barIndex) else { return project }
        var next = project
        next.bars[barIndex].section = sectionName?.trimmingCharacters(in: .whitespaces).isEmpty == true ? nil : sectionName
        return next
    }

    /// 整段克隆：将目标段落的小节完整复制，插入到工程末尾或指定小节之后
    public static func cloneSection(
        project: StudioProject,
        section: StudioSongSection,
        insertAfterBar: Int? = nil
    ) -> StudioProject {
        guard section.startBar <= section.endBar,
              project.bars.indices.contains(section.startBar),
              project.bars.indices.contains(section.endBar) else {
            return project
        }

        var next = project
        let sourceBars = Array(project.bars[section.startBar...section.endBar])
        var clonedBars: [StudioBar] = []

        let newSectionName: String
        if section.name.contains("1") {
            newSectionName = section.name.replacingOccurrences(of: "1", with: "2")
        } else if !section.name.contains("2") && !section.name.contains("3") {
            newSectionName = "\(section.name) (副本)"
        } else {
            newSectionName = section.name
        }

        for (idx, bar) in sourceBars.enumerated() {
            var newBar = bar
            newBar.id = "bar_\(UUID().uuidString.prefix(8))"
            // 只在克隆段落的第 1 小节标记新的段落头
            newBar.section = (idx == 0) ? newSectionName : nil

            var newTrackBeats: [String: [StudioBeat]] = [:]
            for (trackId, beats) in bar.trackBeats {
                newTrackBeats[trackId] = beats.map { beat in
                    var newBeat = beat
                    newBeat.id = "beat_\(UUID().uuidString.prefix(8))"
                    return newBeat
                }
            }
            newBar.trackBeats = newTrackBeats
            clonedBars.append(newBar)
        }

        let insertionPoint = insertAfterBar.map { min(next.bars.count, max(0, $0 + 1)) } ?? next.bars.count
        next.bars.insert(contentsOf: clonedBars, at: insertionPoint)

        // 重新编号所有小节
        for idx in next.bars.indices {
            next.bars[idx].index = idx
        }

        return next
    }

    /// 整段移调：将目标段落中所有的音符品位进行全局移调 (+/- 半音)
    public static func transposeSection(
        project: StudioProject,
        section: StudioSongSection,
        semitones: Int
    ) -> StudioProject {
        guard semitones != 0,
              section.startBar <= section.endBar,
              project.bars.indices.contains(section.startBar),
              project.bars.indices.contains(section.endBar) else {
            return project
        }

        var next = project
        for barIdx in section.startBar...section.endBar {
            var bar = next.bars[barIdx]
            for (trackId, beats) in bar.trackBeats {
                bar.trackBeats[trackId] = beats.map { beat in
                    var newBeat = beat
                    newBeat.notes = beat.notes.map { note in
                        var newNote = note
                        let transposedFret = note.fret + semitones
                        // 确保品位落在吉他合理品位范围 0~24
                        newNote.fret = max(0, min(24, transposedFret))
                        return newNote
                    }
                    return newBeat
                }
            }
            next.bars[barIdx] = bar
        }

        return next
    }

    /// 删除整段小节
    public static func deleteSection(
        project: StudioProject,
        section: StudioSongSection
    ) -> StudioProject {
        guard section.startBar <= section.endBar,
              project.bars.indices.contains(section.startBar),
              project.bars.indices.contains(section.endBar),
              project.bars.count > section.barCount else {
            return project
        }

        var next = project
        next.bars.removeSubrange(section.startBar...section.endBar)

        for idx in next.bars.indices {
            next.bars[idx].index = idx
        }

        return next
    }
}
