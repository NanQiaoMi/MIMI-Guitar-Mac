import MIMICore
import SwiftUI

struct NativeStudioChord: Identifiable, Hashable {
    let name: String
    let root: String
    let frets: [Int]
    let detail: String
    var id: String { name }
}

enum NativeStudioChordLibrary {
    static let guitar: [NativeStudioChord] = [
        .init(name: "C", root: "C", frets: [-1, 3, 2, 0, 1, 0], detail: "C 大调主和弦"),
        .init(name: "Cmaj7", root: "C", frets: [-1, 3, 2, 0, 0, 0], detail: "C 大七和弦"),
        .init(name: "Cadd9", root: "C", frets: [-1, 3, 2, 0, 3, 0], detail: "流行常用加九和弦"),
        .init(name: "Csus4", root: "C", frets: [-1, 3, 3, 0, 1, 0], detail: "C 挂四和弦"),
        .init(name: "D", root: "D", frets: [-1, -1, 0, 2, 3, 2], detail: "D 大三和弦"),
        .init(name: "Dm", root: "D", frets: [-1, -1, 0, 2, 3, 1], detail: "D 小三和弦"),
        .init(name: "D7", root: "D", frets: [-1, -1, 0, 2, 1, 2], detail: "D 属七和弦"),
        .init(name: "Dsus4", root: "D", frets: [-1, -1, 0, 2, 3, 3], detail: "D 挂四和弦"),
        .init(name: "D/F#", root: "D", frets: [2, 0, 0, 2, 3, 2], detail: "D 转位斜杠和弦"),
        .init(name: "E", root: "E", frets: [0, 2, 2, 1, 0, 0], detail: "E 大三和弦"),
        .init(name: "Em", root: "E", frets: [0, 2, 2, 0, 0, 0], detail: "Em 小三和弦"),
        .init(name: "Em7", root: "E", frets: [0, 2, 2, 0, 3, 0], detail: "Em7 小七和弦"),
        .init(name: "E7", root: "E", frets: [0, 2, 0, 1, 0, 0], detail: "E 属七和弦"),
        .init(name: "F", root: "F", frets: [1, 3, 3, 2, 1, 1], detail: "F 大横按和弦"),
        .init(name: "Fmaj7", root: "F", frets: [-1, -1, 3, 2, 1, 0], detail: "F 大七和弦（小横按）"),
        .init(name: "Fm", root: "F", frets: [1, 3, 3, 1, 1, 1], detail: "F 小三和弦"),
        .init(name: "G", root: "G", frets: [3, 2, 0, 0, 0, 3], detail: "G 大三和弦"),
        .init(name: "G/B", root: "G", frets: [-1, 2, 0, 0, 3, 3], detail: "G 转位斜杠和弦"),
        .init(name: "G7", root: "G", frets: [3, 2, 0, 0, 0, 1], detail: "G 属七和弦"),
        .init(name: "Gsus4", root: "G", frets: [3, 2, 0, 0, 1, 3], detail: "G 挂四和弦"),
        .init(name: "A", root: "A", frets: [-1, 0, 2, 2, 2, 0], detail: "A 大三和弦"),
        .init(name: "Am", root: "A", frets: [-1, 0, 2, 2, 1, 0], detail: "Am 小三和弦"),
        .init(name: "Am7", root: "A", frets: [-1, 0, 2, 0, 1, 0], detail: "Am7 小七和弦"),
        .init(name: "A7", root: "A", frets: [-1, 0, 2, 0, 2, 0], detail: "A 属七和弦"),
        .init(name: "Asus2", root: "A", frets: [-1, 0, 2, 2, 0, 0], detail: "A 挂二和弦"),
        .init(name: "Bm", root: "B", frets: [-1, 2, 4, 4, 3, 2], detail: "Bm 小三和弦"),
        .init(name: "Bm7", root: "B", frets: [-1, 2, 4, 2, 3, 2], detail: "Bm7 小七和弦"),
        .init(name: "B7", root: "B", frets: [-1, 2, 1, 2, 0, 2], detail: "B 属七和弦"),
    ]

    static let ukulele: [NativeStudioChord] = [
        .init(name: "C", root: "C", frets: [0, 0, 0, 3], detail: "C 大三和弦"),
        .init(name: "Cmaj7", root: "C", frets: [0, 0, 0, 2], detail: "C 大七和弦"),
        .init(name: "C7", root: "C", frets: [0, 0, 0, 1], detail: "C 属七和弦"),
        .init(name: "D", root: "D", frets: [2, 2, 2, 0], detail: "D 大三和弦"),
        .init(name: "Dm", root: "D", frets: [2, 2, 1, 0], detail: "D 小三和弦"),
        .init(name: "D7", root: "D", frets: [2, 0, 2, 0], detail: "D 属七和弦"),
        .init(name: "Em", root: "E", frets: [0, 4, 3, 2], detail: "Em 小三和弦"),
        .init(name: "Em7", root: "E", frets: [0, 2, 0, 2], detail: "Em7 小七和弦"),
        .init(name: "E7", root: "E", frets: [1, 2, 0, 2], detail: "E7 属七和弦"),
        .init(name: "F", root: "F", frets: [2, 0, 1, 0], detail: "F 大三和弦"),
        .init(name: "Fm", root: "F", frets: [1, 0, 1, 3], detail: "F 小三和弦"),
        .init(name: "G", root: "G", frets: [0, 2, 3, 2], detail: "G 大三和弦"),
        .init(name: "G7", root: "G", frets: [0, 2, 1, 2], detail: "G 属七和弦"),
        .init(name: "A", root: "A", frets: [2, 1, 0, 0], detail: "A 大三和弦"),
        .init(name: "Am", root: "A", frets: [2, 0, 0, 0], detail: "Am 小三和弦"),
        .init(name: "Am7", root: "A", frets: [0, 0, 0, 0], detail: "Am7 小七和弦"),
        .init(name: "A7", root: "A", frets: [0, 1, 0, 0], detail: "A7 属七和弦"),
        .init(name: "Bm", root: "B", frets: [4, 2, 2, 2], detail: "Bm 小三和弦"),
        .init(name: "B7", root: "B", frets: [2, 3, 2, 2], detail: "B7 属七和弦"),
    ]

    static func chords(for track: StudioTrack?) -> [NativeStudioChord] {
        guard let track else { return guitar }
        if track.program == 33 { return [] }
        return track.tuning.count == 4 || track.program == 24 ? ukulele : guitar
    }
}

struct NativeStudioChordDiagram: View {
    let chord: NativeStudioChord

    var body: some View {
        Canvas { context, size in
            let count = max(1, chord.frets.count)
            let left: CGFloat = 7
            let right: CGFloat = size.width - 7
            let top: CGFloat = 9
            let bottom: CGFloat = size.height - 7
            let fretCount: CGFloat = 4
            for string in 0..<count {
                let x = left + (right - left) * CGFloat(string) / CGFloat(max(1, count - 1))
                var line = Path(); line.move(to: CGPoint(x: x, y: top)); line.addLine(to: CGPoint(x: x, y: bottom))
                context.stroke(line, with: .color(Color(nsColor: .separatorColor)), lineWidth: 1)
            }
            for fret in 0...4 {
                let y = top + (bottom - top) * CGFloat(fret) / fretCount
                var line = Path(); line.move(to: CGPoint(x: left, y: y)); line.addLine(to: CGPoint(x: right, y: y))
                context.stroke(line, with: .color(fret == 0 ? Color.primary.opacity(0.75) : Color.secondary.opacity(0.35)), lineWidth: fret == 0 ? 1.5 : 0.8)
            }
            for (index, fret) in chord.frets.enumerated() {
                let x = left + (right - left) * CGFloat(index) / CGFloat(max(1, count - 1))
                let marker = CGRect(x: x - 3.2, y: 2, width: 6.4, height: 6.4)
                if fret < 0 {
                    var cross = Path(); cross.move(to: CGPoint(x: marker.minX, y: marker.minY)); cross.addLine(to: CGPoint(x: marker.maxX, y: marker.maxY)); cross.move(to: CGPoint(x: marker.maxX, y: marker.minY)); cross.addLine(to: CGPoint(x: marker.minX, y: marker.maxY))
                    context.stroke(cross, with: .color(Color.secondary), lineWidth: 1)
                } else if fret == 0 {
                    context.stroke(Path(ellipseIn: marker), with: .color(Color.secondary), lineWidth: 0.8)
                } else if fret <= 4 {
                    let y = top + (bottom - top) * (CGFloat(fret) - 0.5) / fretCount
                    context.fill(Path(ellipseIn: CGRect(x: x - 3.3, y: y - 3.3, width: 6.6, height: 6.6)), with: .color(Color(red: 0.59, green: 0.42, blue: 0.10)))
                }
            }
        }
        .frame(width: 54, height: 67)
        .accessibilityHidden(true)
    }
}

struct NativeStudioFretboard: View, Equatable {
    let track: StudioTrack
    let notes: [StudioNote]
    let capo: Int
    let selectedString: Int
    let selectedFret: Int
    var onSelect: (Int, Int) -> Void

    private let frets = Array(0...24)
    private let dots: Set<Int> = [3, 5, 7, 9, 15, 17, 19, 21]
    private let doubleDots: Set<Int> = [12, 24]

    static func == (lhs: NativeStudioFretboard, rhs: NativeStudioFretboard) -> Bool {
        // The action closes over the stable Studio @StateObject. Compare only
        // the values rendered by the board so unrelated model publications do
        // not rebuild its 150 interactive cells.
        lhs.track.name == rhs.track.name &&
        lhs.track.tuningName == rhs.track.tuningName &&
        lhs.track.tuning == rhs.track.tuning &&
        lhs.notes == rhs.notes &&
        lhs.capo == rhs.capo &&
        lhs.selectedString == rhs.selectedString &&
        lhs.selectedFret == rhs.selectedFret
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Label("\(track.name) · 24 品实况指板", systemImage: "guitars").font(.system(size: 12, weight: .semibold))
                Text(track.tuningName).font(.system(size: 10, design: .rounded)).padding(.horizontal, 7).padding(.vertical, 3).background(Color.secondary.opacity(0.10), in: Capsule())
                if capo > 0 { Text("Capo \(capo) 品").font(.system(size: 10, weight: .bold)).foregroundStyle(.orange) }
                Spacer()
                Text("点击试听并写入当前拍").font(.system(size: 10)).foregroundStyle(.secondary)
            }
            ScrollView(.horizontal) {
                VStack(spacing: 1) {
                    HStack(spacing: 0) {
                        Text("弦 / 品").frame(width: 72)
                        ForEach(frets, id: \.self) { fret in
                            Text(fret == 0 ? "空弦" : String(fret))
                                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                .foregroundStyle(doubleDots.contains(fret) ? Color.primary : (dots.contains(fret) ? Color.brown : Color.secondary))
                                .frame(width: fret == 0 ? 40 : 34)
                        }
                    }.frame(height: 20).overlay(alignment: .bottom) { Rectangle().fill(Color.secondary.opacity(0.18)).frame(height: 1) }
                    ForEach(1...max(1, track.tuning.count), id: \.self) { string in
                        HStack(spacing: 0) {
                            Text("\(string)弦  \(noteName(midi(for: string)))")
                                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                .foregroundStyle(Color(red: 0.54, green: 0.42, blue: 0.16))
                                .frame(width: 72, alignment: .center)
                            ForEach(frets, id: \.self) { fret in
                                let active = notes.contains { $0.string == string && $0.fret == fret }
                                let selected = string == selectedString && fret == selectedFret
                                NativeStudioFretboardCell(
                                    string: string,
                                    fret: fret,
                                    isActive: active,
                                    isSelected: selected,
                                    stringThickness: stringThickness(string),
                                    hasDoubleDot: doubleDots.contains(fret),
                                    hasDot: dots.contains(fret),
                                    onSelect: onSelect
                                )
                                .equatable()
                            }
                        }
                    }
                }
                .padding(.vertical, 5)
                .background(LinearGradient(colors: [Color(red: 0.96, green: 0.94, blue: 0.89), .white, Color(red: 0.95, green: 0.92, blue: 0.85)], startPoint: .top, endPoint: .bottom), in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color(red: 0.86, green: 0.82, blue: 0.75), lineWidth: 1))
            }
            .scrollIndicators(.visible)
        }
        .padding(9)
        .background(Color(red: 0.98, green: 0.97, blue: 0.94), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(red: 0.91, green: 0.88, blue: 0.82), lineWidth: 1))
    }

    private func stringThickness(_ string: Int) -> Double { max(0.45, Double(track.tuning.count - string + 1) * 0.14) }
    private func midi(for string: Int) -> Int { track.tuning.indices.contains(string - 1) ? track.tuning[string - 1] : 64 }
    private func noteName(_ midi: Int) -> String {
        let names = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]
        return "\(names[(midi % 12 + 12) % 12])\(midi / 12 - 1)"
    }
}

private struct NativeStudioFretboardCell: View, Equatable {
    let string: Int
    let fret: Int
    let isActive: Bool
    let isSelected: Bool
    let stringThickness: Double
    let hasDoubleDot: Bool
    let hasDot: Bool
    var onSelect: (Int, Int) -> Void

    private var width: CGFloat { fret == 0 ? 40 : 34 }

    static func == (lhs: NativeStudioFretboardCell, rhs: NativeStudioFretboardCell) -> Bool {
        // The callback is stable for this board; all visible and accessible
        // cell state is represented by these scalar values.
        lhs.string == rhs.string &&
        lhs.fret == rhs.fret &&
        lhs.isActive == rhs.isActive &&
        lhs.isSelected == rhs.isSelected &&
        lhs.stringThickness == rhs.stringThickness &&
        lhs.hasDoubleDot == rhs.hasDoubleDot &&
        lhs.hasDot == rhs.hasDot
    }

    var body: some View {
        Button { onSelect(string, fret) } label: {
            ZStack {
                Rectangle().fill(Color.white.opacity(0.42))
                Rectangle().fill(Color.black.opacity(stringThickness))
                    .frame(height: CGFloat(stringThickness * 4))
                if isActive || isSelected {
                    Text(fret == 0 ? "0" : String(fret))
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                        .frame(width: 17, height: 17)
                        .background(
                            isSelected ? Color(red: 0.78, green: 0.29, blue: 0.19) : Color(red: 0.18, green: 0.16, blue: 0.14),
                            in: Circle()
                        )
                        .overlay(Circle().stroke(Color(red: 0.77, green: 0.60, blue: 0.27), lineWidth: 1.5))
                } else if hasDoubleDot {
                    HStack(spacing: 2) { dot; dot }
                } else if hasDot {
                    dot
                }
            }
            .frame(width: width, height: 29)
            .overlay(alignment: .trailing) { Rectangle().fill(Color.secondary.opacity(0.20)).frame(width: 0.7) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(string) 弦 · \(fret == 0 ? "空弦" : "\(fret) 品") · 点击试听并录入")
        .accessibilityLabel("\(string) 弦，\(fret == 0 ? "空弦" : "\(fret) 品")，试听并录入")
    }

    private var dot: some View {
        Circle().fill(Color(red: 0.76, green: 0.60, blue: 0.28).opacity(0.55)).frame(width: 5, height: 5)
    }
}
