import SwiftUI

struct HomeChordChip: View {
    let chord: String
    var compact = false

    @State private var isPresented = false
    @State private var isPinned = false
    @State private var anchorHovered = false
    @State private var popoverHovered = false
    @FocusState private var isFocused: Bool

    private var fingering: [String]? { HomeChordFingerings.values[chord] }

    var body: some View {
        Button {
            isPinned.toggle()
            isPresented = isPinned || anchorHovered || isFocused
        } label: {
            Text(chord)
                .font(.system(size: compact ? 10 : 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(MIMITheme.bodyInk)
                .padding(.horizontal, compact ? 7 : 9)
                .frame(minWidth: compact ? 30 : 44, minHeight: compact ? 29 : 44)
                .background(.white, in: RoundedRectangle(cornerRadius: compact ? 7 : 9))
                .overlay(RoundedRectangle(cornerRadius: compact ? 7 : 9).stroke(MIMITheme.softBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .focused($isFocused)
        .accessibilityLabel(fingering == nil ? "查看\(chord)和弦指法图收录情况" : "预览\(chord)和弦指法图")
        .accessibilityHint("悬停或聚焦查看；点击可固定或关闭指法预览")
        .onHover { inside in
            anchorHovered = inside
            if inside { isPresented = true } else { scheduleHide() }
        }
        .onChange(of: isFocused) { focused in
            if focused { isPresented = true } else { scheduleHide() }
        }
        .popover(isPresented: $isPresented, arrowEdge: .top) {
            VStack(spacing: 7) {
                Text(fingering == nil ? "\(chord) 和弦" : "\(chord) 和弦指法图")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color(hex: 0xE2C078))
                ZStack {
                    RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(0.96))
                    if let fingering {
                        HomeChordDiagram(chord: chord, fingering: fingering)
                            .padding(7)
                    } else {
                        Text("暂未收录此和弦指法图")
                            .font(MIMITheme.bodyFont(size: 10))
                            .foregroundStyle(MIMITheme.bodyInk)
                            .multilineTextAlignment(.center)
                            .padding(8)
                    }
                }
                .frame(width: 96, height: 96)
            }
            .padding(11)
            .background(Color(hex: 0x2D2926))
            .onHover { inside in
                popoverHovered = inside
                if !inside { scheduleHide() }
            }
        }
    }

    private func scheduleHide() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            guard !anchorHovered, !popoverHovered, !isPinned, !isFocused else { return }
            isPresented = false
        }
    }
}

private struct HomeChordDiagram: View {
    let chord: String
    let fingering: [String]

    var body: some View {
        Canvas { context, size in
            let scale = min(size.width / 42, size.height / 44)
            let offset = CGPoint(x: (size.width - 42 * scale) / 2, y: (size.height - 44 * scale) / 2)
            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: offset.x + x * scale, y: offset.y + y * scale)
            }

            context.draw(Text(chord).font(.custom("Arial", size: 8 * scale)).foregroundColor(Color(hex: 0xE53E3E)), at: point(23, 11))
            let fretLines: [CGFloat] = [16, 23, 30, 37, 44]
            for y in fretLines {
                var path = Path(); path.move(to: point(8, y)); path.addLine(to: point(38, y))
                context.stroke(path, with: .color(Color(hex: 0x333333)), lineWidth: max(0.65, scale))
            }
            let stringX: [CGFloat] = [8, 14, 20, 26, 32, 38]
            for x in stringX {
                var path = Path(); path.move(to: point(x, 16)); path.addLine(to: point(x, 44))
                context.stroke(path, with: .color(Color(hex: 0x333333)), lineWidth: max(0.65, scale))
            }
            for (index, value) in fingering.enumerated() where index < stringX.count {
                let x = stringX[index]
                if value.lowercased() == "x" {
                    var cross = Path()
                    cross.move(to: point(x - 1.5, 12.5)); cross.addLine(to: point(x + 1.5, 15.5))
                    cross.move(to: point(x + 1.5, 12.5)); cross.addLine(to: point(x - 1.5, 15.5))
                    context.stroke(cross, with: .color(Color(hex: 0x333333)), lineWidth: max(0.9, 1.5 * scale))
                } else if let fret = Int(value), fret > 0 {
                    let center = point(x, 19.5 + CGFloat(fret - 1) * 7)
                    let radius = 2.5 * scale
                    context.fill(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)), with: .color(Color(hex: 0x555555)))
                }
            }
        }
        .accessibilityLabel("\(chord) 吉他和弦图")
    }
}

private enum HomeChordFingerings {
    static let values: [String: [String]] = [
        "C": ["x", "3", "2", "0", "1", "0"], "C7": ["x", "3", "2", "3", "1", "0"],
        "Cmaj7": ["x", "3", "2", "0", "0", "0"], "Cadd9": ["x", "3", "2", "0", "3", "0"],
        "Cm": ["x", "3", "1", "0", "1", "3"], "Caug": ["x", "3", "2", "1", "1", "0"],
        "D": ["x", "x", "0", "2", "3", "2"], "Dm": ["x", "x", "0", "2", "3", "1"],
        "Dm7": ["x", "x", "0", "2", "1", "1"], "D7": ["x", "x", "0", "2", "1", "2"],
        "Dsus2": ["x", "x", "0", "2", "3", "0"], "Dsus4": ["x", "x", "0", "2", "3", "3"],
        "D6": ["x", "x", "0", "2", "0", "2"], "D6add9": ["x", "x", "0", "2", "0", "0"],
        "Dmaj7": ["x", "x", "0", "2", "2", "2"], "D11": ["x", "5", "4", "5", "3", "0"],
        "A": ["x", "0", "2", "2", "2", "0"], "Am": ["x", "0", "2", "2", "1", "0"],
        "Am7": ["x", "0", "2", "0", "1", "0"], "A7": ["x", "0", "2", "0", "2", "0"],
        "Asus4": ["x", "0", "2", "2", "3", "0"], "Ab": ["x", "x", "1", "1", "1", "4"],
        "E": ["0", "2", "2", "1", "0", "0"], "Em": ["0", "2", "2", "0", "0", "0"],
        "Em7": ["0", "2", "2", "0", "3", "0"], "Emaj7": ["0", "2", "1", "1", "0", "0"],
        "E7": ["0", "2", "0", "1", "0", "0"], "Esus4": ["0", "2", "2", "2", "0", "0"],
        "F": ["1", "3", "3", "2", "1", "1"], "Fm": ["1", "3", "3", "1", "1", "1"],
        "Fmaj7": ["1", "x", "3", "2", "1", "0"], "Fmaj9": ["1", "x", "2", "1", "1", "0"],
        "F7": ["1", "3", "1", "2", "1", "1"], "G": ["3", "2", "0", "0", "0", "3"],
        "G6": ["3", "2", "0", "0", "0", "0"], "G7": ["3", "2", "0", "0", "0", "1"],
        "Gsus4": ["3", "2", "0", "0", "1", "3"], "Gsus2": ["3", "0", "0", "0", "3", "3"],
        "Gadd9": ["3", "0", "0", "0", "0", "3"], "Gm": ["3", "1", "0", "0", "3", "3"],
        "B": ["x", "2", "4", "4", "4", "2"], "Bm": ["x", "2", "4", "4", "3", "2"],
        "Bm7": ["x", "2", "4", "2", "3", "2"], "B7": ["x", "2", "1", "2", "0", "2"],
        "Bb": ["x", "1", "3", "3", "3", "1"], "F#m": ["2", "4", "4", "2", "2", "2"],
    ]
}
