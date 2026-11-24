import AppKit
import MIMICore
import SwiftUI

struct NativePlayerPane: View {
    @StateObject private var model: NativePlayerModel
    @State private var selectedPanel: PlayerPanel = .practice
    @State private var isPanelCollapsed = true
    @State private var showManuscriptGallery = false
    @State private var showExportOptions = false
    @AppStorage("mimi.motion.preference") private var motionPreference = "system"
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    private let item: CatalogItem?
    private let personalScore: PersonalScore?
    private let isFocused: Bool
    private let viewportHeight: CGFloat?
    private let onToggleFocus: (() -> Void)?

    private var motionPolicy: MIMIMotionPolicy {
        MIMIMotionPolicy.resolve(preference: motionPreference, reduceMotion: reduceMotion)
    }

    init(
        item: CatalogItem?,
        personalScore: PersonalScore? = nil,
        contentRoot: URL,
        personalStore: PersonalStore,
        importedFileURL: URL? = nil,
        mode: NativePlayerMode = .player,
        onPersonalDataChanged: @escaping @MainActor () -> Void = {},
        isFocused: Bool = false,
        viewportHeight: CGFloat? = nil,
        onToggleFocus: (() -> Void)? = nil
    ) {
        self.item = item
        self.personalScore = personalScore
        self.isFocused = isFocused
        self.viewportHeight = viewportHeight
        self.onToggleFocus = onToggleFocus
        _model = StateObject(wrappedValue: NativePlayerModel(
            item: item,
            personalScore: personalScore,
            contentRoot: contentRoot,
            personalStore: personalStore,
            importedFileURL: importedFileURL,
            mode: mode,
            onPersonalDataChanged: onPersonalDataChanged
        ))
        _selectedPanel = State(initialValue: mode == .practice ? .practice : .performance)
    }

#if MIMI_RUNTIME_DIAGNOSTICS
    init(runtimeDiagnosticModel model: NativePlayerModel) {
        item = model.item
        personalScore = model.personalScore
        isFocused = false
        viewportHeight = nil
        onToggleFocus = nil
        _model = StateObject(wrappedValue: model)
        _selectedPanel = State(initialValue: model.mode == .practice ? .practice : .performance)
    }
#endif

    var body: some View {
        VStack(spacing: 0) {
            playerToolbar

            if !isPanelCollapsed {
                panelBody
                    .frame(maxWidth: .infinity)
                    .frame(height: panelHeight)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 10)
                    .transition(motionPolicy.allowsSpatialMotion ? .move(edge: .top).combined(with: .opacity) : .opacity)
            }

            Group {
                if let sourceError = model.sourceError {
                    emptyState(title: "无法打开谱面", symbol: "music.note.list", detail: sourceError)
                } else if let playerError = model.playerRootError {
                    emptyState(title: "本地谱面引擎不可用", symbol: "exclamationmark.triangle", detail: playerError)
                } else if model.source == nil {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text(model.statusMessage).font(MIMITheme.bodyFont(size: 13)).foregroundStyle(MIMITheme.mutedInk)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ZStack(alignment: .top) {
                        NativePlayerWebView(model: model)
                            .id(model.webViewIdentity)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(MIMITheme.paper)

                        if let toast = model.loopToastMessage {
                            HStack(spacing: 8) {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(MIMITheme.terracotta)
                                Text(toast)
                                    .font(MIMITheme.bodyFont(size: 12.5, weight: .semibold))
                                    .foregroundStyle(MIMITheme.bodyInk)
                                Button {
                                    withAnimation(.easeOut(duration: 0.2)) {
                                        model.loopToastMessage = nil
                                    }
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(MIMITheme.mutedInk)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 18)
                                    .fill(Color.white.opacity(0.95))
                                    .shadow(color: Color.black.opacity(0.12), radius: 8, x: 0, y: 3)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 18)
                                    .stroke(MIMITheme.terracotta.opacity(0.35), lineWidth: 1)
                            )
                            .padding(.top, 12)
                            .transition(.move(edge: .top).combined(with: .opacity))
                            .zIndex(100)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            statusBar
        }
        .frame(maxWidth: .infinity)
        .frame(height: (viewportHeight.map { max(360, $0) } ?? 650) + (isPanelCollapsed ? 0 : panelHeight + 10))
        .background(MIMITheme.paper)
        .animation(motionPolicy.panelAnimation, value: isPanelCollapsed)
        .animation(motionPolicy.panelAnimation, value: isFocused)
        .sheet(isPresented: $showManuscriptGallery) {
            NativeManuscriptGalleryView(model: model)
        }
        .confirmationDialog("导出与打印", isPresented: $showExportOptions, titleVisibility: .visible) {
            Button("保存原谱原件…") { model.exportOriginalSource() }
            Button("导出 PDF…") { model.exportPDF() }
                .disabled(!model.canExportRenderedScore)
                .help(model.isXhe ? "文本和弦谱暂不支持分页 PDF 导出" : "导出全谱分页 A4 PDF")
            Button("导出谱面长图…") { model.exportLongImage() }
                .disabled(!model.canExportRenderedScore)
                .help(model.isXhe ? "文本和弦谱暂不支持长图导出" : "导出整首谱面的分页长图")
            Button("打印…") { model.printScore() }
            Button("取消", role: .cancel) {}
        }
        .onAppear {
            model.setNativeViewVisible(true)
            syncMotionPreference()
#if MIMI_RUNTIME_DIAGNOSTICS
            if model.mode == .player { RuntimePlayerPaneDiagnostics.register(model) }
#endif
        }
        .onChange(of: motionPreference) { _ in syncMotionPreference() }
        .onChange(of: reduceMotion) { _ in syncMotionPreference() }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            syncMotionPreference()
        }
        .onDisappear {
            model.setNativeViewVisible(false)
            model.leavePlayerPane()
#if MIMI_RUNTIME_DIAGNOSTICS
            RuntimePlayerPaneDiagnostics.clear(model)
#endif
        }
        .onChange(of: scenePhase) { phase in model.setApplicationActive(phase == .active) }
        .onChange(of: item?.id) { _ in
            if let item {
                model.open(item: item, autoplay: false)
            }
        }
        .onChange(of: personalScore?.id) { _ in
            if let personalScore {
                model.loadPersonalScore(personalScore)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("MIMI.TogglePlayback"))) { _ in
            model.togglePlayback()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("MIMI.StopPlayback"))) { _ in
            model.stopPlayback()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("MIMI.WindowOcclusionDidChange"))) { notification in
            if let isOccluded = notification.userInfo?["isOccluded"] as? Bool {
                model.setNativeViewVisible(!isOccluded)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("MIMI.Player.ExportPDF"))) { _ in
            model.exportPDF()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("MIMI.Player.ZoomIn"))) { _ in
            model.zoomIn()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("MIMI.Player.ZoomOut"))) { _ in
            model.zoomOut()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("MIMI.Player.ZoomReset"))) { _ in
            model.resetZoom()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("MIMI.Player.SetZoom"))) { notification in
            if let value = notification.object as? NSNumber {
                model.zoom = min(1.6, max(0.6, ((value.doubleValue * 100).rounded() / 100)))
                model.applyZoom()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("MIMI.Player.SeekForward"))) { _ in
            model.seekBySeconds(5)
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("MIMI.Player.SeekBackward"))) { _ in
            model.seekBySeconds(-5)
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("MIMI.Player.PreviousBar"))) { _ in
            model.seekPreviousBar()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("MIMI.Player.NextBar"))) { _ in
            model.seekNextBar()
        }
    }

    private var panelHeight: CGFloat {
        switch selectedPanel {
        case .practice: return 270
        case .fretboard: return (model.primaryTrack?.tuning.count ?? 6) <= 4 ? 188 : 236
        case .tracks, .review: return 205
        case .manuscript, .performance, .display, .export: return 135
        }
    }

    private func syncMotionPreference() {
        let storedPreference = UserDefaults.standard.string(forKey: "mimi.motion.preference") ?? motionPreference
        model.setMotionPreference(MIMIMotionPolicy.resolve(preference: storedPreference, reduceMotion: reduceMotion).rawValue)
    }

    private func emptyState(title: String, symbol: String, detail: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 30))
                .foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
        }
        .frame(maxWidth: 580)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }

    private var transportControls: some View {
        HStack(spacing: 6) {
            Button(action: { model.togglePlayback() }) {
                HStack(spacing: 5) {
                    Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 11, weight: .bold))
                    Text(model.isPlaying ? "暂停" : "播放")
                        .font(MIMITheme.bodyFont(size: 12, weight: .semibold))
                }
                .padding(.horizontal, 14)
                .frame(height: 32)
                .foregroundStyle(.white)
                .background(
                    LinearGradient(
                        colors: [Color(hex: 0x302B26), Color(hex: 0x201D1A)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    in: Capsule()
                )
                .shadow(color: Color(hex: 0x483620).opacity(0.18), radius: 4, x: 0, y: 1.5)
            }
            .buttonStyle(.plain)
            .disabled(!model.canPlay)
            .help(model.canPlay ? "播放或暂停" : model.playDisabledReason)

            Button { model.stopPlayback() } label: {
                Image(systemName: "backward.end.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(MIMITheme.bodyInk)
                    .frame(width: 32, height: 32)
                    .background(MIMITheme.paperWhite, in: Circle())
                    .overlay(Circle().stroke(MIMITheme.softBorder, lineWidth: 1))
                    .shadow(color: Color(nsColor: .dynamic(lightHex: 0x483620, darkHex: 0x000000)).opacity(0.02), radius: 3, x: 0, y: 1)
            }
            .buttonStyle(.plain)
            .disabled(!model.canPlay)
            .help(model.canPlay ? "停止并回到开头" : model.playDisabledReason)
        }
    }

    private var playbackTools: some View {
        HStack(spacing: 6) {
            NativePlayerTempoStepper(model: model)

            Menu {
                Button {
                    model.setLoopPoint("A")
                } label: {
                    if let ptA = model.loopPointADetails {
                        Label("重设起点 A (当前: 第 \(ptA.bar ?? 1) 小节)", systemImage: "a.circle.fill")
                    } else if let loop = model.loopDetails {
                        Label("重设起点 A (当前: 第 \(loop.startBar ?? 1) 小节)", systemImage: "a.circle")
                    } else {
                        Label("设置循环起点 A", systemImage: "a.circle")
                    }
                }
                .disabled(!model.canPlay)

                Button {
                    model.setLoopPoint("B")
                } label: {
                    if let loop = model.loopDetails {
                        Label("重设终点 B (当前: 第 \(loop.endBar ?? 1) 小节)", systemImage: "b.circle.fill")
                    } else {
                        Label("设置循环终点 B", systemImage: "b.circle")
                    }
                }
                .disabled(!model.canPlay || (model.loopPointA == nil && model.loopRange == nil))

                if model.loopRange != nil || model.loopPointA != nil {
                    Divider()
                    if let loop = model.loopDetails {
                        Text("区间：第 \(loop.startBar ?? 1) 至 \(loop.endBar ?? loop.startBar ?? 1) 小节 (tick \(loop.startTick)–\(loop.endTick))")
                            .font(.system(size: 10, design: .monospaced))
                    } else if let ptA = model.loopPointADetails {
                        Text("起点 A：第 \(ptA.bar ?? 1) 小节 (tick \(ptA.tick))")
                            .font(.system(size: 10, design: .monospaced))
                    }
                    Button(role: .destructive) {
                        model.clearLoop()
                    } label: {
                        Label("清除 A–B 循环", systemImage: "xmark.circle")
                    }
                }
            } label: {
                if let loop = model.loopDetails {
                    Label("循环 A–B (第\(loop.startBar ?? 1)–\(loop.endBar ?? loop.startBar ?? 1)节)", systemImage: "arrow.triangle.2.circlepath")
                } else if model.loopPointA != nil {
                    Label("循环 (待设 B 点)", systemImage: "arrow.triangle.2.circlepath")
                } else {
                    Label("循环", systemImage: "arrow.triangle.2.circlepath")
                }
            }
            .buttonStyle(NativePlayerPillButtonStyle(prominent: model.loopRange != nil))
            .menuStyle(.borderlessButton)
            .disabled(!model.scoreReady)
            .help(model.scoreReady ? "设置、查看或清除 A–B 循环" : model.scoreAvailabilityReason)

            Toggle("节拍器", isOn: Binding(get: { model.metronome }, set: { model.setMetronome($0) }))
                .toggleStyle(NativePlayerTogglePillStyle())
                .disabled(!model.scoreReady)
                .help(model.scoreReady ? "切换节拍器" : model.scoreAvailabilityReason)

            Button {
                onToggleFocus?()
            } label: {
                Image(systemName: isFocused ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isFocused ? .white : MIMITheme.bodyInk)
                    .frame(width: 32, height: 32)
                    .background(isFocused ? MIMITheme.ink : MIMITheme.paperWhite, in: Circle())
                    .overlay(Circle().stroke(isFocused ? Color.clear : MIMITheme.softBorder, lineWidth: 1))
                    .shadow(color: Color(nsColor: .dynamic(lightHex: 0x483620, darkHex: 0x000000)).opacity(0.02), radius: 3, x: 0, y: 1)
            }
            .buttonStyle(.plain)
            .disabled(onToggleFocus == nil)
            .help(onToggleFocus == nil ? "此播放器尚未连接专注阅谱状态" : isFocused ? "退出全屏阅谱" : "全屏阅谱")
        }
    }

    private var masterPlaybackDeck: some View {
        ViewThatFits(in: .horizontal) {
            // Standard / Wide layout: All in one single line
            HStack(spacing: 10) {
                transportControls
                NativePlayerPositionBar(
                    positionState: model.positionState,
                    canSeek: model.canPlay,
                    compact: true,
                    tempo: model.tempo,
                    loopDetails: model.loopDetails,
                    loopPointADetails: model.loopPointADetails,
                    onClearLoop: { model.clearLoop() }
                ) { model.seek(toRatio: $0) }
                playbackTools
            }

            // Compact fallback layout
            VStack(spacing: 6) {
                HStack(spacing: 10) {
                    transportControls
                    Spacer(minLength: 0)
                    playbackTools
                }
                NativePlayerPositionBar(
                    positionState: model.positionState,
                    canSeek: model.canPlay,
                    compact: false,
                    tempo: model.tempo,
                    loopDetails: model.loopDetails,
                    loopPointADetails: model.loopPointADetails,
                    onClearLoop: { model.clearLoop() }
                ) { model.seek(toRatio: $0) }
            }
        }
    }

    private var playerToolbar: some View {
        VStack(spacing: 6) {
            masterPlaybackDeck.animation(motionPolicy.controlAnimation, value: isFocused)
            if !isFocused {
                settingsDrawerBar
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(MIMITheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(MIMITheme.softBorder, lineWidth: 1))
        .shadow(color: Color(nsColor: .dynamic(lightHex: 0x483620, darkHex: 0x000000)).opacity(0.03), radius: 8, x: 0, y: 2)
        .padding(.horizontal, 8).padding(.top, 6).padding(.bottom, 6)
    }

    private var settingsDrawerBar: some View {
        HStack(spacing: 3) {
            drawerPill(.performance, title: "演奏", symbol: "guitars")
            drawerPill(.display, title: "显示", symbol: "rectangle.inset.filled")
            drawerPill(.tracks, title: "音轨", symbol: "slider.horizontal.3")
            drawerPill(.fretboard, title: "指板", symbol: "pianokeys")
            drawerPill(.practice, title: "练习面板", symbol: "metronome")
            drawerPill(.export, title: "导出", symbol: "square.and.arrow.up")

            Menu {
                Button { selectPanel(.review) } label: { Label("练习回顾", systemImage: PlayerPanel.review.symbol) }
                Button { selectPanel(.manuscript) } label: { Label("手稿与分页", systemImage: PlayerPanel.manuscript.symbol) }
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 10, weight: .semibold))
                    if !isPanelCollapsed && (selectedPanel == .review || selectedPanel == .manuscript) {
                        Text(selectedPanel == .review ? "回顾" : "手稿")
                            .font(MIMITheme.bodyFont(size: 11, weight: .semibold))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 7, weight: .bold))
                    }
                }
                .foregroundStyle(
                    (!isPanelCollapsed && (selectedPanel == .review || selectedPanel == .manuscript)) ? MIMITheme.darkGold : MIMITheme.bodyInk.opacity(0.8)
                )
                .padding(.horizontal, 8)
                .frame(height: 28)
                .background(
                    (!isPanelCollapsed && (selectedPanel == .review || selectedPanel == .manuscript)) ? MIMITheme.paperWhite : Color.clear,
                    in: Capsule()
                )
                .overlay(
                    Group {
                        if !isPanelCollapsed && (selectedPanel == .review || selectedPanel == .manuscript) {
                            Capsule().stroke(MIMITheme.warmGold.opacity(0.4), lineWidth: 1)
                        }
                    }
                )
            }
            .buttonStyle(.plain)
            .menuStyle(.borderlessButton)
            .help("打开练习回顾或手稿分页")

            Spacer(minLength: 0)

            if !isPanelCollapsed {
                Button {
                    withAnimation(motionPolicy.panelAnimation) {
                        isPanelCollapsed = true
                    }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 8, weight: .bold))
                        Text("收起面板")
                            .font(MIMITheme.bodyFont(size: 10.5, weight: .medium))
                    }
                    .foregroundStyle(MIMITheme.mutedInk)
                    .padding(.horizontal, 8)
                    .frame(height: 26)
                    .background(MIMITheme.paperWhite, in: Capsule())
                    .overlay(Capsule().stroke(MIMITheme.softBorder, lineWidth: 0.8))
                }
                .buttonStyle(.plain)
                .help("收起当前设置面板")
                .transition(.opacity)
            }
        }
        .padding(3)
        .background(MIMITheme.navigationSegment, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(MIMITheme.softBorder, lineWidth: 0.8))
    }

    private func drawerPill(_ panel: PlayerPanel, title: String, symbol: String) -> some View {
        let isSelected = !isPanelCollapsed && selectedPanel == panel
        return Button {
            withAnimation(motionPolicy.panelAnimation) {
                selectPanel(panel)
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 10.5, weight: isSelected ? .bold : .medium))
                Text(title)
                    .font(MIMITheme.bodyFont(size: 11, weight: isSelected ? .semibold : .medium))
                if isSelected {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 7, weight: .bold))
                }
            }
            .foregroundStyle(isSelected ? MIMITheme.darkGold : MIMITheme.bodyInk.opacity(0.82))
            .padding(.horizontal, 9)
            .frame(height: 28)
            .background(isSelected ? MIMITheme.paperWhite : Color.clear, in: Capsule())
            .overlay(
                Group {
                    if isSelected {
                        Capsule().stroke(MIMITheme.warmGold.opacity(0.4), lineWidth: 1)
                    }
                }
            )
            .shadow(color: isSelected ? Color(nsColor: .dynamic(lightHex: 0x483620, darkHex: 0x000000)).opacity(0.06) : .clear, radius: 2, x: 0, y: 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(panelAvailabilityHelp(panel))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func selectPanel(_ panel: PlayerPanel) {
        if selectedPanel == panel && !isPanelCollapsed {
            isPanelCollapsed = true
        } else {
            selectedPanel = panel
            isPanelCollapsed = false
        }
    }

    private func panelAvailabilityHelp(_ panel: PlayerPanel) -> String {
        switch panel {
        case .performance: return "演奏设置：预备拍、变调夹、移调和恢复默认"
        case .display: return model.scoreReady ? "显示设置：谱型、数字谱、和弦、缩放和分页" : model.scoreAvailabilityReason
        case .tracks: return model.scoreReady ? "音轨、可见性、静音、独奏、音量与音色" : model.scoreAvailabilityReason
        case .fretboard: return model.scoreReady ? "查看与当前演奏音符同步的真实指板" : model.scoreAvailabilityReason
        case .practice: return model.canJoinPractice ? "练习片段、速度计划、断点和练习记录" : model.practiceAvailabilityReason
        case .review: return model.scoreReady ? "回顾与恢复当前曲谱的练习状态" : model.scoreAvailabilityReason
        case .manuscript: return model.canExport ? "打开手稿扫描、分页和原件操作" : model.exportAvailabilityReason
        case .export: return model.canExport ? "保存原件、导出完整 PDF 或谱面长图、打印" : model.exportAvailabilityReason
        }
    }

    private var panelBody: some View {
        VStack(alignment: .leading, spacing: 6) {
            if selectedPanel != .fretboard {
                HStack {
                    Label(selectedPanel.title, systemImage: selectedPanel.symbol)
                        .font(MIMITheme.bodyFont(size: 11.5, weight: .semibold)).foregroundStyle(MIMITheme.ink)
                    Spacer(minLength: 0)
                    Button {
                        withAnimation(motionPolicy.panelAnimation) {
                            isPanelCollapsed = true
                        }
                    } label: {
                        Label("收起", systemImage: "chevron.up")
                    }
                    .buttonStyle(NativePlayerPillButtonStyle()).help("收起当前播放器设置面板")
                }
                .padding(.horizontal, 2)
            }
            Group {
                switch selectedPanel {
                case .practice: NativePracticePanel(model: model)
                case .tracks: NativeTrackMixerPanel(model: model)
                case .review: NativePracticeReviewPanel(model: model)
                case .fretboard: fretboardView
                case .manuscript: NativeManuscriptPanel(model: model) { showManuscriptGallery = true }
                case .performance: performanceSettingsPanel
                case .display: displaySettingsPanel
                case .export: exportPanel
                }
            }
        }
        .padding(.horizontal, 10).padding(.top, 8).padding(.bottom, 5)
        .background(MIMITheme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(MIMITheme.softBorder, lineWidth: 1))
    }

    private var performanceSettingsPanel: some View {
        NativePlayerFlowLayout(horizontalSpacing: 8, verticalSpacing: 8) {
            Toggle("预备拍", isOn: Binding(get: { model.countIn }, set: { model.setCountIn($0) }))
                .toggleStyle(NativePlayerTogglePillStyle()).disabled(!model.scoreReady)
                .help(model.scoreReady ? "播放前添加预备拍" : model.scoreAvailabilityReason)

            Menu {
                Button("恢复原谱变调夹") { model.setCapo(model.capo, useSource: true) }
                Divider()
                ForEach(0...12, id: \.self) { value in
                    Button(value == 0 ? "无变调夹" : "第 \(value) 品") { model.setCapo(value, useSource: false) }
                }
            } label: {
                Label(model.useSourceCapo ? "原谱变调夹" : "变调夹 \(model.capo)", systemImage: "guitars")
            }
            .buttonStyle(NativePlayerPillButtonStyle()).menuStyle(.borderlessButton)
            .disabled(!model.scoreReady).help(model.scoreReady ? "设置变调夹或恢复原谱设置" : model.scoreAvailabilityReason)

            HStack(spacing: 7) {
                Button { model.setTranspose(model.transpose - 1) } label: { Image(systemName: "minus") }.buttonStyle(.plain)
                Text("移调 \(model.transpose > 0 ? "+" : "")\(model.transpose)")
                    .font(.system(size: 12, weight: .medium, design: .rounded).monospacedDigit()).frame(minWidth: 74)
                Button { model.setTranspose(model.transpose + 1) } label: { Image(systemName: "plus") }.buttonStyle(.plain)
            }
            .padding(.horizontal, 10).frame(height: 36)
            .background(MIMITheme.paper, in: Capsule()).overlay(Capsule().stroke(MIMITheme.softBorder, lineWidth: 1))
            .disabled(!model.scoreReady).help(model.scoreReady ? "按半音移调" : model.scoreAvailabilityReason)

            Button { model.restoreDefaults() } label: { Label("恢复默认", systemImage: "arrow.counterclockwise") }
                .buttonStyle(NativePlayerPillButtonStyle()).disabled(!model.scoreReady)
                .help(model.scoreReady ? "恢复原谱速度、变调夹、转调、显示和音色" : model.scoreAvailabilityReason)
        }
    }

    private var displaySettingsPanel: some View {
        NativePlayerFlowLayout(horizontalSpacing: 8, verticalSpacing: 8) {
            Menu {
                Button("吉他谱 + 简谱") { model.setDisplayMode("mixed") }
                Button("纯六线谱 / 四线谱") { model.setDisplayMode("tab") }
            } label: {
                Label(model.displayMode == "tab" ? "纯六线谱" : "简谱并排", systemImage: "music.note.list")
            }
            .buttonStyle(NativePlayerPillButtonStyle()).menuStyle(.borderlessButton)
            .disabled(!model.scoreReady).help(model.scoreReady ? "切换吉他谱显示模式" : model.scoreAvailabilityReason)

            Toggle("数字谱", isOn: Binding(get: { model.numberTab }, set: { model.setNumberTab($0) }))
                .toggleStyle(NativePlayerTogglePillStyle()).disabled(!model.scoreReady)
                .help(model.scoreReady ? "切换数字谱显示" : model.scoreAvailabilityReason)

            Menu {
                Button("和弦名称") { model.setChordMode("name") }
                Button("和弦指法图") { model.setChordMode("diagram") }
            } label: {
                Label(model.chordMode == "diagram" ? "指法图" : "和弦名", systemImage: "hand.draw")
            }
            .buttonStyle(NativePlayerPillButtonStyle()).menuStyle(.borderlessButton)
            .disabled(!model.scoreReady).help(model.scoreReady ? "切换和弦名称或指法图" : model.scoreAvailabilityReason)

            HStack(spacing: 7) {
                Text("缩放").font(MIMITheme.bodyFont(size: 12)).foregroundStyle(MIMITheme.mutedInk)
                Slider(value: $model.zoom, in: 0.6...1.6, step: 0.05) { editing in
                    if !editing { model.applyZoom() }
                }
                .frame(width: 100).disabled(!model.scoreReady).tint(MIMITheme.warmGold)
            }
            .padding(.horizontal, 10).frame(height: 36)
            .background(MIMITheme.paper, in: Capsule()).overlay(Capsule().stroke(MIMITheme.softBorder, lineWidth: 1))
            .help(model.scoreReady ? "按原谱缩放规则调整谱面" : model.scoreAvailabilityReason)

            Toggle("实时指板", isOn: Binding(get: { model.showFretboard }, set: { model.setShowFretboard($0) }))
                .toggleStyle(NativePlayerTogglePillStyle()).disabled(!model.scoreReady)
                .help(model.scoreReady ? "同步显示当前音符的指板状态" : model.scoreAvailabilityReason)

            Button { selectPanel(.manuscript) } label: { Label("手稿与分页", systemImage: PlayerPanel.manuscript.symbol) }
                .buttonStyle(NativePlayerPillButtonStyle()).disabled(!model.canExport)
                .help(model.canExport ? "查看原版手稿与谱面分页" : model.exportAvailabilityReason)
        }
        .overlay(alignment: .bottomTrailing) {
            if !model.scoreReady {
                Text(model.scoreAvailabilityReason).font(MIMITheme.bodyFont(size: 11)).foregroundStyle(MIMITheme.mutedInk)
                    .padding(.top, 4).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var exportPanel: some View {
        NativePlayerFlowLayout(horizontalSpacing: 8, verticalSpacing: 8) {
            Button { model.exportOriginalSource() } label: { Label("保存原谱原件…", systemImage: "doc.text") }
                .buttonStyle(NativePlayerPillButtonStyle()).disabled(model.source == nil)
                .help(model.source == nil ? model.exportAvailabilityReason : "保存本地原始曲谱文件")
            Button { model.exportPDF() } label: { Label("导出 PDF…", systemImage: "doc.richtext") }
                .buttonStyle(NativePlayerPillButtonStyle()).disabled(!model.canExportRenderedScore)
                .help(model.canExportRenderedScore ? "导出完整谱面分页 A4 PDF" : model.exportAvailabilityReason)
            Button { model.exportLongImage() } label: { Label("谱面长图…", systemImage: "photo") }
                .buttonStyle(NativePlayerPillButtonStyle()).disabled(!model.canExportRenderedScore)
                .help(model.canExportRenderedScore ? "导出完整谱面长图" : model.exportAvailabilityReason)
            Button { model.printScore() } label: { Label("打印…", systemImage: "printer") }
                .buttonStyle(NativePlayerPillButtonStyle()).disabled(!model.canExport)
                .help(model.canExport ? "打印曲谱" : model.exportAvailabilityReason)
            Button { showExportOptions = true } label: { Label("更多导出选项", systemImage: "ellipsis.circle") }
                .buttonStyle(NativePlayerPillButtonStyle()).disabled(!model.canExport)
                .help(model.canExport ? "查看导出与打印选项" : model.exportAvailabilityReason)
        }
    }

    private var fretboardView: some View {
        NativeFretboardView(
            track: model.primaryTrack,
            notes: model.currentBeatNotes,
            capo: model.activeCapo,
            currentChord: model.currentBeatChord,
            scoreKey: model.displayKey,
            playedBeatSequence: model.playedBeatSequence,
            onFretClick: { model.previewFret(string: $0, fret: $1) },
            onChordPreview: { model.previewChordNotes($0) }
        )
    }

    private func setFretboardVisible(_ visible: Bool) {
        model.setShowFretboard(visible)
        if visible {
            selectedPanel = .fretboard
            isPanelCollapsed = false
        } else if selectedPanel == .fretboard {
            isPanelCollapsed = true
        }
    }

    @ViewBuilder
    private var statusBar: some View {
        if model.isLoading || model.isLoadingSound || model.playerError != nil {
            Divider()
            HStack(spacing: 9) {
                if model.isLoading {
                    ProgressView().controlSize(.small)
                } else if let progress = model.soundProgress {
                    ProgressView(value: progress).controlSize(.small).frame(width: 96)
                } else if model.isLoadingSound {
                    ProgressView().controlSize(.small)
                }

                Text(model.statusMessage)
                    .font(.caption)
            .foregroundColor(model.playerError == nil ? MIMITheme.mutedInk : MIMITheme.terracotta)
                    .lineLimit(1)
                    .textSelection(.enabled)

                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
        }
    }
}

