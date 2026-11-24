import AppKit
import MIMICore
import SwiftUI

struct NativePlayerPillButtonStyle: ButtonStyle {
    var prominent = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("mimi.motion.preference") private var motionPreference = "system"

    private var motionPolicy: MIMIMotionPolicy {
        MIMIMotionPolicy.resolve(preference: motionPreference, reduceMotion: reduceMotion)
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(MIMITheme.bodyFont(size: 12, weight: prominent ? .semibold : .medium))
            .foregroundStyle(prominent ? Color.white : MIMITheme.bodyInk)
            .padding(.horizontal, 13)
            .frame(minHeight: 34)
            .background(Capsule(style: .continuous).fill(prominent
                ? MIMITheme.ink
                : (configuration.isPressed ? MIMITheme.navigationSegment : MIMITheme.paperWhite)))
            .overlay(Capsule(style: .continuous).stroke(prominent ? MIMITheme.ink : MIMITheme.softBorder, lineWidth: 1))
            .shadow(color: Color(nsColor: .dynamic(lightHex: 0x483620, darkHex: 0x000000)).opacity(0.025), radius: 4, x: 0, y: 1)
            .opacity(isEnabled ? 1 : 0.46)
            .scaleEffect(configuration.isPressed && motionPolicy.allowsSpatialMotion ? 0.98 : 1)
            .animation(motionPolicy.controlAnimation, value: configuration.isPressed)
    }
}

struct NativePlayerTogglePillStyle: ToggleStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("mimi.motion.preference") private var motionPreference = "system"

    private var motionPolicy: MIMIMotionPolicy {
        MIMIMotionPolicy.resolve(preference: motionPreference, reduceMotion: reduceMotion)
    }

    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            configuration.label
                .font(MIMITheme.bodyFont(size: 12, weight: configuration.isOn ? .semibold : .medium))
                .foregroundStyle(configuration.isOn ? Color.white : MIMITheme.bodyInk)
                .padding(.horizontal, 13)
                .frame(minHeight: 34)
                .background(Capsule(style: .continuous).fill(configuration.isOn ? MIMITheme.ink : MIMITheme.paperWhite))
                .overlay(Capsule(style: .continuous).stroke(configuration.isOn ? MIMITheme.ink : MIMITheme.softBorder, lineWidth: 1))
                .shadow(color: Color(nsColor: .dynamic(lightHex: 0x483620, darkHex: 0x000000)).opacity(0.025), radius: 4, x: 0, y: 1)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.46)
        .animation(motionPolicy.controlAnimation, value: configuration.isOn)
    }
}

enum PlayerPanel: String, CaseIterable, Identifiable {
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

struct NativePlayerFlowLayout: Layout {
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
struct NativePlayerTempoStepper: View {
    @ObservedObject var model: NativePlayerModel
    @State private var showTempoPopover = false

    init(model: NativePlayerModel) {
        self.model = model
    }

    var body: some View {
        HStack(spacing: 3) {
            Button {
                stepTempo(-1)
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 9, weight: .bold))
                    .frame(width: 18, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!model.canPlay || model.tempo <= model.tempoRange.lowerBound)
            .help("速度微调 -1 BPM")

            Button {
                showTempoPopover.toggle()
            } label: {
                HStack(spacing: 3) {
                    Text("\(Int(model.tempo.rounded()))")
                        .font(.system(size: 11.5, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(MIMITheme.ink)
                    Text("BPM")
                        .font(MIMITheme.bodyFont(size: 9.5, weight: .medium))
                        .foregroundStyle(MIMITheme.mutedInk)
                }
                .padding(.horizontal, 4)
                .frame(height: 26)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showTempoPopover, arrowEdge: .bottom) {
                tempoPopoverContent
            }
            .help("点击打开精确速度调节与倍速快捷选项")

            Button {
                stepTempo(1)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 9, weight: .bold))
                    .frame(width: 18, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!model.canPlay || model.tempo >= model.tempoRange.upperBound)
            .help("速度微调 +1 BPM")
        }
        .padding(.horizontal, 4)
        .frame(height: 32)
        .background(MIMITheme.paperWhite, in: Capsule())
        .overlay(Capsule().stroke(MIMITheme.softBorder, lineWidth: 1))
        .shadow(color: Color(nsColor: .dynamic(lightHex: 0x483620, darkHex: 0x000000)).opacity(0.02), radius: 4, x: 0, y: 1)
        .disabled(!model.canPlay)
        .help(model.canPlay ? "调整播放速度（单击微调，点数字展开倍速面板）" : model.playDisabledReason)
    }

    private func stepTempo(_ delta: Double) {
        let newTempo = min(model.tempoRange.upperBound, max(model.tempoRange.lowerBound, (model.tempo + delta).rounded()))
        model.tempo = newTempo
        model.applyTempo()
    }

    private var tempoPopoverContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("播放速度 (BPM)")
                    .font(MIMITheme.bodyFont(size: 12, weight: .semibold))
                    .foregroundStyle(MIMITheme.ink)
                Spacer()
                Text("\(Int(model.tempo.rounded()))")
                    .font(.system(size: 13, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(MIMITheme.darkGold)
            }

            Slider(value: $model.tempo, in: model.tempoRange, step: 1) { editing in
                model.tempoEditingChanged(editing)
            }
            .tint(MIMITheme.darkGold)

            HStack(spacing: 6) {
                speedPresetButton("0.5x", ratio: 0.5)
                speedPresetButton("0.75x", ratio: 0.75)
                speedPresetButton("原速", ratio: 1.0)
                speedPresetButton("1.25x", ratio: 1.25)
            }

            if model.sourceTempo > 0 && abs(model.tempo - model.sourceTempo) > 0.5 {
                Button {
                    model.tempo = model.sourceTempo
                    model.applyTempo()
                } label: {
                    Label("恢复原谱速度 (\(Int(model.sourceTempo.rounded())) BPM)", systemImage: "arrow.counterclockwise")
                        .font(MIMITheme.bodyFont(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundStyle(MIMITheme.darkGold)
                .padding(.top, 2)
            }
        }
        .padding(14)
        .frame(width: 230)
    }

    private func speedPresetButton(_ title: String, ratio: Double) -> some View {
        let targetTempo = (model.sourceTempo > 0 ? model.sourceTempo * ratio : 80.0 * ratio).rounded()
        let isCurrent = abs(model.tempo - targetTempo) < 1.0
        return Button {
            model.tempo = min(model.tempoRange.upperBound, max(model.tempoRange.lowerBound, targetTempo))
            model.applyTempo()
        } label: {
            Text(title)
                .font(MIMITheme.bodyFont(size: 11, weight: isCurrent ? .bold : .medium))
                .foregroundStyle(isCurrent ? MIMITheme.darkGold : MIMITheme.bodyInk)
                .frame(maxWidth: .infinity)
                .frame(height: 24)
                .background(isCurrent ? MIMITheme.warmGold.opacity(0.18) : Color(hex: 0xF5F0E6), in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }
}

@MainActor
struct NativePlayerPositionBar: View {
    @ObservedObject var positionState: NativePlayerPositionState
    let canSeek: Bool
    var compact: Bool = false
    var tempo: Double = 80
    var loopDetails: NativePlayerLoopDetails? = nil
    var loopPointADetails: NativePlayerPointADetails? = nil
    var onClearLoop: (() -> Void)? = nil
    let onSeek: (Double) -> Void
    @State private var isScrubbing = false
    @State private var scrubRatio = 0.0

    init(
        positionState: NativePlayerPositionState,
        canSeek: Bool,
        compact: Bool = false,
        tempo: Double = 80,
        loopDetails: NativePlayerLoopDetails? = nil,
        loopPointADetails: NativePlayerPointADetails? = nil,
        onClearLoop: (() -> Void)? = nil,
        onSeek: @escaping (Double) -> Void
    ) {
        self.positionState = positionState
        self.canSeek = canSeek
        self.compact = compact
        self.tempo = tempo
        self.loopDetails = loopDetails
        self.loopPointADetails = loopPointADetails
        self.onClearLoop = onClearLoop
        self.onSeek = onSeek
    }

    var body: some View {
        let now = ProcessInfo.processInfo.systemUptime
        let sample = positionState.sample
        let duration = sample?.durationMs ?? 0
        let liveTime = sample?.time(at: now) ?? 0
        let liveRatio = duration > 0 ? min(1, max(0, liveTime / duration)) : 0
        let displayedRatio = isScrubbing ? scrubRatio : liveRatio
        let help = canSeek && duration > 0 ? "拖动以定位到曲谱时间" : "曲谱或音源尚未就绪，无法定位"

        if compact {
            HStack(spacing: 6) {
                Text(Self.timeLabel(duration * displayedRatio))
                    .font(.system(size: 11, weight: .medium, design: .monospaced).monospacedDigit())
                    .foregroundStyle(MIMITheme.mutedInk)
                    .frame(width: 38, alignment: .trailing)

                MIMIFluidAudioWaveform(
                    isPlaying: sample?.isPlaying == true,
                    bpm: tempo,
                    width: 65,
                    height: 20
                )

                NativePlayerPositionSlider(
                    timeMs: sample?.timeMs ?? 0,
                    receivedAtUptime: sample?.receivedAtUptime ?? now,
                    durationMs: duration,
                    isPlaying: sample?.isPlaying == true,
                    canSeek: canSeek && duration > 0,
                    isScrubbing: isScrubbing,
                    scrubRatio: scrubRatio,
                    resetRevision: sample?.transportRevision ?? 0,
                    loopStartRatio: loopDetails?.startRatio,
                    loopEndRatio: loopDetails?.endRatio,
                    pointARatio: loopPointADetails?.ratio,
                    help: help,
                    onEditingChanged: { editing in
                        if editing { scrubRatio = liveRatio }
                        isScrubbing = editing
                    },
                    onScrubChanged: { scrubRatio = $0 },
                    onSeek: onSeek
                )
                .frame(minWidth: 90, maxWidth: .infinity)
                .frame(minHeight: 22)

                Text(Self.timeLabel(duration))
                    .font(.system(size: 11, weight: .medium, design: .monospaced).monospacedDigit())
                    .foregroundStyle(MIMITheme.mutedInk)
                    .frame(width: 38, alignment: .leading)

                if let bar = sample?.bar, bar > 0 {
                    HStack(spacing: 2) {
                        Text("第 \(bar) 小节")
                        if let beat = sample?.beat, beat > 0 {
                            Text("· \(beat) 拍")
                        }
                    }
                    .font(MIMITheme.bodyFont(size: 10.5, weight: .medium))
                    .foregroundStyle(MIMITheme.mutedInk)
                    .padding(.horizontal, 6)
                    .frame(height: 22)
                    .background(Color.white.opacity(0.85), in: Capsule())
                    .overlay(Capsule().stroke(MIMITheme.softBorder.opacity(0.8), lineWidth: 0.8))
                    .help("当前演奏位置")
                }

                if let loop = loopDetails {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 9.5, weight: .bold))
                        Text("A \(loop.startBar ?? 1) ➔ B \(loop.endBar ?? loop.startBar ?? 1) 节")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                        if let onClearLoop {
                            Button {
                                onClearLoop()
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(Color.white.opacity(0.85))
                            }
                            .buttonStyle(.plain)
                            .help("清除 A–B 循环")
                        }
                    }
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 6)
                    .frame(height: 22)
                    .background(MIMITheme.terracotta, in: Capsule())
                    .help("当前 A–B 循环区间：第 \(loop.startBar ?? 1) 至 \(loop.endBar ?? loop.startBar ?? 1) 小节")
                } else if let ptA = loopPointADetails {
                    HStack(spacing: 3) {
                        Circle()
                            .fill(MIMITheme.terracotta)
                            .frame(width: 5, height: 5)
                        Text("A点: 第 \(ptA.bar ?? 1) 节 · 待设 B")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(MIMITheme.terracotta)
                    }
                    .padding(.horizontal, 6)
                    .frame(height: 22)
                    .background(MIMITheme.terracotta.opacity(0.12), in: Capsule())
                    .overlay(Capsule().stroke(MIMITheme.terracotta.opacity(0.3), lineWidth: 0.8))
                    .help("已设置循环起点 A：第 \(ptA.bar ?? 1) 小节，播放或拖动到目标后请点击「设置循环终点 B」")
                }
            }
            .padding(.horizontal, 4)
        } else {
            HStack(spacing: 8) {
                Text(Self.timeLabel(duration * displayedRatio))
                    .font(.system(size: 11.5, weight: .medium, design: .monospaced).monospacedDigit())
                    .foregroundStyle(MIMITheme.mutedInk).frame(width: 48, alignment: .trailing)

                MIMIFluidAudioWaveform(
                    isPlaying: sample?.isPlaying == true,
                    bpm: tempo,
                    width: 85,
                    height: 22
                )

                NativePlayerPositionSlider(
                    timeMs: sample?.timeMs ?? 0,
                    receivedAtUptime: sample?.receivedAtUptime ?? now,
                    durationMs: duration,
                    isPlaying: sample?.isPlaying == true,
                    canSeek: canSeek && duration > 0,
                    isScrubbing: isScrubbing,
                    scrubRatio: scrubRatio,
                    resetRevision: sample?.transportRevision ?? 0,
                    loopStartRatio: loopDetails?.startRatio,
                    loopEndRatio: loopDetails?.endRatio,
                    pointARatio: loopPointADetails?.ratio,
                    help: help,
                    onEditingChanged: { editing in
                        if editing { scrubRatio = liveRatio }
                        isScrubbing = editing
                    },
                    onScrubChanged: { scrubRatio = $0 },
                    onSeek: onSeek
                )
                .frame(minHeight: 22)

                Text(Self.timeLabel(duration))
                    .font(.system(size: 11.5, weight: .medium, design: .monospaced).monospacedDigit())
                    .foregroundStyle(MIMITheme.mutedInk).frame(width: 48, alignment: .leading)

                if let loop = loopDetails {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 9.5, weight: .bold))
                        Text("A \(loop.startBar ?? 1) ➔ B \(loop.endBar ?? loop.startBar ?? 1) 节")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                        if let onClearLoop {
                            Button {
                                onClearLoop()
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(Color.white.opacity(0.85))
                            }
                            .buttonStyle(.plain)
                            .help("清除 A–B 循环")
                        }
                    }
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 6)
                    .frame(height: 22)
                    .background(MIMITheme.terracotta, in: Capsule())
                } else if let ptA = loopPointADetails {
                    HStack(spacing: 3) {
                        Circle()
                            .fill(MIMITheme.terracotta)
                            .frame(width: 5, height: 5)
                        Text("A点: 第 \(ptA.bar ?? 1) 节 · 待设 B")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(MIMITheme.terracotta)
                    }
                    .padding(.horizontal, 6)
                    .frame(height: 22)
                    .background(MIMITheme.terracotta.opacity(0.12), in: Capsule())
                    .overlay(Capsule().stroke(MIMITheme.terracotta.opacity(0.3), lineWidth: 0.8))
                }

                Text(Self.positionLabel(bar: sample?.bar, beat: sample?.beat))
                    .font(MIMITheme.bodyFont(size: 11.5)).foregroundStyle(MIMITheme.mutedInk)
                    .frame(width: 140, alignment: .trailing)
                    .lineLimit(1)
                    .help("拍号未知时显示短横线；首拍从1计数")
            }
            .padding(.horizontal, 10).padding(.top, 2).padding(.bottom, 4)
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

