import MIMICore
import SwiftUI

struct HomeHeroBackdrop: View {
    var body: some View {
        ZStack(alignment: .topTrailing) {
            LinearGradient(colors: [MIMITheme.paperWhite.opacity(0.97), Color(hex: 0xFCF8F0), MIMITheme.paperWhite], startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [MIMITheme.warmGold.opacity(0.12), .clear], center: UnitPoint(x: 0.85, y: 0.08), startRadius: 10, endRadius: 600)
            PaperGrainOverlay()
        }
    }
}

struct HomeAuditionScope<Content: View>: View {
    @StateObject private var state: AuditionItemViewState
    let content: (AuditionPlaybackSnapshot) -> Content

    init(controller: NativeAuditionController, @ViewBuilder content: @escaping (AuditionPlaybackSnapshot) -> Content) {
        _state = StateObject(wrappedValue: controller.viewState())
        self.content = content
    }

    var body: some View {
        content(state.snapshot)
    }
}


struct HomeHotwordFlowLayout: Layout {
    var spacing: CGFloat = 7

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let availableWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var usedWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > availableWidth {
                usedWidth = max(usedWidth, x - spacing)
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        usedWidth = max(usedWidth, max(0, x - spacing))
        return CGSize(width: min(availableWidth, usedWidth), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(
                at: CGPoint(x: x, y: y),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: size.width, height: size.height)
            )
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

struct HomeSearchField: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("mimi.motion.preference") private var motionPreference = "system"
    let isHeroVisible: Bool
    let onSubmit: (String) -> Void

    init(isHeroVisible: Bool, onSubmit: @escaping (String) -> Void) {
        self.isHeroVisible = isHeroVisible
        self.onSubmit = onSubmit
    }
    @State private var searchText = ""
    @FocusState private var isFocused: Bool
    @State private var displayedPlaceholder = HomeSearchPlaceholder.values[0]
    @State private var placeholderIndex = 0
    @State private var typewriterTimer: Timer?

    private var canRunTypewriter: Bool {
        motionPreference == "system" && !reduceMotion && isHeroVisible && !isFocused && scenePhase == .active
    }

    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: "magnifyingglass").font(.system(size: 15)).foregroundStyle(MIMITheme.mutedInk).padding(.leading, 16)
            TextField(displayedPlaceholder, text: $searchText)
                .font(MIMITheme.bodyFont(size: 15)).textFieldStyle(.plain)
                .padding(.horizontal, 12).frame(height: 55)
                .focused($isFocused)
                .onSubmit { onSubmit(searchText) }
            Button { onSubmit(searchText) } label: {
                HStack(spacing: 7) {
                    Text("检索").font(MIMITheme.bodyFont(size: 13, weight: .semibold))
                    Text("⌘K").font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(MIMITheme.warmGold)
                }
                .foregroundStyle(MIMITheme.paperWhite)
                .padding(.horizontal, 17).frame(height: 39)
                .background(MIMITheme.ink, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain).padding(.trailing, 8)
        }
        .background(MIMITheme.paper, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(MIMITheme.softBorder, lineWidth: 1))
        .onAppear { syncTypewriter() }
        .onDisappear { stopTypewriter(reset: true) }
        .onChange(of: isFocused) { _ in syncTypewriter() }
        .onChange(of: isHeroVisible) { _ in syncTypewriter() }
        .onChange(of: scenePhase) { _ in syncTypewriter() }
        .onChange(of: motionPreference) { _ in syncTypewriter() }
        .onChange(of: reduceMotion) { _ in syncTypewriter() }
    }

    private func syncTypewriter() {
        stopTypewriter(reset: false)
        guard canRunTypewriter else { return }
        scheduleTypewriter(after: 4.5)
    }

    private func stopTypewriter(reset: Bool) {
        typewriterTimer?.invalidate()
        typewriterTimer = nil
        guard reset else { return }
        placeholderIndex = 0
        displayedPlaceholder = HomeSearchPlaceholder.values[0]
    }

    private func scheduleTypewriter(after interval: TimeInterval) {
        typewriterTimer?.invalidate()
        typewriterTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            guard canRunTypewriter else { stopTypewriter(reset: false); return }
            placeholderIndex = (placeholderIndex + 1) % HomeSearchPlaceholder.values.count
            displayedPlaceholder = HomeSearchPlaceholder.values[placeholderIndex]
        }
    }
}

struct HeroFeatureCard: View {
    let item: CatalogItem
    let masterpiece: SourceMasterpiece
    let controller: NativeAuditionController
    let onShuffle: () -> Void
    let onOpen: () -> Void
    @StateObject private var auditionState: AuditionItemViewState
    @State private var isHovered = false

    private var playback: AuditionPlaybackSnapshot { auditionState.snapshot }
    private var isActive: Bool { playback.isActive }

    init(item: CatalogItem, masterpiece: SourceMasterpiece, controller: NativeAuditionController, onShuffle: @escaping () -> Void, onOpen: @escaping () -> Void) {
        self.item = item
        self.masterpiece = masterpiece
        self.controller = controller
        self.onShuffle = onShuffle
        self.onOpen = onOpen
        _auditionState = StateObject(wrappedValue: controller.viewState(itemID: item.id, tracksClock: true))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                HStack(spacing: 8) {
                    Text(masterpiece.seal).font(MIMITheme.displayFont(size: 13, weight: .bold)).foregroundStyle(masterpiece.sealColor)
                        .frame(width: 27, height: 27).background(masterpiece.sealColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(masterpiece.sealColor.opacity(0.35), lineWidth: 1))
                    Text("今日典藏焦点").font(.system(size: 10, weight: .bold, design: .monospaced)).tracking(1).foregroundStyle(MIMITheme.mutedInk)
                }
                Spacer(minLength: 3)
                Button(action: onShuffle) {
                    Label("换一曲", systemImage: "shuffle").font(MIMITheme.bodyFont(size: 10, weight: .medium))
                        .foregroundStyle(MIMITheme.bodyInk).padding(.horizontal, 10).frame(height: 32)
                        .background(MIMITheme.paper, in: Capsule()).overlay(Capsule().stroke(MIMITheme.softBorder, lineWidth: 1))
                }.buttonStyle(.plain).help("切换到下一首源站典藏名作")
                MIMIPill(title: "精选展示", tint: MIMITheme.terracotta, fill: MIMITheme.terracotta.opacity(0.08))
            }
            HStack(alignment: .firstTextBaseline) {
                Text(masterpiece.title).font(MIMITheme.displayFont(size: 26, weight: .bold)).foregroundStyle(MIMITheme.ink)
                Spacer(minLength: 4)
                MIMIPill(title: masterpiece.keyDescription, tint: Color(hex: 0x8F6D2B), fill: MIMITheme.warmGold.opacity(0.12))
            }
            Text("\(masterpiece.artist) · 速度 J=\(masterpiece.bpm) · \(masterpiece.timeSignature)")
                .font(MIMITheme.bodyFont(size: 11)).foregroundStyle(MIMITheme.mutedInk)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("ORIGINAL TAB MANUSCRIPT", systemImage: "music.note")
                        .font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundStyle(MIMITheme.bodyInk)
                    Spacer()
                    Text(masterpiece.level)
                        .font(MIMITheme.bodyFont(size: 10, weight: .semibold))
                        .foregroundStyle(masterpiece.levelColor)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(masterpiece.levelColor.opacity(0.09), in: Capsule())
                        .overlay(Capsule().stroke(masterpiece.levelColor.opacity(0.28), lineWidth: 1))
                }
                HeroTabStaff(masterpiece: masterpiece, progress: isActive && playback.isPlaying && auditionState.clock.endTime > 0 ? auditionState.clock.currentTime / auditionState.clock.endTime : nil)
                    .frame(height: 74)
                Button {
                    if !(item.scoreURL?.isEmpty != false) { controller.toggle(item: item) } else { onOpen() }
                } label: {
                    HStack(spacing: 9) {
                        if playback.isLoading { ProgressView().controlSize(.small).tint(.white) }
                        else { Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill") }
                        Text(playback.isLoading ? "加载曲谱…" : (playback.isPlaying ? "暂停播放" : "播放曲谱"))
                        Spacer()
                        if isActive && !playback.statusMessage.isEmpty {
                            Text(playback.statusMessage).font(.system(size: 9)).lineLimit(1).foregroundStyle(.white.opacity(0.75))
                        }
                    }
                    .font(MIMITheme.bodyFont(size: 12, weight: .semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 14).frame(minHeight: 44)
                    .background(LinearGradient(colors: [MIMITheme.ink, Color(hex: 0x3D3833), MIMITheme.ink], startPoint: .leading, endPoint: .trailing), in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .disabled((item.scoreURL?.isEmpty != false))
                if isActive && !playback.isLoading && !playback.isPlaying && !playback.canPlay && !playback.statusMessage.isEmpty {
                    HStack(spacing: 6) {
                        Text("曲谱播放失败：\(playback.statusMessage)").lineLimit(2)
                        Button("打开《\(masterpiece.title)》曲谱", action: onOpen).underline()
                    }
                    .font(MIMITheme.bodyFont(size: 10)).foregroundStyle(Color(hex: 0x9B3328))
                }
            }
            .padding(13)
            .background(Color(hex: 0xFAF8F4), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(MIMITheme.softBorder, lineWidth: 1))
            HStack(spacing: 6) {
                Text("核心和弦:").font(MIMITheme.bodyFont(size: 10)).foregroundStyle(MIMITheme.mutedInk)
                ForEach(masterpiece.chords, id: \.self) { chord in HomeChordChip(chord: chord) }
                Spacer(minLength: 4)
                Button("研习 →", action: onOpen).font(MIMITheme.bodyFont(size: 11, weight: .semibold)).foregroundStyle(MIMITheme.darkGold).buttonStyle(.plain)
            }
        }
        .padding(20)
        .background(
            LinearGradient(colors: [Color(hex: 0xFAF7F0), MIMITheme.paperWhite, Color(hex: 0xFAF6EE)], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 25, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 25, style: .continuous)
                .stroke(isHovered ? MIMITheme.warmGold.opacity(0.45) : MIMITheme.softBorder, lineWidth: 1)
        )
        .onHover { isHovered = $0 }
    }
}


struct HeroTabStaff: View {
    let masterpiece: SourceMasterpiece
    let progress: Double?

    var body: some View {
        Canvas { context, size in
            let scale = min(size.width / 300, size.height / 74)
            var drawing = context
            drawing.translateBy(x: (size.width - 300 * scale) / 2, y: (size.height - 74 * scale) / 2)
            drawing.scaleBy(x: scale, y: scale)
            let paper = Color(hex: 0xFAF8F4)
            let staff = Color(hex: 0xE0D6C0)
            let divider = Color(hex: 0xD5C7B0)
            let labels: [(String, CGFloat)] = [("T", 23), ("A", 41), ("B", 59)]
            for (label, y) in labels {
                drawing.draw(Text(label).font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundColor(MIMITheme.mutedInk), at: CGPoint(x: 6, y: y))
            }
            let barLines: [CGFloat] = [20, 292]
            for x in barLines {
                var path = Path(); path.move(to: CGPoint(x: x, y: 12)); path.addLine(to: CGPoint(x: x, y: 62))
                drawing.stroke(path, with: .color(divider), lineWidth: 1.5)
            }
            let staffLines: [CGFloat] = [12, 22, 32, 42, 52, 62]
            for y in staffLines {
                var path = Path(); path.move(to: CGPoint(x: 20, y: y)); path.addLine(to: CGPoint(x: 292, y: y))
                drawing.stroke(path, with: .color(staff), lineWidth: 1)
            }
            for (columnIndex, column) in masterpiece.tabColumns.enumerated() {
                let x: CGFloat = 60 + CGFloat(columnIndex) * 65
                for note in column.notes {
                    let y: CGFloat = 12 + CGFloat(note.string - 1) * 10
                    drawing.fill(Path(CGRect(x: x - 7, y: y - 6, width: 14, height: 12)), with: .color(paper))
                    drawing.draw(Text(String(note.fret)).font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundColor(note.isRoot ? MIMITheme.terracotta : MIMITheme.ink), at: CGPoint(x: x, y: y + 4))
                }
            }
            if let progress {
                let x = CGFloat(35 + min(1, max(0, progress)) * 245)
                var playhead = Path(); playhead.move(to: CGPoint(x: x, y: 4)); playhead.addLine(to: CGPoint(x: x, y: 70))
                drawing.stroke(playhead, with: .color(MIMITheme.terracotta.opacity(0.9)), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            }
        }
        .accessibilityLabel("\(masterpiece.title) 原版六线谱片段")
    }
}



struct PaperGrainOverlay: View {
    var opacity = 0.14
    var body: some View {
        Image(decorative: PaperAmbienceTile.grain, scale: 2, orientation: .up)
            .resizable(resizingMode: .tile)
            .opacity(opacity / 0.14)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

