import AppKit
import MIMICore
import SwiftUI

private struct ScopedStudioProject: Identifiable {
    let project: StudioProject
    let namespace: String

    var id: String { "\(namespace):\(project.id)" }
}

private enum NativeStudioDockTab: String, CaseIterable, Identifiable {
    case workbench
    case mixer

    var id: String { rawValue }
    var title: String { self == .workbench ? "工作台" : "调音台" }
    var symbol: String { self == .workbench ? "guitars" : "slider.horizontal.3" }
}

private struct NativeStudioStableRegion<Key: Equatable, Content: View>: View, Equatable {
    let key: Key
    private let contentProvider: () -> Content

    init(key: Key, @ViewBuilder content: @escaping () -> Content) {
        self.key = key
        contentProvider = content
    }

    static func == (lhs: NativeStudioStableRegion<Key, Content>, rhs: NativeStudioStableRegion<Key, Content>) -> Bool {
        lhs.key == rhs.key
    }

    var body: some View { contentProvider() }
}

private struct NativeStudioMetadataEditorState: Equatable {
    let projectID: String
    let title: String
    let artist: String
    let album: String?
    let words: String?
    let music: String?
    let tabber: String?
    let key: String
    let tempo: Int
    let numerator: Int
    let denominator: Int
    let selectedTrack: Int
    let selectedTrackCapo: Int?
    let isPlaying: Bool
    let isDirty: Bool
    let isBooted: Bool
    let barCount: Int
    let trackCount: Int
    let source: StudioSource?

    init(_ project: StudioProject, selectedTrack: Int, isPlaying: Bool, isDirty: Bool, isBooted: Bool) {
        projectID = project.id
        title = project.title
        artist = project.artist
        album = project.album
        words = project.words
        music = project.music
        tabber = project.tabber
        key = project.key
        tempo = project.initialTempo
        numerator = project.timeSignatureNumerator
        denominator = project.timeSignatureDenominator
        self.selectedTrack = selectedTrack
        selectedTrackCapo = project.tracks.indices.contains(selectedTrack) ? project.tracks[selectedTrack].capo : nil
        self.isPlaying = isPlaying
        self.isDirty = isDirty
        self.isBooted = isBooted
        barCount = project.bars.count
        trackCount = project.tracks.count
        source = project.source
    }
}

private struct NativeStudioFlowLayout: Layout {
    let horizontalSpacing: CGFloat
    let verticalSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let widthLimit = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var widestRow: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + horizontalSpacing + size.width > widthLimit {
                widestRow = max(widestRow, x)
                y += rowHeight + verticalSpacing
                x = 0
                rowHeight = 0
            }
            if x > 0 { x += horizontalSpacing }
            x += size.width
            rowHeight = max(rowHeight, size.height)
        }

        widestRow = max(widestRow, x)
        return CGSize(width: widthLimit.isFinite ? widthLimit : widestRow, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX && x + horizontalSpacing + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + verticalSpacing
                rowHeight = 0
            }
            if x > bounds.minX { x += horizontalSpacing }
            subview.place(
                at: CGPoint(x: x, y: y),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: size.width, height: size.height)
            )
            x += size.width
            rowHeight = max(rowHeight, size.height)
        }
    }

}

private struct NativeStudioTrackSelectorState: Equatable {
    let projectID: String
    let tracks: [StudioTrack]
    let selectedTrack: Int
    let isPlaying: Bool
}

private struct NativeStudioTrackInspectorState: Equatable {
    let projectID: String
    let track: StudioTrack
    let trackCount: Int
}

private struct NativeStudioBeatTimingState: Equatable {
    let duration: Int
    let dot: Bool
    let triplet: Bool
}

private struct NativeStudioBarInspectorState: Equatable {
    let projectID: String
    let barID: String
    let index: Int
    let numerator: Int
    let denominator: Int
    let tempo: Double?
    let section: String?
    let repeatStart: Bool?
    let repeatEnd: Bool?
    let repeatCount: Int?
    let volta: Int?
    let selectedTrackID: String
    let beatTiming: [NativeStudioBeatTimingState]

    init(projectID: String, bar: StudioBar, selectedTrackID: String) {
        self.projectID = projectID
        barID = bar.id
        index = bar.index
        numerator = bar.timeSignatureNumerator
        denominator = bar.timeSignatureDenominator
        tempo = bar.tempo
        section = bar.section
        repeatStart = bar.repeatStart
        repeatEnd = bar.repeatEnd
        repeatCount = bar.repeatCount
        volta = bar.volta
        self.selectedTrackID = selectedTrackID
        beatTiming = (bar.trackBeats[selectedTrackID] ?? []).map {
            NativeStudioBeatTimingState(duration: $0.duration, dot: $0.dot, triplet: $0.triplet)
        }
    }

}

private struct NativeStudioChordLibraryState: Equatable {
    let projectID: String
    let track: StudioTrack
    let root: String
    let search: String
    let input: String
}

private struct NativeStudioLyricsInspectorState: Equatable {
    let projectID: String
    let trackID: String
    let lyrics: String?
}

private struct NativeStudioWarningsInspectorState: Equatable {
    let warnings: [String]
}

private struct NativeStudioLinkedPracticeInspectorState: Equatable {
    let projectID: String
    let linkedID: String
}

struct NativeStudioPane: View {
#if MIMI_RUNTIME_DIAGNOSTICS
    private static let runtimeStudioPruneTarget = ProcessInfo.processInfo.environment["MIMI_RUNTIME_STUDIO_PRUNE"]
    private static let diagnosticFretboardHeight: CGFloat = 250
    private static let diagnosticEditToolsContentHeight: CGFloat = 130
#endif

    @StateObject private var model: NativeStudioModel
    @State private var didFinishInitialLoad = false
    @State private var didRequestInitialProject = false
    @State private var showGuide = false
    @State private var showShortcuts = false
    @State private var showProjectLibrary = false
    @State private var showProjectDetails = false
    @State private var showTrackSettings = false
    @State private var showBarSettings = false
    @State private var showStudioInfo = false
    @State private var showLyricsDrawer = false
    @State private var showDiscardLyricsAlert = false
    @State private var showGMInstrumentBrowser = false
    @State private var gmSearch = ""
    @State private var gmFamily = "全部音色"
    @State private var chordRoot = "ALL"
    @State private var chordSearch = ""
    @State private var chordInput = ""
    @State private var selectedDockTab: NativeStudioDockTab = .workbench
    @State private var isDockCollapsed = false
    @State private var selectedRibbonCategory: StudioRibbonCategory = .notes
    @State private var showTempoKeySheet = false
    @State private var showArrangerDrawer = false
    @State private var metadataDraft = StudioMetadataDraft()
    @State private var lyricDraftChanged = false
    @Environment(\.scenePhase) private var scenePhase
    private let openProject: StudioProject?
    private let importURL: URL?
    private let projectID: String?
    private let cloneFrom: CatalogItem?
    private let cloneFromScore: PersonalScore?

    init(
        contentRoot: URL,
        personalStore: PersonalStore,
        onOpenPractice: @escaping (String) -> Void,
        onPersonalDataChanged: @escaping () -> Void = {},
        onStudioFileConsumed: @escaping () -> Void = {},
        cloneFrom: CatalogItem? = nil,
        cloneFromScore: PersonalScore? = nil,
        openProject: StudioProject? = nil,
        projectID: String? = nil,
        importURL: URL? = nil
    ) {
        self.openProject = openProject
        self.projectID = projectID
        self.importURL = importURL
        self.cloneFrom = cloneFrom
        self.cloneFromScore = cloneFromScore
        _model = StateObject(wrappedValue: NativeStudioModel(
            contentRoot: contentRoot,
            personalStore: personalStore,
            onOpenPractice: onOpenPractice,
            onPersonalDataChanged: onPersonalDataChanged,
            onStudioFileConsumed: onStudioFileConsumed,
            cloneFrom: cloneFrom,
            cloneFromScore: cloneFromScore,
            importURL: importURL,
            projectID: projectID,
            openProject: openProject
        ))
    }

#if MIMI_RUNTIME_DIAGNOSTICS
    init(runtimeDiagnosticModel model: NativeStudioModel) {
        openProject = nil
        importURL = nil
        projectID = nil
        cloneFrom = nil
        cloneFromScore = nil
        _model = StateObject(wrappedValue: model)
    }
#endif

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.vertical) {
                VStack(spacing: 20) {
                    VStack(spacing: 12) {
                        if let project = model.project {
                            studioHeader(project)
                            studioSectionBlueprintBar(project)
                        }
                        ZStack {
                            editorSurface
                            if model.project == nil {
                                emptyStudioState
                                    .background(Color(red: 0.965, green: 0.948, blue: 0.914))
                            }
                        }
                        .frame(minHeight: 560)
                    }
                    .padding(24)
                    .frame(maxWidth: 1240)
                    .background(Color(red: 0.984, green: 0.976, blue: 0.957))
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .frame(maxWidth: .infinity)

                    MIMISiteFooter()
                        .frame(maxWidth: .infinity)
                }
                .padding(.top, 24)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .scrollIndicators(.automatic)
            Divider()
            statusBar
        }
        .background(Color(red: 0.965, green: 0.948, blue: 0.914))
        .task {
            await model.loadInitial()
            didFinishInitialLoad = true
            createInitialProjectIfNeeded()
        }
        .onChange(of: model.isBooted) { _ in createInitialProjectIfNeeded() }
        .onChange(of: model.project?.id) { _ in createInitialProjectIfNeeded() }
        .onChange(of: importURL?.absoluteString) { value in if value != nil, let importURL { model.openStudioFile(importURL) } }
        .onChange(of: openProject?.id) { value in if value != nil, let openProject { model.openSavedProject(openProject) } }
        .onChange(of: projectID) { value in if let value { model.openProject(id: value) } }
        .onChange(of: cloneFrom?.id) { value in if value != nil, let cloneFrom { Task { await model.cloneFromCatalog(cloneFrom) } } }
        .onChange(of: cloneFromScore?.id) { value in if value != nil, let cloneFromScore { Task { await model.cloneFromPersonalScore(cloneFromScore) } } }
        .onChange(of: model.selectedTrack) { value in
            if showLyricsDrawer, model.lyricTargetTrackID != model.currentTrack?.id { model.switchLyricsTarget(to: value) }
        }
        .onChange(of: model.shortcutQuery) { _ in model.searchShortcuts() }
        .onChange(of: model.shortcutCategory) { _ in model.searchShortcuts() }
        .onDisappear { model.leave() }
        .onChange(of: scenePhase) { phase in if phase != .active { model.pausePlayback() } }
        .onReceive(NotificationCenter.default.publisher(for: MIMISystemNotification.appWillResignActive)) { _ in model.pausePlayback() }
        .onReceive(NotificationCenter.default.publisher(for: MIMISystemNotification.appWillSleep)) { _ in model.pausePlayback() }
        .alert("删除工程？", isPresented: $model.showingDeleteAlert) {
            Button("取消", role: .cancel) { model.pendingDeleteID = nil }
            Button("删除", role: .destructive) { model.deleteProjectConfirmed() }
        } message: {
            Text("仅删除本地工坊工程。已关联的练习副本或原始附件会保留。")
        }
        .alert("保留未保存工程？", isPresented: $model.showingLeaveAlert) {
            Button("返回继续编辑", role: .cancel) {}
            Button("保存草稿并离开") { if let project = model.project { model.persistDraftBeforeLeave(project) } }
        } message: {
            Text("本地草稿已自动保存。离开前可再确认保留。")
        }
        .alert("清空当前音轨歌词？", isPresented: $model.showingClearLyricsAlert) {
            Button("取消", role: .cancel) {}
            Button("清空已写入歌词", role: .destructive) { model.clearLyricsConfirmed() }
        } message: {
            Text("将从此工程的目标音轨中删除已对齐歌词。输入框草稿会保留，可随后重新对齐。")
        }
        .alert("丢弃歌词草稿？", isPresented: $showDiscardLyricsAlert) {
            Button("继续编辑", role: .cancel) {}
            Button("丢弃并重载", role: .destructive) { model.discardCurrentLyricsDraftAndReload() }
        } message: {
            Text("这会删除当前工程与音轨绑定的未应用歌词草稿，并重新载入谱面中已保存的歌词。")
        }
        .sheet(isPresented: $showGuide) { guideSheet.frame(minWidth: 600, minHeight: 520) }
        .sheet(isPresented: $showShortcuts) { shortcutSheet.frame(minWidth: 620, minHeight: 560) }
        .sheet(isPresented: $showProjectLibrary) { projectSidebar.frame(minWidth: 320, minHeight: 520) }
        .sheet(isPresented: $showProjectDetails) {
            if let project = model.project { projectDetailsSheet(project).frame(minWidth: 660, minHeight: 400) }
        }
        .sheet(isPresented: $showTrackSettings) {
            if let project = model.project { trackSettingsSheet(project).frame(minWidth: 620, minHeight: 460) }
        }
        .sheet(isPresented: $showBarSettings) {
            if let project = model.project { barSettingsSheet(project).frame(minWidth: 560, minHeight: 400) }
        }
        .sheet(isPresented: $showStudioInfo) {
            if let project = model.project { studioInfoSheet(project).frame(minWidth: 620, minHeight: 460) }
        }
        .sheet(isPresented: $showLyricsDrawer, onDismiss: { model.persistCurrentLyricsDraft() }) {
            lyricsDrawer.frame(minWidth: 600, minHeight: 520)
        }
        .sheet(isPresented: $showTempoKeySheet) {
            if let project = model.project { tempoKeySettingsSheet(project) }
        }
        .sheet(isPresented: $showArrangerDrawer) {
            if let project = model.project { studioArrangerSheet(project) }
        }
    }


    private func createInitialProjectIfNeeded() {
        guard !didRequestInitialProject,
              didFinishInitialLoad,
              model.didLoadInitialDataSuccessfully,
              model.isBooted,
              model.project == nil,
              model.savedProjects.isEmpty,
              model.draftProjects.isEmpty,
              !model.isBusy,
              openProject == nil,
              importURL == nil,
              projectID == nil,
              cloneFrom == nil,
              cloneFromScore == nil else { return }
        didRequestInitialProject = true
        model.createProject(instrument: "guitar")
    }

    private func studioHeader(_ project: StudioProject) -> some View {
        studioMasterDeck(project)
    }

    private func studioMasterDeck(_ project: StudioProject) -> some View {
        NativeStudioStableRegion(key: NativeStudioMetadataEditorState(
            project,
            selectedTrack: model.selectedTrack,
            isPlaying: model.isPlaying,
            isDirty: model.isDirty,
            isBooted: model.isBooted
        )) {
            VStack(spacing: 0) {
                // Tier 1: Project Identity & Master Actions
                HStack(spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "music.note.list")
                            .font(.system(size: 15))
                            .foregroundStyle(Color(red: 0.55, green: 0.39, blue: 0.12))

                        TextField("作品标题", text: binding(project.title) { ["title": $0] })
                            .font(.system(size: 18, weight: .bold, design: .serif))
                            .textFieldStyle(.plain)
                            .frame(minWidth: 150, maxWidth: 320)

                        Text("·")
                            .foregroundStyle(Color.secondary.opacity(0.5))

                        TextField("演奏者 / 艺人", text: binding(project.artist) { ["artist": $0] })
                            .font(.system(size: 12, weight: .medium))
                            .textFieldStyle(.plain)
                            .frame(minWidth: 90, maxWidth: 180)

                        Button {
                            showArrangerDrawer = true
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "slider.horizontal.2")
                                    .font(.system(size: 8))
                                Text("\(project.tracks.count) 轨 · \(project.bars.count) 小节")
                                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color(red: 0.55, green: 0.48, blue: 0.40).opacity(0.12), in: Capsule())
                            .foregroundStyle(Color(red: 0.45, green: 0.38, blue: 0.30))
                        }
                        .buttonStyle(.plain)
                        .help("打开多轨配器与混音工作台")

                        if model.isDirty {
                            Circle()
                                .fill(Color(red: 0.78, green: 0.39, blue: 0.25))
                                .frame(width: 7, height: 7)
                                .help("有未保存更改")
                        }
                    }

                    Spacer(minLength: 8)

                    HStack(spacing: 6) {
                        Button { model.undo() } label: {
                            Image(systemName: "arrow.uturn.backward")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .help("撤销 (⌘Z)")
                        .buttonStyle(NativeStudioHeaderButtonStyle())
                        .frame(width: 34, height: 32)

                        Button { model.redo() } label: {
                            Image(systemName: "arrow.uturn.forward")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .help("重做 (⇧⌘Z)")
                        .buttonStyle(NativeStudioHeaderButtonStyle())
                        .frame(width: 34, height: 32)

                        Divider().frame(height: 18).padding(.horizontal, 2)

                        Button { model.save() } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "square.and.arrow.down")
                                Text(model.isBusy ? "保存中…" : "保存")
                            }
                            .font(.system(size: 11, weight: .semibold))
                        }
                        .disabled(model.isBusy)
                        .buttonStyle(NativeStudioHeaderButtonStyle(prominent: true))

                        Menu {
                            Group {
                                Button { showProjectDetails = true } label: { Label("工程署名与来源…", systemImage: "info.circle") }
                                Button { model.saveAsPracticeCopy() } label: { Label("更新练习副本", systemImage: "music.note.list") }
                                    .disabled(model.isBusy)
                                Button { showGuide = true } label: { Label("教程指南", systemImage: "book.closed") }
                                Button { model.searchShortcuts(); showShortcuts = true } label: { Label("快捷键速查", systemImage: "keyboard") }
                                Divider()
                                Button { model.importFromPanel() } label: { Label("导入外部谱面…", systemImage: "square.and.arrow.down") }
                                Divider()
                                Button("工坊 JSON") { model.export(format: "json") }
                                Button("AlphaTex") { model.export(format: "tex") }
                                Button("MIMI IBE") { model.export(format: "ibe") }
                            }
                            Group {
                                Button("Guitar Pro 7/8") { model.export(format: "gp") }
                                Divider()
                                Button("导出 PDF") { model.exportPDF() }
                                Button("导出 PNG 页面") { model.exportPNG() }
                                Button("打印谱面…") { model.printScore() }
                                if project.source != nil {
                                    Divider()
                                    Button("下载导入时的原始文件") { model.downloadOriginalSource() }
                                }
                                if model.currentTrack != nil {
                                    Divider()
                                    Button { showTrackSettings = true } label: { Label("音轨属性…", systemImage: "guitars") }
                                    if model.currentBar != nil {
                                        Button { showBarSettings = true } label: { Label("小节属性…", systemImage: "slider.horizontal.3") }
                                        Button { showStudioInfo = true } label: { Label("转换说明与关联练习…", systemImage: "doc.text.magnifyingglass") }
                                    }
                                }
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 12, weight: .bold))
                                .frame(width: 32, height: 32)
                        }
                        .menuStyle(.borderlessButton)
                        .buttonStyle(NativeStudioHeaderButtonStyle())
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 11)
                .padding(.bottom, 8)

                Divider().overlay(Color(red: 0.90, green: 0.86, blue: 0.79))

                // Tier 2: Playback Transport & Responsive Controls
                HStack(spacing: 8) {
                    // Play / Pause / Stop / Seek
                    HStack(spacing: 5) {
                        Button { model.togglePlayback() } label: {
                            HStack(spacing: 5) {
                                Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                                Text(model.isPlaying ? "暂停" : "播放")
                            }
                            .font(.system(size: 11, weight: .bold))
                        }
                        .help("播放/暂停 (Space)")
                        .buttonStyle(NativeStudioHeaderButtonStyle(prominent: true))
                        .frame(minWidth: 68)
                        .frame(height: 32)

                        Button { model.stopPlayback() } label: {
                            Image(systemName: "stop.fill")
                                .font(.system(size: 10))
                        }
                        .help("停止并回到谱首")
                        .buttonStyle(NativeStudioHeaderButtonStyle())
                        .frame(width: 32, height: 32)

                        Button { model.seekToCursor() } label: {
                            Image(systemName: "scope")
                                .font(.system(size: 10))
                        }
                        .help("将谱面滚动到当前拍")
                        .buttonStyle(NativeStudioHeaderButtonStyle())
                        .frame(width: 32, height: 32)
                        .disabled(!model.isBooted || model.project == nil)
                    }

                    Divider().frame(height: 20)

                    // Metronome & Signature Capsule (Tap to adjust)
                    Button {
                        showTempoKeySheet = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "metronome")
                                .font(.system(size: 9))
                                .foregroundStyle(Color(red: 0.55, green: 0.39, blue: 0.12))
                            Text("♩ \(project.initialTempo)")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))

                            Text("·").foregroundStyle(.secondary.opacity(0.6))

                            Text("\(project.timeSignatureNumerator)/\(project.timeSignatureDenominator)")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))

                            Text("·").foregroundStyle(.secondary.opacity(0.6))

                            Text("\(project.key) 调")
                                .font(.system(size: 11, weight: .semibold))

                            if let track = model.currentTrack, track.capo > 0 {
                                Text("·").foregroundStyle(.secondary.opacity(0.6))
                                Text("Capo \(track.capo)品")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(Color(red: 0.78, green: 0.39, blue: 0.25))
                            }

                            Image(systemName: "slider.horizontal.2")
                                .font(.system(size: 9))
                                .foregroundStyle(Color(red: 0.55, green: 0.39, blue: 0.12))
                        }
                        .foregroundStyle(Color(red: 0.38, green: 0.30, blue: 0.22))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color(red: 0.93, green: 0.90, blue: 0.84), in: Capsule())
                        .overlay(Capsule().stroke(Color(red: 0.87, green: 0.83, blue: 0.76), lineWidth: 0.7))
                    }
                    .buttonStyle(.plain)
                    .help("轻触调节曲速、拍号、调性与变调夹 (支持触控滑块与快捷预设)")

                    Spacer(minLength: 4)

                    // Auxiliary View Docks & Actions
                    HStack(spacing: 5) {
                        Button { showArrangerDrawer = true } label: {
                            Label("配器与混音", systemImage: "slider.horizontal.3")
                        }
                        .buttonStyle(NativeStudioHeaderButtonStyle())

                        Button { model.beginLyricsSession(); showLyricsDrawer = true } label: {
                            Label("歌词", systemImage: "text.alignleft")
                        }
                        .disabled(model.currentTrack == nil)
                        .buttonStyle(NativeStudioHeaderButtonStyle())

                        Button { showProjectLibrary = true } label: {
                            Label("草稿", systemImage: "folder")
                        }
                        .buttonStyle(NativeStudioHeaderButtonStyle())

                        Menu {
                            Button { model.createProject(instrument: "guitar") } label: { Label("原声吉他", systemImage: "guitars") }
                            Button { model.createProject(instrument: "ukulele") } label: { Label("尤克里里", systemImage: "music.note") }
                            Button { model.createProject(instrument: "bass") } label: { Label("电贝斯", systemImage: "guitars.fill") }
                            Button { model.createProject(instrument: "band") } label: { Label("乐队编配", systemImage: "music.mic") }
                        } label: {
                            Label("新建", systemImage: "plus")
                        }
                        .menuStyle(.borderlessButton)
                        .buttonStyle(NativeStudioHeaderButtonStyle())
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .background(Color(red: 0.984, green: 0.976, blue: 0.957))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color(red: 0.89, green: 0.85, blue: 0.78), lineWidth: 1))
            .shadow(color: .black.opacity(0.035), radius: 10, y: 3)
            .padding(.horizontal, 10)
            .padding(.top, 8)
        }
        .equatable()
    }

    private var projectSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("本地工程").font(.headline)
                Spacer()
                Text("\(model.savedProjects.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                Button("完成") { showProjectLibrary = false }.buttonStyle(.borderless)
            }.padding(.horizontal, 14).padding(.vertical, 12)
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(model.savedProjects.map { ScopedStudioProject(project: $0, namespace: "saved") }) { row in
                        sidebarProject(row.project, isDraft: false)
                    }
                    if !model.draftProjects.isEmpty {
                        HStack { Text("自动草稿").font(.caption.weight(.semibold)).foregroundStyle(.secondary); Spacer() }
                            .padding(.horizontal, 14).padding(.top, 16).padding(.bottom, 5)
                        ForEach(model.draftProjects.map { ScopedStudioProject(project: $0, namespace: "draft") }) { row in
                            sidebarProject(row.project, isDraft: true)
                        }
                    }
                }.padding(.horizontal, 6).padding(.bottom, 12)
            }
            Divider()
            VStack(alignment: .leading, spacing: 5) {
                Label("MIMI Guitar Studio", systemImage: "music.note.list").font(.caption.weight(.semibold))
                Text("原件与工坊工程分开保存，练习副本可随时更新。")
                    .font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }.padding(12)
        }
        .background(MIMIPlatformColor.secondarySystemBackground)
    }

    private func sidebarProject(_ item: StudioProject, isDraft: Bool) -> some View {
        HStack(spacing: 6) {
            Button {
                if isDraft { model.openDraft(item) } else { model.openSavedProject(item) }
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title.isEmpty ? "未命名工程" : item.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                    Text("\(item.tracks.count) 轨 · \(item.bars.count) 小节 · \(Date(timeIntervalSince1970: item.updatedAt / 1000), style: .date)")
                        .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 9).padding(.vertical, 8)
                .background(model.project?.id == item.id ? Color.accentColor.opacity(0.12) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }.buttonStyle(.plain)
            Menu {
                Button("打开工程") { if isDraft { model.openDraft(item) } else { model.openSavedProject(item) } }
                if isDraft { Button("删除本地草稿", role: .destructive) { model.deleteLocalDraft(item.id) } }
                else { Button("删除工程…", role: .destructive) { model.requestDeleteProject(item.id) } }
            } label: { Image(systemName: "ellipsis").foregroundStyle(.secondary).frame(width: 22, height: 28) }
                .menuStyle(.borderlessButton)
        }
    }


    private var editorSurface: some View {
        VStack(spacing: 0) {
            if model.project != nil {
                if !model.conversionWarnings.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color(red: 0.59, green: 0.42, blue: 0.10))
                        Text("导入转换报告 · \(model.conversionWarnings.count) 项需要检查；原文件备份保留。")
                            .font(.system(size: 10, weight: .medium)).foregroundStyle(Color(red: 0.40, green: 0.31, blue: 0.18))
                        Spacer(minLength: 4)
                        Button("查看") { showStudioInfo = true }.buttonStyle(.plain).font(.system(size: 10, weight: .semibold))
                    }
                    .padding(.horizontal, 14).padding(.vertical, 6)
                    .background(Color(red: 1.0, green: 0.97, blue: 0.88))
                }
#if MIMI_RUNTIME_DIAGNOSTICS
                if Self.runtimeStudioPruneTarget == "no-tools" {
                    Color.clear
                        .frame(maxWidth: .infinity)
                        .frame(height: Self.diagnosticEditToolsContentHeight)
                        .accessibilityHidden(true)
                } else {
                    editTools
                }
#else
                editTools
#endif
            }
            NativeStudioWebView(model: model)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 560)
                .background(Color(red: 0.965, green: 0.948, blue: 0.914))
            if let project = model.project {
                notationStatus
                studioDock(project)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func studioDock(_ project: StudioProject) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 9) {
                Button { isDockCollapsed.toggle() } label: {
                    Label(isDockCollapsed ? "展开工作台" : "收起工作台", systemImage: isDockCollapsed ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(Color(red: 0.17, green: 0.15, blue: 0.13), in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)

                HStack(spacing: 3) {
                    ForEach(NativeStudioDockTab.allCases) { tab in
                        Button { selectedDockTab = tab } label: {
                            Label(tab.title, systemImage: tab.symbol)
                                .font(.system(size: 11, weight: selectedDockTab == tab ? .semibold : .regular))
                                .foregroundStyle(selectedDockTab == tab ? Color(red: 0.48, green: 0.34, blue: 0.12) : Color.secondary)
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .background(selectedDockTab == tab ? Color(red: 0.77, green: 0.61, blue: 0.27).opacity(0.16) : .clear, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(3)
                .background(Color(red: 0.93, green: 0.90, blue: 0.84), in: Capsule())

                Spacer(minLength: 8)
                Text("0–24 输入品数 · Space 播放 · Alt+1…6 切换时值")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Color(red: 0.55, green: 0.48, blue: 0.40))
                    .lineLimit(1)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)

            if !isDockCollapsed {
                Divider()
#if MIMI_RUNTIME_DIAGNOSTICS
                if Self.runtimeStudioPruneTarget == "no-inspector" {
                    Color.clear.frame(height: 232).accessibilityHidden(true)
                } else {
                    studioDockContent(project)
                }
#else
                studioDockContent(project)
#endif
            }
        }
        .background(Color(red: 0.984, green: 0.976, blue: 0.957))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(red: 0.89, green: 0.85, blue: 0.78), lineWidth: 1))
        .shadow(color: .black.opacity(0.04), radius: 10, y: 3)
        .padding(.horizontal, 10).padding(.vertical, 8)
    }

    @ViewBuilder
    private func studioDockContent(_ project: StudioProject) -> some View {
        switch selectedDockTab {
        case .workbench:
            if let track = model.currentTrack {
                VStack(spacing: 4) {
                    trackSelector(project)
                    GeometryReader { proxy in
                        let chordLibraryWidth = max(300, proxy.size.width * 0.36)
                        HStack(alignment: .top, spacing: 12) {
                            ScrollView(.vertical) {
                                chordLibrarySection(track, projectID: project.id)
                                    .frame(width: chordLibraryWidth, alignment: .topLeading)
                            }
                            .scrollIndicators(.hidden)
                            .frame(width: chordLibraryWidth, height: proxy.size.height, alignment: .top)
                            ScrollView(.vertical) {
                                studioFretboardSection(track)
                                    .frame(maxWidth: .infinity, alignment: .topLeading)
                            }
                            .scrollIndicators(.hidden)
                            .frame(height: proxy.size.height, alignment: .top)
                        }
                    }
                }
                .padding(.horizontal, 10).padding(.top, 3).padding(.bottom, 7)
                .frame(height: 244)
            }
        case .mixer:
            studioMixer(project)
                .frame(maxWidth: .infinity)
                .frame(height: 244)
        }
    }


    private func studioMixer(_ project: StudioProject) -> some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 8) {
                ForEach(Array(project.tracks.enumerated()), id: \.element.id) { index, track in
                    VStack(alignment: .leading, spacing: 7) {
                        HStack(spacing: 6) {
                            Button { model.chooseTrack(index) } label: {
                                HStack(spacing: 5) {
                                    Text(String(format: "%02d", index + 1)).font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
                                    Text(track.name).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                                }
                            }
                            .buttonStyle(.plain).foregroundStyle(model.selectedTrack == index ? Color(red: 0.55, green: 0.37, blue: 0.11) : Color.primary)
                            Spacer(minLength: 0)
                            if model.selectedTrack == index { Image(systemName: "scope").font(.system(size: 9)).foregroundStyle(Color(red: 0.59, green: 0.42, blue: 0.10)) }
                        }
                        HStack(spacing: 5) {
                            Toggle("静音", isOn: trackBoolBinding(track.mute, field: "mute"))
                            Toggle("独奏", isOn: trackBoolBinding(track.solo, field: "solo"))
                        }
                        .toggleStyle(.button).controlSize(.mini).font(.system(size: 9))
                        HStack(spacing: 5) {
                            Image(systemName: "speaker.wave.1.fill").font(.system(size: 9)).foregroundStyle(.secondary)
                            Slider(value: trackDoubleBinding(track.volume, field: "volume"), in: 0...1).tint(Color(red: 0.59, green: 0.42, blue: 0.10))
                            Text("\(Int(track.volume * 100))").font(.system(size: 9, design: .monospaced)).frame(width: 26, alignment: .trailing)
                        }
                        HStack(spacing: 5) {
                            Text("L").font(.system(size: 8, design: .monospaced)).foregroundStyle(.secondary)
                            Slider(value: trackDoubleBinding(track.pan, field: "pan"), in: -1...1).tint(Color(red: 0.59, green: 0.42, blue: 0.10))
                            Text("R").font(.system(size: 8, design: .monospaced)).foregroundStyle(.secondary)
                        }
                        Divider()
                        HStack {
                            Text("\(track.tuningName) · Capo \(track.capo)").font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
                            Spacer(minLength: 0)
                            Button { showTrackSettings = true; model.chooseTrack(index) } label: { Image(systemName: "slider.horizontal.3") }
                                .buttonStyle(.plain).help("音轨属性")
                        }
                    }
                    .padding(10)
                    .frame(width: 218, height: 204, alignment: .topLeading)
                    .background(Color(red: 1.0, green: 0.995, blue: 0.98), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(Color(red: 0.89, green: 0.85, blue: 0.78), lineWidth: 1))
                }
                Button { model.apply("track", arguments: ["field": "add"]) } label: {
                    VStack(spacing: 7) {
                        Image(systemName: "plus.circle").font(.system(size: 20))
                        Text("新增音轨").font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(Color(red: 0.55, green: 0.42, blue: 0.22))
                    .frame(width: 105, height: 204)
                    .background(Color(red: 0.96, green: 0.94, blue: 0.90), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                }.buttonStyle(.plain)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
        }
        .scrollIndicators(.hidden)
        .background(Color(red: 0.976, green: 0.965, blue: 0.940))
    }

    private func projectDetailsSheet(_ project: StudioProject) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            sheetHeading("工程署名与来源", symbol: "music.note.list") { showProjectDetails = false }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    TextField("专辑", text: binding(project.album ?? "") { ["album": $0] })
                    HStack(spacing: 10) {
                        TextField("作词", text: binding(project.words ?? "") { ["words": $0] })
                        TextField("作曲", text: binding(project.music ?? "") { ["music": $0] })
                        TextField("制谱人", text: binding(project.tabber ?? "") { ["tabber": $0] })
                    }
                    if let source = project.source {
                        VStack(alignment: .leading, spacing: 5) {
                            Label(source.kind == "library" ? "曲库引用" : "本机原件", systemImage: source.kind == "library" ? "books.vertical" : "doc.text")
                                .font(.system(size: 12, weight: .semibold))
                            Text("\(source.fileName) · \(source.format.uppercased())")
                            Text("来源编号：\(source.id)")
                        }
                        .font(.system(size: 11)).foregroundStyle(Color(red: 0.45, green: 0.38, blue: 0.29))
                        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(red: 0.96, green: 0.94, blue: 0.90), in: RoundedRectangle(cornerRadius: 10))
                        .textSelection(.enabled)
                    }
                }
                .textFieldStyle(.roundedBorder)
                .padding(.bottom, 6)
            }
            HStack {
                Text("\(project.bars.count) 小节 · \(project.tracks.count) 轨")
                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                Spacer()
                Button("完成") { showProjectDetails = false }.buttonStyle(NativeStudioHeaderButtonStyle(prominent: true))
            }
        }
        .padding(18)
        .background(Color(red: 0.984, green: 0.976, blue: 0.957))
    }

    private func trackSettingsSheet(_ project: StudioProject) -> some View {
        let track = model.currentTrack
        return VStack(alignment: .leading, spacing: 13) {
            sheetHeading("音轨属性", symbol: "guitars") { showTrackSettings = false }
            if let track {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        TextField("音轨名称", text: trackTextBinding(track.name, field: "name"))
                        HStack {
                            Text("GM 音色"); Spacer()
                            Picker("GM 音色", selection: trackIntBinding(track.program, field: "program")) {
                                ForEach(Array(gmPrograms.enumerated()), id: \.offset) { index, name in Text("\(index + 1). \(name)").tag(index) }
                            }.labelsHidden().frame(width: 260)
                            Button("浏览 128 种音色…") { showGMInstrumentBrowser = true }.buttonStyle(NativeStudioHeaderButtonStyle())
                        }
                        HStack { Text("变调夹"); Stepper("\(track.capo) 品", value: trackIntBinding(track.capo, field: "capo"), in: 0...24).frame(width: 150) }
                        HStack { Text("音量").frame(width: 46, alignment: .leading); Slider(value: trackDoubleBinding(track.volume, field: "volume"), in: 0...1); Text("\(Int(track.volume * 100))%").monospacedDigit().frame(width: 42) }
                        HStack { Text("声像").frame(width: 46, alignment: .leading); Slider(value: trackDoubleBinding(track.pan, field: "pan"), in: -1...1); Text(track.pan < -0.15 ? "左" : (track.pan > 0.15 ? "右" : "中")).frame(width: 42) }
                        HStack { Toggle("静音", isOn: trackBoolBinding(track.mute, field: "mute")); Toggle("独奏", isOn: trackBoolBinding(track.solo, field: "solo")) }
                        TextField("调弦名称", text: trackTextBinding(track.tuningName, field: "tuningName"))
                        TextField("弦高到低 MIDI 音高，以逗号分隔", text: tuningBinding(track.tuning)).font(.system(size: 11, design: .monospaced))
                        HStack {
                            Button("试听选中音符") { model.previewSelectedNote() }.buttonStyle(NativeStudioHeaderButtonStyle())
                            Spacer()
                            Button("删除音轨", role: .destructive) { model.apply("track", arguments: ["field": "remove"]); showTrackSettings = false }
                                .disabled(project.tracks.count <= 1)
                        }
                    }
                    .padding(.vertical, 2)
                }
            } else {
                Text("选择一个音轨后可编辑它的音色、调弦与混音。")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .background(Color(red: 0.984, green: 0.976, blue: 0.957))
        .sheet(isPresented: $showGMInstrumentBrowser) { gmInstrumentBrowser.frame(minWidth: 620, minHeight: 520) }
    }

    private func barSettingsSheet(_ project: StudioProject) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            sheetHeading("小节属性", symbol: "slider.horizontal.3") { showBarSettings = false }
            if let bar = model.currentBar {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack { Text("拍号"); Stepper("\(bar.timeSignatureNumerator)/\(bar.timeSignatureDenominator)", value: barMetaIntBinding(bar.timeSignatureNumerator, field: "timeSignatureNumerator"), in: 1...32).frame(width: 190) }
                        HStack { Text("分母"); Stepper("\(bar.timeSignatureDenominator)", value: barMetaIntBinding(bar.timeSignatureDenominator, field: "timeSignatureDenominator"), in: 1...32).frame(width: 150) }
                        HStack { Text("局部速度"); Stepper(bar.tempo.map { "♩ \(Int($0))" } ?? "沿用前段", value: barTempoBinding(bar.tempo), in: 20...300).frame(width: 180) }
                        TextField("段落：前奏 / 主歌 / 副歌 / Solo…", text: barMetaTextBinding(bar.section ?? "", field: "section"))
                        HStack { Toggle("反复开始", isOn: barMetaBoolBinding(bar.repeatStart == true, field: "repeatStart")); Toggle("反复结束", isOn: barMetaBoolBinding(bar.repeatEnd == true, field: "repeatEnd")) }
                        HStack { Text("反复次数"); Stepper("\(bar.repeatCount ?? 2)", value: barMetaIntBinding(bar.repeatCount ?? 2, field: "repeatCount"), in: 2...8) }
                        HStack { Text("Volta"); Stepper(bar.volta.map { String($0) } ?? "无", value: barMetaIntBinding(bar.volta ?? 1, field: "volta"), in: 1...8) }
                        timingSummary(bar)
                    }
                }
            } else {
                Text("先在谱面中选择一个小节。")
                    .foregroundStyle(.secondary)
            }
            HStack {
                Button { model.apply("duplicateBar") } label: { Label("复制小节", systemImage: "plus.square.on.square") }.buttonStyle(NativeStudioHeaderButtonStyle())
                Button { model.insertBarAtCursorAndAdvance() } label: { Label("加小节", systemImage: "plus.square") }.buttonStyle(NativeStudioHeaderButtonStyle())
                Button { model.apply("deleteBar") } label: { Label("删小节", systemImage: "minus.square") }.buttonStyle(NativeStudioHeaderButtonStyle())
                Spacer()
                Button("完成") { showBarSettings = false }.buttonStyle(NativeStudioHeaderButtonStyle(prominent: true))
            }
        }
        .padding(18)
        .background(Color(red: 0.984, green: 0.976, blue: 0.957))
    }

    private func studioInfoSheet(_ project: StudioProject) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            sheetHeading("转换说明与关联练习", symbol: "doc.text.magnifyingglass") { showStudioInfo = false }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if !model.conversionWarnings.isEmpty {
                        inspectorSection("导入转换说明 · \(model.conversionWarnings.count)") {
                            ForEach(Array(model.conversionWarnings.enumerated()), id: \.offset) { index, warning in
                                Text("\(index + 1). \(warning)").font(.system(size: 11)).fixedSize(horizontal: false, vertical: true)
                            }
                            Text("原文件字节单独保存在原始备份中。")
                                .font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                        }
                    }
                    if let linkedID = model.linkedPracticeScoreID {
                        inspectorSection("练习副本") {
                            Text("已关联个人曲谱：\(linkedID)").font(.system(size: 11)).textSelection(.enabled)
                            HStack {
                                Button("打开练习页") { model.openPractice(linkedID) }.buttonStyle(NativeStudioHeaderButtonStyle())
                                Button("用当前工程更新副本") { model.saveAsPracticeCopy() }.buttonStyle(NativeStudioHeaderButtonStyle())
                            }
                        }
                    } else {
                        inspectorSection("练习副本") {
                            Text("将当前工程保存为个人练习副本，可在“我的谱”中回顾和继续练习。")
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                            Button("保存为练习副本") { model.saveAsPracticeCopy() }.buttonStyle(NativeStudioHeaderButtonStyle())
                        }
                    }
                    inspectorSection("当前工程") {
                        Text("\(project.title) · \(project.tracks.count) 轨 · \(project.bars.count) 小节")
                            .font(.system(size: 11)).textSelection(.enabled)
                        if let source = project.source { Text("来源：\(source.fileName) · \(source.format.uppercased())").font(.system(size: 10)).textSelection(.enabled) }
                    }
                }
                .padding(.bottom, 6)
            }
            HStack { Spacer(); Button("完成") { showStudioInfo = false }.buttonStyle(NativeStudioHeaderButtonStyle(prominent: true)) }
        }
        .padding(18)
        .background(Color(red: 0.984, green: 0.976, blue: 0.957))
    }

    private func sheetHeading(_ title: String, symbol: String, close: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Label(title, systemImage: symbol).font(.system(size: 17, weight: .semibold, design: .serif))
            Spacer()
            Button("完成", action: close).buttonStyle(.plain).foregroundStyle(Color(red: 0.45, green: 0.37, blue: 0.28))
        }
        .padding(.bottom, 3)
    }

    private func tempoKeySettingsSheet(_ project: StudioProject) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            sheetHeading("乐曲曲速、节拍与调性设定", symbol: "metronome") { showTempoKeySheet = false }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // 1. BPM
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("速度 (BPM)").font(.system(size: 13, weight: .semibold))
                            Spacer()
                            Text("\(project.initialTempo)").font(.system(size: 20, weight: .bold, design: .monospaced))
                            Text("BPM").font(.caption).foregroundStyle(.secondary)
                        }
                        HStack(spacing: 12) {
                            Button {
                                if project.initialTempo > 30 {
                                    model.apply("metadata", arguments: ["values": ["initialTempo": project.initialTempo - 1]])
                                }
                            } label: {
                                Image(systemName: "minus")
                                    .frame(width: 36, height: 36)
                                    .background(Color(red: 0.93, green: 0.90, blue: 0.84), in: RoundedRectangle(cornerRadius: 8))
                            }.buttonStyle(.plain)

                            Slider(
                                value: Binding(
                                    get: { Double(project.initialTempo) },
                                    set: { model.apply("metadata", arguments: ["values": ["initialTempo": min(300, max(30, Int($0)))]]) }
                                ),
                                in: 30...300,
                                step: 1
                            )
                            .tint(Color(red: 0.55, green: 0.39, blue: 0.12))

                            Button {
                                if project.initialTempo < 300 {
                                    model.apply("metadata", arguments: ["values": ["initialTempo": project.initialTempo + 1]])
                                }
                            } label: {
                                Image(systemName: "plus")
                                    .frame(width: 36, height: 36)
                                    .background(Color(red: 0.93, green: 0.90, blue: 0.84), in: RoundedRectangle(cornerRadius: 8))
                            }.buttonStyle(.plain)
                        }

                        HStack(spacing: 6) {
                            ForEach([60, 72, 84, 96, 108, 120, 136, 150], id: \.self) { bpm in
                                Button("\(bpm)") {
                                    model.apply("metadata", arguments: ["values": ["initialTempo": bpm]])
                                }
                                .font(.system(size: 11, weight: project.initialTempo == bpm ? .bold : .regular))
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                                .background(project.initialTempo == bpm ? Color(red: 0.17, green: 0.15, blue: 0.13) : Color(red: 0.93, green: 0.90, blue: 0.84), in: Capsule())
                                .foregroundStyle(project.initialTempo == bpm ? .white : Color(red: 0.35, green: 0.28, blue: 0.20))
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(12)
                    .background(Color(red: 0.96, green: 0.94, blue: 0.90), in: RoundedRectangle(cornerRadius: 12))

                    // 2. Time Signature
                    VStack(alignment: .leading, spacing: 8) {
                        Text("拍号 (Time Signature)").font(.system(size: 13, weight: .semibold))
                        HStack(spacing: 8) {
                            ForEach([("4/4", 4, 4), ("3/4", 3, 4), ("2/4", 2, 4), ("6/8", 6, 8), ("12/8", 12, 8)], id: \.0) { sig, num, den in
                                let isSel = project.timeSignatureNumerator == num && project.timeSignatureDenominator == den
                                Button(sig) {
                                    model.apply("metadata", arguments: ["values": ["timeSignatureNumerator": num, "timeSignatureDenominator": den]])
                                }
                                .font(.system(size: 12, weight: isSel ? .bold : .regular))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .background(isSel ? Color(red: 0.55, green: 0.39, blue: 0.12) : Color(red: 0.93, green: 0.90, blue: 0.84), in: Capsule())
                                .foregroundStyle(isSel ? .white : Color(red: 0.35, green: 0.28, blue: 0.20))
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(12)
                    .background(Color(red: 0.96, green: 0.94, blue: 0.90), in: RoundedRectangle(cornerRadius: 12))

                    // 3. Key
                    VStack(alignment: .leading, spacing: 8) {
                        Text("调性 (Key)").font(.system(size: 13, weight: .semibold))
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(["C", "G", "D", "A", "E", "B", "F", "Bb", "Eb", "Ab", "Am", "Em", "Dm"], id: \.self) { k in
                                    let isSel = project.key == k
                                    Button(k) {
                                        model.apply("metadata", arguments: ["values": ["key": k]])
                                    }
                                    .font(.system(size: 12, weight: isSel ? .bold : .regular))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .background(isSel ? Color(red: 0.55, green: 0.39, blue: 0.12) : Color(red: 0.93, green: 0.90, blue: 0.84), in: Capsule())
                                    .foregroundStyle(isSel ? .white : Color(red: 0.35, green: 0.28, blue: 0.20))
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .padding(12)
                    .background(Color(red: 0.96, green: 0.94, blue: 0.90), in: RoundedRectangle(cornerRadius: 12))

                    // 4. Capo
                    if let track = model.currentTrack {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("当前音轨变调夹 (Capo)").font(.system(size: 13, weight: .semibold))
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 6) {
                                    ForEach(0...12, id: \.self) { c in
                                        let isSel = track.capo == c
                                        Button(c == 0 ? "无" : "\(c)品") {
                                            model.apply("track", arguments: ["field": "capo", "value": c])
                                        }
                                        .font(.system(size: 12, weight: isSel ? .bold : .regular))
                                        .padding(.horizontal, 11)
                                        .padding(.vertical, 7)
                                        .background(isSel ? Color(red: 0.55, green: 0.39, blue: 0.12) : Color(red: 0.93, green: 0.90, blue: 0.84), in: Capsule())
                                        .foregroundStyle(isSel ? .white : Color(red: 0.35, green: 0.28, blue: 0.20))
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                        .padding(12)
                        .background(Color(red: 0.96, green: 0.94, blue: 0.90), in: RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
            HStack {
                Spacer()
                Button("完成") { showTempoKeySheet = false }
                    .buttonStyle(NativeStudioHeaderButtonStyle(prominent: true))
            }
        }
        .padding(18)
        .frame(minWidth: 480, maxWidth: 540, minHeight: 460)
        .background(Color(red: 0.984, green: 0.976, blue: 0.957))
    }

    private func studioSectionBlueprintBar(_ project: StudioProject) -> some View {
        let sections = StudioSectionBlueprint.extractSections(from: project)
        return HStack(spacing: 8) {
            // Label
            HStack(spacing: 4) {
                Image(systemName: "map.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Color(red: 0.55, green: 0.39, blue: 0.12))
                Text("曲式蓝图")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color(red: 0.55, green: 0.39, blue: 0.12))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(red: 0.55, green: 0.39, blue: 0.12).opacity(0.12), in: Capsule())

            // Scrollable Section Pills
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(sections) { sec in
                        let isCurrent = model.cursor.barIndex >= sec.startBar && model.cursor.barIndex <= sec.endBar
                        Menu {
                            Button {
                                model.jumpToSection(sec)
                            } label: {
                                Label("跳转至此段 (第 \(sec.startBar + 1) 小节)", systemImage: "arrow.right.circle")
                            }
                            Button {
                                model.cloneSection(sec)
                            } label: {
                                Label("克隆此段落 (追加在末尾)", systemImage: "doc.on.doc")
                            }
                            Menu("全局移调") {
                                Button("升半音 (+1)") { model.transposeSection(sec, semitones: 1) }
                                Button("升全音 (+2)") { model.transposeSection(sec, semitones: 2) }
                                Button("降半音 (-1)") { model.transposeSection(sec, semitones: -1) }
                                Button("降全音 (-2)") { model.transposeSection(sec, semitones: -2) }
                            }
                            if sections.count > 1 {
                                Button(role: .destructive) {
                                    model.deleteSection(sec)
                                } label: {
                                    Label("删除此段落", systemImage: "trash")
                                }
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Circle()
                                    .fill(sec.themeColor)
                                    .frame(width: 7, height: 7)
                                Text(sec.badgeLabel)
                                    .font(.system(size: 11, weight: isCurrent ? .bold : .medium))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                isCurrent
                                    ? sec.themeColor.opacity(0.18)
                                    : Color(red: 0.94, green: 0.91, blue: 0.85),
                                in: Capsule()
                            )
                            .overlay(
                                Capsule().stroke(isCurrent ? sec.themeColor : Color.clear, lineWidth: 1.2)
                            )
                            .foregroundStyle(isCurrent ? Color(red: 0.17, green: 0.15, blue: 0.13) : Color(red: 0.38, green: 0.32, blue: 0.25))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Spacer(minLength: 4)

            // Actions: Quick section marker
            Menu {
                ForEach(StudioSectionBlueprint.standardSectionNames, id: \.self) { name in
                    Button(name) {
                        model.markBarAsSection(barIndex: model.cursor.barIndex, sectionName: name)
                    }
                }
                Divider()
                Button("清除当前小节段落标记") {
                    model.markBarAsSection(barIndex: model.cursor.barIndex, sectionName: nil)
                }
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "bookmark")
                        .font(.system(size: 10))
                    Text("标记第 \(model.cursor.barIndex + 1) 小节…")
                        .font(.system(size: 11, weight: .medium))
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Color(red: 0.92, green: 0.88, blue: 0.81), in: Capsule())
                .foregroundStyle(Color(red: 0.32, green: 0.26, blue: 0.19))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(Color(red: 0.965, green: 0.948, blue: 0.918))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color(red: 0.89, green: 0.85, blue: 0.78), lineWidth: 0.8))
    }

    private func studioArrangerSheet(_ project: StudioProject) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            sheetHeading("多轨配器与混音工作台", symbol: "slider.horizontal.3") { showArrangerDrawer = false }

            ScrollView {
                VStack(spacing: 12) {
                    // Track list
                    ForEach(Array(project.tracks.enumerated()), id: \.element.id) { index, track in
                        let isCurrent = model.selectedTrack == index
                        VStack(spacing: 8) {
                            HStack(spacing: 10) {
                                Button {
                                    model.chooseTrack(index)
                                } label: {
                                    HStack(spacing: 5) {
                                        Circle()
                                            .fill(isCurrent ? Color(red: 0.88, green: 0.35, blue: 0.22) : Color.gray.opacity(0.4))
                                            .frame(width: 8, height: 8)
                                        Text(isCurrent ? "当前编辑轨" : "切换为当前")
                                            .font(.system(size: 10, weight: .bold))
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(isCurrent ? Color(red: 0.88, green: 0.35, blue: 0.22).opacity(0.12) : Color.clear, in: Capsule())
                                    .foregroundStyle(isCurrent ? Color(red: 0.88, green: 0.35, blue: 0.22) : Color.secondary)
                                }
                                .buttonStyle(.plain)

                                Text(track.name)
                                    .font(.headline.weight(.semibold))

                                Text("(\(track.tuningName))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                Spacer()

                                Button {
                                    model.updateTrackMixing(index: index, solo: !track.solo)
                                } label: {
                                    Text("S")
                                        .font(.system(size: 11, weight: .bold))
                                        .frame(width: 26, height: 26)
                                        .background(track.solo ? Color.yellow : Color.gray.opacity(0.15), in: Circle())
                                        .foregroundStyle(track.solo ? Color.black : Color.primary)
                                }
                                .buttonStyle(.plain)
                                .help("独奏 Solo")

                                Button {
                                    model.updateTrackMixing(index: index, mute: !track.mute)
                                } label: {
                                    Text("M")
                                        .font(.system(size: 11, weight: .bold))
                                        .frame(width: 26, height: 26)
                                        .background(track.mute ? Color.red : Color.gray.opacity(0.15), in: Circle())
                                        .foregroundStyle(track.mute ? Color.white : Color.primary)
                                }
                                .buttonStyle(.plain)
                                .help("静音 Mute")

                                Menu {
                                    Button("复制此音轨与乐谱") {
                                        if let updated = StudioArrangerLogic.duplicateTrack(project: project, trackIndex: index) {
                                            model.undoStack = Array((model.undoStack + [project]).suffix(100))
                                            model.redoStack.removeAll()
                                            model.recordProjectMutation(updated, status: "已复制音轨")
                                            model.selectedTrack = updated.tracks.count - 1
                                        }
                                    }
                                    if project.tracks.count > 1 {
                                        Button("删除此音轨", role: .destructive) {
                                            model.removeTrack(index: index)
                                        }
                                    }
                                } label: {
                                    Image(systemName: "ellipsis.circle")
                                        .font(.system(size: 15))
                                }
                                .buttonStyle(.plain)
                            }

                            // Volume & Pan Sliders
                            HStack(spacing: 16) {
                                HStack(spacing: 6) {
                                    Image(systemName: "speaker.wave.2.fill")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                    Slider(
                                        value: Binding(
                                            get: { track.volume },
                                            set: { val in model.updateTrackMixing(index: index, volume: val) }
                                        ),
                                        in: 0.0...1.5
                                    )
                                    Text("\(Int(track.volume * 100))%")
                                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                                        .frame(width: 38, alignment: .trailing)
                                }

                                HStack(spacing: 6) {
                                    Text("L")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(.secondary)
                                    Slider(
                                        value: Binding(
                                            get: { track.pan },
                                            set: { val in model.updateTrackMixing(index: index, pan: val) }
                                        ),
                                        in: -1.0...1.0
                                    )
                                    Text("R")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: 160)
                            }
                        }
                        .padding(12)
                        .background(isCurrent ? Color(red: 0.985, green: 0.97, blue: 0.94) : Color(red: 0.95, green: 0.93, blue: 0.89))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(isCurrent ? Color(red: 0.88, green: 0.35, blue: 0.22).opacity(0.4) : Color.clear, lineWidth: 1)
                        )
                    }

                    // Add Track Presets Section
                    VStack(alignment: .leading, spacing: 8) {
                        Text("新增乐器分轨")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Color(red: 0.55, green: 0.39, blue: 0.12))

                        HStack(spacing: 6) {
                            ForEach(StudioTrackPreset.standardPresets) { preset in
                                Button {
                                    model.addTrackPreset(preset)
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: preset.iconName)
                                            .font(.system(size: 10))
                                        Text("+ \(preset.name)")
                                            .font(.system(size: 11, weight: .medium))
                                    }
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 6)
                                    .background(Color(red: 0.92, green: 0.88, blue: 0.81), in: Capsule())
                                    .foregroundStyle(Color(red: 0.25, green: 0.20, blue: 0.15))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(red: 0.96, green: 0.94, blue: 0.90))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }

            HStack {
                Spacer()
                Button("完成") { showArrangerDrawer = false }
                    .buttonStyle(NativeStudioHeaderButtonStyle(prominent: true))
            }
        }
        .padding(18)
        .frame(minWidth: 540, maxWidth: 620, minHeight: 480)
        .background(Color(red: 0.984, green: 0.976, blue: 0.957))
    }

    private func trackSelector(_ project: StudioProject) -> some View {
        NativeStudioStableRegion(key: NativeStudioTrackSelectorState(
            projectID: project.id,
            tracks: project.tracks,
            selectedTrack: model.selectedTrack,
            isPlaying: model.isPlaying
        )) {
            HStack(spacing: 6) {
                ForEach(Array(project.tracks.enumerated()), id: \.element.id) { index, track in
                    Button { model.chooseTrack(index) } label: {
                        HStack(spacing: 5) {
                            Image(systemName: track.mute ? "speaker.slash" : "guitars")
                            Text(track.name).lineLimit(1)
                            if track.solo { Text("S").font(.caption2.bold()).foregroundStyle(.orange) }
                        }
                        .font(.system(size: 12, weight: model.selectedTrack == index ? .semibold : .regular))
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(model.selectedTrack == index ? Color(red: 0.17, green: 0.15, blue: 0.13) : Color.clear)
                        .foregroundStyle(model.selectedTrack == index ? Color.white : Color(red: 0.45, green: 0.37, blue: 0.28))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                Button { model.apply("track", arguments: ["field": "add"]) } label: { Image(systemName: "plus.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(Color(red: 0.59, green: 0.42, blue: 0.10)).help("新增音轨")
                Spacer(minLength: 0)
                if model.isPlaying { Label("播放中", systemImage: "waveform").foregroundStyle(Color(red: 0.59, green: 0.42, blue: 0.10)) }
            }
            .font(.system(size: 10, weight: .medium))
            .padding(.horizontal, 7).padding(.vertical, 2)
        }
        .equatable()
    }

    private var notationStatus: some View {
        HStack {
            Label("音符边界由 AlphaTab BoundsLookup 命中", systemImage: "scope")
            Spacer()
            if model.isPlaying { Label("演奏中", systemImage: "waveform").foregroundStyle(.orange) }
            Text("小节 \(model.cursor.barIndex + 1) · 拍 \(model.cursor.beatIndex + 1) · \(model.cursor.stringIndex) 弦")
                .monospacedDigit().foregroundStyle(.secondary)
        }.font(.caption).padding(.horizontal, 14).padding(.vertical, 6)
            .background(Color(nsColor: .controlBackgroundColor))
    }

    private func inspector(_ project: StudioProject) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                if let track = model.currentTrack {
                    NativeStudioStableRegion(key: NativeStudioTrackInspectorState(projectID: project.id, track: track, trackCount: project.tracks.count)) {
                        inspectorSection("音轨与调弦") {
                            TextField("音轨名称", text: trackTextBinding(track.name, field: "name"))
                            HStack { Text("GM 音色"); Spacer(); Picker("", selection: trackIntBinding(track.program, field: "program")) {
                                ForEach(Array(gmPrograms.enumerated()), id: \.offset) { index, name in Text("\(index + 1). \(name)").tag(index) }
                            }.labelsHidden().frame(width: 180) }
                            Button { showGMInstrumentBrowser = true } label: { Label("搜索与试听全部 128 种 GM 音色", systemImage: "magnifyingglass") }
                                .buttonStyle(.bordered).controlSize(.small)
                            HStack { Text("变调夹"); Stepper("\(track.capo) 品", value: trackIntBinding(track.capo, field: "capo"), in: 0...24).frame(width: 140) }
                            HStack { Text("音量"); Slider(value: trackDoubleBinding(track.volume, field: "volume"), in: 0...1); Text("\(Int(track.volume * 100))%").monospacedDigit().frame(width: 40) }
                            HStack { Text("声像"); Slider(value: trackDoubleBinding(track.pan, field: "pan"), in: -1...1); Text(track.pan < -0.15 ? "左" : (track.pan > 0.15 ? "右" : "中")).frame(width: 40) }
                            HStack {
                                Toggle("静音", isOn: trackBoolBinding(track.mute, field: "mute"))
                                Toggle("独奏", isOn: trackBoolBinding(track.solo, field: "solo"))
                            }
                            TextField("调弦名称", text: trackTextBinding(track.tuningName, field: "tuningName"))
                            TextField("弦高到低 MIDI 音高，以逗号分隔", text: tuningBinding(track.tuning)).font(.caption.monospaced())
                            HStack {
                                Button("试听选中音符") { model.previewSelectedNote() }
                                Spacer()
                                Button("删除音轨", role: .destructive) { model.apply("track", arguments: ["field": "remove"]) }.disabled(project.tracks.count <= 1)
                            }
                        }
                    }
                    .equatable()
                }
                if let bar = model.currentBar {
                    NativeStudioStableRegion(key: NativeStudioBarInspectorState(projectID: project.id, bar: bar, selectedTrackID: model.currentTrack?.id ?? "")) {
                        inspectorSection("第 \(bar.index + 1) 小节") {
                            HStack { Text("拍号"); Stepper("\(bar.timeSignatureNumerator)/\(bar.timeSignatureDenominator)", value: barMetaIntBinding(bar.timeSignatureNumerator, field: "timeSignatureNumerator"), in: 1...32).frame(width: 180) }
                            HStack { Text("分母"); Stepper("\(bar.timeSignatureDenominator)", value: barMetaIntBinding(bar.timeSignatureDenominator, field: "timeSignatureDenominator"), in: 1...32).frame(width: 120) }
                            HStack { Text("局部速度"); Stepper(bar.tempo.map { "♩ \(Int($0))" } ?? "沿用前段", value: barTempoBinding(bar.tempo), in: 20...300).frame(width: 170) }
                            TextField("段落：前奏 / 主歌 / 副歌 / Solo…", text: barMetaTextBinding(bar.section ?? "", field: "section"))
                            HStack {
                                Toggle("反复开始", isOn: barMetaBoolBinding(bar.repeatStart == true, field: "repeatStart"))
                                Toggle("反复结束", isOn: barMetaBoolBinding(bar.repeatEnd == true, field: "repeatEnd"))
                            }
                            HStack { Text("反复次数"); Stepper("\(bar.repeatCount ?? 2)", value: barMetaIntBinding(bar.repeatCount ?? 2, field: "repeatCount"), in: 2...8) }
                            HStack { Text("Volta"); Stepper(bar.volta.map(String.init) ?? "无", value: barMetaIntBinding(bar.volta ?? 1, field: "volta"), in: 1...8) }
                            timingSummary(bar)
                        }
                    }
                    .equatable()
                }
                if let track = model.currentTrack {
                    NativeStudioStableRegion(key: NativeStudioLyricsInspectorState(projectID: project.id, trackID: track.id, lyrics: model.currentBeat?.lyrics)) {
                        inspectorSection("歌词工作流") {
                            Text("歌词草稿按工程、音轨和编辑 revision 保存；打开完整对齐面板可切轨、检查冲突、对齐或清空。")
                                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            Button { model.beginLyricsSession(); showLyricsDrawer = true } label: { Label("打开歌词吸附与对齐", systemImage: "text.alignleft") }
                            if let text = model.currentBeat?.lyrics, !text.isEmpty { Text("当前拍歌词：\(text)").font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                    .equatable()
                }
                if !model.conversionWarnings.isEmpty {
                    NativeStudioStableRegion(key: NativeStudioWarningsInspectorState(warnings: model.conversionWarnings)) {
                        inspectorSection("导入转换说明 · \(model.conversionWarnings.count)") {
                            ForEach(Array(model.conversionWarnings.enumerated()), id: \.offset) { index, warning in Text("\(index + 1). \(warning)").font(.caption).fixedSize(horizontal: false, vertical: true).padding(.vertical, 3) }
                            Text("原文件字节已单独保存；这些提醒描述编辑副本未建模的效果。")
                                .font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                        }
                    }
                    .equatable()
                }
                if let linkedID = model.linkedPracticeScoreID {
                    NativeStudioStableRegion(key: NativeStudioLinkedPracticeInspectorState(projectID: project.id, linkedID: linkedID)) {
                        inspectorSection("练习副本") {
                            Text("已链接到个人曲谱：\(linkedID)").font(.caption).textSelection(.enabled)
                            Button("打开练习页") { model.openPractice(linkedID) }
                            Button("用当前工程更新副本") { model.saveAsPracticeCopy() }
                        }
                    }
                    .equatable()
                }
            }
            .padding(12)
        }
        .background(MIMIPlatformColor.secondarySystemBackground)
    }

    private func studioFretboardSection(_ track: StudioTrack) -> some View {
        inspectorSection("24 品实时指板") {
#if MIMI_RUNTIME_DIAGNOSTICS
            if Self.runtimeStudioPruneTarget == "no-fretboard" {
                Color.clear
                    .frame(maxWidth: .infinity)
                    .frame(height: Self.diagnosticFretboardHeight)
                    .accessibilityHidden(true)
            } else {
                NativeStudioFretboard(
                    track: track,
                    notes: model.currentBeat?.notes ?? [],
                    capo: track.capo,
                    selectedString: model.cursor.stringIndex,
                    selectedFret: model.selectedFret
                ) { string, fret in model.enterFret(fret, string: string) }
                    .equatable()
                    .frame(minHeight: 152)
            }
#else
            NativeStudioFretboard(
                track: track,
                notes: model.currentBeat?.notes ?? [],
                capo: track.capo,
                selectedString: model.cursor.stringIndex,
                selectedFret: model.selectedFret
            ) { string, fret in model.enterFret(fret, string: string) }
                .equatable()
                .frame(minHeight: 152)
#endif
            Text("选择弦与品位会立即试听并写入当前拍；和弦模式保留同一拍，单音步进会移至下一拍。")
                .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }


    private func chordLibrarySection(_ track: StudioTrack, projectID: String) -> some View {
        NativeStudioStableRegion(key: NativeStudioChordLibraryState(projectID: projectID, track: track, root: chordRoot, search: chordSearch, input: chordInput)) {
            chordLibraryContent(track)
        }
        .equatable()
    }

    private func chordLibraryContent(_ track: StudioTrack) -> some View {
        let library = NativeStudioChordLibrary.chords(for: track)
        let query = chordSearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let visible = library.filter { chord in
            (chordRoot == "ALL" || chord.root == chordRoot) &&
            (query.isEmpty || chord.name.lowercased().contains(query) || chord.detail.lowercased().contains(query))
        }
        return inspectorSection("和弦库与指法试听 · \(library.count) 个") {
            if library.isEmpty {
                Text("贝斯以单音录入为主。请通过实时指板试听并输入当前弦品。")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            } else {
                HStack(spacing: 6) {
                    TextField("和弦名，如 C、Am7", text: $chordInput)
                        .frame(minWidth: 90)
                    Button("标注") { model.apply("chord", arguments: ["value": chordInput]) }
                        .disabled(chordInput.isEmpty)
                    TextField("搜索和弦", text: $chordSearch)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                        .frame(minWidth: 100)
                }
                NativeStudioFlowLayout(horizontalSpacing: 4, verticalSpacing: 4) {
                    ForEach(["ALL", "C", "D", "E", "F", "G", "A", "B"], id: \.self) { root in
                        let isSelected = chordRoot == root
                        Button { chordRoot = root } label: {
                            Text(root == "ALL" ? "全部" : root)
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(isSelected ? Color.white : Color(red: 0.42, green: 0.34, blue: 0.25))
                                .padding(.horizontal, 7).padding(.vertical, 4)
                                .background(
                                    isSelected ? Color(red: 0.18, green: 0.16, blue: 0.14) : Color(red: 0.94, green: 0.91, blue: 0.85),
                                    in: Capsule()
                                )
                                .overlay(Capsule().stroke(Color(red: 0.87, green: 0.83, blue: 0.76), lineWidth: isSelected ? 0 : 0.8))
                        }
                        .buttonStyle(.plain)
                        .fixedSize()
                    }
                    Text("常用").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    ForEach(["C", "Am", "F", "G", "Dm", "Em"], id: \.self) { name in
                        if let chord = library.first(where: { $0.name == name }) {
                            Button { selectChord(chord) } label: {
                                Text(name)
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(Color(red: 0.48, green: 0.34, blue: 0.12))
                                    .padding(.horizontal, 7).padding(.vertical, 4)
                                    .background(Color(red: 0.98, green: 0.96, blue: 0.91), in: Capsule())
                                    .overlay(Capsule().stroke(Color(red: 0.87, green: 0.83, blue: 0.76), lineWidth: 0.8))
                            }
                            .buttonStyle(.plain)
                            .fixedSize()
                        }
                    }
                }
                if visible.isEmpty {
                    Text("没有匹配的和弦")
                        .font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 84)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 112), spacing: 5)], spacing: 5) {
                        ForEach(visible) { chord in
                            Button { selectChord(chord) } label: {
                                HStack(spacing: 6) {
                                    NativeStudioChordDiagram(chord: chord)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(chord.name).font(.system(size: 12, weight: .bold, design: .serif)).foregroundStyle(Color(red: 0.59, green: 0.42, blue: 0.10))
                                        Text(chord.frets.map { $0 < 0 ? "x" : String($0) }.joined(separator: " "))
                                            .font(.system(size: 8, design: .monospaced)).foregroundStyle(.secondary)
                                        Text(chord.detail).font(.system(size: 8)).foregroundStyle(.secondary).lineLimit(2)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .padding(4)
                                .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
                                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 7))
                                .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color(red: 0.87, green: 0.83, blue: 0.76), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                            .help("试听并将 \(chord.name) 指法写入当前拍")
                        }
                    }
                }
                Text("点击和弦会试听真实扫弦、写入和弦名称并录入各弦品位。")
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }


    private func selectChord(_ chord: NativeStudioChord) {
        chordInput = chord.name
        model.apply("chord", arguments: ["value": chord.name])
        let stringCount = chord.frets.count
        let selected = chord.frets.enumerated().compactMap { index, fret -> (Int, Int)? in
            guard fret >= 0 else { return nil }
            return (stringCount - index, fret)
        }
        for (string, fret) in selected {
            model.apply("fret", arguments: ["stringIndex": string, "fret": fret])
        }
        model.previewChord(selected.map { ["string": $0.0, "fret": $0.1] })
    }

    private var gmInstrumentBrowser: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("GM 音色浏览器", systemImage: "slider.horizontal.3").font(.title2.weight(.semibold))
                Spacer()
                Button("完成") { showGMInstrumentBrowser = false }
            }
            Text("选择音色会更新当前音轨，并用当前拍和弦（没有音符时使用 C 和弦）做真实 SoundFont 扫弦试听。")
                .font(.callout).foregroundStyle(.secondary)
            HStack(spacing: 10) {
                TextField("搜索中文或 GM 音色名称", text: $gmSearch)
                Picker("类别", selection: $gmFamily) {
                    Text("全部音色").tag("全部音色")
                    ForEach(gmFamilies.map { $0.name }, id: \.self) { Text($0).tag($0) }
                }.frame(width: 190)
            }
            List(filteredGMRows) { row in
                Button { chooseGMInstrument(row.program) } label: {
                    HStack(spacing: 10) {
                        Text(String(format: "%03d", row.program + 1)).font(.system(.body, design: .monospaced)).foregroundStyle(.secondary).frame(width: 46, alignment: .trailing)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.name).font(.system(size: 13, weight: .medium))
                            Text("\(row.family) · GM \(row.program + 1)").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if model.currentTrack?.program == row.program { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
                        Image(systemName: "waveform").foregroundStyle(Color(red: 0.59, green: 0.42, blue: 0.10))
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
            .listStyle(.inset)
            HStack {
                Text("128 个 GM 程序 · 按音色族分类").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("试听当前拍和弦") {
                    let program = model.currentTrack?.program ?? 24
                    previewGMChord(program: program)
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.currentTrack == nil)
            }
        }
        .padding(20)
    }

    private var filteredGMRows: [NativeGMProgramRow] {
        let query = gmSearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return gmPrograms.enumerated().compactMap { index, name in
            let family = gmFamilies.first(where: { $0.programs.contains(index) })?.name ?? "其他"
            guard gmFamily == "全部音色" || gmFamily == family else { return nil }
            guard query.isEmpty || name.lowercased().contains(query) || "gm \(index + 1)".contains(query) || family.lowercased().contains(query) else { return nil }
            return NativeGMProgramRow(program: index, name: name, family: family)
        }
    }


    private func chooseGMInstrument(_ program: Int) {
        model.apply("track", arguments: ["field": "program", "value": program])
        previewGMChord(program: program)
        showGMInstrumentBrowser = false
    }

    private func previewGMChord(program: Int) {
        if let notes = model.currentBeat?.notes, !notes.isEmpty {
            model.previewChord(notes.map { ["string": $0.string, "fret": $0.fret] }, program: program)
            return
        }
        let library = NativeStudioChordLibrary.chords(for: model.currentTrack)
        let chord = library.first(where: { $0.name == chordInput }) ?? library.first(where: { $0.name == "C" })
        guard let chord else { return }
        let selected = chord.frets.enumerated().compactMap { index, fret -> (Int, Int)? in
            guard fret >= 0 else { return nil }
            return (chord.frets.count - index, fret)
        }
        model.previewChord(selected.map { ["string": $0.0, "fret": $0.1] }, program: program)
    }

    private var lyricsDrawer: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("歌词智能吸附与对齐", systemImage: "text.alignleft").font(.title2.weight(.semibold))
                Spacer()
                Button("完成") { showLyricsDrawer = false }
            }
            Text("粘贴整首歌词，按中文单字和英文单词切分，并依次吸附到目标音轨的非休止发声音符。")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let project = model.project {
                HStack {
                    Text("歌词目标音轨")
                    Picker("歌词目标音轨", selection: Binding(
                        get: { project.tracks.firstIndex(where: { $0.id == model.lyricTargetTrackID }) ?? model.selectedTrack },
                        set: { model.switchLyricsTarget(to: $0) }
                    )) {
                        ForEach(Array(project.tracks.enumerated()), id: \.element.id) { index, track in
                            Text(track.name).tag(index)
                        }
                    }
                    .labelsHidden().frame(width: 240)
                    Spacer()
                    Button("保存草稿") { model.persistCurrentLyricsDraft() }
                }
                HStack(spacing: 8) {
                    Label("\(model.lyricWordCount) 个字词", systemImage: "text.word.spacing")
                    Text("可用音符拍位 \(model.lyricAvailablePositions)")
                    Text("已写入 \(model.lyricExistingCount) 处")
                    Spacer()
                    if model.lyricsTargetMatchesCurrentProject, let trackID = model.lyricTargetTrackID,
                       let track = project.tracks.first(where: { $0.id == trackID }) {
                        Text("\(project.title) · \(track.name)").lineLimit(1).foregroundStyle(.secondary)
                    } else { Text("草稿绑定到原工程；切换到当前工程后再应用").foregroundStyle(.orange) }
                }.font(.caption)
                if !model.lyricsTargetMatchesRevision {
                    Label("工程内容已变化；草稿仍保留。请重载目标歌词后再应用。", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
            TextEditor(text: Binding(
                get: { model.lyricDraft },
                set: { value in Task { @MainActor in model.updateLyricsDraft(value) } }
            ))
                .font(.system(size: 14, design: .serif))
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color(nsColor: .separatorColor), lineWidth: 1))
            HStack {
                Button("重载当前工程歌词") { model.discardCurrentLyricsDraftAndReload() }
                Button("丢弃未应用草稿…", role: .destructive) { showDiscardLyricsAlert = true }
                Spacer()
                Button("清空已写入歌词…", role: .destructive) { model.showingClearLyricsAlert = true }
                    .disabled(model.lyricExistingCount == 0 || !model.lyricsTargetMatchesCurrentProject || !model.lyricsTargetMatchesRevision)
                Button("智能对齐") { model.alignLyrics() }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.lyricWordCount == 0 || model.lyricWordCount > model.lyricAvailablePositions || !model.lyricsTargetMatchesCurrentProject || !model.lyricsTargetMatchesRevision)
            }
            Text(model.status).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
        }
        .padding(22)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func inspectorSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 12, weight: .semibold))
            content()
        }
        .font(.system(size: 11))
        .padding(10)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func timingSummary(_ bar: StudioBar) -> some View {
        let beats = bar.trackBeats[model.currentTrack?.id ?? ""] ?? []
        let total = beats.reduce(0.0) { partial, beat in
            var duration = 4.0 / Double(max(1, beat.duration))
            if beat.dot { duration *= 1.5 }
            if beat.triplet { duration *= 2.0 / 3.0 }
            return partial + duration
        }
        let expected = Double(bar.timeSignatureNumerator) * 4.0 / Double(max(1, bar.timeSignatureDenominator))
        let delta = total - expected
        return HStack {
            Image(systemName: abs(delta) < 0.001 ? "checkmark.circle.fill" : (delta > 0 ? "exclamationmark.triangle.fill" : "circle.dashed"))
            Text(abs(delta) < 0.001 ? "小节时值完整" : (delta > 0 ? "超出 \(String(format: "%.2f", delta)) 拍" : "还差 \(String(format: "%.2f", abs(delta))) 拍"))
            Spacer()
            Text("\(beats.count) 拍").monospacedDigit()
        }.foregroundStyle(abs(delta) < 0.001 ? .green : .orange).font(.caption)
    }

    private var editTools: some View {
        let beat = model.currentBeat
        return NativeStudioEditTools(
            model: model,
            rhythm: NativeStudioRhythmToolState(
                duration: beat?.duration,
                dot: beat?.dot == true,
                triplet: beat?.triplet == true,
                rest: beat?.isRest == true,
                chordMode: model.chordMode
            ),
            pitch: NativeStudioPitchToolState(
                stringIndex: model.cursor.stringIndex,
                stringCount: max(1, model.currentTrack?.tuning.count ?? 6),
                fret: model.selectedFret
            ),
            techniques: NativeStudioTechniqueToolState(active: model.activeTechniques),
            brush: NativeStudioBrushToolState(
                direction: beat?.brush,
                canEdit: beat.map { !$0.isRest && !$0.notes.isEmpty } ?? false
            ),
            onShowBarSettings: { showBarSettings = true },
            selectedCategory: $selectedRibbonCategory
        )
    }

    private var emptyStudioState: some View {
        VStack(spacing: 14) {
            Image(systemName: "music.note.list").font(.system(size: 38)).foregroundStyle(.secondary)
            Text("MIMI Guitar Studio").font(.title2.weight(.semibold))
            Text("选择乐器模板开始编曲，或导入原谱创建可编辑副本。音轨、歌词、原件与草稿分别保存。")
                .multilineTextAlignment(.center).foregroundStyle(.secondary).frame(maxWidth: 500)
            HStack {
                Button("原声吉他") { model.createProject(instrument: "guitar") }
                Button("尤克里里") { model.createProject(instrument: "ukulele") }
                Button("贝斯") { model.createProject(instrument: "bass") }
                Button("乐队") { model.createProject(instrument: "band") }
                Button("导入乐谱…") { model.importFromPanel() }
            }.buttonStyle(.borderedProminent)
            if let error = model.engineError { Text(error).foregroundStyle(.red).textSelection(.enabled) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).padding(32)
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            if model.isBusy { ProgressView().controlSize(.small) }
            Text(model.status).lineLimit(1).textSelection(.enabled)
            Spacer()
            if model.isDirty { Label("有未保存更改", systemImage: "doc.text").foregroundStyle(.orange) }
            if let error = model.engineError { Text(error).foregroundStyle(.red).lineLimit(1) }
        }.font(.caption).padding(.horizontal, 12).padding(.vertical, 6)
    }

    private var guideSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { Text("工坊使用指南").font(.title2.bold()); Spacer(); Button("完成") { showGuide = false } }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    guideStep("1 · 选择工程模板", "吉他、尤克里里、贝斯和乐队模板均预置调弦、音色与四个 4/4 小节。也可打开曲库曲目“改编到工坊”或导入 IBE、Guitar Pro 3–8、GPX、MusicXML、AlphaTex 与工坊/AlphaTab JSON。")
                    guideStep("2 · 在谱面上定位", "点按 AlphaTab 五线谱或 TAB 小节，编辑器使用 AlphaTab BoundsLookup 命中拍位与音符边界；顶部音轨标签切换当前轨。键盘 Tab 仅移动焦点，不会改谱。")
                    guideStep("3 · 编写音符和节奏", "输入 0–9 可继续组成 10–24 品，0 表示空弦；上下键换弦，左右键移动拍位，Alt+1…6 选择音符时值。附点、三连音、休止符和奏法按钮会写入结构化工程。")
                    guideStep("4 · 音轨、歌词与段落", "每轨可配置 GM 音色、调弦、变调夹、音量、声像、静音和独奏。小节支持拍号、局部速度、段落、反复与 Volta。和弦名/歌词按拍位记录，歌词工具按中文单字与英文词对齐到发声音符。")
                    guideStep("5 · 保存和导出", "草稿自动留在本地；保存会比较数据库 revision 与工程更新时间，冲突时草稿保留，重新载入最新版本后可手动合并。可导出 JSON、AlphaTex、MIMI IBE、GP7/8、PDF、PNG 或打印。")
                    guideStep("转换保留", "导入时原文件字节进入个人原件库。可编辑副本只映射当前模型支持的音符、奏法和单主声部；下方转换说明会列出被省略/近似处理的效果。导出 GP 文件内容由 AlphaTab GP7 序列化器生成。")
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }.padding(24)
    }

    private func guideStep(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 5) { Text(title).font(.headline); Text(detail).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
    }

    private var shortcutSheet: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { Text("工坊快捷键").font(.title2.bold()); Spacer(); Button("完成") { showShortcuts = false } }
            HStack { TextField("搜索操作、功能或快捷键", text: $model.shortcutQuery); Picker("分类", selection: $model.shortcutCategory) {
                Text("全部").tag("all"); Text("编辑").tag("edit"); Text("节奏").tag("rhythm"); Text("技法").tag("technique"); Text("播放").tag("playback"); Text("工程与草稿").tag("project")
            }.frame(width: 145) }
            Table(filteredShortcuts) {
                TableColumn("按键") { Text($0.key).font(.system(.body, design: .monospaced)) }.width(min: 110, ideal: 150)
                TableColumn("操作说明") { Text($0.desc).fixedSize(horizontal: false, vertical: true) }
            }
        }.padding(20)
    }

    private var filteredShortcuts: [NativeStudioShortcutInfo] {
        model.shortcutResults
    }

    private func binding(_ value: String, values: @escaping (String) -> [String: Any]) -> Binding<String> {
        Binding(get: { model.project.map { _ in value } ?? value }, set: { model.apply("metadata", arguments: ["values": values($0)]) })
    }

    private func integerBinding(_ value: Int, values: @escaping (Int) -> [String: Any]) -> Binding<Int> {
        Binding(get: { value }, set: { model.apply("metadata", arguments: ["values": values($0)]) })
    }

    private func trackTextBinding(_ value: String, field: String) -> Binding<String> { Binding(get: { value }, set: { model.apply("track", arguments: ["field": field, "value": $0]) }) }
    private func trackIntBinding(_ value: Int, field: String) -> Binding<Int> { Binding(get: { value }, set: { model.apply("track", arguments: ["field": field, "value": $0]) }) }
    private func trackDoubleBinding(_ value: Double, field: String) -> Binding<Double> { Binding(get: { value }, set: { model.apply("track", arguments: ["field": field, "value": $0]) }) }
    private func trackBoolBinding(_ value: Bool, field: String) -> Binding<Bool> { Binding(get: { value }, set: { model.apply("track", arguments: ["field": field, "value": $0]) }) }
    private func tuningBinding(_ value: [Int]) -> Binding<String> { Binding(get: { value.map(String.init).joined(separator: ", ") }, set: { model.apply("track", arguments: ["field": "tuning", "value": $0]) }) }
    private func barMetaIntBinding(_ value: Int, field: String) -> Binding<Int> { Binding(get: { value }, set: { model.apply("barMeta", arguments: ["field": field, "value": $0]) }) }
    private func barMetaTextBinding(_ value: String, field: String) -> Binding<String> { Binding(get: { value }, set: { model.apply("barMeta", arguments: ["field": field, "value": $0.isEmpty ? NSNull() : $0]) }) }
    private func barMetaBoolBinding(_ value: Bool, field: String) -> Binding<Bool> { Binding(get: { value }, set: { model.apply("barMeta", arguments: ["field": field, "value": $0]) }) }
    private func barTempoBinding(_ value: Double?) -> Binding<Int> { Binding(get: { Int(value ?? Double(model.project?.initialTempo ?? 120)) }, set: { model.apply("barMeta", arguments: ["field": "tempo", "value": $0]) }) }

    private let chordPalette = ["C", "Cm", "C7", "Cmaj7", "D", "Dm", "D7", "Em", "E7", "F", "Fm", "G", "G7", "Am", "A7", "B7", "G/B"]
    private let gmFamilies: [(name: String, programs: ClosedRange<Int>)] = [
        ("钢琴与键盘", 0...7), ("色彩打击乐", 8...15), ("风琴与键盘", 16...23),
        ("吉他族", 24...31), ("贝斯族", 32...39), ("弦乐", 40...47),
        ("合奏与合唱", 48...55), ("铜管", 56...63), ("萨克斯", 64...71),
        ("木管", 72...79), ("合成主音", 80...87), ("合成铺底", 88...95),
        ("合成效果", 96...103), ("民族乐器", 104...111), ("打击乐", 112...119), ("音效", 120...127),
    ]
    private let gmPrograms = [
        "大钢琴", "明亮钢琴", "电钢琴 1", "电钢琴 2", "酒吧钢琴", "电钢琴 3", "羽管键琴", "击弦古钢琴", "钢片琴", "钟琴", "音乐盒", "颤音琴", "马林巴", "木琴", "管钟", "扬琴", "风琴音栓", "打击管风琴", "摇滚风琴", "教堂管风琴", "簧风琴", "手风琴", "口琴", "探戈手风琴", "尼龙弦吉他", "钢弦吉他", "爵士电吉他", "清音电吉他", "闷音电吉他", "过载吉他", "失真吉他", "吉他泛音", "原声贝斯", "指弹电贝斯", "拨片电贝斯", "无品贝斯", "击弦贝斯 1", "击弦贝斯 2", "合成贝斯 1", "合成贝斯 2", "小提琴", "中提琴", "大提琴", "低音提琴", "弦乐震音", "弦乐拨奏", "竖琴", "定音鼓", "弦乐合奏 1", "弦乐合奏 2", "合成弦乐 1", "合成弦乐 2", "合唱啊音", "人声合唱", "合成人声", "管弦乐敲击", "小号", "长号", "大号", "弱音小号", "法国号", "铜管组", "合成铜管 1", "合成铜管 2", "高音萨克斯", "中音萨克斯", "次中音萨克斯", "上低音萨克斯", "双簧管", "英国管", "巴松管", "单簧管", "短笛", "长笛", "竖笛", "排箫", "瓶笛", "尺八", "哨笛", "陶笛", "方波主音", "锯齿主音", "汽笛主音", "合奏主音", "5度主音", "贝斯主音", "新世纪铺底", "温暖铺底", "多变铺底", "合唱铺底", "弓弦铺底", "金属铺底", "光环铺底", "扫频铺底", "雨声效果", "音轨效果", "水晶效果", "氛围效果", "明亮效果", "妖精效果", "回声效果", "科幻效果", "雨滴", "音轨声", "水晶音", "大气音", "明亮音", "小妖精", "回声", "科幻", "西塔琴", "班卓琴", "三昧线", "古筝", "卡林巴", "风笛", "提琴", "山达琴", "铜铃", "阿哥哥", "钢鼓", "木块", "太鼓", "旋律通鼓", "合成鼓", "反向铙钹"
    ]
}

private struct NativeStudioRhythmToolState: Equatable {
    let duration: Int?
    let dot: Bool
    let triplet: Bool
    let rest: Bool
    let chordMode: Bool
}

private struct NativeStudioPitchToolState: Equatable {
    let stringIndex: Int
    let stringCount: Int
    let fret: Int
}

private struct NativeStudioTechniqueToolState: Equatable {
    let active: Set<String>
}

private struct NativeStudioBrushToolState: Equatable {
    let direction: String?
    let canEdit: Bool
}

private struct NativeStudioToolButtonStyle: ButtonStyle {
    let tone: Color
    var isActive = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        NativeStudioToolButtonFace(
            label: configuration.label,
            tone: tone,
            isActive: isActive,
            isEnabled: isEnabled,
            isPressed: configuration.isPressed
        )
    }
}

private struct NativeStudioToolButtonFace<Label: View>: View {
    let label: Label
    let tone: Color
    let isActive: Bool
    let isEnabled: Bool
    let isPressed: Bool

    @Environment(\.isFocused) private var isFocused
    @State private var isHovered = false

    var body: some View {
        label
            .font(.system(size: 12))
            .foregroundStyle(isActive ? Color(red: 0.99, green: 0.98, blue: 0.95) : tone)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                RoundedRectangle(cornerRadius: 5)
                    .fill(isActive ? Color(red: 0.17, green: 0.15, blue: 0.13) : (isPressed ? tone.opacity(0.14) : (isHovered ? tone.opacity(0.08) : .clear)))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 5).stroke(
                    isFocused ? Color(red: 0.59, green: 0.42, blue: 0.10) : (isActive ? Color(red: 0.17, green: 0.15, blue: 0.13) : Color(red: 0.87, green: 0.83, blue: 0.76)),
                    lineWidth: isFocused ? 2 : 0.75
                )
            }
            .opacity(isEnabled ? 1 : 0.45)
            .contentShape(RoundedRectangle(cornerRadius: 5))
            .onHover { isHovered = $0 }
    }
}

private struct NativeStudioHeaderButtonStyle: ButtonStyle {
    var prominent = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(prominent ? Color(red: 0.99, green: 0.98, blue: 0.95) : Color(red: 0.42, green: 0.34, blue: 0.25))
            .padding(.horizontal, 11)
            .frame(minHeight: 31)
            .background {
                Capsule(style: .continuous).fill(prominent
                    ? Color(red: 0.17, green: 0.15, blue: 0.13)
                    : (configuration.isPressed ? Color(red: 0.89, green: 0.84, blue: 0.74) : Color(red: 0.94, green: 0.91, blue: 0.85)))
            }
            .overlay(Capsule(style: .continuous).stroke(Color(red: 0.87, green: 0.83, blue: 0.76), lineWidth: prominent ? 0 : 0.8))
            .opacity(isEnabled ? 1 : 0.46)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

enum StudioRibbonCategory: String, CaseIterable, Identifiable {
    case notes = "rhythm"
    case techniques = "techniques"
    case arranging = "arranging"
    case measures = "measures"
    case pitch = "pitch"
    case all = "all"

    var id: String { rawValue }
    var title: String {
        switch self {
        case .notes: return "时值与音符"
        case .techniques: return "吉他技法"
        case .arranging: return "和弦编配"
        case .measures: return "小节曲式"
        case .pitch: return "触控选品录入"
        case .all: return "全部平铺"
        }
    }

    var symbol: String {
        switch self {
        case .notes: return "music.note"
        case .techniques: return "guitars"
        case .arranging: return "wand.and.stars"
        case .measures: return "square.split.3x1"
        case .pitch: return "hand.tap"
        case .all: return "square.grid.2x2"
        }
    }

}

fileprivate func durationGlyph(_ value: Int) -> String {
    switch value {
    case 1: return "\u{1D15D}"
    case 2: return "\u{1D15E}"
    case 4: return "\u{1D15F}"
    case 8: return "\u{1D160}"
    case 16: return "\u{1D161}"
    default: return "\u{1D162}"
    }
}

fileprivate func durationTitle(_ value: Int) -> String {
    switch value {
    case 1: return "全音"
    case 2: return "二分"
    case 4: return "四分"
    case 8: return "八分"
    case 16: return "十六分"
    default: return "三十二分"
    }
}

@MainActor
private struct NativeStudioEditTools: View {
    let model: NativeStudioModel
    let rhythm: NativeStudioRhythmToolState
    let pitch: NativeStudioPitchToolState
    let techniques: NativeStudioTechniqueToolState
    let brush: NativeStudioBrushToolState
    let onShowBarSettings: () -> Void
    @Binding var selectedCategory: StudioRibbonCategory
    @State private var selectedChordName = "C"
    @State private var selectedPattern = StudioAccompanimentPattern.allPatterns[0]

    var body: some View {
        VStack(spacing: 5) {
            // Category switcher
            HStack(spacing: 6) {
                HStack(spacing: 2) {
                    ForEach(StudioRibbonCategory.allCases) { cat in
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                selectedCategory = cat
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: cat.symbol)
                                    .font(.system(size: 10))
                                Text(cat.title)
                                    .font(.system(size: 11, weight: selectedCategory == cat ? .bold : .medium))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                selectedCategory == cat
                                    ? Color(red: 0.17, green: 0.15, blue: 0.13)
                                    : Color.clear,
                                in: Capsule()
                            )
                            .foregroundStyle(
                                selectedCategory == cat
                                    ? Color.white
                                    : Color(red: 0.45, green: 0.37, blue: 0.28)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(3)
                .background(Color(red: 0.93, green: 0.90, blue: 0.84), in: Capsule())

                Spacer(minLength: 4)

                // Quick cursor status info
                HStack(spacing: 6) {
                    Text("当前光标: \(pitch.stringIndex) 弦 · \(pitch.fret) 品")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color(red: 0.55, green: 0.39, blue: 0.12))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(red: 0.55, green: 0.39, blue: 0.12).opacity(0.12), in: Capsule())
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 6)

            // Content Area for current segment
            VStack(spacing: 0) {
                switch selectedCategory {
                case .notes:
                    ScrollView(.horizontal, showsIndicators: false) {
                        notesBar
                            .padding(.horizontal, 14)
                            .padding(.vertical, 4)
                    }
                case .techniques:
                    ScrollView(.horizontal, showsIndicators: false) {
                        techniquesBar
                            .padding(.horizontal, 14)
                            .padding(.vertical, 4)
                    }
                case .arranging:
                    ScrollView(.horizontal, showsIndicators: false) {
                        arrangingBar
                            .padding(.horizontal, 14)
                            .padding(.vertical, 4)
                    }
                case .measures:
                    ScrollView(.horizontal, showsIndicators: false) {
                        measuresBar
                            .padding(.horizontal, 14)
                            .padding(.vertical, 4)
                    }
                case .pitch:
                    ScrollView(.horizontal, showsIndicators: false) {
                        pitchBar
                            .padding(.horizontal, 14)
                            .padding(.vertical, 4)
                    }
                case .all:
                    allBar
                        .padding(.horizontal, 14)
                        .padding(.vertical, 4)
                }
            }
            .frame(minHeight: 44)
        }
        .padding(.vertical, 3)
        .background(Color(red: 0.965, green: 0.941, blue: 0.902))
        .overlay(alignment: .top) { Rectangle().fill(Color(red: 0.89, green: 0.85, blue: 0.78)).frame(height: 1) }
        .overlay(alignment: .bottom) { Rectangle().fill(Color(red: 0.89, green: 0.85, blue: 0.78)).frame(height: 1) }
    }

    private var notesBar: some View {
        HStack(spacing: 8) {
            // Note durations
            HStack(spacing: 4) {
                ForEach([1, 2, 4, 8, 16, 32] as [Int], id: \.self) { (value: Int) in
                    let isActive = rhythm.duration == Optional(value)
                    Button {
                        model.apply("duration", arguments: ["duration": value])
                    } label: {
                        HStack(spacing: 4) {
                            Text(durationGlyph(value))
                                .font(.custom(MIMIFontRegistry.musicSymbolFontName, size: 16, relativeTo: .body))
                            Text(durationTitle(value))
                                .font(.system(size: 11, weight: isActive ? .bold : .medium))
                        }
                        .padding(.horizontal, 8)
                        .frame(minWidth: value >= 16 ? 68 : 60)
                        .frame(height: 36)
                        .background(
                            isActive
                                ? Color(red: 0.17, green: 0.15, blue: 0.13)
                                : Color(red: 0.93, green: 0.90, blue: 0.84),
                            in: RoundedRectangle(cornerRadius: 8)
                        )
                        .foregroundStyle(isActive ? Color.white : Color(red: 0.28, green: 0.24, blue: 0.20))
                    }
                    .buttonStyle(.plain)
                    .help("时值 \(durationTitle(value))")
                }
            }

            Divider().frame(height: 22)

            // Modifiers & rest
            HStack(spacing: 4) {
                Button { model.apply("dot") } label: {
                    Text("• 附点")
                        .font(.system(size: 11, weight: rhythm.dot ? .bold : .medium))
                        .padding(.horizontal, 8)
                        .frame(height: 36)
                        .background(rhythm.dot ? Color(red: 0.55, green: 0.39, blue: 0.12) : Color(red: 0.93, green: 0.90, blue: 0.84), in: RoundedRectangle(cornerRadius: 8))
                        .foregroundStyle(rhythm.dot ? Color.white : Color(red: 0.28, green: 0.24, blue: 0.20))
                }
                .buttonStyle(.plain)

                Button { model.apply("triplet") } label: {
                    Text("3 三连音")
                        .font(.system(size: 11, weight: rhythm.triplet ? .bold : .medium))
                        .padding(.horizontal, 8)
                        .frame(height: 36)
                        .background(rhythm.triplet ? Color(red: 0.55, green: 0.39, blue: 0.12) : Color(red: 0.93, green: 0.90, blue: 0.84), in: RoundedRectangle(cornerRadius: 8))
                        .foregroundStyle(rhythm.triplet ? Color.white : Color(red: 0.28, green: 0.24, blue: 0.20))
                }
                .buttonStyle(.plain)

                Button { model.apply("rest") } label: {
                    Text("𝄽 休止")
                        .font(.system(size: 11, weight: rhythm.rest ? .bold : .medium))
                        .padding(.horizontal, 8)
                        .frame(height: 36)
                        .background(rhythm.rest ? Color(red: 0.70, green: 0.27, blue: 0.19) : Color(red: 0.93, green: 0.90, blue: 0.84), in: RoundedRectangle(cornerRadius: 8))
                        .foregroundStyle(rhythm.rest ? Color.white : Color(red: 0.28, green: 0.24, blue: 0.20))
                }
                .buttonStyle(.plain)
            }

            Divider().frame(height: 22)

            // Beat timing actions
            HStack(spacing: 4) {
                Button { model.apply("insertBeat") } label: {
                    Label("插拍", systemImage: "plus")
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 8)
                        .frame(height: 36)
                        .background(Color(red: 0.93, green: 0.90, blue: 0.84), in: RoundedRectangle(cornerRadius: 8))
                        .foregroundStyle(Color(red: 0.28, green: 0.24, blue: 0.20))
                }
                .buttonStyle(.plain)
                .help("在当前拍后插入一个空白拍")

                Button { model.apply("deleteBeat") } label: {
                    Label("删拍", systemImage: "minus")
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 8)
                        .frame(height: 36)
                        .background(Color(red: 0.93, green: 0.90, blue: 0.84), in: RoundedRectangle(cornerRadius: 8))
                        .foregroundStyle(Color(red: 0.70, green: 0.27, blue: 0.19))
                }
                .buttonStyle(.plain)
                .help("删除当前拍")

                Button { model.chordMode.toggle() } label: {
                    Label(rhythm.chordMode ? "和弦模式" : "单步进", systemImage: rhythm.chordMode ? "pianokeys" : "music.note")
                        .font(.system(size: 11, weight: rhythm.chordMode ? .bold : .medium))
                        .padding(.horizontal, 9)
                        .frame(height: 36)
                        .background(rhythm.chordMode ? Color(red: 0.55, green: 0.39, blue: 0.12) : Color(red: 0.93, green: 0.90, blue: 0.84), in: RoundedRectangle(cornerRadius: 8))
                        .foregroundStyle(rhythm.chordMode ? Color.white : Color(red: 0.28, green: 0.24, blue: 0.20))
                }
                .buttonStyle(.plain)
                .help("和弦模式：同一拍录入多弦；单步进：输入后光标自动后移")
            }
        }
    }


    private var techniquesBar: some View {
        HStack(spacing: 12) {
            // Articulations
            HStack(spacing: 4) {
                techniqueButton("延音", key: "tie", symbol: "~")
                techniqueButton("击勾", key: "hammerPull", symbol: "H/P")
                techniqueButton("滑音", key: "slide", symbol: "sl.")
                techniqueButton("推弦", key: "bend", symbol: "↗")
                techniqueButton("颤音", key: "vibrato", symbol: "≈")
            }

            Divider().frame(height: 22)

            // Timbre
            HStack(spacing: 4) {
                techniqueButton("泛音", key: "harmonic", symbol: "◇")
                techniqueButton("闷音", key: "palmMute", symbol: "P.M.")
                techniqueButton("死音", key: "dead", symbol: "×")
            }

            Divider().frame(height: 22)

            // Brush
            HStack(spacing: 4) {
                brushButton("↑ 上扫", direction: "up")
                brushButton("↓ 下扫", direction: "down")
                Button("清除") { model.apply("brush", arguments: ["direction": "clear"]) }
                    .font(.system(size: 11))
                    .padding(.horizontal, 8)
                    .frame(height: 36)
                    .background(Color(red: 0.93, green: 0.90, blue: 0.84), in: RoundedRectangle(cornerRadius: 8))
                    .foregroundStyle(Color.secondary)
                    .buttonStyle(.plain)
                    .disabled(brush.direction == nil)
            }
        }
    }


    private func techniqueButton(_ title: String, key: String, symbol: String) -> some View {
        let isActive = techniques.active.contains(key)
        return Button {
            model.apply("technique", arguments: ["technique": key])
        } label: {
            HStack(spacing: 3) {
                Text(symbol).font(.system(size: 11, weight: .bold, design: .monospaced))
                Text(title).font(.system(size: 11, weight: isActive ? .bold : .medium))
            }
            .padding(.horizontal, 9)
            .frame(height: 36)
            .background(
                isActive
                    ? Color(red: 0.17, green: 0.15, blue: 0.13)
                    : Color(red: 0.93, green: 0.90, blue: 0.84),
                in: RoundedRectangle(cornerRadius: 8)
            )
            .foregroundStyle(isActive ? Color.white : Color(red: 0.28, green: 0.24, blue: 0.20))
        }
        .buttonStyle(.plain)
        .help("\(title) (\(key))")
    }

    private func brushButton(_ title: String, direction: String) -> some View {
        let isActive = brush.direction == direction
        return Button {
            model.apply("brush", arguments: ["direction": direction])
        } label: {
            Text(title)
                .font(.system(size: 11, weight: isActive ? .bold : .medium))
                .padding(.horizontal, 9)
                .frame(height: 36)
                .background(
                    isActive
                        ? Color(red: 0.55, green: 0.39, blue: 0.12)
                        : Color(red: 0.93, green: 0.90, blue: 0.84),
                    in: RoundedRectangle(cornerRadius: 8)
                )
                .foregroundStyle(isActive ? Color.white : Color(red: 0.28, green: 0.24, blue: 0.20))
        }
        .buttonStyle(.plain)
        .disabled(!brush.canEdit)
        .help("扫弦 \(title)")
    }

    private var measuresBar: some View {
        HStack(spacing: 8) {
            Button { model.insertBarAtCursorAndAdvance() } label: {
                Label("加小节", systemImage: "plus")
                    .font(.system(size: 11, weight: .bold))
                    .padding(.horizontal, 12)
                    .frame(height: 36)
                    .background(Color(red: 0.55, green: 0.39, blue: 0.12), in: RoundedRectangle(cornerRadius: 8))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .help("在当前位置插入一个小节并光标后移")

            Button { model.apply("duplicateBar") } label: {
                Label("复制小节", systemImage: "plus.square.on.square")
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 11)
                    .frame(height: 36)
                    .background(Color(red: 0.93, green: 0.90, blue: 0.84), in: RoundedRectangle(cornerRadius: 8))
                    .foregroundStyle(Color(red: 0.28, green: 0.24, blue: 0.20))
            }
            .buttonStyle(.plain)
            .help("复制当前小节并追加")

            Button { model.apply("deleteBar") } label: {
                Label("删小节", systemImage: "trash")
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 11)
                    .frame(height: 36)
                    .background(Color(red: 0.93, green: 0.90, blue: 0.84), in: RoundedRectangle(cornerRadius: 8))
                    .foregroundStyle(Color(red: 0.70, green: 0.27, blue: 0.19))
            }
            .buttonStyle(.plain)
            .help("删除当前小节")

            Divider().frame(height: 22)

            Button { onShowBarSettings() } label: {
                Label("小节属性…", systemImage: "slider.horizontal.3")
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 12)
                    .frame(height: 36)
                    .background(Color(red: 0.93, green: 0.90, blue: 0.84), in: RoundedRectangle(cornerRadius: 8))
                    .foregroundStyle(Color(red: 0.28, green: 0.24, blue: 0.20))
            }
            .buttonStyle(.plain)
            .help("设定当前小节调号、变节拍、反复记号与跳房子")
        }
    }


    private var pitchBar: some View {
        HStack(spacing: 10) {
            // String selector
            HStack(spacing: 3) {
                Text("琴弦").font(.system(size: 10, weight: .bold)).foregroundStyle(Color(red: 0.55, green: 0.45, blue: 0.35))
                ForEach(1...pitch.stringCount, id: \.self) { str in
                    let isCur = pitch.stringIndex == str
                    Button {
                        model.setCursor(string: str)
                    } label: {
                        Text("\(str)弦")
                            .font(.system(size: 11, weight: isCur ? .bold : .medium))
                            .padding(.horizontal, 7)
                            .frame(height: 36)
                            .background(
                                isCur
                                    ? Color(red: 0.17, green: 0.15, blue: 0.13)
                                    : Color(red: 0.93, green: 0.90, blue: 0.84),
                                in: RoundedRectangle(cornerRadius: 8)
                            )
                            .foregroundStyle(isCur ? Color.white : Color(red: 0.28, green: 0.24, blue: 0.20))
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider().frame(height: 22)

            // Quick fret buttons
            HStack(spacing: 3) {
                Text("常用品位").font(.system(size: 10, weight: .bold)).foregroundStyle(Color(red: 0.55, green: 0.45, blue: 0.35))
                ForEach([0, 1, 2, 3, 5, 7, 9, 12] as [Int], id: \.self) { (fr: Int) in
                    let isSel = pitch.fret == fr
                    Button {
                        model.selectedFret = fr
                        model.enterFret(fr, string: pitch.stringIndex)
                    } label: {
                        Text(fr == 0 ? "空弦" : "\(fr)")
                            .font(.system(size: 11, weight: isSel ? .bold : .medium, design: .monospaced))
                            .padding(.horizontal, 7)
                            .frame(minWidth: 32)
                            .frame(height: 36)
                            .background(
                                isSel
                                    ? Color(red: 0.55, green: 0.39, blue: 0.12)
                                    : Color(red: 0.93, green: 0.90, blue: 0.84),
                                in: RoundedRectangle(cornerRadius: 8)
                            )
                            .foregroundStyle(isSel ? Color.white : Color(red: 0.28, green: 0.24, blue: 0.20))
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider().frame(height: 22)

            // Fret stepper & enter
            HStack(spacing: 4) {
                Button {
                    if pitch.fret > 0 { model.enterFret(pitch.fret - 1, string: pitch.stringIndex) }
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 32, height: 36)
                        .background(Color(red: 0.93, green: 0.90, blue: 0.84), in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)

                Text("\(pitch.fret)品")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .frame(width: 36, alignment: .center)

                Button {
                    if pitch.fret < 24 { model.enterFret(pitch.fret + 1, string: pitch.stringIndex) }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 32, height: 36)
                        .background(Color(red: 0.93, green: 0.90, blue: 0.84), in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)

                Button {
                    model.enterFret(pitch.fret, string: pitch.stringIndex)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "square.and.pencil")
                        Text("录入")
                    }
                    .font(.system(size: 11, weight: .bold))
                    .padding(.horizontal, 12)
                    .frame(height: 36)
                    .background(Color(red: 0.55, green: 0.39, blue: 0.12), in: RoundedRectangle(cornerRadius: 8))
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }
        }
    }


    private var allBar: some View {
        VStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                notesBar
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    techniquesBar
                    Divider().frame(height: 22)
                    measuresBar
                    Divider().frame(height: 22)
                    pitchBar
                }
            }
        }
    }

    private var arrangingBar: some View {
        HStack(spacing: 10) {
            // Group 1: 走向套路 (Progressions)
            HStack(spacing: 5) {
                Text("走向:")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color(red: 0.55, green: 0.39, blue: 0.12))

                ForEach(ChordProgressionPreset.presets.prefix(3)) { prog in
                    Button {
                        model.applyProgressionPattern(progression: prog, pattern: selectedPattern)
                    } label: {
                        Text(prog.name)
                            .font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(Color(red: 0.93, green: 0.89, blue: 0.82), in: Capsule())
                            .foregroundStyle(Color(red: 0.28, green: 0.22, blue: 0.16))
                    }
                    .buttonStyle(.plain)
                    .help(prog.description)
                }
            }

            Divider().frame(height: 22)

            // Group 2: 单和弦快速应用
            HStack(spacing: 4) {
                Text("和弦:")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color(red: 0.55, green: 0.39, blue: 0.12))

                ForEach(["C", "G", "Am", "Em", "F", "Fmaj7", "Dm", "G7", "Cadd9", "G/B"], id: \.self) { chordName in
                    Button {
                        selectedChordName = chordName
                        model.applyAccompanimentPattern(chordName: chordName, pattern: selectedPattern)
                    } label: {
                        Text(chordName)
                            .font(.system(size: 11, weight: selectedChordName == chordName ? .bold : .medium, design: .rounded))
                            .frame(minWidth: 30)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 5)
                            .background(
                                selectedChordName == chordName
                                    ? Color(red: 0.88, green: 0.35, blue: 0.22)
                                    : Color(red: 0.94, green: 0.91, blue: 0.85),
                                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                            )
                            .foregroundStyle(selectedChordName == chordName ? Color.white : Color(red: 0.24, green: 0.19, blue: 0.14))
                    }
                    .buttonStyle(.plain)
                    .help("为当前小节写入 \(chordName) 和弦伴奏")
                }
            }

            Divider().frame(height: 22)

            // Group 3: 伴奏织体类型
            HStack(spacing: 4) {
                ForEach(StudioAccompanimentPattern.allPatterns) { pat in
                    Button {
                        selectedPattern = pat
                        model.applyAccompanimentPattern(chordName: selectedChordName, pattern: pat)
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: pat.category.symbol)
                                .font(.system(size: 9))
                            Text(pat.name)
                                .font(.system(size: 11, weight: selectedPattern.id == pat.id ? .bold : .regular))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(
                            selectedPattern.id == pat.id
                                ? Color(red: 0.17, green: 0.15, blue: 0.13)
                                : Color.clear,
                            in: Capsule()
                        )
                        .foregroundStyle(
                            selectedPattern.id == pat.id
                                ? Color.white
                                : Color(red: 0.42, green: 0.34, blue: 0.25)
                        )
                    }
                    .buttonStyle(.plain)
                    .help(pat.description)
                }
            }
        }
    }
}


private struct NativeGMProgramRow: Identifiable {
    let program: Int
    let name: String
    let family: String
    var id: Int { program }
}

private struct StudioMetadataDraft {}

