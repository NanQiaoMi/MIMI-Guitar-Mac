import SwiftUI
import MIMICore

struct NativeTrackMixerPanel: View {
    @ObservedObject var model: NativePlayerModel

    var body: some View {
        ScrollView(.vertical) {
            VStack(spacing: 8) {
                ForEach(model.tracks) { track in
                    trackRow(track)
                }
                if model.tracks.isEmpty {
                    Label(model.scoreReady ? "谱面没有可混音音轨" : "等待谱面音轨载入…", systemImage: "slider.horizontal.3")
                        .font(MIMITheme.bodyFont(size: 12)).foregroundStyle(MIMITheme.mutedInk).frame(maxWidth: .infinity, minHeight: 100)
                }
            }
        }
        .scrollIndicators(.visible)
    }

    private func trackRow(_ track: NativePlayerTrack) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 9) {
                Toggle("", isOn: Binding(get: { track.show }, set: { model.setTrack(track, field: "show", value: $0) }))
                    .labelsHidden().toggleStyle(.checkbox).help("在谱面中显示/隐藏此轨")
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.name).font(MIMITheme.bodyFont(size: 12, weight: .semibold)).lineLimit(1)
                    Text(track.percussion ? "打击乐" : tuningName(track.tuning))
                        .font(MIMITheme.bodyFont(size: 10)).foregroundStyle(MIMITheme.mutedInk).lineLimit(1)
                }.frame(minWidth: 110, alignment: .leading)
                Button(track.muted ? "已静音" : "静音") { model.setTrack(track, field: "muted", value: !track.muted) }
                    .buttonStyle(.bordered).tint(track.muted ? MIMITheme.terracotta : MIMITheme.mutedInk)
                Button(track.soloed ? "独奏中" : "独奏") { model.setTrack(track, field: "soloed", value: !track.soloed) }
                    .buttonStyle(.bordered).tint(track.soloed ? MIMITheme.warmGold : MIMITheme.mutedInk)
                Menu {
                    Button("恢复原谱音色 · \(instrumentName(track.sourceProgram))") {
                        model.setTrack(track, field: "restoreProgram", value: true)
                    }
                    Divider()
                    ForEach(model.gmInstruments) { instrument in
                        Button("\(instrument.program + 1). \(instrument.name)") {
                            model.setTrack(track, field: "program", value: instrument.program)
                        }
                    }
                } label: {
                    Label(track.instrumentOverride ? instrumentName(track.program) : "原谱 · \(instrumentName(track.sourceProgram))", systemImage: "music.note")
                        .lineLimit(1).frame(maxWidth: 205, alignment: .leading)
                }
                .menuStyle(.borderlessButton)
                Text("音量").font(MIMITheme.bodyFont(size: 10)).foregroundStyle(MIMITheme.mutedInk)
                Slider(value: Binding(get: { track.volume }, set: { model.setTrack(track, field: "volume", value: $0) }), in: 0...1)
                    .frame(width: 100).disabled(!model.audioReady)
                Text("\(Int((track.volume * 100).rounded()))%")
                    .font(.system(size: 10, design: .rounded).monospacedDigit()).frame(width: 34, alignment: .trailing)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(track.show ? MIMITheme.paperWhite : MIMITheme.paper.opacity(0.65), in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(MIMITheme.softBorder, lineWidth: 1))
        }
    }

    private func tuningName(_ tuning: [Int]) -> String {
        guard !tuning.isEmpty else { return "未识别调弦" }
        let names = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]
        return tuning.map { "\(names[($0 % 12 + 12) % 12])\($0 / 12 - 1)" }.joined(separator: " · ")
    }

    private func instrumentName(_ program: Int) -> String {
        model.gmInstruments.first(where: { $0.program == program })?.name ?? "MIDI \(program + 1)"
    }
}

struct NativePracticePanel: View {
    @ObservedObject var model: NativePlayerModel
    @State private var fragmentName = ""
    @State private var fragmentNote = ""
    @State private var editingFragment: PracticeFragment?
    @State private var editName = ""
    @State private var editNote = ""
    @State private var startBpm = 60.0
    @State private var targetBpm = 90.0
    @State private var stepBpm = 5.0
    @State private var lapsPerLevel = 3
    @State private var showFragmentEditor = false

    private var activeFragments: [PracticeFragment] { model.practiceFragments.filter { $0.deletedAt == nil } }

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 10) {
                practiceHeader
                if model.practiceJoined { practiceNote } else { joinPrompt }
                loopEditor
                fragmentEditor
                fragmentList
                speedEditor
                if let saveError = model.saveError ?? model.practiceOperationError {
                    Label(saveError, systemImage: "exclamationmark.triangle.fill")
                        .font(MIMITheme.bodyFont(size: 11)).foregroundStyle(MIMITheme.terracotta)
                        .textSelection(.enabled)
                    Button("重试保存") { model.retryLastSave() }.buttonStyle(.bordered)
                }
            }
            .padding(.bottom, 8)
        }
        .scrollIndicators(.visible)
        .sheet(isPresented: $showFragmentEditor) { newFragmentSheet }
        .sheet(item: $editingFragment) { fragment in editFragmentSheet(fragment) }
        .onChange(of: model.practiceSpeedPlan?.startBpm) { _ in
            if let plan = model.practiceSpeedPlan { updateSpeedFields(plan) }
        }
    }

    private var practiceHeader: some View {
        HStack(spacing: 10) {
            Label("个人练习", systemImage: "repeat")
                .font(MIMITheme.bodyFont(size: 12, weight: .semibold))
            if let session = model.activePracticeSession {
                Text(sessionLabel(session.state)).font(MIMITheme.bodyFont(size: 10, weight: .medium))
                    .foregroundStyle(MIMITheme.darkGold).padding(.horizontal, 8).padding(.vertical, 4)
                    .background(MIMITheme.warmGold.opacity(0.13), in: Capsule())
            }
            Spacer()
            if model.practiceJoined {
                Picker("练习状态", selection: Binding(get: { model.practiceItem?.status ?? .todo }, set: { model.setPracticeStatus($0) })) {
                    Text("待练").tag(PracticeStatus.todo)
                    Text("练习中").tag(PracticeStatus.practicing)
                    Text("已掌握").tag(PracticeStatus.mastered)
                    Text("归档").tag(PracticeStatus.archived)
                }.frame(width: 145)
                Button("结束本次练习") { model.finishPracticeSession() }
                    .buttonStyle(.bordered).disabled(model.activePracticeSession == nil)
            }
        }
    }

    private var joinPrompt: some View {
        HStack(spacing: 12) {
            Text(model.isTemporaryLocalImport
                 ? "临时打开的本地文件只在当前播放器中可用；请先从我的曲库导入，才能加入待练。"
                 : "将这首谱加入个人待练后，播放时会按实际持有音频焦点的时长记录练习切片。")
                .font(MIMITheme.bodyFont(size: 11)).foregroundStyle(MIMITheme.mutedInk)
            Spacer()
            Button(model.practiceBusy ? "正在保存…" : "加入待练") { model.joinPractice() }
                .buttonStyle(.borderedProminent).tint(MIMITheme.terracotta).disabled(model.practiceBusy || !model.canJoinPractice)
        }
    }

    private var practiceNote: some View {
        HStack(alignment: .top, spacing: 8) {
            TextField("本次练习备注", text: $model.practiceNoteDraft, axis: .vertical)
                .lineLimit(1...3).textFieldStyle(.roundedBorder)
            Button("保存备注") { model.savePracticeNote() }.buttonStyle(.bordered)
        }
    }

    private var loopEditor: some View {
        HStack(spacing: 9) {
            Label("A–B 小节循环", systemImage: "arrow.triangle.2.circlepath")
                .font(MIMITheme.bodyFont(size: 11, weight: .semibold))
            Button("设 A") { model.setLoopPoint("A") }.buttonStyle(.bordered).disabled(!model.canPlay)
            Button("设 B") { model.setLoopPoint("B") }.buttonStyle(.bordered).disabled(model.loopPointA == nil || !model.canPlay)
            if let range = model.loopRange {
                Text("\(range.startTick) ≤ tick < \(range.endTick) · \(model.loopLapCount) 圈")
                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(MIMITheme.mutedInk)
                Button("清除") { model.clearLoop() }.buttonStyle(.bordered)
            } else if let pointA = model.loopPointA {
                Text("A 点 tick \(pointA.tick) · 本拍结束 \(pointA.beatEndTick)")
                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(MIMITheme.mutedInk)
            } else {
                Text("播放到目标拍后依次设置 A 与 B")
                    .font(MIMITheme.bodyFont(size: 10)).foregroundStyle(MIMITheme.mutedInk)
            }
            Spacer(minLength: 0)
        }
    }

    private var fragmentEditor: some View {
        HStack(spacing: 8) {
            Label("片段库", systemImage: "bookmark")
                .font(MIMITheme.bodyFont(size: 11, weight: .semibold))
            Button("保存当前 A–B 片段…") {
                fragmentName = "第 \(model.currentBar) 小节片段"
                fragmentNote = ""
                showFragmentEditor = true
            }
            .buttonStyle(.bordered).disabled(model.loopRange == nil || !model.practiceJoined)
            Text("片段绑定当前谱面摘要；删除会保留墓碑用于备份合并。")
                .font(MIMITheme.bodyFont(size: 10)).foregroundStyle(MIMITheme.mutedInk)
            Spacer()
        }
    }

    @ViewBuilder private var fragmentList: some View {
        if activeFragments.isEmpty {
            Text("还没有保存片段。设定 A–B 后可命名并记录备注。")
                .font(MIMITheme.bodyFont(size: 10)).foregroundStyle(MIMITheme.mutedInk)
        } else {
            ForEach(activeFragments) { fragment in
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(fragment.name).font(MIMITheme.bodyFont(size: 11, weight: .medium))
                        Text("tick \(fragment.range.startTick)–\(fragment.range.endTick) · \(Int(fragment.speed.startBpm))→\(Int(fragment.speed.targetBpm)) BPM · \(fragment.note)")
                            .font(MIMITheme.bodyFont(size: 9)).foregroundStyle(MIMITheme.mutedInk).lineLimit(1)
                    }
                    Spacer()
                    Button("应用") { model.applyPracticeFragment(fragment) }.buttonStyle(.bordered).disabled(fragment.scoreRevision != model.resume?.scoreRevision && model.resume != nil)
                    Button { editName = fragment.name; editNote = fragment.note; editingFragment = fragment } label: { Image(systemName: "pencil") }
                        .buttonStyle(.bordered).help("改名或编辑备注")
                    Button(role: .destructive) { model.deletePracticeFragment(fragment) } label: { Image(systemName: "trash") }
                        .buttonStyle(.bordered).help("删除片段（保留删除记录）")
                }
                .padding(.horizontal, 9).padding(.vertical, 6)
                .background(MIMITheme.paperWhite, in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var speedEditor: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Label("循环提速计划", systemImage: "speedometer")
                    .font(MIMITheme.bodyFont(size: 11, weight: .semibold))
                Spacer()
                if let plan = model.practiceSpeedPlan {
                    Text("当前 \(Int(plan.currentBpm)) BPM · 完成 \(plan.completedLaps)/\(plan.lapsPerLevel) 圈后递增")
                        .font(MIMITheme.bodyFont(size: 10)).foregroundStyle(MIMITheme.darkGold)
                    Button("取消计划") { model.clearSpeedPlan() }.buttonStyle(.bordered)
                }
            }
            HStack(spacing: 8) {
                labeledNumber("起始", value: $startBpm, range: 20...300, step: 1)
                labeledNumber("目标", value: $targetBpm, range: 20...300, step: 1)
                labeledNumber("每级 +", value: $stepBpm, range: 1...60, step: 1)
                Stepper("每级 \(lapsPerLevel) 圈", value: $lapsPerLevel, in: 1...32).frame(width: 120)
                Button("按 A–B 圈数提速") { model.configureSpeedPlan(start: startBpm, target: targetBpm, step: stepBpm, laps: lapsPerLevel) }
                    .buttonStyle(.borderedProminent).tint(MIMITheme.darkGold).disabled(model.loopRange == nil || !model.canPlay)
                Spacer(minLength: 0)
            }
        }
        .padding(9).background(MIMITheme.warmGold.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
    }

    private func labeledNumber(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double) -> some View {
        HStack(spacing: 4) {
            Text(title).font(MIMITheme.bodyFont(size: 9)).foregroundStyle(MIMITheme.mutedInk)
            TextField(title, value: value, format: .number.precision(.fractionLength(0)))
                .frame(width: 48).textFieldStyle(.roundedBorder)
        }
    }

    private var newFragmentSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("保存练习片段").font(MIMITheme.displayFont(size: 18, weight: .semibold))
            TextField("片段名称", text: $fragmentName)
            TextField("练习备注", text: $fragmentNote, axis: .vertical).lineLimit(3...5)
            if let range = model.loopRange { Text("保存区间：\(range.startTick) ≤ tick < \(range.endTick)").font(.caption).foregroundStyle(.secondary) }
            HStack {
                Button("取消") { showFragmentEditor = false }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("保存片段") { model.savePracticeFragment(name: fragmentName, note: fragmentNote); showFragmentEditor = false }
                    .buttonStyle(.borderedProminent).disabled(fragmentName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(20).frame(width: 390)
    }

    private func editFragmentSheet(_ fragment: PracticeFragment) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("编辑练习片段").font(MIMITheme.displayFont(size: 18, weight: .semibold))
            TextField("片段名称", text: $editName)
            TextField("练习备注", text: $editNote, axis: .vertical).lineLimit(3...5)
            HStack {
                Button("取消") { editingFragment = nil }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("保存更改") { model.updatePracticeFragment(fragment, name: editName, note: editNote); editingFragment = nil }
                    .buttonStyle(.borderedProminent)
            }
        }.padding(20).frame(width: 390)
    }

    private func updateSpeedFields(_ plan: PracticeSpeedPlan) {
        startBpm = plan.startBpm; targetBpm = plan.targetBpm; stepBpm = plan.stepBpm; lapsPerLevel = plan.lapsPerLevel
    }

    private func sessionLabel(_ state: String) -> String {
        switch state {
        case "active": return "记录中"
        case "paused": return "已暂停"
        case "interrupted": return "已中断，可恢复"
        case "completed": return "已完成"
        default: return state
        }
    }
}

struct NativePracticeReviewPanel: View {
    @ObservedObject var model: NativePlayerModel

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("练习回顾", systemImage: "chart.bar.xaxis").font(MIMITheme.bodyFont(size: 12, weight: .semibold))
                    Spacer()
                    if let resume = model.resume {
                        Text("上次位置 · \(clock(resume.timeMs)) · \(Int(resume.speed)) BPM")
                            .font(MIMITheme.bodyFont(size: 10)).foregroundStyle(MIMITheme.mutedInk)
                        Button("恢复设置") { model.restoreResume(resume) }.buttonStyle(.bordered).disabled(!model.scoreReady)
                    }
                }
                if let outdated = model.outdatedResume {
                    Label("保存的断点属于旧版谱面摘要，不能按当前位置自动恢复（\(String(outdated.scoreRevision.prefix(12)))）。", systemImage: "clock.arrow.circlepath")
                        .font(MIMITheme.bodyFont(size: 10)).foregroundStyle(MIMITheme.terracotta)
                }
                if model.practiceSessions.isEmpty {
                    Text("这首曲目还没有练习会话。只有播放实际发声且持有音频焦点时才记录时长。")
                        .font(MIMITheme.bodyFont(size: 11)).foregroundStyle(MIMITheme.mutedInk).padding(.vertical, 10)
                }
                ForEach(model.practiceSessions) { session in
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(sessionDate(session.startedAt)).font(MIMITheme.bodyFont(size: 11, weight: .medium))
                            Text("\(sessionLabel(session.state)) · \(session.slices.count) 个真实播放切片 · \(session.timezone)")
                                .font(MIMITheme.bodyFont(size: 9)).foregroundStyle(MIMITheme.mutedInk)
                            if !session.note.isEmpty { Text(session.note).font(MIMITheme.bodyFont(size: 10)).lineLimit(1) }
                        }
                        Spacer()
                        Text(clock(session.slices.reduce(0) { $0 + $1.durationMs }))
                            .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
                        if session.scoreRevision == model.resume?.scoreRevision, session.state != "completed" {
                            Button("继续") { if let resume = model.resume { model.restoreResume(resume) } }
                                .buttonStyle(.bordered).disabled(!model.scoreReady)
                        }
                    }
                    .padding(9).background(MIMITheme.paperWhite, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(MIMITheme.softBorder, lineWidth: 1))
                }
            }
        }
        .scrollIndicators(.visible)
    }

    private func sessionDate(_ milliseconds: Double) -> String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "zh_CN"); formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: Date(timeIntervalSince1970: milliseconds / 1_000))
    }
    private func clock(_ milliseconds: Double) -> String {
        let seconds = max(0, Int(milliseconds / 1_000))
        return "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
    }
    private func sessionLabel(_ state: String) -> String {
        switch state {
        case "active": return "记录中"
        case "paused": return "已暂停"
        case "interrupted": return "已中断"
        case "completed": return "已完成"
        default: return state
        }
    }
}
