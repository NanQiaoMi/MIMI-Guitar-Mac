import Foundation
import MIMICore

// MARK: - 编曲与高级制谱扩展 (NativeStudioModel Arranging Extensions)

extension NativeStudioModel {

    // MARK: - 伴奏织体应用 (Texture Application)

    /// 将伴奏织体应用到指定小节（默认当前光标所在小节）
    func applyAccompanimentPattern(
        chordName: String,
        pattern: StudioAccompanimentPattern,
        toBar barIndex: Int? = nil
    ) {
        guard let current = project else {
            status = "请先新建或打开工程。"
            return
        }
        let targetBar = barIndex ?? cursor.barIndex
        guard current.bars.indices.contains(targetBar) else {
            status = "目标小节无效。"
            return
        }

        if let updated = StudioPatternGenerator.applyPatternToBar(
            project: current,
            trackIndex: selectedTrack,
            barIndex: targetBar,
            chordName: chordName,
            pattern: pattern
        ) {
            undoStack = Array((undoStack + [current]).suffix(100))
            redoStack.removeAll()
            recordProjectMutation(updated, status: "已生成第 \(targetBar + 1) 小节伴奏 · \(chordName) (\(pattern.name))")

            // 试听所选和弦
            if let chord = GuitarChordLibrary.find(chordName) {
                var notesToPlay: [[String: Int]] = []
                for s in 1...6 {
                    if let f = chord.fret(forString: s) {
                        notesToPlay.append(["string": s, "fret": f + (currentTrack?.capo ?? 0)])
                    }
                }
                previewChord(notesToPlay)
            }
        } else {
            status = "无法为 \(chordName) 生成伴奏织体。"
        }
    }

    /// 将经典和弦走向与伴奏织体批量应用到连续小节中
    func applyProgressionPattern(
        progression: ChordProgressionPreset,
        pattern: StudioAccompanimentPattern,
        startBar: Int? = nil
    ) {
        guard let current = project else {
            status = "请先新建或打开工程。"
            return
        }
        let start = startBar ?? cursor.barIndex

        if let updated = StudioPatternGenerator.applyProgression(
            project: current,
            trackIndex: selectedTrack,
            startBarIndex: start,
            progression: progression,
            pattern: pattern
        ) {
            undoStack = Array((undoStack + [current]).suffix(100))
            redoStack.removeAll()
            recordProjectMutation(updated, status: "已应用「\(progression.name)」走向共 \(progression.chords.count) 小节")
        } else {
            status = "和弦进行生成失败。"
        }
    }

    // MARK: - 曲式与段落蓝图管理 (Section Management)

    /// 标记指定小节的曲式段落名称
    func markBarAsSection(barIndex: Int, sectionName: String?) {
        guard let current = project, current.bars.indices.contains(barIndex) else { return }
        let updated = StudioSectionBlueprint.markBarAsSection(
            project: current,
            barIndex: barIndex,
            sectionName: sectionName
        )
        undoStack = Array((undoStack + [current]).suffix(100))
        redoStack.removeAll()
        let label = sectionName ?? "清除标记"
        recordProjectMutation(updated, status: "第 \(barIndex + 1) 小节已标记为：\(label)")
    }

    /// 整段克隆：将目标段落完整复制并追加/插入
    func cloneSection(_ section: StudioSongSection) {
        guard let current = project else { return }
        let updated = StudioSectionBlueprint.cloneSection(project: current, section: section)
        undoStack = Array((undoStack + [current]).suffix(100))
        redoStack.removeAll()
        recordProjectMutation(updated, status: "已克隆「\(section.name)」共 \(section.barCount) 小节")
        // 将光标定位至新追加段落首小节
        setCursor(bar: current.bars.count, beat: 0)
    }

    /// 整段移调：按半音数全局升降调
    func transposeSection(_ section: StudioSongSection, semitones: Int) {
        guard let current = project, semitones != 0 else { return }
        let updated = StudioSectionBlueprint.transposeSection(project: current, section: section, semitones: semitones)
        undoStack = Array((undoStack + [current]).suffix(100))
        redoStack.removeAll()
        let sign = semitones > 0 ? "+\(semitones)" : "\(semitones)"
        recordProjectMutation(updated, status: "已对「\(section.name)」移调 \(sign) 半音")
    }

    /// 整段删除
    func deleteSection(_ section: StudioSongSection) {
        guard let current = project, current.bars.count > section.barCount else {
            status = "乐谱至少需要保留 1 个小节。"
            return
        }
        let updated = StudioSectionBlueprint.deleteSection(project: current, section: section)
        undoStack = Array((undoStack + [current]).suffix(100))
        redoStack.removeAll()
        recordProjectMutation(updated, status: "已删除段落「\(section.name)」")
        setCursor(bar: min(section.startBar, max(0, updated.bars.count - 1)), beat: 0)
    }

    /// 跳转到指定小节并更新光标与滚动
    func jumpToBar(_ barIndex: Int) {
        guard let project, project.bars.indices.contains(barIndex) else { return }
        setCursor(bar: barIndex, beat: 0)
        seekToCursor()
    }

    /// 跳转到指定段落起始
    func jumpToSection(_ section: StudioSongSection) {
        jumpToBar(section.startBar)
    }

    // MARK: - 多音轨配器管理 (Multi-Track Arranging)

    /// 新增乐器分轨
    func addTrackPreset(_ preset: StudioTrackPreset) {
        guard let current = project else { return }
        let updated = StudioArrangerLogic.addTrack(project: current, preset: preset)
        undoStack = Array((undoStack + [current]).suffix(100))
        redoStack.removeAll()
        recordProjectMutation(updated, status: "已添加分轨：\(preset.name)")
        selectedTrack = updated.tracks.count - 1
        setCursor(bar: cursor.barIndex, beat: 0, string: 1)
    }

    /// 复制当前音轨
    func duplicateCurrentTrack() {
        guard let current = project else { return }
        if let updated = StudioArrangerLogic.duplicateTrack(project: current, trackIndex: selectedTrack) {
            undoStack = Array((undoStack + [current]).suffix(100))
            redoStack.removeAll()
            recordProjectMutation(updated, status: "已复制当前音轨")
            selectedTrack = updated.tracks.count - 1
        }
    }

    /// 删除指定音轨
    func removeTrack(index: Int) {
        guard let current = project else { return }
        if let updated = StudioArrangerLogic.removeTrack(project: current, trackIndex: index) {
            undoStack = Array((undoStack + [current]).suffix(100))
            redoStack.removeAll()
            recordProjectMutation(updated, status: "已删除音轨")
            selectedTrack = max(0, min(selectedTrack, updated.tracks.count - 1))
            setCursor(bar: cursor.barIndex, beat: 0, string: 1)
        } else {
            status = "工程至少需要保留 1 条音轨。"
        }
    }

    /// 调节音轨混音参数 (Solo, Mute, Volume, Pan, Capo)
    func updateTrackMixing(
        index: Int,
        volume: Double? = nil,
        pan: Double? = nil,
        mute: Bool? = nil,
        solo: Bool? = nil,
        capo: Int? = nil,
        name: String? = nil
    ) {
        guard let current = project else { return }
        let updated = StudioArrangerLogic.updateTrack(
            project: current,
            trackIndex: index,
            volume: volume,
            pan: pan,
            mute: mute,
            solo: solo,
            capo: capo,
            name: name
        )
        // 混音参数调整直接同步，不入撤销栈以保持拖拽平滑
        recordProjectMutation(updated, status: "混音参数已更新")
    }
}
