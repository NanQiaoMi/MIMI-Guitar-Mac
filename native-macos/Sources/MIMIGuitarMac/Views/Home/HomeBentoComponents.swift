import MIMICore
import SwiftUI

struct SynthesizerTimeBadge: View {
    @StateObject private var clockState: AuditionItemViewState

    init(controller: NativeAuditionController) {
        _clockState = StateObject(wrappedValue: controller.viewState(tracksClock: true))
    }

    var body: some View {
        let cur = max(0, Int((clockState.clock.currentTime / 1000.0).rounded()))
        let end = max(0, Int((clockState.clock.endTime / 1000.0).rounded()))
        Text(String(format: "%d:%02d / %d:%02d", cur / 60, cur % 60, end / 60, end % 60))
            .font(.system(size: 10, weight: .medium, design: .monospaced).monospacedDigit())
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }
}

struct SynthesizerEqualizerBars: View {
    let isPlaying: Bool

    // 24 harmonic equalizer bar heights replicated from web BentoGridFeatures.svelte
    private static let baseHeights: [Double] = [
        40, 65, 80, 45, 90, 75, 60, 95, 70, 85, 50, 65,
        90, 40, 75, 85, 60, 70, 95, 55, 80, 65, 90, 45
    ]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isPlaying)) { timeline in
            Canvas { context, size in
                let w = size.width
                let h = size.height
                guard w > 0, h > 0 else { return }

                let count = Self.baseHeights.count
                let spacing: CGFloat = 4.0
                let totalSpacing = spacing * CGFloat(count - 1)
                let barWidth = max(2.5, (w - totalSpacing) / CGFloat(count))
                let now = timeline.date.timeIntervalSinceReferenceDate
                let gradient = Gradient(colors: [Color(hex: 0x8F6D2B), MIMITheme.warmGold])

                for (i, base) in Self.baseHeights.enumerated() {
                    let dynamicPercent: Double
                    if isPlaying {
                        // Formula from web: h * (0.6 + 0.5 * sin(time / 120 + i)) -> ~8.33 rad/s angular speed
                        let wave = sin(now * 8.33 + Double(i) * 0.47)
                        dynamicPercent = min(100.0, max(15.0, base * (0.6 + 0.5 * wave)))
                    } else {
                        dynamicPercent = base
                    }

                    let barHeight = max(4.0, h * CGFloat(dynamicPercent / 100.0))
                    let x = CGFloat(i) * (barWidth + spacing)
                    let y = h - barHeight
                    let rect = CGRect(x: x, y: y, width: barWidth, height: barHeight)
                    let path = Path(roundedRect: rect, cornerRadius: min(barWidth / 2, 2.5))

                    let opacity = min(1.0, 0.48 + dynamicPercent / 180.0)
                    context.opacity = opacity
                    context.fill(
                        path,
                        with: .linearGradient(
                            gradient,
                            startPoint: CGPoint(x: x, y: h),
                            endPoint: CGPoint(x: x, y: y)
                        )
                    )
                }
            }
        }
        .frame(height: 76)
        .padding(.horizontal, 10)
        .padding(.top, 4)
        .background(MIMITheme.paper, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityHidden(true)
    }
}

struct SynthesizerBentoCard: View {
    let item: CatalogItem?
    let controller: NativeAuditionController
    @StateObject private var globalAuditionState: AuditionItemViewState
    @StateObject private var itemAuditionState: AuditionItemViewState
    private var playback: AuditionPlaybackSnapshot { globalAuditionState.snapshot }
    private var itemPlayback: AuditionPlaybackSnapshot { itemAuditionState.snapshot }
    private var playing: Bool { playback.isPlaying }
    private var isSunnyPlaying: Bool { itemPlayback.isPlaying }

    init(item: CatalogItem?, controller: NativeAuditionController) {
        self.item = item
        self.controller = controller
        _globalAuditionState = StateObject(wrappedValue: controller.viewState(tracksClock: false))
        _itemAuditionState = StateObject(wrappedValue: controller.viewState(itemID: item?.id))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack {
                Label(playing ? "正在试听原谱" : "60FPS AUDIO SYNTHESIZER", systemImage: playing ? "waveform" : "waveform.path")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundStyle(.white).padding(.horizontal, 11).padding(.vertical, 6).background(MIMITheme.ink, in: Capsule())
                Spacer()
                Text(playing ? playback.statusMessage : "高保真原谱音源")
                    .font(MIMITheme.bodyFont(size: 10, weight: .medium)).foregroundStyle(MIMITheme.terracotta).lineLimit(1)
            }
            VStack(alignment: .leading, spacing: 7) {
                Text("内置原声吉他 SoundFont 高清合成器")
                    .font(MIMITheme.displayFont(size: 21, weight: .bold))
                    .foregroundStyle(MIMITheme.ink)
                    .padding(.vertical, 1)
                Text("通过捆绑的谱面渲染与本地音源播放，谱面和声音保持同步。点击试听以打开真实随包原谱，不自动播放。")
                    .font(MIMITheme.bodyFont(size: 12))
                    .foregroundStyle(MIMITheme.bodyInk)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button {
                if let item { controller.toggle(item: item, previewDuration: 30) }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isSunnyPlaying ? "pause.fill" : "play.fill")
                    Text(isSunnyPlaying ? "暂停试听《\(item?.title ?? "晴天")》" : "试听典藏原谱: 《\(item?.title ?? "晴天")》")
                        .lineLimit(1)
                    Spacer()
                    if playing {
                        SynthesizerTimeBadge(controller: controller)
                    } else {
                        Text("30s")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                    }
                }
                .font(MIMITheme.bodyFont(size: 12, weight: .semibold)).foregroundStyle(MIMITheme.bodyInk)
                .padding(12).background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 14)).overlay(RoundedRectangle(cornerRadius: 14).stroke(MIMITheme.softBorder, lineWidth: 1))
            }.buttonStyle(.plain).disabled(item?.scoreURL == nil)

            // High-performance equalizer bars rendered via Metal Canvas (0 subviews, 0% idle CPU)
            SynthesizerEqualizerBars(isPlaying: playing)

            HStack {
                Label("SONiVOX SoundFont", systemImage: "speaker.wave.2.fill")
                Spacer()
                Text("声音初始化时间不计入试听").foregroundStyle(MIMITheme.mutedInk)
            }.font(.system(size: 10, weight: .medium)).foregroundStyle(MIMITheme.bodyInk)
        }
        .padding(22).frame(maxWidth: .infinity, minHeight: 360, alignment: .leading)
        .background(LinearGradient(colors: [.white, Color(hex: 0xFAF6EE)], startPoint: .topLeading, endPoint: .bottomTrailing))
        .mimiCard(radius: 25)
    }
}

struct NotationBentoCard: View {
    @State private var activeNotation = "mixed"
    init() {}
    private let choices = [("简谱并排", "mixed"), ("纯六线谱", "tab"), ("数字简谱", "jianpu")]

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                MIMIPill(title: "🎼 简六双排", tint: MIMITheme.bodyInk, fill: MIMITheme.paper)
                Spacer()
                Text("同步预览").font(.system(size: 9, weight: .medium, design: .monospaced)).foregroundStyle(MIMITheme.mutedInk)
            }
            Text("简谱 · 六线谱 · 和弦一键切换")
                .font(MIMITheme.displayFont(size: 18, weight: .bold))
                .foregroundStyle(MIMITheme.ink)
                .lineLimit(1)
                .padding(.vertical, 1)
            Text("首创简谱与六线谱完美对齐技术，歌词、唱名、左右手指法一目了然。")
                .font(MIMITheme.bodyFont(size: 11))
                .foregroundStyle(MIMITheme.bodyInk)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 3) {
                ForEach(choices, id: \.1) { choice in
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            activeNotation = choice.1
                        }
                    } label: {
                        Text(choice.0)
                            .font(MIMITheme.bodyFont(size: 11, weight: activeNotation == choice.1 ? .semibold : .medium))
                            .foregroundStyle(activeNotation == choice.1 ? MIMITheme.ink : MIMITheme.bodyInk)
                            .frame(maxWidth: .infinity)
                            .frame(height: 29)
                            .background(activeNotation == choice.1 ? Color.white : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .shadow(color: activeNotation == choice.1 ? Color.black.opacity(0.06) : .clear, radius: 2, y: 1)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(Color(hex: 0xEDE5D8), in: RoundedRectangle(cornerRadius: 11, style: .continuous))

            VStack(spacing: 8) {
                if activeNotation == "mixed" || activeNotation == "jianpu" {
                    HStack {
                        ForEach(["1", "2", "3", "5"], id: \.self) { value in
                            Text(value)
                                .font(.system(size: 13, weight: .bold, design: .monospaced))
                                .foregroundStyle(MIMITheme.terracotta)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.bottom, 6)
                    .overlay(alignment: .bottom) { Rectangle().fill(Color(hex: 0xF0EAE0)).frame(height: 1) }
                }
                if activeNotation == "mixed" || activeNotation == "tab" {
                    HStack {
                        ForEach(Array(["0", "2", "3", "2"].enumerated()), id: \.offset) { _, value in
                            Text(value)
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .foregroundStyle(Color(hex: 0x5C4A38))
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 98, alignment: .center)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(.white, in: RoundedRectangle(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13).stroke(Color(hex: 0xE8E2D4), lineWidth: 1))
        }
        .padding(20).frame(maxWidth: .infinity, minHeight: 360, alignment: .topLeading)
        .mimiCard(radius: 25, fill: MIMITheme.paperWhite)
    }
}

struct BentoDemoTrack: Identifiable {
    let id: String
    let title: String
    let symbol: String
    let volume: Double
}

struct TrackMixerBentoCard: View {
    @State private var mutedTracks: Set<String> = []
    init() {}
    private let tracks = [
        BentoDemoTrack(id: "guitar", title: "主音吉他", symbol: "guitars", volume: 0.90),
        BentoDemoTrack(id: "bass", title: "贝斯声部", symbol: "waveform", volume: 0.75),
        BentoDemoTrack(id: "drums", title: "打击鼓组", symbol: "music.note.list", volume: 0.60),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                MIMIPill(title: "🎚 多轨调音台", tint: MIMITheme.bodyInk, fill: MIMITheme.paper)
                Spacer()
                Text("MIXER").font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundStyle(MIMITheme.mutedInk)
            }
            Text("为每件乐器单独调整聆听重点").font(MIMITheme.displayFont(size: 19, weight: .bold)).foregroundStyle(MIMITheme.ink)
            Text("静音按钮改变当前预览轨道状态，进入播放器可对真实音轨进行完整混音。")
                .font(MIMITheme.bodyFont(size: 11)).foregroundStyle(MIMITheme.bodyInk).lineSpacing(3)
            VStack(spacing: 10) {
                ForEach(tracks) { track in
                    HStack(spacing: 10) {
                        Image(systemName: track.symbol).frame(width: 20).foregroundStyle(mutedTracks.contains(track.id) ? MIMITheme.mutedInk : MIMITheme.darkGold)
                        Text(track.title).font(MIMITheme.bodyFont(size: 11, weight: .medium)).foregroundStyle(MIMITheme.ink).frame(width: 66, alignment: .leading)
                        ZStack(alignment: .leading) {
                            Capsule().fill(MIMITheme.softBorder).frame(height: 5)
                            if !mutedTracks.contains(track.id) {
                                Capsule().fill(MIMITheme.warmGold.gradient)
                                    .frame(height: 5)
                                    .scaleEffect(x: track.volume, y: 1, anchor: .leading)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 14)
                        Button(mutedTracks.contains(track.id) ? "取消静音" : "MUTE") {
                            if mutedTracks.contains(track.id) { mutedTracks.remove(track.id) } else { mutedTracks.insert(track.id) }
                        }
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(mutedTracks.contains(track.id) ? MIMITheme.terracotta : MIMITheme.bodyInk)
                        .padding(.horizontal, 8).frame(height: 27).background(MIMITheme.paper, in: Capsule()).overlay(Capsule().stroke(MIMITheme.softBorder, lineWidth: 1))
                        .buttonStyle(.plain)
                    }
                }
            }
            Spacer(minLength: 0)
            Label("示例音轨静音状态已更新", systemImage: "checkmark.circle.fill").font(.system(size: 10)).foregroundStyle(Color(hex: 0x3D5947))
        }
        .padding(20).frame(maxWidth: .infinity, minHeight: 360, alignment: .topLeading)
        .mimiCard(radius: 25)
    }
}

struct FretPosition: Hashable { let string: Int; let fret: Int }

struct FretboardBentoCard: View {
    @EnvironmentObject private var model: AppModel
    @State private var activeFret: FretPosition?
    let item: CatalogItem?
    let controller: NativeAuditionController
    @StateObject private var globalAuditionState: AuditionItemViewState
    @StateObject private var itemAuditionState: AuditionItemViewState
    private let stringNames = ["e", "B", "G", "D", "A", "E"]
    private let fretNumbers = [0, 1, 2, 3, 5, 7, 9, 12]
    private let chordPatterns: [[FretPosition]] = [
        [FretPosition(string: 6, fret: 3), FretPosition(string: 2, fret: 3), FretPosition(string: 1, fret: 3)],
        [FretPosition(string: 4, fret: 0), FretPosition(string: 3, fret: 0)],
        [FretPosition(string: 2, fret: 3), FretPosition(string: 1, fret: 3)],
        [FretPosition(string: 5, fret: 2), FretPosition(string: 4, fret: 2), FretPosition(string: 2, fret: 3)],
        [FretPosition(string: 3, fret: 0), FretPosition(string: 2, fret: 3)],
        [FretPosition(string: 5, fret: 3), FretPosition(string: 4, fret: 2), FretPosition(string: 2, fret: 3)],
        [FretPosition(string: 3, fret: 0), FretPosition(string: 1, fret: 3)],
        [FretPosition(string: 4, fret: 0), FretPosition(string: 3, fret: 2), FretPosition(string: 2, fret: 3)],
        [FretPosition(string: 1, fret: 2), FretPosition(string: 2, fret: 3)],
    ]

    init(item: CatalogItem? = nil, controller: NativeAuditionController) {
        self.item = item
        self.controller = controller
        _globalAuditionState = StateObject(wrappedValue: controller.viewState(tracksClock: false, tracksNotes: true))
        _itemAuditionState = StateObject(wrappedValue: controller.viewState(itemID: item?.id))
    }

    private var playback: AuditionPlaybackSnapshot { itemAuditionState.snapshot }
    private var isPlaying: Bool { globalAuditionState.snapshot.isPlaying }
    private var isSunnyPlaying: Bool { playback.isPlaying }
    private var isDemoLoading: Bool { playback.isLoading }
    private var demoError: String? { playback.errorMessage }

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            heading
            Text("沿着琴弦与品柱，理解每一个音的位置")
                .font(MIMITheme.displayFont(size: 19, weight: .bold))
                .foregroundStyle(MIMITheme.ink)
            Text("播放《晴天》时指板跟随真实发声音符高亮；停止播放后可点选品位手动查看。")
                .font(MIMITheme.bodyFont(size: 11))
                .foregroundStyle(MIMITheme.bodyInk)
            if let demoError {
                HStack(spacing: 7) {
                    Text("曲谱播放失败：\(demoError)").lineLimit(2)
                    if let item {
                        Button("打开《\(item.title)》曲谱") { model.openCatalogItem(item) }.buttonStyle(.plain).underline()
                    }
                }
                .font(MIMITheme.bodyFont(size: 10)).foregroundStyle(MIMITheme.terracotta)
            }
            fretboard
            fretLabels
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 360, alignment: .topLeading)
        .mimiCard(radius: 25)
    }

    private var heading: some View {
        HStack {
            MIMIPill(title: "🎸 虚拟指板", tint: MIMITheme.bodyInk, fill: MIMITheme.paper)
            Text("22 品全息指板投影").font(MIMITheme.bodyFont(size: 10)).foregroundStyle(MIMITheme.darkGold)
            Spacer(minLength: 6)
            Button {
                activeFret = nil
                if let item { controller.toggle(item: item) }
            } label: {
                HStack(spacing: 6) {
                    if isDemoLoading { ProgressView().controlSize(.small) }
                    else { Image(systemName: isSunnyPlaying ? "pause.fill" : "play.fill") }
                    Text(auditionButtonTitle)
                }
                .font(MIMITheme.bodyFont(size: 10, weight: .medium))
            }
            .buttonStyle(.bordered)
            .disabled(item?.scoreURL == nil)
            .help("播放或暂停《晴天》曲谱")
        }
    }

    private var auditionButtonTitle: String {
        if isDemoLoading { return "加载曲谱…" }
        if isSunnyPlaying { return "暂停《\(item?.title ?? "晴天")》播放" }
        return "播放《\(item?.title ?? "晴天")》曲谱"
    }

    private var fretboard: some View {
        HStack(spacing: 0) {
            stringLabels
            fretGrid
        }
    }

    private var stringLabels: some View {
        VStack(spacing: 0) {
            ForEach(Array(stringNames.enumerated()), id: \.offset) { index, name in
                Text(name)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(index < 3 ? Color(hex: 0xC5A35D) : Color(hex: 0xC9C5BF))
                    .frame(width: 27, height: 26)
            }
        }
    }

    private var fretGrid: some View {
        GeometryReader { proxy in
            let totalWidth = proxy.size.width
            let totalHeight = proxy.size.height
            let colWidth = totalWidth / CGFloat(fretNumbers.count)
            let rowHeight = totalHeight / CGFloat(stringNames.count)
            let notes = globalAuditionState.activeNotes.map { FretPosition(string: $0.string, fret: $0.fret) }

            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isPlaying || !notes.isEmpty)) { timeline in
                Canvas { context, size in
                    // 1. Draw fretboard background
                    let bgRect = CGRect(origin: .zero, size: size)
                    let bgPath = Path(roundedRect: bgRect, cornerRadius: 7)
                    let gradient = Gradient(colors: [Color(hex: 0x42372B), Color(hex: 0x5A4836)])
                    context.fill(bgPath, with: .linearGradient(gradient, startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))

                    // 2. Fret marker inlays at frets 3, 5, 7, 9, 12
                    let markerFrets: [Int] = [3, 5, 7, 9, 12]
                    for (col, fret) in fretNumbers.enumerated() {
                        if markerFrets.contains(fret) {
                            let cx = (CGFloat(col) + 0.5) * colWidth
                            let cy = size.height / 2
                            let dotRect = CGRect(x: cx - 2.5, y: cy - 2.5, width: 5, height: 5)
                            context.fill(Path(ellipseIn: dotRect), with: .color(Color(hex: 0xD9C79E).opacity(0.7)))
                        }
                    }

                    // 3. Vertical fret wires
                    for col in 0..<fretNumbers.count {
                        let x = CGFloat(col + 1) * colWidth
                        let wireWidth: CGFloat = (fretNumbers[col] == 0) ? 3 : 1.4
                        let wireRect = CGRect(x: x - wireWidth, y: 0, width: wireWidth, height: size.height)
                        context.fill(Path(wireRect), with: .color(Color(hex: 0xCFC6B7)))
                    }

                    // 4. Horizontal strings
                    for stringIndex in 0..<stringNames.count {
                        let y = (CGFloat(stringIndex) + 0.5) * rowHeight
                        let stringGauge: CGFloat = CGFloat(1 + (stringIndex / 2))
                        let stringRect = CGRect(x: 0, y: y - stringGauge / 2, width: size.width, height: stringGauge)
                        let stringColor = (stringIndex < 2) ? Color(hex: 0xC8C2B6) : MIMITheme.warmGold.opacity(0.85)
                        context.fill(Path(stringRect), with: .color(stringColor))
                    }

                    // 5. Highlighted fret notes (dynamic notes from score or rhythmic chord pattern)
                    let currentHighlights: [FretPosition]
                    if isPlaying {
                        if !notes.isEmpty {
                            currentHighlights = notes
                        } else {
                            let now = timeline.date.timeIntervalSinceReferenceDate
                            let patternIndex = Int(now / 0.28) % chordPatterns.count
                            currentHighlights = chordPatterns[patternIndex]
                        }
                    } else {
                        currentHighlights = [activeFret ?? FretPosition(string: 2, fret: 3)]
                    }

                    for pos in currentHighlights {
                        let stringIndex = 6 - pos.string
                        guard stringIndex >= 0 && stringIndex < stringNames.count else { continue }
                        guard let col = fretNumbers.firstIndex(of: pos.fret) else { continue }
                        let cellRect = CGRect(x: CGFloat(col) * colWidth, y: CGFloat(stringIndex) * rowHeight, width: colWidth, height: rowHeight)
                        context.fill(Path(cellRect), with: .color(MIMITheme.terracotta.opacity(0.18)))

                        let dotDiameter: CGFloat = 15
                        let dotRect = CGRect(x: cellRect.midX - dotDiameter / 2, y: cellRect.midY - dotDiameter / 2, width: dotDiameter, height: dotDiameter)
                        context.fill(Path(ellipseIn: dotRect), with: .color(MIMITheme.terracotta))

                        let text = Text(pos.fret == 0 ? "0" : "\(pos.fret)")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundColor(.white)
                        context.draw(context.resolve(text), at: CGPoint(x: dotRect.midX, y: dotRect.midY), anchor: .center)
                    }
                }
            }
            .gesture(
                SpatialTapGesture().onEnded { gesture in
                    let col = Int(gesture.location.x / colWidth)
                    let row = Int(gesture.location.y / rowHeight)
                    if col >= 0 && col < fretNumbers.count && row >= 0 && row < stringNames.count {
                        activeFret = FretPosition(string: 6 - row, fret: fretNumbers[col])
                    }
                }
            )
        }
        .frame(height: 156)
    }

    private var fretLabels: some View {
        HStack {
            Text("0品 / 空弦")
            Spacer()
            ForEach(["3", "5", "7", "9"], id: \.self) { fret in
                Text(fret)
                Spacer()
            }
            Text("12")
        }
        .font(.system(size: 9, weight: .medium, design: .monospaced))
        .foregroundStyle(MIMITheme.mutedInk)
        .padding(.leading, 29)
    }
}

