import AppKit
import Combine
import CryptoKit
import Foundation
import ImageIO
import MIMICore
import SwiftUI
import UniformTypeIdentifiers
import WebKit

enum NativePlayerMode: String {
    case player
    case practice
}

fileprivate struct NativePlaybackPositionSample: Equatable {
    let timeMs: Double
    let durationMs: Double
    let speedRatio: Double
    let isPlaying: Bool
    let receivedAtUptime: TimeInterval
    let tick: Double?
    let bar: Int?
    let beat: Int?

    func time(at uptime: TimeInterval) -> Double {
        let elapsedMs = isPlaying ? max(0, uptime - receivedAtUptime) * 1_000 : 0
        let upperBound = durationMs > 0 ? durationMs : .greatestFiniteMagnitude
        return min(upperBound, max(0, timeMs + elapsedMs))
    }
}

@MainActor
fileprivate final class NativePlayerPositionState: ObservableObject {
    @Published private(set) var sample: NativePlaybackPositionSample?

    func reanchor(
        timeMs: Double,
        durationMs: Double,
        speedRatio: Double,
        isPlaying: Bool,
        tick: Double? = nil,
        bar: Int? = nil,
        beat: Int? = nil,
        receivedAtUptime: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) {
        guard timeMs.isFinite, durationMs.isFinite, speedRatio.isFinite else { return }
        sample = NativePlaybackPositionSample(
            timeMs: max(0, timeMs),
            durationMs: max(0, durationMs),
            speedRatio: max(0, speedRatio),
            isPlaying: isPlaying,
            receivedAtUptime: receivedAtUptime,
            tick: tick,
            bar: bar,
            beat: beat
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
            beat: beat ?? (replacingUnknowns ? nil : sample.beat)
        )
    }

    func clear() {
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

struct NativePlayerPane: View {
    @StateObject private var model: NativePlayerModel
    @State private var selectedPanel: PlayerPanel = .practice
    @State private var isPanelCollapsed = true
    @State private var showManuscriptGallery = false
    @State private var showExportOptions = false
    @AppStorage("mimi.motion.preference") private var motionPreference = "system"
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
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
                    NativePlayerWebView(model: model)
                        .id(model.webViewIdentity)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(MIMITheme.paper)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if !isPanelCollapsed {
                panelBody
                    .frame(maxWidth: .infinity)
                    .frame(height: panelHeight)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 10)
                    .transition(motionPolicy.allowsSpatialMotion ? .move(edge: .top).combined(with: .opacity) : .opacity)
            }

            statusBar
        }
        .frame(maxWidth: .infinity)
        .frame(height: viewportHeight.map { max(360, $0) } ?? 650)
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
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("MIMI.TogglePlayback"))) { _ in
            model.togglePlayback()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("MIMI.StopPlayback"))) { _ in
            model.stopPlayback()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("MIMI.Player.ExportPDF"))) { _ in
            model.exportPDF()
        }
    }

    private var panelHeight: CGFloat {
        switch selectedPanel {
        case .practice: return 286
        case .tracks, .fretboard, .manuscript, .review: return 220
        case .performance, .display, .export: return 148
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

    private var transportBar: some View {
        NativePlayerFlowLayout(horizontalSpacing: 10, verticalSpacing: 7) {
            HStack(spacing: 7) {
                Button(action: { model.togglePlayback() }) {
                    Label(model.isPlaying ? "暂停" : "播放", systemImage: model.isPlaying ? "pause.fill" : "play.fill")
                }
                .buttonStyle(NativePlayerPillButtonStyle(prominent: true))
                .disabled(!model.canPlay)
                .help(model.canPlay ? "播放或暂停" : model.playDisabledReason)

                Button { model.stopPlayback() } label: { Label("重来", systemImage: "backward.end.fill") }
                    .buttonStyle(NativePlayerPillButtonStyle())
                    .disabled(!model.canPlay)
                    .help(model.canPlay ? "停止并回到开头" : model.playDisabledReason)
            }

            HStack(spacing: 7) {
                Text("BPM").font(MIMITheme.bodyFont(size: 12, weight: .semibold)).foregroundStyle(MIMITheme.mutedInk)
                Slider(value: $model.tempo, in: model.tempoRange, step: 1) { editing in
                    model.tempoEditingChanged(editing)
                }
                .frame(width: 118).disabled(!model.canPlay).tint(MIMITheme.warmGold)
                Text("\(Int(model.tempo.rounded()))")
                    .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(MIMITheme.ink).frame(width: 32, alignment: .trailing)
            }
            .padding(.horizontal, 10).frame(height: 36)
            .background(MIMITheme.paper, in: Capsule()).overlay(Capsule().stroke(MIMITheme.softBorder, lineWidth: 1))
            .help(model.canPlay ? "直接调整播放速度；范围跟随原谱速度" : model.playDisabledReason)

            Menu {
                Button("设置循环起点 A") { model.setLoopPoint("A") }.disabled(!model.canPlay)
                Button("设置循环终点 B") { model.setLoopPoint("B") }
                    .disabled(!model.canPlay || model.loopPointA == nil)
                if let range = model.loopRange {
                    Divider()
                    Text("tick \(range.startTick)–\(range.endTick)")
                    Button("清除 A–B 循环") { model.clearLoop() }
                }
            } label: {
                Label(model.loopRange == nil ? "循环" : "循环 A–B", systemImage: "arrow.triangle.2.circlepath")
            }
            .buttonStyle(NativePlayerPillButtonStyle())
            .menuStyle(.borderlessButton)
            .disabled(!model.scoreReady)
            .help(model.scoreReady ? "设置、查看或清除 A–B 循环" : model.scoreAvailabilityReason)

            Toggle("节拍器", isOn: Binding(get: { model.metronome }, set: { model.setMetronome($0) }))
                .toggleStyle(NativePlayerTogglePillStyle()).disabled(!model.scoreReady)
                .help(model.scoreReady ? "切换节拍器" : model.scoreAvailabilityReason)

            Button {
                onToggleFocus?()
            } label: {
                Label(isFocused ? "退出全屏" : "全屏", systemImage: isFocused ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
            }
            .buttonStyle(NativePlayerPillButtonStyle())
            .disabled(onToggleFocus == nil)
            .help(onToggleFocus == nil ? "此播放器尚未连接专注阅谱状态" : isFocused ? "退出全屏阅谱" : "全屏阅谱")
        }
        .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var playerToolbar: some View {
        VStack(spacing: 0) {
            transportBar.animation(motionPolicy.controlAnimation, value: isFocused)
            NativePlayerPositionBar(positionState: model.positionState, canSeek: model.canPlay) { model.seek(toRatio: $0) }
            settingsBar
        }
        .background(LinearGradient(colors: [Color(hex: 0xFBF9F4), Color(hex: 0xF5EFE4)], startPoint: .top, endPoint: .bottom))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color(hex: 0xE2D8C3), lineWidth: 1))
        .overlay(alignment: .topLeading) { RoundedRectangle(cornerRadius: 1).fill(Color(hex: 0xC49A45).opacity(0.55)).frame(width: 20, height: 2).padding(.leading, 12).padding(.top, 12) }
        .overlay(alignment: .topTrailing) { RoundedRectangle(cornerRadius: 1).fill(Color(hex: 0xC49A45).opacity(0.55)).frame(width: 20, height: 2).padding(.trailing, 12).padding(.top, 12) }
        .padding(.horizontal, 8).padding(.top, 8).padding(.bottom, 8)
    }

    private var settingsBar: some View {
        NativePlayerFlowLayout(horizontalSpacing: 7, verticalSpacing: 6) {
            settingsButton(.performance, title: "演奏", symbol: "guitars")
            settingsButton(.display, title: "显示", symbol: "rectangle.inset.filled")
            settingsButton(.tracks, title: "音轨", symbol: "slider.horizontal.3")
            settingsButton(.fretboard, title: "指板", symbol: "pianokeys")
            settingsButton(.practice, title: "练习面板", symbol: "metronome")
            settingsButton(.export, title: "导出", symbol: "square.and.arrow.up")
            Menu {
                Button { selectPanel(.review) } label: { Label("练习回顾", systemImage: PlayerPanel.review.symbol) }
                Button { selectPanel(.manuscript) } label: { Label("手稿与分页", systemImage: PlayerPanel.manuscript.symbol) }
            } label: {
                Label("更多", systemImage: "ellipsis")
            }
            .buttonStyle(NativePlayerPillButtonStyle())
            .menuStyle(.borderlessButton)
            .help("打开练习回顾或手稿分页")
        }
        .padding(.horizontal, 12).padding(.top, 4).padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func settingsButton(_ panel: PlayerPanel, title: String, symbol: String) -> some View {
        let isSelected = !isPanelCollapsed && selectedPanel == panel
        return Button { selectPanel(panel) } label: {
            Label(title, systemImage: symbol)
                .font(MIMITheme.bodyFont(size: 12, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? MIMITheme.darkGold : MIMITheme.bodyInk)
                .padding(.horizontal, 11)
                .frame(minHeight: 34)
                .background(isSelected ? MIMITheme.warmGold.opacity(0.13) : Color(hex: 0xFBF9F4), in: Capsule())
                .overlay(Capsule().stroke(isSelected ? MIMITheme.warmGold.opacity(0.46) : MIMITheme.softBorder, lineWidth: 1))
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
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(selectedPanel.title, systemImage: selectedPanel.symbol)
                    .font(MIMITheme.bodyFont(size: 12, weight: .semibold)).foregroundStyle(MIMITheme.ink)
                Spacer(minLength: 0)
                Button { isPanelCollapsed = true } label: { Label("收起", systemImage: "chevron.down") }
                    .buttonStyle(NativePlayerPillButtonStyle()).help("收起当前播放器设置面板")
            }
            .padding(.horizontal, 2)
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
        .background(Color(hex: 0xFBF9F4), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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

private struct NativePlayerPillButtonStyle: ButtonStyle {
    var prominent = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("mimi.motion.preference") private var motionPreference = "system"

    private var motionPolicy: MIMIMotionPolicy {
        MIMIMotionPolicy.resolve(preference: motionPreference, reduceMotion: reduceMotion)
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(prominent ? Color.white : MIMITheme.bodyInk)
            .padding(.horizontal, 12)
            .frame(minHeight: 36)
            .background(Capsule(style: .continuous).fill(prominent
                ? MIMITheme.ink
                : (configuration.isPressed ? Color(hex: 0xEEE5D7) : Color(hex: 0xFBF9F4))))
            .overlay(Capsule(style: .continuous).stroke(prominent ? MIMITheme.ink : MIMITheme.softBorder, lineWidth: 1))
            .opacity(isEnabled ? 1 : 0.46)
            .scaleEffect(configuration.isPressed && motionPolicy.allowsSpatialMotion ? 0.98 : 1)
            .animation(motionPolicy.controlAnimation, value: configuration.isPressed)
    }
}

private struct NativePlayerTogglePillStyle: ToggleStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("mimi.motion.preference") private var motionPreference = "system"

    private var motionPolicy: MIMIMotionPolicy {
        MIMIMotionPolicy.resolve(preference: motionPreference, reduceMotion: reduceMotion)
    }

    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            configuration.label
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(configuration.isOn ? Color.white : MIMITheme.bodyInk)
                .padding(.horizontal, 12)
                .frame(minHeight: 36)
                .background(Capsule(style: .continuous).fill(configuration.isOn ? MIMITheme.ink : Color(hex: 0xFBF9F4)))
                .overlay(Capsule(style: .continuous).stroke(configuration.isOn ? MIMITheme.ink : MIMITheme.softBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.46)
        .animation(motionPolicy.controlAnimation, value: configuration.isOn)
    }
}

private enum PlayerPanel: String, CaseIterable, Identifiable {
    case performance, display, tracks, fretboard, practice, export, manuscript, review
    var id: String { rawValue }
    var title: String {
        switch self {
        case .performance: return "演奏设置"
        case .display: return "显示设置"
        case .tracks: return "音轨与音色"
        case .fretboard: return "实时指板"
        case .practice: return "练习面板"
        case .export: return "导出与打印"
        case .manuscript: return "手稿与分页"
        case .review: return "回顾"
        }
    }
    var symbol: String {
        switch self {
        case .performance: return "guitars"
        case .display: return "rectangle.inset.filled"
        case .tracks: return "slider.horizontal.3"
        case .fretboard: return "guitars"
        case .practice: return "metronome"
        case .export: return "square.and.arrow.up"
        case .manuscript: return "doc.text.image"
        case .review: return "chart.bar.xaxis"
        }
    }
}

private struct NativePlayerFlowLayout: Layout {
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

@MainActor
private struct NativePlayerPositionBar: View {
    @ObservedObject var positionState: NativePlayerPositionState
    let canSeek: Bool
    let onSeek: (Double) -> Void
    @State private var isScrubbing = false
    @State private var scrubRatio = 0.0

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: positionState.sample?.isPlaying != true)) { _ in
            let now = ProcessInfo.processInfo.systemUptime
            let sample = positionState.sample
            let duration = sample?.durationMs ?? 0
            let liveTime = sample?.time(at: now) ?? 0
            let liveRatio = duration > 0 ? min(1, max(0, liveTime / duration)) : 0
            let displayedRatio = isScrubbing ? scrubRatio : liveRatio

            HStack(spacing: 10) {
                Text(Self.timeLabel(duration * displayedRatio))
                    .font(.system(size: 12, weight: .medium, design: .monospaced).monospacedDigit())
                    .foregroundStyle(MIMITheme.mutedInk).frame(width: 58, alignment: .trailing)

                Slider(value: Binding(
                    get: { isScrubbing ? scrubRatio : liveRatio },
                    set: { scrubRatio = min(1, max(0, $0)) }
                ), in: 0...1) { editing in
                    if editing {
                        scrubRatio = liveRatio
                        isScrubbing = true
                    } else {
                        let requestedRatio = scrubRatio
                        isScrubbing = false
                        onSeek(requestedRatio)
                    }
                }
                .disabled(!canSeek || duration <= 0)
                .tint(MIMITheme.terracotta)
                .help(canSeek && duration > 0 ? "拖动以定位到曲谱时间" : "曲谱或音频尚未就绪，无法定位")

                Text(Self.timeLabel(duration))
                    .font(.system(size: 12, weight: .medium, design: .monospaced).monospacedDigit())
                    .foregroundStyle(MIMITheme.mutedInk).frame(width: 58, alignment: .leading)

                Text(Self.positionLabel(bar: sample?.bar, beat: sample?.beat))
                    .font(MIMITheme.bodyFont(size: 12)).foregroundStyle(MIMITheme.mutedInk)
                    .frame(width: 164, alignment: .trailing)
                    .lineLimit(1)
                    .help("拍号未知时显示短横线；首拍从1计数")
            }
            .padding(.horizontal, 15).padding(.top, 2).padding(.bottom, 6)
        }
    }

    private static func timeLabel(_ milliseconds: Double) -> String {
        let totalSeconds = max(0, Int(milliseconds.isFinite ? milliseconds / 1_000 : 0))
        return "\(totalSeconds / 60):\(String(format: "%02d", totalSeconds % 60))"
    }

    private static func positionLabel(bar: Int?, beat: Int?) -> String {
        guard let bar, bar > 0 else { return "小节 — · 拍 —" }
        let beatLabel = beat.flatMap { $0 > 0 ? String($0) : nil } ?? "—"
        return "第 \(bar) 小节 · 第 \(beatLabel) 拍"
    }
}

enum NativePlayerSourceKind: String {
    case ibe
    case guitarPro = "gp"
    case musicXML = "musicxml"
    case json
    case xhe
}

struct NativePlayerSource {
    let url: URL
    let kind: NativePlayerSourceKind
    let isImported: Bool
}

@MainActor
final class NativePlayerModel: ObservableObject {
    @Published var item: CatalogItem?
    @Published var personalScore: PersonalScore?
    @Published var mode: NativePlayerMode
    @Published var webViewIdentity = UUID()
    @Published var source: NativePlayerSource?
    @Published var sourceError: String?
    @Published var playerRootError: String?
    @Published var playerError: String?
    @Published var statusMessage = "等待本地谱面引擎…"
    @Published var isLoading = false
    @Published var isLoadingSound = false
    @Published var soundProgress: Double?
    @Published var scoreReady = false
    @Published var audioReady = false
    @Published var isPlaying = false
    @Published var tempo: Double
    @Published var sourceTempo: Double
    @Published var zoom = 1.0
    var currentTime: Double = 0
    var endTime: Double = 0
    @Published var metadataTitle: String
    @Published var metadataArtist: String
    @Published var metadataAlbum = ""
    @Published var metadataKey = ""
    @Published var metadataTuning = ""
    var seekRatio: Double = 0
    var currentTick: Double = 0
    @Published var scoreEndTick = 0
    @Published var currentBar = 0
    @Published var currentBeat = 0
    @Published var currentBeatEndTick = 0
    var currentTickIsSeek = false
    @Published var currentBeatNotes: [NativeFretNote] = []
    @Published var currentBeatChord = ""
    @Published var playedBeatSequence = 0
    @Published var currentPage = 1
    @Published var pageCount = 1
    @Published var barCount = 1
    @Published var manuscriptMessage = ""
    @Published var tracks: [NativePlayerTrack] = []
    @Published var gmInstruments: [NativeGMInstrument] = []
    @Published var displayMode = "mixed"
    @Published var numberTab = true
    @Published var chordMode = "diagram"
    @Published var showFretboard = false
    @Published var capo = 0
    @Published var useSourceCapo = true
    @Published var transpose = 0
    @Published var metronome = false
    @Published var countIn = false
    @Published var loopRange: PracticeTickRange?
    @Published var loopPointA: (tick: Int, beatEndTick: Int)?
    @Published var practiceItem: PracticeItem?
    @Published var practiceFragments: [PracticeFragment] = []
    @Published var practiceSessions: [PracticeSession] = []
    @Published var activePracticeSession: PracticeSession?
    @Published var resume: PlayerResume?
    @Published var outdatedResume: PlayerResume?
    @Published var practiceNoteDraft = ""
    @Published var saveError: String?
    @Published var practiceOperationError: String?
    @Published var practiceSpeedPlan: PracticeSpeedPlan?
    @Published var loopLapCount = 0
    @Published var practiceDataReady = false
    @Published var practiceJoined = false
    @Published var practiceBusy = false
    @Published var appIsActive = true
    @Published var nativeViewVisible = false
    @Published var audioFocusOwned = false
    @Published var resumeWritePending = false

    let contentRoot: URL
    let personalStore: PersonalStore
    let onPersonalDataChanged: @MainActor () -> Void
    fileprivate let positionState = NativePlayerPositionState()

    var playbackPositionChanges: AnyPublisher<Void, Never> {
        positionState.playbackPositionChanges
    }
    private let importedFileURL: URL?
    private var selectedImportedURL: URL?
    private var currentLoadID: String?
    private var playerPageReady = false
    private var pageViewportWidth: Double?
    private var motionPreference = "full"
    private var fretboardPreviewToken = UUID()
    private var readinessTimeout: DispatchWorkItem?
    private var practiceTimer: Timer?
    private var practiceSliceStartUptime: TimeInterval?
    private var practiceSliceStartWallMs: Double?
    private var practiceSliceSequence = 0
    private var practiceEpoch = UUID().uuidString
    private var practiceGeneration = 0
    private var lastResumeCheckpointUptime: TimeInterval?
    private var lastSeenLapID = ""
    private var scoreRevision = ""
    private var scoreIdentity = ""
    private var scoreSource: String = "catalog"
    private var expectedNoteAtEdit: String?
    private var practiceSpeedStart: Double = 60
    private var practiceSpeedTarget: Double = 90
    private var practiceSpeedStep: Double = 5
    private var practiceLapsPerLevel: Int = 3
    private var playbackSpeedRatio = 1.0
    private var pendingSeek: (targetTick: Double, targetTimeMs: Double, requestedAtUptime: TimeInterval)?
    private var positionFence: (timeMs: Double, tick: Double?, expiresAtUptime: TimeInterval, isPlaying: Bool)?
    private var pendingTempoRequest: (targetBpm: Double, speedRatio: Double, requestedAtUptime: TimeInterval)?
    private var tempoPositionFence: (speedRatio: Double, tick: Double?, expiresAtUptime: TimeInterval, isPlaying: Bool)?
    private var rejectedTempoAnchor: (timeMs: Double?, durationMs: Double?, speedRatio: Double, tick: Double?, receivedAtUptime: TimeInterval)?
    private var didReceiveInitialSourceTempo = false
    private var hasExplicitTempoSelection = false
    private var pendingAuditionPlay = false
    private var onReady: (() -> Void)?
    private var resumeDirty = false
    private var lastResumeWriteUptime: TimeInterval?
    private var pendingResumeValue: PlayerResume?
    private var lastSaveRetry: (() -> Void)?
    weak var webView: WKWebView?

    init(
        item: CatalogItem?,
        personalScore: PersonalScore?,
        contentRoot: URL,
        personalStore: PersonalStore,
        importedFileURL: URL?,
        mode: NativePlayerMode,
        onPersonalDataChanged: @escaping @MainActor () -> Void = {}
    ) {
        self.item = item
        self.personalScore = personalScore
        self.mode = mode
        self.contentRoot = contentRoot
        self.personalStore = personalStore
        self.onPersonalDataChanged = onPersonalDataChanged
        self.importedFileURL = importedFileURL
        selectedImportedURL = importedFileURL
        let initialTempo = Double(item?.bpm ?? 80)
        tempo = min(300, max(20, initialTempo))
        sourceTempo = initialTempo > 0 ? initialTempo : 80
        metadataTitle = personalScore?.title ?? item?.title ?? ""
        metadataArtist = personalScore?.artist ?? item?.artist ?? ""
        if PlayerBundleAssets.rootURL() == nil {
            playerRootError = "未找到应用自带的 Resources/Player 文件。请从打包后的 MIMI Guitar.app 启动。"
        }
        if let personalScore {
            loadPersonalScore(personalScore)
        } else if let item {
            open(item: item, autoplay: false)
        } else if let importedFileURL {
            do {
                source = try Self.resolveImportedSource(importedFileURL)
                scoreIdentity = "import:\(source?.url.lastPathComponent ?? UUID().uuidString)"
                scoreSource = "private"
                computeRevision(for: source!)
            } catch { sourceError = error.localizedDescription }
        }
        if PlayerBundleAssets.rootURL() == nil { statusMessage = "未找到本地播放器资源" }
    }

    var isXhe: Bool { source?.kind == .xhe }
    var isScoreSource: Bool {
        source?.kind == .ibe || source?.kind == .guitarPro || source?.kind == .musicXML
    }
    var activeCapo: Int { useSourceCapo ? (primaryTrack?.sourceCapo ?? 0) : capo }
    var primaryTrack: NativePlayerTrack? { tracks.first(where: { !$0.percussion && !$0.tuning.isEmpty }) ?? tracks.first }
    var displayKey: String {
        if let key = item?.key, !key.isEmpty { return key }
        let keys = ["C", "G", "D", "A", "E", "B", "F♯", "C♯", "F", "B♭", "E♭", "A♭", "D♭", "G♭", "C♭"]
        if let signature = Int(metadataKey), (-7...7).contains(signature) { return signature >= 0 ? keys[signature] : keys[7 + abs(signature)] }
        return "C"
    }
    var manuscriptScreenshotURL: URL? {
        guard let reference = item?.screenshotURL, !reference.isEmpty else { return nil }
        return try? AppPaths.resolve(reference: reference, contentRoot: contentRoot)
    }
    var canPlay: Bool { isScoreSource && scoreReady && audioReady && playerError == nil }
    var canSeek: Bool { canPlay && scoreEndTick > 0 }
    var playDisabledReason: String {
        if let playerError { return "无法播放：\(playerError)" }
        if isXhe { return "文本和弦谱不含可播放音轨。" }
        if !isScoreSource { return "当前曲谱格式没有本地数字播放能力。" }
        if !scoreReady { return scoreAvailabilityReason }
        if !audioReady { return "曲谱已载入，等待本地音源加载完成。" }
        return "当前播放功能暂不可用。"
    }
    var scoreAvailabilityReason: String {
        if let sourceError { return sourceError }
        if let playerError { return playerError }
        if isXhe { return "XHE 是文本和弦谱，不提供电子谱面、音轨和实时指板设置。" }
        if source == nil { return isLoading ? statusMessage : "曲谱来源尚未载入。" }
        return isLoading ? statusMessage : "曲谱渲染引擎尚未就绪。"
    }
    var practiceAvailabilityReason: String {
        if isTemporaryLocalImport { return "临时导入的文件不会自动加入个人练习记录。" }
        if !canPlay { return playDisabledReason }
        if scoreRevision.count != 64 { return "本地曲谱校验尚未完成。" }
        return "该曲谱尚未加入练习资料。"
    }
    var exportAvailabilityReason: String {
        if let sourceError { return sourceError }
        if source == nil { return "曲谱来源尚未载入。" }
        if isXhe { return "XHE 可保存原件或打印；文本和弦谱不支持 PDF 或谱面长图导出。" }
        if let playerError { return playerError }
        if !scoreReady { return isLoading ? statusMessage : "等待完整谱面渲染完成。" }
        return "当前导出功能不可用。"
    }
    var isTemporaryLocalImport: Bool { selectedImportedURL != nil && personalScore == nil && item == nil }
    var canJoinPractice: Bool {
        canPlay && scoreRevision.count == 64 && !isTemporaryLocalImport && (personalScore != nil || item != nil)
    }
    var canExport: Bool {
        source != nil && (scoreReady || (isXhe && !isLoading && sourceError == nil && playerError == nil))
    }
    var canExportRenderedScore: Bool { canExport && !isXhe }
    var tempoRange: ClosedRange<Double> {
        let low = min(300, max(20, sourceTempo * 0.125))
        let high = min(300, max(20, sourceTempo * 8))
        return low...max(low, high)
    }

    var playbackClock: String {
        guard endTime > 0 else { return "0:00 / 0:00" }
        return "\(Self.clock(currentTime)) / \(Self.clock(endTime))"
    }

    func connect(_ webView: WKWebView) {
        self.webView = webView
    }

    func setPageViewportWidth(_ width: Double) {
        guard width.isFinite, width > 0 else { return }
        if let pageViewportWidth, abs(pageViewportWidth - width) <= 0.5 { return }
        pageViewportWidth = width
        guard playerPageReady else { return }
        send("setViewportWidth", arguments: ["width": width])
    }

    func setMotionPreference(_ value: String) {
        guard ["full", "gentle", "off"].contains(value) else { return }
        guard motionPreference != value else { return }
        motionPreference = value
        if playerPageReady { send("setMotionPreference", arguments: ["mode": value]) }
    }

    func pageLoadStarted() {
        playerPageReady = false
        isLoading = true
        statusMessage = "启动本地谱面引擎…"
        startReadinessTimeout()
    }

    func pageNavigationFailed(_ message: String) {
        isLoading = false
        isLoadingSound = false
        playerError = "本地谱面页面加载失败：\(message)"
        statusMessage = "本地谱面页面加载失败"
        cancelReadinessTimeout()
    }

    func pageDidBecomeReady() {
        guard let source else { return }
        playerPageReady = true
        resetPositionSample()
        let loadID = UUID().uuidString
        currentLoadID = loadID
        startReadinessTimeout()
        playerError = nil
        isLoading = true
        isLoadingSound = false
        scoreReady = false
        currentPage = 1
        pageCount = 1
        barCount = 1
        audioReady = false
        isPlaying = false
        statusMessage = "读取本地谱面…"
        if let pageViewportWidth {
            send("setViewportWidth", arguments: ["width": pageViewportWidth])
        }
        send("load", arguments: [
            "loadID": loadID,
            "kind": source.kind.rawValue,
            "title": metadataTitle,
            "artist": metadataArtist,
            "bpm": Int(sourceTempo),
        ])
        send("setMotionPreference", arguments: ["mode": motionPreference])
    }

    func receive(_ body: Any) {
        guard let event = body as? [String: Any], let type = event["type"] as? String else { return }
        if type != "ready" {
            guard let loadID = event["loadID"] as? String, loadID == currentLoadID else { return }
        }
        switch type {
        case "ready":
            pageDidBecomeReady()
        case "stage":
            if let value = event["value"] as? String { statusMessage = value }
        case "fileProgress":
            guard let loaded = event["loaded"] as? Double, let total = event["total"] as? Double,
                  loaded >= 0, total > 0 else { return }
            statusMessage = "读取谱面 \(Int((loaded / total * 100).rounded()))%"
        case "scoreMetadata":
            if let value = event["title"] as? String, !value.isEmpty { metadataTitle = value }
            if let value = event["artist"] as? String, !value.isEmpty { metadataArtist = value }
            if let value = event["album"] as? String { metadataAlbum = value }
            if let value = event["key"] as? String { metadataKey = value }
            if let value = event["tuning"] as? String { metadataTuning = value }
            if let value = event["sourceTempo"] as? Double, value > 0 {
                sourceTempo = value
                if !didReceiveInitialSourceTempo {
                    didReceiveInitialSourceTempo = true
                    if !hasExplicitTempoSelection {
                        let preferredTempo = Double(item?.bpm ?? Int(value))
                        tempo = min(tempoRange.upperBound, max(tempoRange.lowerBound, preferredTempo))
                    }
                }
            }
            if let value = event["barCount"] as? Int { barCount = max(1, value) }
        case "tempo":
            let now = ProcessInfo.processInfo.systemUptime
            let originalTempo = Self.eventNumber(event, "originalTempo")
            let modifiedTempo = Self.eventNumber(event, "modifiedTempo")
            let actualTempo = Self.eventNumber(event, "actual")
            let acknowledgedTempo = modifiedTempo ?? actualTempo
            let originalForRatio = originalTempo ?? sourceTempo
            let targetForRatio = acknowledgedTempo ?? tempo
            let speedRatio = Self.eventSpeedRatio(event) ?? (originalForRatio > 0 ? targetForRatio / originalForRatio : playbackSpeedRatio)
            let eventTime = Self.eventNumber(event, "timeMs") ?? Self.eventNumber(event, "currentTime")
            let eventDuration = Self.eventNumber(event, "durationMs") ?? Self.eventNumber(event, "endTime")
            let eventTick = Self.eventNumber(event, "tick")
            guard acceptsTempoAcknowledgement(tempo: acknowledgedTempo, speedRatio: speedRatio, now: now) else {
                rejectedTempoAnchor = (eventTime, eventDuration, speedRatio, eventTick, now)
                break
            }
            rejectedTempoAnchor = nil
            if let originalTempo, originalTempo > 0 { sourceTempo = originalTempo }
            if let acknowledgedTempo, acknowledgedTempo > 0 {
                tempo = acknowledgedTempo
                let initialTarget = Double(item?.bpm ?? Int(sourceTempo))
                if abs(acknowledgedTempo - initialTarget) > 0.5 { hasExplicitTempoSelection = true }
            }
            let resolvedTime: Double?
            if pendingSeek != nil {
                resolvedTime = resolvePendingPosition(timeMs: eventTime, tick: eventTick, isSeek: false, now: now)
            } else {
                positionFence = nil
                resolvedTime = eventTime ?? positionState.interpolatedTime(at: now)
            }
            playbackSpeedRatio = speedRatio
            if let resolvedTime {
                positionFence = nil
                reanchorPosition(timeMs: resolvedTime, durationMs: Self.eventNumber(event, "durationMs"), speedRatio: speedRatio, tick: eventTick, isPlaying: isPlaying, receivedAtUptime: now)
            }
            if eventTime != nil || eventTick != nil {
                tempoPositionFence = (speedRatio, eventTick, now + 1.25, isPlaying)
            }
        case "tempoSyncFailed":
            let now = ProcessInfo.processInfo.systemUptime
            let actualTempo = Self.eventNumber(event, "actualTempo")
            let fallbackRatio = actualTempo.flatMap { sourceTempo > 0 ? $0 / sourceTempo : nil }
            let speedRatio = Self.eventSpeedRatio(event) ?? fallbackRatio ?? playbackSpeedRatio
            let eventTime = Self.eventNumber(event, "timeMs") ?? Self.eventNumber(event, "currentTime")
            let eventDuration = Self.eventNumber(event, "durationMs") ?? Self.eventNumber(event, "endTime")
            let eventTick = Self.eventNumber(event, "tick")
            let failedAnchor = rejectedTempoAnchor.flatMap { anchor in
                abs(anchor.speedRatio - speedRatio) <= 0.01 ? anchor : nil
            }
            pendingTempoRequest = nil
            rejectedTempoAnchor = nil
            positionFence = nil
            tempoPositionFence = nil
            playbackSpeedRatio = speedRatio
            if let actualTempo, actualTempo > 0 {
                tempo = actualTempo
                hasExplicitTempoSelection = true
            }
            isPlaying = false
            releaseAudioFocus()
            if let timeMs = eventTime ?? failedAnchor?.timeMs {
                let tick = eventTick ?? failedAnchor?.tick
                let resolvedTime = resolvePendingPosition(timeMs: timeMs, tick: tick, isSeek: false, now: now)
                reanchorPosition(
                    timeMs: resolvedTime ?? positionState.interpolatedTime(at: now),
                    durationMs: eventDuration ?? failedAnchor?.durationMs,
                    speedRatio: speedRatio,
                    tick: resolvedTime == nil ? nil : tick,
                    isPlaying: false,
                    receivedAtUptime: failedAnchor?.receivedAtUptime ?? now
                )
                if pendingSeek == nil { setPositionFence(timeMs: currentTime, tick: currentTick, isPlaying: false, now: now) }
            } else {
                let localTime = positionState.interpolatedTime(at: now)
                reanchorPosition(timeMs: localTime, durationMs: endTime, speedRatio: speedRatio, tick: nil, isPlaying: false, receivedAtUptime: now)
                if pendingSeek == nil { setPositionFence(timeMs: currentTime, tick: currentTick, isPlaying: false, now: now) }
            }
            let detail = event["message"] as? String
            statusMessage = detail.map { "播放速度同步失败：\($0)" } ?? "播放速度同步失败，已按实际速度暂停。"
        case "scoreReady":
            scoreReady = true
            isLoading = false
            playerError = nil
            isLoadingSound = !audioReady
            statusMessage = audioReady ? "谱面与音源已就绪" : "谱面已载入，等待音源…"
            if audioReady { cancelReadinessTimeout() }
            notifyReadyIfPossible()
        case "xheReady":
            isLoading = false
            isLoadingSound = false
            scoreReady = false
            statusMessage = "文本和弦谱已载入；此格式不含音频播放。"
            cancelReadinessTimeout()
        case "playerReady":
            isLoadingSound = !audioReady
            statusMessage = audioReady ? "渲染器与音源已就绪" : "渲染器就绪，等待音源加载…"
        case "soundProgress":
            guard let loaded = event["loaded"] as? Double, let total = event["total"] as? Double,
                  total > 0 else { return }
            isLoadingSound = true
            soundProgress = min(1, max(0, loaded / total))
            statusMessage = "加载音源 \(Int((loaded / total * 100).rounded()))%"
        case "soundReady":
            audioReady = true
            isLoadingSound = false
            soundProgress = 1
            if scoreReady {
                statusMessage = "谱面与音源已就绪"
                cancelReadinessTimeout()
                notifyReadyIfPossible()
            } else {
                statusMessage = "音源就绪，正在载入谱面…"
            }
        case "soundError":
            isLoadingSound = false
            let message = event["message"] as? String ?? "音源加载失败。"
            playerError = message
            statusMessage = "音源加载失败：\(message)"
            cancelReadinessTimeout()
        case "playbackState":
            let state = event["state"] as? Int ?? 0
            let nextIsPlaying = event["isPlaying"] as? Bool ?? (state == 1)
            let preserveAudioFocus = event["preserveAudioFocus"] as? Bool ?? false
            let wasPlaying = isPlaying
            let now = ProcessInfo.processInfo.systemUptime
            let eventTime = Self.eventNumber(event, "timeMs") ?? Self.eventNumber(event, "currentTime")
            let eventTick = Self.eventNumber(event, "tick")
            let duration = Self.eventNumber(event, "durationMs") ?? endTime
            let speedRatio = Self.eventSpeedRatio(event) ?? playbackSpeedRatio
            let stopped = state == 2
            let resolvedTime: Double?
            if stopped {
                pendingSeek = nil
                positionFence = nil
                tempoPositionFence = nil
                currentTick = 0
                currentBar = 0
                currentBeat = 0
                currentBeatEndTick = 0
                resolvedTime = 0
            } else {
                let acceptAnchor = acceptsTempoCoordinate(speedRatio: Self.eventSpeedRatio(event), tick: eventTick, now: now, hasPendingSeek: pendingSeek != nil, isPlaying: nextIsPlaying)
                resolvedTime = acceptAnchor ? resolvePendingPosition(timeMs: eventTime, tick: eventTick, isSeek: false, now: now) : nil
            }
            isPlaying = nextIsPlaying
            if isPlaying {
                NativePlayerAudioFocus.claim(self) { [weak self] in self?.pausePlayback() }
                updateAudioFocusOwned(true)
            } else if preserveAudioFocus {
                updatePracticeActivity()
            } else {
                releaseAudioFocus()
            }
            if let resolvedTime {
                reanchorPosition(timeMs: resolvedTime, durationMs: duration, speedRatio: speedRatio, tick: stopped ? 0 : eventTick, isPlaying: isPlaying, receivedAtUptime: now)
            } else {
                let localTime = positionState.interpolatedTime(at: now)
                reanchorPosition(timeMs: localTime, durationMs: endTime, speedRatio: playbackSpeedRatio, tick: nil, isPlaying: isPlaying, receivedAtUptime: now)
            }
            if stopped || (wasPlaying && !isPlaying) {
                setPositionFence(timeMs: currentTime, tick: currentTick, isPlaying: false, now: now)
            }
        case "playbackFinished":
            isPlaying = false
            releaseAudioFocus()
            pendingSeek = nil
            positionFence = nil
            tempoPositionFence = nil
            let now = ProcessInfo.processInfo.systemUptime
            let duration = Self.eventNumber(event, "durationMs") ?? endTime
            let finishedTime = Self.eventNumber(event, "timeMs") ?? (duration > 0 ? duration : positionState.interpolatedTime(at: now))
            reanchorPosition(timeMs: finishedTime, durationMs: duration, speedRatio: Self.eventSpeedRatio(event) ?? playbackSpeedRatio, tick: Self.eventNumber(event, "tick"), isPlaying: false, receivedAtUptime: now)
            setPositionFence(timeMs: currentTime, tick: currentTick, isPlaying: false, now: now)
        case "position":
            let now = ProcessInfo.processInfo.systemUptime
            let eventTime = Self.eventNumber(event, "timeMs") ?? Self.eventNumber(event, "currentTime")
            let eventDuration = Self.eventNumber(event, "durationMs") ?? Self.eventNumber(event, "endTime")
            let eventTick = Self.eventNumber(event, "tick")
            let isSeek = event["isSeek"] as? Bool ?? false
            let speedRatio = Self.eventSpeedRatio(event)
            guard acceptsTempoCoordinate(speedRatio: speedRatio, tick: eventTick, now: now, hasPendingSeek: pendingSeek != nil, isPlaying: isPlaying) else { return }
            guard let resolvedTime = resolvePendingPosition(timeMs: eventTime, tick: eventTick, isSeek: isSeek, now: now) else { return }
            let nextDuration = eventDuration ?? endTime
            reanchorPosition(timeMs: resolvedTime, durationMs: nextDuration, speedRatio: speedRatio ?? playbackSpeedRatio, tick: eventTick, isPlaying: isPlaying, receivedAtUptime: now)

            if let value = eventTick {
                let next = max(0, value)
                if currentTick != next { currentTick = next }
            }
            if let value = Self.eventNumber(event, "endTick") {
                let next = max(0, Int(value))
                if scoreEndTick != next { scoreEndTick = next }
            }
            if currentTickIsSeek != isSeek { currentTickIsSeek = isSeek }
            if let beat = event["beat"] as? [String: Any] {
                let bar = Self.eventInt(beat, "bar").flatMap { $0 > 0 ? $0 : nil }
                let beatNumber = Self.eventInt(beat, "beat").flatMap { $0 > 0 ? $0 : nil }
                let nextBar = bar ?? 0
                let nextBeat = beatNumber ?? 0
                if currentBar != nextBar { currentBar = nextBar }
                if currentBeat != nextBeat { currentBeat = nextBeat }
                if let value = Self.eventInt(beat, "endTick"), currentBeatEndTick != value { currentBeatEndTick = value }
                let notes: [NativeFretNote] = (beat["notes"] as? [[String: Any]] ?? []).compactMap { note -> NativeFretNote? in
                    guard let string = note["string"] as? Int, let fret = note["fret"] as? Int else { return nil }
                    return NativeFretNote(string: string, fret: fret, midi: note["midi"] as? Int ?? 0, finger: note["finger"] as? Int)
                }
                if currentBeatNotes != notes { currentBeatNotes = notes }
                if let chord = beat["chord"] as? String, currentBeatChord != chord { currentBeatChord = chord }
                positionState.updateBeat(bar: bar, beat: beatNumber, replacingUnknowns: true)
            } else {
                currentBar = 0
                currentBeat = 0
                currentBeatEndTick = 0
                positionState.updateBeat(bar: nil, beat: nil, replacingUnknowns: true)
            }
            updatePracticeActivity()
        case "playedBeat":
            let bar = Self.eventInt(event, "bar").flatMap { $0 > 0 ? $0 : nil }
            let beat = (Self.eventInt(event, "beat") ?? Self.eventInt(event, "beatNumber"))
                .flatMap { $0 > 0 ? $0 : nil }
            if currentBar != (bar ?? 0) { currentBar = bar ?? 0 }
            if currentBeat != (beat ?? 0) { currentBeat = beat ?? 0 }
            positionState.updateBeat(bar: bar, beat: beat, replacingUnknowns: true)
            let notes: [NativeFretNote] = (event["notes"] as? [[String: Any]] ?? []).compactMap { note -> NativeFretNote? in
                guard let string = note["string"] as? Int, let fret = note["fret"] as? Int else { return nil }
                return NativeFretNote(string: string, fret: fret, midi: note["midi"] as? Int ?? 0, finger: note["finger"] as? Int)
            }
            if currentBeatNotes != notes { currentBeatNotes = notes }
            let chord = event["chord"] as? String ?? ""
            if currentBeatChord != chord { currentBeatChord = chord }
            playedBeatSequence += 1
        case "manuscript":
            pageCount = max(1, event["pageCount"] as? Int ?? pageCount)
            currentPage = min(pageCount, max(1, event["currentPage"] as? Int ?? currentPage))
        case "barSeek":
            if event["ok"] as? Bool == true {
                let bar = (event["barIndex"] as? Int ?? 0) + 1
                currentBar = bar
                manuscriptMessage = "已定位至第 \(bar) 小节。"
            } else {
                manuscriptMessage = event["message"] as? String ?? "无法定位到该小节。"
            }
        case "playerSnapshot", "tracks":
            receivePlayerSnapshot(event)
        case "loop":
            if let range = event["range"] as? [String: Any],
               let start = range["startTick"] as? Int, let end = range["endTick"] as? Int {
                loopRange = PracticeTickRange(startTick: start, endTick: end)
            } else { loopRange = nil }
            if let point = event["pointA"] as? [String: Any],
               let tick = point["tick"] as? Int, let end = point["beatEndTick"] as? Int {
                loopPointA = (tick, end)
            } else { loopPointA = nil }
            practiceSpeedPlan = practiceSpeedPlan.flatMap { plan in
                guard let range = loopRange,
                      plan.loopRange?.startTick == range.startTick,
                      plan.loopRange?.endTick == range.endTick else { return nil }
                return plan
            }
        case "loopLap":
            if let lapID = event["lapId"] as? String { handleLoopLap(lapID) }
        case "error":
            isPlaying = false
            isLoading = false
            isLoadingSound = false
            scoreReady = false
            audioReady = false
            resetPositionSample()
            let message = event["message"] as? String ?? "谱面载入失败。"
            playerError = message
            statusMessage = message
            cancelReadinessTimeout()
        default:
            break
        }
    }

    private func resetPositionSample() {
        pendingSeek = nil
        positionFence = nil
        pendingTempoRequest = nil
        tempoPositionFence = nil
        rejectedTempoAnchor = nil
        currentTime = 0
        endTime = 0
        seekRatio = 0
        currentTick = 0
        scoreEndTick = 0
        currentBar = 0
        currentBeat = 0
        currentBeatEndTick = 0
        currentTickIsSeek = false
        playbackSpeedRatio = 1
        isPlaying = false
        positionState.clear()
    }

    private func reanchorPosition(
        timeMs: Double,
        durationMs: Double?,
        speedRatio: Double,
        tick: Double?,
        isPlaying: Bool,
        receivedAtUptime: TimeInterval
    ) {
        guard timeMs.isFinite else { return }
        let knownDuration = durationMs.flatMap { $0.isFinite && $0 > 0 ? $0 : nil } ?? endTime
        let boundedTime = max(0, knownDuration > 0 ? min(knownDuration, timeMs) : timeMs)
        let safeSpeedRatio = speedRatio.isFinite && speedRatio > 0 ? speedRatio : playbackSpeedRatio
        currentTime = boundedTime
        if knownDuration > 0 { endTime = knownDuration }
        if let tick, tick.isFinite { currentTick = max(0, tick) }
        playbackSpeedRatio = safeSpeedRatio
        seekRatio = endTime > 0 ? min(1, max(0, boundedTime / endTime)) : 0
        positionState.reanchor(
            timeMs: boundedTime,
            durationMs: endTime,
            speedRatio: safeSpeedRatio,
            isPlaying: isPlaying,
            tick: tick ?? (currentTick > 0 ? currentTick : nil),
            bar: currentBar > 0 ? currentBar : nil,
            beat: currentBeat > 0 ? currentBeat : nil,
            receivedAtUptime: receivedAtUptime
        )
    }

    private func resolvePendingPosition(
        timeMs: Double?,
        tick: Double?,
        isSeek: Bool,
        now: TimeInterval
    ) -> Double? {
        if let pendingSeek {
            if isSeek {
                self.pendingSeek = nil
                return timeMs ?? pendingSeek.targetTimeMs
            }
            let age = max(0, now - pendingSeek.requestedAtUptime)
            let tickMatches = tick.map { abs($0 - pendingSeek.targetTick) <= 192 } ?? false
            let timeMatches = timeMs.map { abs($0 - pendingSeek.targetTimeMs) <= 1_500 } ?? false
            if tickMatches || timeMatches {
                self.pendingSeek = nil
                return timeMs ?? pendingSeek.targetTimeMs
            }
            guard age >= 1.5 else { return nil }
            self.pendingSeek = nil
        }

        guard let positionFence else { return timeMs ?? positionState.interpolatedTime(at: now) }
        if now >= positionFence.expiresAtUptime {
            self.positionFence = nil
            return timeMs ?? positionState.interpolatedTime(at: now)
        }
        if let range = loopRange, let tick, let previousTick = positionFence.tick,
           previousTick >= Double(range.endTick - 192), tick <= Double(range.startTick + 192) {
            self.positionFence = nil
            return timeMs ?? positionState.interpolatedTime(at: now)
        }
        guard let timeMs else { return positionState.interpolatedTime(at: now) }
        if timeMs < positionFence.timeMs || !positionFence.isPlaying {
            return positionFence.timeMs
        }
        self.positionFence = nil
        return timeMs
    }

    private func acceptsTempoAcknowledgement(tempo: Double?, speedRatio: Double?, now: TimeInterval) -> Bool {
        guard let request = pendingTempoRequest else { return true }
        if max(0, now - request.requestedAtUptime) >= 3 {
            pendingTempoRequest = nil
            return true
        }

        let tempoMatches = tempo.map { abs($0 - request.targetBpm) <= 0.5 } ?? false
        let ratioMatches = speedRatio.map { abs($0 - request.speedRatio) <= 0.01 } ?? false
        let tempoIsCompatible = tempo == nil || tempoMatches
        let ratioIsCompatible = speedRatio == nil || ratioMatches
        guard (tempo != nil || speedRatio != nil), tempoIsCompatible, ratioIsCompatible else { return false }
        pendingTempoRequest = nil
        return true
    }

    private func acceptsTempoCoordinate(
        speedRatio: Double?,
        tick: Double?,
        now: TimeInterval,
        hasPendingSeek: Bool,
        isPlaying: Bool
    ) -> Bool {
        if let request = pendingTempoRequest {
            if max(0, now - request.requestedAtUptime) >= 3 {
                pendingTempoRequest = nil
            } else {
                guard let speedRatio, abs(speedRatio - request.speedRatio) <= 0.01 else { return false }
                pendingTempoRequest = nil
                tempoPositionFence = (request.speedRatio, tick, now + 1.25, isPlaying)
                return true
            }
        }

        guard let fence = tempoPositionFence else { return true }
        if now >= fence.expiresAtUptime {
            tempoPositionFence = nil
            return true
        }
        if let speedRatio, abs(speedRatio - fence.speedRatio) > 0.01 { return false }
        if fence.isPlaying, isPlaying, !hasPendingSeek, let tick, let anchorTick = fence.tick, tick < anchorTick { return false }
        tempoPositionFence = nil
        return true
    }

    private func setPositionFence(timeMs: Double, tick: Double?, isPlaying: Bool, now: TimeInterval) {
        guard timeMs.isFinite else { return }
        positionFence = (max(0, timeMs), tick, now + 0.55, isPlaying)
    }

    func tempoEditingChanged(_ editing: Bool) {
        if editing {
            hasExplicitTempoSelection = true
        } else {
            applyTempo()
        }
    }

    private static func eventNumber(_ event: [String: Any], _ key: String) -> Double? {
        guard let number = event[key] as? NSNumber else { return nil }
        let value = number.doubleValue
        return value.isFinite ? value : nil
    }

    private static func eventInt(_ event: [String: Any], _ key: String) -> Int? {
        guard let value = eventNumber(event, key), value >= Double(Int.min), value <= Double(Int.max) else { return nil }
        return Int(value.rounded(.towardZero))
    }

    private static func eventSpeedRatio(_ event: [String: Any]) -> Double? {
        if let ratio = eventNumber(event, "speedRatio"), ratio.isFinite, ratio > 0 { return ratio }
        guard let modified = eventNumber(event, "modifiedTempo"), modified > 0,
              let original = eventNumber(event, "originalTempo"), original > 0 else { return nil }
        return modified / original
    }

    func togglePlayback() {
        guard canPlay else { return }
        if isPlaying {
            pausePlayback()
        } else {
            cancelFretboardPreview()
            NativePlayerAudioFocus.claim(self) { [weak self] in self?.pausePlayback() }
            updateAudioFocusOwned(true)
            send("play")
        }
    }

    func stopPlayback() {
        guard canPlay else { return }
        cancelFretboardPreview()
        pendingSeek = nil
        positionFence = nil
        tempoPositionFence = nil
        send("stop")
        isPlaying = false
        releaseAudioFocus()
        currentTime = 0
        currentTick = 0
        currentBar = 0
        currentBeat = 0
        positionState.reanchor(timeMs: 0, durationMs: endTime, speedRatio: playbackSpeedRatio, isPlaying: false, tick: 0)
        seekRatio = 0
        setPositionFence(timeMs: 0, tick: 0, isPlaying: false, now: ProcessInfo.processInfo.systemUptime)
        updatePracticeActivity()
    }

    func applyTempo() {
        guard canPlay else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let ratio = sourceTempo > 0 ? tempo / sourceTempo : playbackSpeedRatio
        hasExplicitTempoSelection = true
        pendingTempoRequest = (tempo, ratio, now)
        positionFence = nil
        tempoPositionFence = nil
        rejectedTempoAnchor = nil
        send("setTempo", arguments: ["targetBpm": tempo])
    }

    func applyZoom() {
        guard isScoreSource && scoreReady else { return }
        send("setZoom", arguments: ["value": zoom])
    }

    func setMetronome(_ enabled: Bool) { metronome = enabled; send("setMetronome", arguments: ["enabled": enabled]); markResumeDirty() }
    func setCountIn(_ enabled: Bool) { countIn = enabled; send("setCountIn", arguments: ["enabled": enabled]); markResumeDirty() }
    func setCapo(_ value: Int, useSource: Bool) {
        capo = min(12, max(0, value)); useSourceCapo = useSource
        send("setCapo", arguments: ["value": capo, "useSource": useSource]); markResumeDirty()
    }
    func setTranspose(_ value: Int) {
        transpose = min(24, max(-24, value)); send("setTranspose", arguments: ["value": transpose]); markResumeDirty()
    }
    func setDisplayMode(_ value: String) { guard ["mixed", "tab"].contains(value) else { return }; displayMode = value; send("setDisplayMode", arguments: ["mode": value]); markResumeDirty() }
    func setNumberTab(_ value: Bool) { numberTab = value; send("setNumberTab", arguments: ["enabled": value]); markResumeDirty() }
    func setChordMode(_ value: String) { guard ["name", "diagram"].contains(value) else { return }; chordMode = value; send("setChordMode", arguments: ["mode": value]); markResumeDirty() }
    func setShowFretboard(_ value: Bool) { showFretboard = value; markResumeDirty() }

    func previewFret(string: Int, fret: Int) {
        guard scoreReady, let track = primaryTrack, !track.percussion else { return }
        if isPlaying { pausePlayback() }
        cancelFretboardPreview()
        NativePlayerAudioFocus.claim(self) { [weak self] in self?.cancelFretboardPreview() }
        currentBeatNotes = [NativeFretNote(string: string, fret: fret, midi: 0)]
        startFretboardPreview("previewFret", arguments: [
            "string": string, "fret": fret, "tuning": track.tuning,
            "capo": activeCapo, "transpose": transpose, "program": track.program,
            "flavor": track.tuning.count == 4 || track.program == 24 ? "ukulele" : "gm",
        ])
    }

    func previewChordNotes(_ notes: [NativeFretNote]) {
        guard scoreReady, let track = primaryTrack, !track.percussion, !notes.isEmpty else { return }
        if isPlaying { pausePlayback() }
        cancelFretboardPreview()
        NativePlayerAudioFocus.claim(self) { [weak self] in self?.cancelFretboardPreview() }
        currentBeatNotes = notes
        let values = notes.map { note -> [String: Any] in
            if note.midi > 0 { return ["midi": note.midi + transpose] }
            return ["string": note.string, "fret": note.fret]
        }
        startFretboardPreview("previewChord", arguments: [
            "notes": values, "tuning": track.tuning, "capo": activeCapo,
            "transpose": transpose, "program": track.program,
            "flavor": track.tuning.count == 4 || track.program == 24 ? "ukulele" : "gm",
            "direction": "down",
        ])
    }

    private func cancelFretboardPreview() {
        fretboardPreviewToken = UUID()
        send("cancelFretboardPreview")
        NativePlayerAudioFocus.release(self)
    }

    private func startFretboardPreview(_ method: String, arguments: [String: Any]) {
        guard let webView else { NativePlayerAudioFocus.release(self); return }
        let token = UUID()
        fretboardPreviewToken = token
        let script = method == "previewFret"
            ? "window.NativeGuitarAudio && window.NativeGuitarAudio.previewFret(payload)"
            : "window.NativeGuitarAudio && window.NativeGuitarAudio.previewChord(payload)"
        statusMessage = "正在载入音色并试听指板…"
        webView.callAsyncJavaScript(script, arguments: ["payload": arguments], in: nil, in: .page) { [weak self] result in
            DispatchQueue.main.async {
                guard let self, self.fretboardPreviewToken == token else { return }
                switch result {
                case .success:
                    self.statusMessage = "指板音符试听完成"
                case .failure(let error):
                    self.statusMessage = "指板试听失败：\(error.localizedDescription)"
                }
                NativePlayerAudioFocus.release(self)
            }
        }
    }

    func seekToBar(_ barIndex: Int) {
        guard canPlay, barIndex >= 0, barIndex < barCount else { return }
        send("seekBar", arguments: ["barIndex": barIndex])
    }

    func scrollToPage(_ page: Int) {
        guard scoreReady else { return }
        let next = min(pageCount, max(1, page))
        currentPage = next
        send("scrollToPage", arguments: ["page": next])
    }

    func openScreenshot() {
        guard let url = manuscriptScreenshotURL else { manuscriptMessage = "没有可打开的本地手稿扫描件。"; return }
        NSWorkspace.shared.open(url)
    }

    func exportScreenshot() {
        guard let source = manuscriptScreenshotURL else { manuscriptMessage = "没有可导出的本地手稿扫描件。"; return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: source.pathExtension) ?? .image]
        panel.nameFieldStringValue = "\(Self.safeFileName(metadataTitle))-原版手稿.\(source.pathExtension)"
        panel.begin { [weak self] response in
            guard response == .OK, let destination = panel.url else { return }
            do {
                if source.standardizedFileURL == destination.standardizedFileURL { return }
                try FileManager.default.copyItem(at: source, to: destination)
                DispatchQueue.main.async { self?.manuscriptMessage = "原版手稿已保存：\(destination.lastPathComponent)" }
            } catch {
                DispatchQueue.main.async { self?.manuscriptMessage = "原版手稿保存失败：\(error.localizedDescription)" }
            }
        }
    }
    func setTrack(_ track: NativePlayerTrack, field: String, value: Any) {
        send("setTrack", arguments: ["index": track.index, "field": field, "value": value])
        markResumeDirty()
    }
    func setLoopPoint(_ point: String) { send("setLoopPoint", arguments: ["which": point]) }
    func clearLoop() { send("clearLoop"); practiceSpeedPlan = nil; markResumeDirty() }
    func applyLoop(_ range: PracticeTickRange) {
        send("applyLoop", arguments: ["startTick": range.startTick, "endTick": range.endTick])
        markResumeDirty()
    }
    func restoreDefaults() { chordMode = "diagram"; send("restoreDefaults"); markResumeDirty() }

    func setNativeViewVisible(_ visible: Bool) {
        nativeViewVisible = visible
        if visible {
            NativePlayerAudioFocus.pauseCurrent(except: self)
        } else if isPlaying {
            pausePlayback()
        }
        if !visible { cancelFretboardPreview() }
        send("setNativeViewVisible", arguments: ["enabled": visible])
        if !visible { releaseAudioFocus() }
        updatePracticeActivity()
    }

    func setApplicationActive(_ active: Bool) {
        appIsActive = active
        if !active && isPlaying { pausePlayback() }
        updatePracticeActivity()
    }

    func setReadyHandler(_ handler: (() -> Void)?) { onReady = handler; notifyReadyIfPossible() }

    func open(item: CatalogItem, autoplay: Bool) {
        self.item = item
        personalScore = nil
        selectedImportedURL = nil
        pendingAuditionPlay = autoplay
        metadataTitle = item.title
        metadataArtist = item.artist ?? ""
        tempo = Double(item.bpm ?? 80)
        sourceTempo = tempo
        didReceiveInitialSourceTempo = false
        hasExplicitTempoSelection = false
        scoreIdentity = "catalog:\(item.id)"
        scoreSource = "catalog"
        sourceError = nil
        playerError = nil
        source = nil
        currentLoadID = nil
        resetPositionSample()
        scoreReady = false
        audioReady = false
        do {
            let resolved = try Self.resolveSource(item: item, contentRoot: contentRoot, importedFileURL: nil)
            source = resolved
            webViewIdentity = UUID()
            computeRevision(for: resolved)
            Task { [personalStore] in try? await personalStore.recordRecent(item.id) }
        } catch { sourceError = error.localizedDescription }
    }

    func playAudition() { pendingAuditionPlay = true; notifyReadyIfPossible() }
    func closeAudition() { pendingAuditionPlay = false; pausePlayback(); stopPlayback() }

    func restoreResume(_ value: PlayerResume) {
        guard value.scoreRevision == scoreRevision else {
            practiceOperationError = "最近断点来自旧谱面版本，已停用续练。"
            return
        }
        guard let encoded = try? JSONEncoder().encode(value),
              let object = (try? JSONSerialization.jsonObject(with: encoded)) as? [String: Any] else {
            practiceOperationError = "断点资料无法安全读取。"
            return
        }
        hasExplicitTempoSelection = true
        send("restoreResume", arguments: ["resume": object])
        markResumeDirty()
    }

    func exportPDF() {
        guard let webView, canExportRenderedScore else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "\(Self.safeFileName(metadataTitle)).pdf"
        let author = metadataArtist
        panel.begin { [weak self, weak webView] response in
            guard response == .OK, let url = panel.url, let self, let webView else { return }
            webView.callAsyncJavaScript(
                "return await window.NativePlayer.exportPdfPages(author)",
                arguments: ["author": author],
                in: nil,
                in: .page,
                completionHandler: { result in
                    guard case .success(let value) = result, let json = value as? String else {
                        let message: String
                        if case .failure(let error) = result { message = error.localizedDescription }
                        else { message = "没有收到分页谱面数据。" }
                        DispatchQueue.main.async { self.statusMessage = "PDF 导出失败：\(message)" }
                        return
                    }
                    DispatchQueue.global(qos: .userInitiated).async {
                        let data = Self.makePDF(json: json)
                        guard let data else {
                            DispatchQueue.main.async { self.statusMessage = "PDF 页面图像无效，未生成文件。" }
                            return
                        }
                        do {
                            try data.write(to: url, options: .atomic)
                            DispatchQueue.main.async { self.statusMessage = "PDF 已保存：\(url.lastPathComponent)" }
                        } catch {
                            DispatchQueue.main.async { self.statusMessage = "PDF 保存失败：\(error.localizedDescription)" }
                        }
                    }
                }
            )
        }
    }

    private nonisolated static func makePDF(json: String) -> Data? {
        guard let bytes = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any],
              let pageImages = object["pages"] as? [String],
              let width = object["widthPoints"] as? Double,
              let height = object["heightPoints"] as? Double,
              !pageImages.isEmpty, width.isFinite, height.isFinite, width > 0, height > 0 else { return nil }
        let output = NSMutableData()
        var mediaBox = CGRect(x: 0, y: 0, width: width, height: height)
        guard let consumer = CGDataConsumer(data: output as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return nil }
        for encoded in pageImages {
            guard let imageData = Data(base64Encoded: encoded),
                  let source = CGImageSourceCreateWithData(imageData as CFData, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                context.closePDF()
                return nil
            }
            context.beginPDFPage(nil)
            context.draw(image, in: mediaBox)
            context.endPDFPage()
        }
        context.closePDF()
        return output as Data
    }

    func exportOriginalSource() {
        guard let source else { return }
        let panel = NSSavePanel()
        let ext = source.url.pathExtension
        panel.allowedContentTypes = [UTType(filenameExtension: ext) ?? .data]
        panel.nameFieldStringValue = "\(Self.safeFileName(metadataTitle)).\(ext.isEmpty ? "score" : ext)"
        panel.canCreateDirectories = true
        panel.begin { [weak self] response in
            guard response == .OK, let destination = panel.url else { return }
            let origin = source.url
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let bytes = try Data(contentsOf: origin, options: .mappedIfSafe)
                    guard !bytes.isEmpty else { throw NativePlayerError.importMissing }
                    try bytes.write(to: destination, options: .atomic)
                    DispatchQueue.main.async { self?.statusMessage = "原谱原件已保存：\(destination.lastPathComponent)" }
                } catch {
                    DispatchQueue.main.async { self?.playerError = "原谱保存失败：\(error.localizedDescription)" }
                }
            }
        }
    }

    func seek(toRatio ratio: Double) {
        guard canPlay, scoreEndTick > 0, ratio.isFinite else { return }
        let next = min(1, max(0, ratio))
        let now = ProcessInfo.processInfo.systemUptime
        let targetTick = (Double(scoreEndTick) * next).rounded(.down)
        let targetTimeMs = max(0, endTime * next)
        pendingSeek = (targetTick, targetTimeMs, now)
        positionFence = nil
        currentTick = targetTick
        currentBar = 0
        currentBeat = 0
        reanchorPosition(timeMs: targetTimeMs, durationMs: endTime, speedRatio: playbackSpeedRatio, tick: targetTick, isPlaying: isPlaying, receivedAtUptime: now)
        seekRatio = next
        send("seek", arguments: ["tick": Int(targetTick)])
    }

    func pausePlayback() {
        let now = ProcessInfo.processInfo.systemUptime
        let currentPosition = positionState.interpolatedTime(at: now)
        send("pause")
        isPlaying = false
        reanchorPosition(timeMs: currentPosition, durationMs: endTime, speedRatio: playbackSpeedRatio, tick: currentTick, isPlaying: false, receivedAtUptime: now)
        setPositionFence(timeMs: currentPosition, tick: currentTick, isPlaying: false, now: now)
        releaseAudioFocus()
        updatePracticeActivity()
    }

    private func send(_ method: String, arguments: [String: Any] = [:]) {
        guard let webView else { return }
        let body: String
        switch method {
        case "load": body = "window.NativePlayer && window.NativePlayer.load(payload)"
        case "setViewportWidth": body = "window.NativePlayer && window.NativePlayer.setViewportWidth(payload.width)"
        case "setMotionPreference": body = "window.NativePlayer && window.NativePlayer.setMotionPreference(payload.mode)"
        case "playPause": body = "window.NativePlayer && window.NativePlayer.playPause()"
        case "play": body = "window.NativePlayer && window.NativePlayer.play()"
        case "pause": body = "window.NativePlayer && window.NativePlayer.pause()"
        case "stop": body = "window.NativePlayer && window.NativePlayer.stop()"
        case "seek": body = "window.NativePlayer && window.NativePlayer.seek(payload.tick)"
        case "setTempo": body = "window.NativePlayer && window.NativePlayer.setTempo(payload.targetBpm)"
        case "setZoom": body = "window.NativePlayer && window.NativePlayer.setZoom(payload.value)"
        case "setMetronome": body = "window.NativePlayer && window.NativePlayer.toggleMetronome(payload.enabled)"
        case "setCountIn": body = "window.NativePlayer && window.NativePlayer.toggleCountIn(payload.enabled)"
        case "setLoopPoint": body = "window.NativePlayer && window.NativePlayer.setLoopPoint(payload.which)"
        case "applyLoop": body = "window.NativePlayer && window.NativePlayer.applyLoop(payload.startTick, payload.endTick)"
        case "clearLoop": body = "window.NativePlayer && window.NativePlayer.clearLoop()"
        case "setTrack": body = "window.NativePlayer && window.NativePlayer.setTrack(payload.index, payload.field, payload.value)"
        case "setCapo": body = "window.NativePlayer && window.NativePlayer.setCapo(payload.value, payload.useSource)"
        case "setTranspose": body = "window.NativePlayer && window.NativePlayer.setTranspose(payload.value)"
        case "setDisplayMode": body = "window.NativePlayer && window.NativePlayer.setDisplayMode(payload.mode)"
        case "setNumberTab": body = "window.NativePlayer && window.NativePlayer.setNumberTab(payload.enabled)"
        case "setChordMode": body = "window.NativePlayer && window.NativePlayer.setChordMode(payload.mode)"
        case "setAudioFocus": body = "window.NativePlayer && window.NativePlayer.setAudioFocus(payload.enabled)"
        case "setNativeViewVisible": body = "window.NativePlayer && window.NativePlayer.setNativeViewVisible(payload.enabled)"
        case "restoreDefaults": body = "window.NativePlayer && window.NativePlayer.restoreDefaults()"
        case "restoreResume": body = "window.NativePlayer && window.NativePlayer.restoreResume(payload.resume)"
        case "createSpeedPlan": body = "window.NativePlayer && window.NativePlayer.createSpeedPlan(payload)"
        case "setSpeedPlan": body = "window.NativePlayer && window.NativePlayer.setSpeedPlan(payload.plan)"
        case "clearSpeedPlan": body = "window.NativePlayer && window.NativePlayer.clearSpeedPlan()"
        case "setStaticExport": body = "window.NativePlayer && window.NativePlayer.setStaticExport(payload.enabled)"
        case "seekBar": body = "window.NativePlayer && window.NativePlayer.seekBar(payload.barIndex)"
        case "scrollToPage": body = "window.NativePlayer && window.NativePlayer.scrollManuscriptToPage(payload.page)"
        case "previewFret": body = "window.NativeGuitarAudio && window.NativeGuitarAudio.previewFret(payload)"
        case "previewChord": body = "window.NativeGuitarAudio && window.NativeGuitarAudio.previewChord(payload)"
        case "cancelFretboardPreview": body = "window.NativeGuitarAudio && window.NativeGuitarAudio.cancel()"
        case "dispose": body = "window.NativePlayer && window.NativePlayer.dispose()"
        default: return
        }
        webView.callAsyncJavaScript(
            body,
            arguments: ["payload": arguments],
            in: nil,
            in: .page,
            completionHandler: { [weak self] result in
                if case .failure(let error) = result {
                    self?.playerError = error.localizedDescription
                    self?.isLoading = false
                    self?.isLoadingSound = false
                    self?.statusMessage = error.localizedDescription
                    self?.readinessTimeout?.cancel()
                    self?.readinessTimeout = nil
                }
            }
        )
    }

    private func startReadinessTimeout() {
        cancelReadinessTimeout()
        let timeout = DispatchWorkItem { [weak self] in
            guard let self, self.isLoading || self.isLoadingSound else { return }
            self.isLoading = false
            self.isLoadingSound = false
            self.audioReady = false
            self.currentLoadID = nil
            self.playerError = "本地谱面或音源加载超过 60 秒。"
            self.statusMessage = self.playerError ?? "本地谱面加载超时。"
            self.send("dispose")
        }
        readinessTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 60, execute: timeout)
    }

    private func cancelReadinessTimeout() {
        readinessTimeout?.cancel()
        readinessTimeout = nil
    }

    func loadPersonalScore(_ score: PersonalScore) {
        guard !["project", "studio", "mimi-project"].contains(score.format.lowercased()) else {
            sourceError = "这是工坊工程，请在制谱工坊中打开；工坊工程 JSON 不会作为 AlphaTab 谱面播放。"
            statusMessage = "请在制谱工坊中打开此工程"
            return
        }
        resetPositionSample()
        didReceiveInitialSourceTempo = false
        hasExplicitTempoSelection = false
        let suppliedCatalogItem = item
        personalScore = score
        item = nil
        scoreIdentity = score.id
        scoreSource = score.source
        metadataTitle = score.title
        metadataArtist = score.artist
        sourceError = nil
        playerError = nil
        source = nil
        scoreReady = false
        audioReady = false
        let expectedScoreID = score.id
        let currentContentRoot = contentRoot
        let suppliedImportedURL = importedFileURL
        Task { [weak self, personalStore] in
            do {
                var resolvedCatalogItem: CatalogItem?
                var verifiedAsset: (url: URL, byteCount: Int, hash: String)?
                var expectedAssetID: String?
                let resolved: NativePlayerSource

                if score.source == "catalog" {
                    let rawCatalogID = score.sourceId.hasPrefix("catalog:")
                        ? String(score.sourceId.dropFirst("catalog:".count))
                        : score.sourceId
                    let suppliedItemID = suppliedCatalogItem.map {
                        $0.id.hasPrefix("catalog:") ? String($0.id.dropFirst("catalog:".count)) : $0.id
                    }
                    let catalogItem: CatalogItem
                    if suppliedItemID == rawCatalogID, let suppliedCatalogItem {
                        catalogItem = suppliedCatalogItem
                    } else {
                        let catalogStore = try CatalogStore(databaseURL: AppPaths.catalogURL(contentRoot: currentContentRoot))
                        guard let found = try await catalogStore.item(id: rawCatalogID) else {
                            throw NativePlayerError.noScore
                        }
                        catalogItem = found
                    }
                    resolvedCatalogItem = catalogItem
                    // Catalog entries (including XHE-only rows) stay in the packaged Content/storage
                    // tree and are never mistaken for user imports that must live in Imports.
                    resolved = try Self.resolveSource(item: catalogItem, contentRoot: currentContentRoot, importedFileURL: nil)
                } else if let suppliedURL = suppliedImportedURL {
                    resolved = try Self.resolveImportedSource(suppliedURL, formatHint: score.format)
                } else if let assetID = score.assetId {
                    guard let asset = try await personalStore.asset(id: assetID) else {
                        throw NativePlayerError.assetMissing(assetID)
                    }
                    let ext = Self.fileExtension(for: score.format)
                    guard let ext else { throw NativePlayerError.unsupportedFormat(score.format) }
                    let assetBytes = asset.bytes
                    let expectedAssetRevision = score.revision
                    let materialized = try await Task.detached(priority: .userInitiated) {
                        try Self.materializePersonalAsset(assetBytes, assetID: assetID, expectedRevision: expectedAssetRevision, extensionName: ext)
                    }.value
                    resolved = try Self.resolveImportedSource(materialized.url, formatHint: score.format)
                    verifiedAsset = materialized
                    expectedAssetID = assetID
                } else if let reference = score.scoreUrl, !reference.isEmpty {
                    guard let storedURL = try? AppPaths.resolve(reference: reference, contentRoot: currentContentRoot) else {
                        throw NativePlayerError.noScore
                    }
                    resolved = try Self.resolveImportedSource(storedURL, formatHint: score.format)
                } else {
                    throw NativePlayerError.noScore
                }

                let fileInfo: (byteCount: Int, hash: String)
                if let verifiedAsset, verifiedAsset.url == resolved.url {
                    fileInfo = (verifiedAsset.byteCount, verifiedAsset.hash)
                } else {
                    let sourceURL = resolved.url
                    fileInfo = try await Task.detached(priority: .userInitiated) {
                        let values = try sourceURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
                        guard values.isRegularFile == true,
                              let size = values.fileSize, size > 0, size <= 30 * 1024 * 1024 else {
                            throw NativePlayerError.importSizeLimit
                        }
                        let bytes = try Data(contentsOf: sourceURL, options: .mappedIfSafe)
                        return (bytes.count, Self.sha256(bytes))
                    }.value
                }
                guard fileInfo.byteCount > 0, fileInfo.byteCount <= 30 * 1024 * 1024 else { throw NativePlayerError.importSizeLimit }
                if let expectedAssetID {
                    guard fileInfo.hash == expectedAssetID, fileInfo.hash == score.revision else {
                        throw NativePlayerError.assetRevisionMismatch
                    }
                }
                await MainActor.run {
                    guard let self, self.scoreIdentity == expectedScoreID else { return }
                    if let resolvedCatalogItem {
                        self.item = resolvedCatalogItem
                        self.metadataTitle = resolvedCatalogItem.title
                        self.metadataArtist = resolvedCatalogItem.artist ?? ""
                    }
                    self.source = resolved
                    self.scoreRevision = fileInfo.hash
                    self.tempo = Double(score.format.lowercased() == "xhe" ? 80 : (self.item?.bpm ?? Int(self.sourceTempo)))
                    self.sourceTempo = max(20, self.tempo)
                    self.webViewIdentity = UUID()
                    self.refreshPracticeData()
                }
            } catch {
                await MainActor.run {
                    guard let self, self.scoreIdentity == expectedScoreID else { return }
                    self.sourceError = error.localizedDescription
                    self.statusMessage = error.localizedDescription
                }
            }
        }
    }

    static func resolveImportedSource(_ url: URL, formatHint: String? = nil) throws -> NativePlayerSource {
        let canonical = url.resolvingSymlinksInPath().standardizedFileURL
        let importRoot = try AppPaths.userDataDirectory()
            .appendingPathComponent("Imports", isDirectory: true)
            .resolvingSymlinksInPath().standardizedFileURL
        guard Self.contains(canonical, in: importRoot) else { throw NativePlayerError.importOutsideSandbox }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: canonical.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            throw NativePlayerError.importMissing
        }
        let attributes = try FileManager.default.attributesOfItem(atPath: canonical.path)
        let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        guard size > 0, size <= 30 * 1024 * 1024 else { throw NativePlayerError.importSizeLimit }
        let ext = canonical.pathExtension.lowercased()
        let kind = try sourceKind(for: ext, formatHint: formatHint)
        return NativePlayerSource(url: canonical, kind: kind, isImported: true)
    }

    static func resolveCatalogScoreSource(
        _ url: URL,
        kind: NativePlayerSourceKind,
        contentRoot: URL
    ) throws -> NativePlayerSource {
        let canonicalContentRoot = contentRoot.standardizedFileURL
            .resolvingSymlinksInPath()
            .standardizedFileURL
        let storageRoot = canonicalContentRoot.appendingPathComponent("storage", isDirectory: true)
            .resolvingSymlinksInPath()
            .standardizedFileURL
        let canonical = url.resolvingSymlinksInPath().standardizedFileURL
        guard Self.contains(storageRoot, in: canonicalContentRoot),
              Self.contains(canonical, in: storageRoot),
              Self.contains(canonical, in: canonicalContentRoot) else {
            throw NativePlayerError.catalogScoreMissing
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: canonical.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            throw NativePlayerError.catalogScoreMissing
        }
        return NativePlayerSource(url: canonical, kind: kind, isImported: false)
    }

    nonisolated private static func materializePersonalAsset(
        _ bytes: Data,
        assetID: String,
        expectedRevision: String,
        extensionName: String
    ) throws -> (url: URL, byteCount: Int, hash: String) {
        guard !bytes.isEmpty, bytes.count <= 30 * 1024 * 1024 else {
            throw NativePlayerError.importSizeLimit
        }
        let assetHash = Self.sha256(bytes)
        guard assetHash == assetID, assetHash == expectedRevision else {
            throw NativePlayerError.assetRevisionMismatch
        }
        let importRoot = try AppPaths.userDataDirectory().appendingPathComponent("Imports", isDirectory: true)
        try FileManager.default.createDirectory(at: importRoot, withIntermediateDirectories: true)
        let file = importRoot.appendingPathComponent("playable-\(assetID).\(extensionName)")
        if let existing = try? Data(contentsOf: file, options: .mappedIfSafe) {
            let existingHash = Self.sha256(existing)
            if existingHash == assetID, existingHash == expectedRevision {
                return (file, existing.count, existingHash)
            }
        }
        try bytes.write(to: file, options: .atomic)
        return (file, bytes.count, assetHash)
    }

    private static func fileExtension(for format: String) -> String? {
        let value = format.lowercased()
        if ["ibe", "gp", "gp3", "gp4", "gp5", "gp6", "gp7", "gp8", "gpx", "musicxml", "xml", "json", "xhe"].contains(value) { return value == "musicxml" ? "musicxml" : value }
        if value == "guitarpro" || value == "guitar-pro" { return "gp" }
        return nil
    }

    nonisolated private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func computeRevision(for source: NativePlayerSource) {
        let expectedIdentity = scoreIdentity
        let expectedURL = source.url
        let expectedAssetID = personalScore?.assetId
        let expectedRevision = personalScore?.revision
        Task { [weak self] in
            do {
                let hash = try await Task.detached(priority: .userInitiated) {
                    let data = try Data(contentsOf: expectedURL, options: .mappedIfSafe)
                    guard !data.isEmpty else { throw NativePlayerError.importMissing }
                    return Self.sha256(data)
                }.value
                guard let self, self.scoreIdentity == expectedIdentity, self.source?.url == expectedURL else { return }
                if let expectedAssetID, let expectedRevision,
                   hash != expectedAssetID || hash != expectedRevision {
                    throw NativePlayerError.assetRevisionMismatch
                }
                self.scoreRevision = hash
            } catch {
                guard let self, self.scoreIdentity == expectedIdentity, self.source?.url == expectedURL else { return }
                self.sourceError = error.localizedDescription
                self.scoreRevision = ""
            }
        }
    }

    private func receivePlayerSnapshot(_ event: [String: Any]) {
        if let end = event["scoreEndTick"] as? NSNumber { scoreEndTick = max(0, end.intValue) }
        if let values = event["tracks"] as? [[String: Any]] {
            tracks = values.compactMap { value in
                guard let index = (value["index"] as? NSNumber)?.intValue else { return nil }
                let tuning = (value["tuning"] as? [NSNumber] ?? []).map(\.intValue)
                return NativePlayerTrack(
                    index: index,
                    name: value["name"] as? String ?? "音轨 \(index + 1)",
                    program: (value["program"] as? NSNumber)?.intValue ?? 0,
                    sourceProgram: (value["sourceProgram"] as? NSNumber)?.intValue ?? 0,
                    sourceCapo: (value["sourceCapo"] as? NSNumber)?.intValue ?? 0,
                    percussion: value["percussion"] as? Bool ?? false,
                    show: value["show"] as? Bool ?? true,
                    muted: value["muted"] as? Bool ?? false,
                    soloed: value["soloed"] as? Bool ?? false,
                    volume: (value["volume"] as? NSNumber)?.doubleValue ?? 1,
                    instrumentOverride: value["instrumentOverride"] as? Bool ?? false,
                    tuning: tuning
                )
            }
        }
        if let values = event["gmInstruments"] as? [[Any]] {
            gmInstruments = values.compactMap { pair in
                guard pair.count >= 2, let program = pair[0] as? NSNumber else { return nil }
                return NativeGMInstrument(program: program.intValue, name: String(describing: pair[1]))
            }
        }
        if let value = event["displayMode"] as? String { displayMode = value }
        if let value = event["numberTab"] as? Bool { numberTab = value }
        if let value = event["chordMode"] as? String { chordMode = value }
        if let value = event["capo"] as? NSNumber { capo = value.intValue }
        if let value = event["useSourceCapo"] as? Bool { useSourceCapo = value }
        if let value = event["transpose"] as? NSNumber { transpose = value.intValue }
        if let value = event["metronome"] as? Bool { metronome = value }
        if let value = event["countIn"] as? Bool { countIn = value }
        if let range = event["loop"] as? [String: Any],
           let start = (range["startTick"] as? NSNumber)?.intValue,
           let end = (range["endTick"] as? NSNumber)?.intValue {
            loopRange = PracticeTickRange(startTick: start, endTick: end)
        }
        markResumeDirty()
    }

    private func notifyReadyIfPossible() {
        guard canPlay else { return }
        cancelReadinessTimeout()
        statusMessage = "谱面与音源已就绪"
        if let callback = onReady {
            onReady = nil
            callback()
        } else if pendingAuditionPlay {
            pendingAuditionPlay = false
            NativePlayerAudioFocus.claim(self) { [weak self] in self?.pausePlayback() }
            updateAudioFocusOwned(true)
            send("play")
        }
    }

    private func markResumeDirty() {
        resumeDirty = true
        scheduleResumeCheckpoint(explicit: true)
    }

    private func scheduleResumeCheckpoint(explicit: Bool = false) {
        guard mode == .practice, practiceJoined, practiceDataReady, scoreReady, scoreEndTick > 0,
              scoreRevision.count == 64 else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if !explicit, let lastResumeWriteUptime, now - lastResumeWriteUptime < 5 { return }
        let mixes = tracks.map { PlayerTrackMix(index: $0.index, muted: $0.muted, soloed: $0.soloed, volume: $0.volume, program: $0.program, instrumentOverride: $0.instrumentOverride) }
        let indexes = tracks.filter(\.show).map(\.index)
        let display = PlayerDisplaySettings(fontScale: zoom, chordMode: chordMode, scoreDisplayMode: displayMode, numberTab: numberTab, showFretboard: showFretboard)
        let value = PlayerResume(
            scoreId: scoreIdentity,
            scoreRevision: scoreRevision,
            tick: min(Double(scoreEndTick), max(0, currentTick)),
            timeMs: max(0, currentTime),
            speed: tempo,
            playbackRatio: sourceTempo > 0 ? tempo / sourceTempo : nil,
            trackMix: mixes,
            display: display,
            capo: capo,
            useSourceCapo: useSourceCapo,
            transpose: transpose,
            loop: loopRange,
            trackIndexes: indexes,
            metronome: metronome,
            countIn: countIn
        )
        pendingResumeValue = value
        resumeWritePending = true
        Task { [weak self] in await self?.persistResume(value) }
    }

    private func persistResume(_ value: PlayerResume) async {
        do {
            for _ in 0..<4 {
                var data = try await personalStore.snapshot()
                guard scoreIdentity == value.scoreId, scoreRevision == value.scoreRevision else { return }
                if let index = data.resumes.firstIndex(where: { $0.scoreId == value.scoreId }) { data.resumes[index] = value }
                else { data.resumes.append(value) }
                do {
                    _ = try await personalStore.commit(data, expectedRevision: data.revision)
                    resume = value
                    pendingResumeValue = nil
                    resumeDirty = false
                    lastResumeWriteUptime = ProcessInfo.processInfo.systemUptime
                    resumeWritePending = false
                    saveError = nil
                    onPersonalDataChanged()
                    return
                } catch PersonalStoreError.revisionConflict { continue }
            }
            throw PersonalStoreError.storage("断点保存遇到连续版本冲突，请重试。")
        } catch {
            resumeWritePending = false
            saveError = error.localizedDescription
            if let pendingResumeValue { lastSaveRetry = { [weak self] in self?.scheduleResumeCheckpoint(explicit: true); self?.pendingResumeValue = pendingResumeValue } }
        }
    }

    func retryLastSave() { lastSaveRetry?() }

    private func refreshPracticeData() {
        guard !scoreIdentity.isEmpty else { return }
        practiceDataReady = false
        let identity = scoreIdentity
        let revision = scoreRevision
        Task { [weak self, personalStore] in
            do {
                let data = try await personalStore.snapshot()
                await MainActor.run {
                    guard let self, self.scoreIdentity == identity, self.scoreRevision == revision else { return }
                    self.practiceItem = data.practiceItems.first(where: { $0.scoreId == identity })
                    self.practiceFragments = data.practiceFragments.filter { $0.scoreId == identity }.sorted { $0.updatedAt > $1.updatedAt }
                    self.practiceSessions = data.sessions.filter { $0.scoreId == identity }.sorted { $0.startedAt > $1.startedAt }
                    self.resume = data.resumes.first(where: { $0.scoreId == identity && $0.scoreRevision == revision })
                    self.outdatedResume = data.resumes.first(where: { $0.scoreId == identity && $0.scoreRevision != revision })
                    self.activePracticeSession = self.practiceSessions.first(where: { $0.scoreRevision == revision && ["active", "paused", "interrupted"].contains($0.state) })
                    self.practiceJoined = self.practiceItem.map { $0.status != .archived } ?? false
                    self.practiceNoteDraft = self.activePracticeSession?.note ?? self.practiceItem?.note ?? ""
                    self.expectedNoteAtEdit = self.practiceNoteDraft
                    self.practiceSpeedPlan = self.activePracticeSession?.speedPlan
                    self.practiceDataReady = true
                    if let session = self.activePracticeSession, session.state == "active" {
                        self.updateSession(session.id) { latest in var next = latest; next.state = "interrupted"; return next }
                    }
                }
            } catch {
                await MainActor.run { self?.saveError = error.localizedDescription; self?.practiceDataReady = true }
            }
        }
    }

    private func updatePersonalData(_ update: (inout PersonalData) throws -> Void) async throws -> PersonalData {
        for _ in 0..<4 {
            var data = try await personalStore.snapshot()
            try update(&data)
            do { return try await personalStore.commit(data, expectedRevision: data.revision) }
            catch PersonalStoreError.revisionConflict { continue }
        }
        throw PersonalStoreError.storage("个人资料持续被其他窗口更新，请重新读取后重试。")
    }

    private func updateSession(_ id: String, transform: @escaping (PracticeSession) throws -> PracticeSession, completion: ((Result<PracticeSession, Error>) -> Void)? = nil) {
        Task { [weak self] in
            guard let self else { return }
            do {
                let saved = try await self.updatePersonalData { data in
                    guard let index = data.sessions.firstIndex(where: { $0.id == id }) else { throw PersonalStoreError.recordConflict("练习记录已被删除。") }
                    let latest = data.sessions[index]
                    guard latest.state != "completed" else { throw PersonalStoreError.recordConflict("练习记录已完成，不能继续修改。") }
                    var next = try transform(latest)
                    next.updatedAt = max(Date().timeIntervalSince1970 * 1000, latest.updatedAt + 1)
                    var slices = Dictionary(uniqueKeysWithValues: latest.slices.map { ($0.id, $0) })
                    for slice in next.slices { slices[slice.id] = slice }
                    next.slices = slices.values.sorted { $0.sequence < $1.sequence }
                    data.sessions[index] = next
                }
                self.practiceSessions = saved.sessions.filter { $0.scoreId == self.scoreIdentity }.sorted { $0.startedAt > $1.startedAt }
                let updated = saved.sessions.first(where: { $0.id == id })
                self.activePracticeSession = updated
                self.onPersonalDataChanged()
                if let updated { completion?(.success(updated)) }
            } catch {
                self.saveError = error.localizedDescription
                self.lastSaveRetry = { [weak self] in self?.updateSession(id, transform: transform, completion: completion) }
                completion?(.failure(error))
            }
        }
    }

    private func updatePracticeActivity() {
        let eligible = mode == .practice && practiceJoined && practiceDataReady && scoreReady && isPlaying && audioReady && nativeViewVisible && appIsActive && audioFocusOwned
        if eligible {
            guard practiceTimer == nil else { return }
            if let session = activePracticeSession, session.scoreRevision == scoreRevision, session.state != "completed" {
                beginPracticeSlice(session)
            } else {
                beginPracticeSession()
            }
        } else if practiceTimer != nil || (activePracticeSession?.state == "active" && (!isPlaying || !audioFocusOwned || !nativeViewVisible || !appIsActive)) {
            endPracticeSlice(interrupted: !nativeViewVisible || !appIsActive || !audioFocusOwned)
        }
    }

    private func beginPracticeSession() {
        guard !practiceBusy, !scoreIdentity.isEmpty, scoreRevision.count == 64 else { return }
        practiceBusy = true
        let now = Date().timeIntervalSince1970 * 1_000
        var session = PracticeSession(id: UUID().uuidString.lowercased(), scoreId: scoreIdentity, scoreRevision: scoreRevision, state: "active", startedAt: now, updatedAt: now)
        session.timezone = TimeZone.current.identifier
        Task { [weak self] in
            guard let self else { return }
            do {
                let saved = try await self.updatePersonalData { $0.sessions.append(session) }
                self.practiceSessions = saved.sessions.filter { $0.scoreId == self.scoreIdentity }.sorted { $0.startedAt > $1.startedAt }
                self.activePracticeSession = saved.sessions.first(where: { $0.id == session.id })
                self.practiceEpoch = UUID().uuidString
                self.practiceSliceSequence = 0
                self.practiceBusy = false
                self.onPersonalDataChanged()
                self.beginPracticeSlice(self.activePracticeSession ?? session)
            } catch {
                self.practiceBusy = false
                self.saveError = error.localizedDescription
                self.lastSaveRetry = { [weak self] in self?.beginPracticeSession() }
            }
        }
    }

    private func beginPracticeSlice(_ session: PracticeSession) {
        guard practiceTimer == nil, session.scoreRevision == scoreRevision, session.state != "completed" else { return }
        if session.state != "active" { updateSession(session.id) { latest in var next = latest; next.state = "active"; return next } }
        practiceSliceStartUptime = ProcessInfo.processInfo.systemUptime
        practiceSliceStartWallMs = Date().timeIntervalSince1970 * 1_000
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.practiceTimerTick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        practiceTimer = timer
    }

    private func practiceTimerTick() {
        guard let start = practiceSliceStartUptime else { return }
        if ProcessInfo.processInfo.systemUptime - start >= 5 {
            endPracticeSlice(interrupted: false, continueSession: true)
            if let session = activePracticeSession { beginPracticeSlice(session) }
        }
        let now = ProcessInfo.processInfo.systemUptime
        if isResumeCheckpointDue(now: now, lastWrite: lastResumeWriteUptime, interval: 5) { scheduleResumeCheckpoint() }
    }

    private func isResumeCheckpointDue(now: TimeInterval, lastWrite: TimeInterval?, interval: TimeInterval) -> Bool {
        guard let lastWrite else { return true }
        return now < lastWrite || now - lastWrite >= interval
    }

    private func endPracticeSlice(interrupted: Bool, continueSession: Bool = false) {
        practiceTimer?.invalidate()
        practiceTimer = nil
        guard let session = activePracticeSession else { practiceSliceStartUptime = nil; return }
        var addedSlice: PracticeSlice?
        if let start = practiceSliceStartUptime, let wallStart = practiceSliceStartWallMs {
            let duration = max(0, Int((ProcessInfo.processInfo.systemUptime - start) * 1_000))
            if duration > 0 {
                practiceSliceSequence += 1
                let slice = PracticeSlice(id: "\(session.id):\(practiceEpoch):\(practiceSliceSequence)", sequence: practiceSliceSequence, epoch: practiceEpoch, startedAt: wallStart, durationMs: Double(duration))
                if !session.slices.contains(where: { $0.id == slice.id }) { addedSlice = slice }
            }
        }
        practiceSliceStartUptime = nil
        practiceSliceStartWallMs = nil
        let nextState = continueSession ? "active" : (interrupted ? "interrupted" : "paused")
        let nextSpeedPlan = practiceSpeedPlan
        updateSession(session.id) { latest in
            var next = latest
            if let addedSlice, !next.slices.contains(where: { $0.id == addedSlice.id }) { next.slices.append(addedSlice) }
            next.state = nextState
            next.speedPlan = nextSpeedPlan
            return next
        }
    }

    func joinPractice() {
        guard !practiceBusy else { return }
        guard canJoinPractice else {
            saveError = isTemporaryLocalImport
                ? "临时打开的本地文件尚未保存到个人曲库，不能加入待练。"
                : "曲谱或音源尚未就绪，暂时不能加入待练。"
            return
        }
        practiceBusy = true
        let scoreID = scoreIdentity
        let score: PersonalScore
        if let personalScore {
            score = personalScore
        } else if let item {
            let now = Date().timeIntervalSince1970 * 1_000
            let category = ["guitar", "ukulele", "bass"].contains(item.category) ? item.category : "guitar"
            let rawFormat = item.format.lowercased()
            let format = rawFormat == "ibe" ? "ibe" : (rawFormat == "xhe" ? "xhe" : "gp")
            score = PersonalScore(
                id: scoreID,
                source: "catalog",
                sourceId: item.id,
                revision: scoreRevision,
                title: item.title,
                artist: item.artist ?? "",
                category: category,
                format: format,
                scoreUrl: item.scoreURL,
                createdAt: now,
                updatedAt: now
            )
        } else {
            practiceBusy = false
            saveError = "此曲谱没有可保存的个人曲谱记录。"
            return
        }
        Task { [weak self] in
            guard let self else { return }
            do {
                let saved = try await self.personalStore.joinPractice(score)
                self.practiceItem = saved.practiceItems.first(where: { $0.scoreId == scoreID })
                self.practiceJoined = true
                self.practiceBusy = false
                self.onPersonalDataChanged()
                self.markResumeDirty()
            } catch {
                self.practiceBusy = false
                self.saveError = error.localizedDescription
                self.lastSaveRetry = { [weak self] in self?.joinPractice() }
            }
        }
    }

    func setPracticeStatus(_ status: PracticeStatus) {
        guard let item = practiceItem else { return }
        Task { [weak self] in
            guard let self else { return }
            do {
                let saved = try await personalStore.setPracticeStatus(scoreID: item.scoreId, status: status)
                self.practiceItem = saved.practiceItems.first(where: { $0.scoreId == item.scoreId })
                self.practiceJoined = status != .archived
                self.onPersonalDataChanged()
            } catch { self.saveError = error.localizedDescription }
        }
    }

    func savePracticeNote() {
        let draft = practiceNoteDraft
        let current = activePracticeSession
        if let current {
            let expectedNote = expectedNoteAtEdit ?? current.note
            guard expectedNote == current.note else {
                practiceOperationError = "练习备注已在其他窗口修改；为避免覆盖，请先刷新后再编辑。"
                return
            }
            updateSession(current.id, transform: { latest in
                guard latest.note == expectedNote else {
                    throw PersonalStoreError.recordConflict("练习备注已在其他窗口更新，请重新载入后再试。")
                }
                var next = latest; next.note = draft; return next
            }, completion: { [weak self] result in
                guard let self else { return }
                switch result {
                case .success:
                    self.expectedNoteAtEdit = draft
                    self.saveError = nil
                    self.practiceOperationError = nil
                case .failure(let error):
                    self.practiceOperationError = error.localizedDescription
                }
            })
        } else {
            let base = practiceItem
            guard let base else {
                practiceOperationError = "待练条目已移除，请刷新后再保存备注。"
                return
            }
            let expectedNote = base.note
            Task { [weak self] in
                guard let self else { return }
                do {
                    let saved = try await personalStore.updatePracticeNote(scoreID: base.scoreId, note: draft, expectedNote: expectedNote)
                    self.practiceItem = saved.practiceItems.first(where: { $0.scoreId == base.scoreId })
                    self.expectedNoteAtEdit = draft
                    self.saveError = nil
                    self.practiceOperationError = nil
                    self.onPersonalDataChanged()
                } catch {
                    self.saveError = error.localizedDescription
                    self.practiceOperationError = error.localizedDescription
                }
            }
        }
    }

    func savePracticeFragment(name: String, note: String) {
        guard let range = loopRange, scoreRevision.count == 64, range.endTick <= scoreEndTick else {
            practiceOperationError = "请先设置当前曲谱内有效的 A-B 半开区间，再保存片段。"
            return
        }
        let now = Date().timeIntervalSince1970 * 1_000
        let speed = PracticeFragmentSpeed(nativeAnchorBpm: sourceTempo, startBpm: practiceSpeedPlan?.startBpm ?? practiceSpeedStart, targetBpm: practiceSpeedPlan?.targetBpm ?? practiceSpeedTarget, stepBpm: practiceSpeedPlan?.stepBpm ?? practiceSpeedStep, lapsPerLevel: practiceSpeedPlan?.lapsPerLevel ?? practiceLapsPerLevel)
        let fragment = PracticeFragment(id: UUID().uuidString.lowercased(), scoreId: scoreIdentity, scoreRevision: scoreRevision, name: name.trimmingCharacters(in: .whitespacesAndNewlines), note: note, range: range, speed: speed, createdAt: now, updatedAt: now)
        Task { [weak self] in
            guard let self else { return }
            do {
                let saved = try await personalStore.savePracticeFragment(fragment)
                self.practiceFragments = saved.practiceFragments.filter { $0.scoreId == self.scoreIdentity }.sorted { $0.updatedAt > $1.updatedAt }
                self.practiceOperationError = nil
                self.onPersonalDataChanged()
            } catch { self.practiceOperationError = error.localizedDescription }
        }
    }

    func updatePracticeFragment(_ fragment: PracticeFragment, name: String, note: String) {
        var updated = fragment
        updated.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.note = note
        updated.updatedAt = max(Date().timeIntervalSince1970 * 1_000, fragment.updatedAt + 1)
        Task { [weak self] in
            guard let self else { return }
            do {
                let saved = try await personalStore.savePracticeFragment(updated, expectedUpdatedAt: fragment.updatedAt)
                self.practiceFragments = saved.practiceFragments.filter { $0.scoreId == self.scoreIdentity }.sorted { $0.updatedAt > $1.updatedAt }
                self.onPersonalDataChanged()
            } catch { self.practiceOperationError = error.localizedDescription }
        }
    }

    func deletePracticeFragment(_ fragment: PracticeFragment) {
        Task { [weak self] in
            guard let self else { return }
            do {
                let saved = try await personalStore.deletePracticeFragment(id: fragment.id, expectedUpdatedAt: fragment.updatedAt)
                self.practiceFragments = saved.practiceFragments.filter { $0.scoreId == self.scoreIdentity }.sorted { $0.updatedAt > $1.updatedAt }
                self.onPersonalDataChanged()
            } catch { self.practiceOperationError = error.localizedDescription }
        }
    }

    func applyPracticeFragment(_ fragment: PracticeFragment) {
        guard fragment.deletedAt == nil, fragment.scoreId == scoreIdentity, fragment.scoreRevision == scoreRevision,
              fragment.range.startTick >= 0, fragment.range.endTick > fragment.range.startTick, fragment.range.endTick <= scoreEndTick else {
            practiceOperationError = "片段已删除、属于其他曲谱/版本或超出当前谱面；请重新选择 A-B。"
            return
        }
        pausePlayback()
        practiceOperationError = nil
        practiceSpeedPlan = PracticeSpeedPlan(revision: scoreRevision, nativeAnchorBpm: fragment.speed.nativeAnchorBpm, loopRange: fragment.range, startBpm: fragment.speed.startBpm, targetBpm: fragment.speed.targetBpm, stepBpm: fragment.speed.stepBpm, lapsPerLevel: fragment.speed.lapsPerLevel, currentBpm: fragment.speed.startBpm, completedLaps: 0)
        applyLoop(fragment.range)
        send("setSpeedPlan", arguments: ["plan": Self.dictionary(from: practiceSpeedPlan!)])
        tempo = fragment.speed.startBpm
        applyTempo()
        markResumeDirty()
    }

    func configureSpeedPlan(start: Double, target: Double, step: Double, laps: Int) {
        guard let loopRange else { practiceOperationError = "请先建立有效 A-B 区间。"; return }
        guard scoreRevision.count == 64, start >= 20, target >= start, target <= 300, step > 0, laps > 0,
              start / sourceTempo >= 0.125, target / sourceTempo <= 8 else {
            practiceOperationError = "提速计划参数超出可播放范围。"; return
        }
        practiceSpeedStart = start; practiceSpeedTarget = target; practiceSpeedStep = step; practiceLapsPerLevel = laps
        let plan = PracticeSpeedPlan(revision: scoreRevision, nativeAnchorBpm: sourceTempo, loopRange: loopRange, startBpm: start, targetBpm: target, stepBpm: step, lapsPerLevel: laps, currentBpm: start, completedLaps: 0)
        practiceSpeedPlan = plan
        send("createSpeedPlan", arguments: ["revision": scoreRevision, "startBpm": start, "targetBpm": target, "stepBpm": step, "lapsPerLevel": laps])
        tempo = start
        applyTempo()
        markResumeDirty()
    }

    func clearSpeedPlan() {
        practiceSpeedPlan = nil
        send("clearSpeedPlan")
        if let session = activePracticeSession {
            updateSession(session.id) { latest in
                var next = latest
                next.speedPlan = nil
                return next
            }
        }
        practiceOperationError = nil
        markResumeDirty()
    }

    private static func dictionary<T: Encodable>(from value: T) -> [String: Any] {
        guard let data = try? JSONEncoder().encode(value), let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return object
    }

    private func handleLoopLap(_ lapID: String) {
        guard !lapID.isEmpty, lapID != lastSeenLapID, var plan = practiceSpeedPlan,
              plan.revision == scoreRevision, plan.loopRange?.startTick == loopRange?.startTick,
              plan.loopRange?.endTick == loopRange?.endTick else { return }
        positionFence = nil
        lastSeenLapID = lapID
        loopLapCount += 1
        plan.completedLaps += 1
        if plan.completedLaps >= plan.lapsPerLevel {
            plan.completedLaps = 0
            plan.currentBpm = min(plan.targetBpm, plan.currentBpm + plan.stepBpm)
            tempo = plan.currentBpm
            applyTempo()
        }
        practiceSpeedPlan = plan
        send("setSpeedPlan", arguments: ["plan": Self.dictionary(from: plan)])
        if let session = activePracticeSession { updateSession(session.id) { latest in var next = latest; next.speedPlan = plan; return next } }
        markResumeDirty()
    }

    private func releaseAudioFocus() {
        if audioFocusOwned {
            audioFocusOwned = false
            send("setAudioFocus", arguments: ["enabled": false])
            NativePlayerAudioFocus.release(self)
        }
    }

    func updateAudioFocusOwned(_ owned: Bool) {
        audioFocusOwned = owned
        send("setAudioFocus", arguments: ["enabled": owned])
        updatePracticeActivity()
    }

    func leavePlayerPane() {
        if isPlaying { pausePlayback() } else { releaseAudioFocus() }
        endPracticeSlice(interrupted: true)
        scheduleResumeCheckpoint(explicit: true)
    }

    func finishPracticeSession() {
        if isPlaying { pausePlayback() }
        guard let session = activePracticeSession else { return }
        endPracticeSlice(interrupted: false)
        updateSession(session.id) { latest in var next = latest; next.state = "completed"; next.endedAt = Date().timeIntervalSince1970 * 1_000; return next }
        activePracticeSession = nil
    }

    func printScore() {
        guard let webView, canExport else { return }
        send("setStaticExport", arguments: ["enabled": true])
        webView.printOperation(with: NSPrintInfo.shared).run()
        send("setStaticExport", arguments: ["enabled": false])
    }

    func exportLongImage() {
        guard let webView, canExportRenderedScore else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "\(Self.safeFileName(metadataTitle))-乐谱长图.png"
        panel.begin { [weak self, weak webView] response in
            guard response == .OK, let url = panel.url, let self, let webView else { return }
            webView.callAsyncJavaScript(
                "return await window.NativePlayer.exportPngData()",
                arguments: [:],
                in: nil,
                in: .page,
                completionHandler: { result in
                    guard case .success(let value) = result,
                          let base64 = value as? String,
                          let png = Data(base64Encoded: base64),
                          png.starts(with: [0x89, 0x50, 0x4E, 0x47]) else {
                        let message: String
                        if case .failure(let error) = result { message = error.localizedDescription }
                        else { message = "没有可用的长图数据。" }
                        DispatchQueue.main.async { self.statusMessage = "长图生成失败：\(message)" }
                        return
                    }
                    DispatchQueue.global(qos: .userInitiated).async {
                        do {
                            try png.write(to: url, options: .atomic)
                            DispatchQueue.main.async { self.statusMessage = "谱面长图已保存：\(url.lastPathComponent)" }
                        } catch {
                            DispatchQueue.main.async { self.statusMessage = "长图保存失败：\(error.localizedDescription)" }
                        }
                    }
                }
            )
        }
    }

    private static func safeFileName(_ value: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:?%*|\"<>\n\r")
        let clean = value.components(separatedBy: invalid).filter { !$0.isEmpty }.joined(separator: "-")
        return clean.isEmpty ? "MIMI-Guitar" : String(clean.prefix(100))
    }

    static func resolveSource(
        item: CatalogItem,
        contentRoot: URL,
        importedFileURL: URL?
    ) throws -> NativePlayerSource {
        if let importedFileURL {
            return try resolveImportedSource(importedFileURL)
        }

        let selectedReference: String
        let selectedKind: NativePlayerSourceKind
        if let scoreURL = item.scoreURL, !scoreURL.isEmpty {
            let extensionName = URL(fileURLWithPath: scoreURL).pathExtension.lowercased()
            selectedKind = try sourceKind(for: extensionName, formatHint: item.format)
            selectedReference = scoreURL
        } else if let xheURL = item.xheURL, !xheURL.isEmpty {
            selectedKind = .xhe
            selectedReference = xheURL
        } else if item.format.lowercased() == "xhe", let scoreURL = item.scoreURL, !scoreURL.isEmpty {
            selectedKind = .xhe
            selectedReference = scoreURL
        } else {
            throw NativePlayerError.noScore
        }

        let url = try AppPaths.resolve(reference: selectedReference, contentRoot: contentRoot)
        return try resolveCatalogScoreSource(url, kind: selectedKind, contentRoot: contentRoot)
    }

    private static func sourceKind(for extensionName: String, formatHint: String? = nil) throws -> NativePlayerSourceKind {
        if extensionName == "ibe" { return .ibe }
        if extensionName == "xhe" { return .xhe }
        if extensionName == "musicxml" || extensionName == "xml" { return .musicXML }
        if extensionName == "json" { return .json }
        let guitarProExtensions: Set<String> = ["gp", "gp3", "gp4", "gp5", "gp6", "gp7", "gp8", "gpx"]
        if guitarProExtensions.contains(extensionName) { return .guitarPro }
        if extensionName.isEmpty, formatHint?.lowercased() == "xhe" { return .xhe }
        throw NativePlayerError.unsupportedFormat(extensionName)
    }

    private static func contains(_ candidate: URL, in parent: URL) -> Bool {
        let childPath = candidate.standardizedFileURL.path
        let parentPath = parent.standardizedFileURL.path
        return childPath.hasPrefix(parentPath.hasSuffix("/") ? parentPath : parentPath + "/")
    }

    private static func clock(_ milliseconds: Double) -> String {
        let totalSeconds = max(0, Int(milliseconds / 1000))
        return "\(totalSeconds / 60):\(String(format: "%02d", totalSeconds % 60))"
    }
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

private enum NativePlayerError: LocalizedError {
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
