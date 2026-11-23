import MIMICore
import SwiftUI

struct MasterpieceCard: View {
    let item: CatalogItem
    let info: StageMasterpiece
    let isPlaying: Bool
    let isLoading: Bool
    let statusMessage: String
    let onOpen: () -> Void
    let onTogglePlay: () -> Void

    init(
        item: CatalogItem,
        info: StageMasterpiece,
        isPlaying: Bool,
        isLoading: Bool,
        statusMessage: String,
        onOpen: @escaping () -> Void,
        onTogglePlay: @escaping () -> Void
    ) {
        self.item = item
        self.info = info
        self.isPlaying = isPlaying
        self.isLoading = isLoading
        self.statusMessage = statusMessage
        self.onOpen = onOpen
        self.onTogglePlay = onTogglePlay
    }

    @State private var isHovered = false
    @State private var isTitleHovered = false
    @State private var isAuditionHovered = false
    @State private var isCtaHovered = false

    private var source: SourceMasterpiece? {
        HomeMasterpieceData.rows.first(where: { $0.id == info.id })
    }

    private var themeColor: Color {
        source?.sealColor ?? MIMITheme.terracotta
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header Row: Song Seal Stamp + Key/Form Badge + Level/Difficulty Pill
            HStack(alignment: .center, spacing: 8) {
                Text(info.seal)
                    .font(MIMITheme.displayFont(size: 13, weight: .bold))
                    .foregroundStyle(themeColor)
                    .frame(width: 28, height: 28)
                    .background(
                        themeColor.opacity(0.09),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(themeColor.opacity(0.35), lineWidth: 1)
                    )
                    .shadow(color: themeColor.opacity(0.12), radius: 2, y: 1)

                Text("\(info.key) 调 · \(info.sheetForm)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(MIMITheme.bodyInk)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3.5)
                    .background(
                        Color.dynamic(lightHex: 0xF3EFE6, darkHex: 0x302A24),
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                    )

                Spacer()

                if let level = source?.level, let levelColor = source?.levelColor {
                    Text(level)
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(levelColor)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(levelColor.opacity(0.09), in: Capsule())
                        .overlay(Capsule().stroke(levelColor.opacity(0.28), lineWidth: 1))
                }
            }

            // Title & Artist Metadata
            VStack(alignment: .leading, spacing: 4) {
                Button(action: onOpen) {
                    Text(info.title)
                        .font(MIMITheme.displayFont(size: 20, weight: .bold))
                        .foregroundStyle(isTitleHovered ? themeColor : MIMITheme.ink)
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
                .onHover { isTitleHovered = $0 }

                Text("\(info.artist) · \(source?.timeSignature ?? "4/4 拍") · \(source?.keyDescription ?? "\(info.key) 调")")
                    .font(MIMITheme.bodyFont(size: 11))
                    .foregroundStyle(MIMITheme.mutedInk)
                    .lineLimit(1)
            }

            // Poetic Curator Description
            Text(info.description)
                .font(MIMITheme.bodyFont(size: 11.5))
                .foregroundStyle(MIMITheme.bodyInk)
                .lineSpacing(3.5)
                .lineLimit(2)
                .frame(minHeight: 34, alignment: .topLeading)

            // The Centerpiece: Authentic 6-Line Guitar TAB Stave
            MasterpieceTabScoreStage(
                masterpiece: source,
                fallbackInfo: info,
                isPlaying: isPlaying,
                isLoading: isLoading
            )

            // Dedicated Tactile Audition Pill Button
            Button(action: onTogglePlay) {
                HStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(isPlaying ? themeColor : (isAuditionHovered ? MIMITheme.darkGold : MIMITheme.ink))
                            .frame(width: 24, height: 24)
                        if isLoading {
                            ProgressView().controlSize(.small).tint(.white)
                        } else {
                            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 9.5, weight: .bold))
                                .foregroundStyle(.white)
                                .offset(x: isPlaying ? 0 : 0.8)
                        }
                    }

                    Text(isLoading ? "正在加载声效…" : (isPlaying ? "暂停前奏试听" : "试听原版声效"))
                        .font(MIMITheme.bodyFont(size: 10.5, weight: .semibold))
                        .foregroundStyle(isPlaying ? themeColor : MIMITheme.ink)

                    Spacer()

                    if !statusMessage.isEmpty {
                        Text(statusMessage)
                            .font(.system(size: 9))
                            .lineLimit(1)
                            .foregroundStyle(MIMITheme.mutedInk)
                    } else if let bpm = source?.bpm {
                        Text("♩=\(bpm)")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundStyle(MIMITheme.mutedInk)
                    }
                }
                .padding(.horizontal, 9)
                .frame(height: 35)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.dynamic(lightHex: 0xFFFFFF, darkHex: 0x2A2520))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(
                            isPlaying ? themeColor.opacity(0.55) : (isAuditionHovered ? MIMITheme.warmGold.opacity(0.5) : MIMITheme.softBorder),
                            lineWidth: 1
                        )
                )
                .shadow(
                    color: Color.black.opacity(isAuditionHovered ? 0.04 : 0.015),
                    radius: 2,
                    y: 1
                )
            }
            .buttonStyle(.plain)
            .disabled((item.scoreURL?.isEmpty != false))
            .onHover { isAuditionHovered = $0 }

            // Bottom Harmonic Palette & "研习乐谱 →" CTA
            HStack(spacing: 5) {
                HStack(spacing: 4) {
                    ForEach(info.chords.prefix(3), id: \.self) { chord in
                        HomeChordChip(chord: chord, compact: true)
                    }
                }
                Spacer(minLength: 4)
                Button(action: onOpen) {
                    HStack(spacing: 4) {
                        Text("研习曲谱")
                        Image(systemName: "arrow.right")
                            .font(.system(size: 8.5, weight: .bold))
                    }
                    .font(MIMITheme.bodyFont(size: 10.5, weight: .semibold))
                    .foregroundStyle(isCtaHovered ? .white : MIMITheme.darkGold)
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(
                        isCtaHovered ? MIMITheme.darkGold : MIMITheme.warmGold.opacity(0.12),
                        in: Capsule()
                    )
                    .overlay(
                        Capsule().stroke(MIMITheme.warmGold.opacity(isCtaHovered ? 0 : 0.35), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .onHover { isCtaHovered = $0 }
            }
        }
        .padding(15)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.dynamic(lightHex: 0xFFFFFF, darkHex: 0x27231E),
                            Color.dynamic(lightHex: 0xFAF7F2, darkHex: 0x231F1A)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(
                    isPlaying ? themeColor.opacity(0.6) : (isHovered ? MIMITheme.warmGold.opacity(0.55) : MIMITheme.softBorder),
                    lineWidth: 1
                )
        )
        .shadow(
            color: Color(nsColor: .dynamic(lightHex: 0x483620, darkHex: 0x000000))
                .opacity(isHovered ? 0.08 : (isPlaying ? 0.06 : 0.025)),
            radius: isHovered ? 12 : 3,
            x: 0,
            y: isHovered ? 5 : 1.5
        )
        .offset(y: isHovered ? -3 : 0)
        .animation(.spring(response: 0.28, dampingFraction: 0.78), value: isHovered)
        .onHover { isHovered = $0 }
    }
}

struct MasterpieceRhythmBars: View {
    let isPlaying: Bool
    let color: Color
    @State private var phase = false

    var body: some View {
        HStack(spacing: 2.5) {
            ForEach(0..<4) { index in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(isPlaying ? color : MIMITheme.mutedInk.opacity(0.35))
                    .frame(width: 2.5, height: barHeight(for: index))
            }
        }
        .frame(height: 12, alignment: .bottom)
        .onAppear {
            if isPlaying {
                withAnimation(.easeInOut(duration: 0.45).repeatForever(autoreverses: true)) {
                    phase.toggle()
                }
            }
        }
        .onChange(of: isPlaying) { playing in
            if playing {
                withAnimation(.easeInOut(duration: 0.45).repeatForever(autoreverses: true)) {
                    phase.toggle()
                }
            } else {
                phase = false
            }
        }
    }

    private func barHeight(for index: Int) -> CGFloat {
        if !isPlaying {
            let staticHeights: [CGFloat] = [4, 7, 5, 8]
            return staticHeights[index % 4]
        }
        if phase {
            let heightsA: [CGFloat] = [11, 4, 12, 6]
            return heightsA[index % 4]
        } else {
            let heightsB: [CGFloat] = [5, 12, 6, 11]
            return heightsB[index % 4]
        }
    }
}

struct MasterpieceTabScoreStage: View {
    let masterpiece: SourceMasterpiece?
    let fallbackInfo: StageMasterpiece
    let isPlaying: Bool
    let isLoading: Bool

    @State private var playheadPhase: Double = 0

    var body: some View {
        VStack(spacing: 4) {
            // Header bar inside the manuscript box
            HStack(spacing: 5) {
                Image(systemName: "guitars.fill")
                    .font(.system(size: 8.5))
                    .foregroundStyle(masterpiece?.sealColor ?? MIMITheme.terracotta)
                Text("原版六线谱 · 前奏片段")
                    .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(MIMITheme.bodyInk)
                Spacer()
                MasterpieceRhythmBars(isPlaying: isPlaying, color: masterpiece?.sealColor ?? MIMITheme.warmGold)
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)

            // The 6-line staff Canvas
            Canvas { context, size in
                let columns = masterpiece?.tabColumns ?? []
                let width = size.width
                let height = size.height

                let staffColor = Color(nsColor: .dynamic(lightHex: 0xDDD3C0, darkHex: 0x443B32))
                let barLineColor = Color(nsColor: .dynamic(lightHex: 0xCFBEA3, darkHex: 0x54493E))
                let notePaperColor = Color(nsColor: .dynamic(lightHex: 0xF7F4EB, darkHex: 0x221E1A))
                let textColor = Color(nsColor: .dynamic(lightHex: 0x24201D, darkHex: 0xF5EFE6))
                let rootColor = masterpiece?.sealColor ?? MIMITheme.terracotta
                let chordLabelColor = Color(nsColor: .dynamic(lightHex: 0x8F6B28, darkHex: 0xE0B65C))

                // Margins
                let leftMargin: CGFloat = 24
                let rightMargin: CGFloat = width - 8
                let topMargin: CGFloat = 17 // room for chord names at y: 6
                let bottomMargin: CGFloat = height - 7
                let staffHeight = bottomMargin - topMargin
                let lineSpacing = staffHeight / 5.0

                // TAB label on the left margin
                let tabLabels: [(String, CGFloat)] = [
                    ("T", topMargin + lineSpacing * 0.8),
                    ("A", topMargin + lineSpacing * 2.5),
                    ("B", topMargin + lineSpacing * 4.2)
                ]
                for (char, y) in tabLabels {
                    context.draw(
                        Text(char).font(.system(size: 7.5, weight: .black, design: .monospaced)).foregroundColor(MIMITheme.mutedInk.opacity(0.7)),
                        at: CGPoint(x: 10, y: y),
                        anchor: .center
                    )
                }

                // Bar lines (start and end)
                var leftBar = Path()
                leftBar.move(to: CGPoint(x: leftMargin, y: topMargin))
                leftBar.addLine(to: CGPoint(x: leftMargin, y: bottomMargin))
                context.stroke(leftBar, with: .color(barLineColor), lineWidth: 1.2)

                var rightBar = Path()
                rightBar.move(to: CGPoint(x: rightMargin, y: topMargin))
                rightBar.addLine(to: CGPoint(x: rightMargin, y: bottomMargin))
                context.stroke(rightBar, with: .color(barLineColor), lineWidth: 1.2)

                // 6 guitar strings
                for i in 0..<6 {
                    let y = topMargin + CGFloat(i) * lineSpacing
                    var line = Path()
                    line.move(to: CGPoint(x: leftMargin, y: y))
                    line.addLine(to: CGPoint(x: rightMargin, y: y))
                    context.stroke(line, with: .color(staffColor), lineWidth: 0.8)
                }

                // Note columns
                let displayColumns: [SourceTabColumn]
                if !columns.isEmpty {
                    displayColumns = columns
                } else {
                    displayColumns = fallbackInfo.chords.prefix(4).map { SourceTabColumn(chordName: $0, notes: []) }
                }

                let colCount = max(1, displayColumns.count)
                let availableWidth = rightMargin - leftMargin - 16
                let colSpacing = availableWidth / CGFloat(colCount)

                for (colIdx, col) in displayColumns.enumerated() {
                    let x = leftMargin + 10 + CGFloat(colIdx) * colSpacing + colSpacing * 0.45

                    // Chord name above the staff
                    if !col.chordName.isEmpty {
                        context.draw(
                            Text(col.chordName).font(.system(size: 9.5, weight: .bold, design: .monospaced)).foregroundColor(chordLabelColor),
                            at: CGPoint(x: x, y: 7),
                            anchor: .center
                        )
                    }

                    // Notes
                    for note in col.notes {
                        guard note.string >= 1 && note.string <= 6 else { continue }
                        let y = topMargin + CGFloat(note.string - 1) * lineSpacing

                        // Clean paper cutout so string doesn't cut through number
                        let cutoutRect = CGRect(x: x - 6.5, y: y - 5, width: 13, height: 10)
                        context.fill(Path(roundedRect: cutoutRect, cornerRadius: 2), with: .color(notePaperColor))

                        let noteColor = note.isRoot ? rootColor : textColor
                        context.draw(
                            Text(String(note.fret)).font(.system(size: 9.5, weight: .bold, design: .monospaced)).foregroundColor(noteColor),
                            at: CGPoint(x: x, y: y),
                            anchor: .center
                        )
                    }
                }

                // Animated sweep playhead if isPlaying
                if isPlaying {
                    let sweepX = leftMargin + 4 + (rightMargin - leftMargin - 8) * playheadPhase
                    var playhead = Path()
                    playhead.move(to: CGPoint(x: sweepX, y: topMargin - 3))
                    playhead.addLine(to: CGPoint(x: sweepX, y: bottomMargin + 3))
                    context.stroke(
                        playhead,
                        with: .color(rootColor.opacity(0.85)),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round)
                    )
                }
            }
            .frame(height: 70)
            .padding(.bottom, 6)
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.dynamic(lightHex: 0xF7F4EB, darkHex: 0x221E1A))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.dynamic(lightHex: 0xE5DCB0, darkHex: 0x3A332B), lineWidth: 1)
        )
        .onAppear {
            if isPlaying { startPlayheadAnimation() }
        }
        .onChange(of: isPlaying) { playing in
            if playing { startPlayheadAnimation() }
            else { playheadPhase = 0 }
        }
    }

    private func startPlayheadAnimation() {
        withAnimation(.linear(duration: 2.4).repeatForever(autoreverses: false)) {
            playheadPhase = 1.0
        }
    }
}

