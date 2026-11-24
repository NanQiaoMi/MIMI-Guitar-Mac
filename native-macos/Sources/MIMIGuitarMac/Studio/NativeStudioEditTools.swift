import AppKit
import MIMICore
import SwiftUI

struct NativeStudioRhythmToolState: Equatable {
    let duration: Int?
    let dot: Bool
    let triplet: Bool
    let rest: Bool
    let chordMode: Bool
}

struct NativeStudioPitchToolState: Equatable {
    let stringIndex: Int
    let stringCount: Int
    let fret: Int
}

struct NativeStudioTechniqueToolState: Equatable {
    let active: Set<String>
}

struct NativeStudioBrushToolState: Equatable {
    let direction: String?
    let canEdit: Bool
}

struct NativeStudioToolButtonStyle: ButtonStyle {
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

struct NativeStudioHeaderButtonStyle: ButtonStyle {
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
struct NativeStudioEditTools: View {
    let model: NativeStudioModel
    let rhythm: NativeStudioRhythmToolState
    let pitch: NativeStudioPitchToolState
    let techniques: NativeStudioTechniqueToolState
    let brush: NativeStudioBrushToolState
    let onShowBarSettings: () -> Void
    @Binding var selectedCategory: StudioRibbonCategory
    @State private var selectedChordName = "C"
    @State private var selectedPattern = StudioAccompanimentPattern.allPatterns[0]

    init(
        model: NativeStudioModel,
        rhythm: NativeStudioRhythmToolState,
        pitch: NativeStudioPitchToolState,
        techniques: NativeStudioTechniqueToolState,
        brush: NativeStudioBrushToolState,
        onShowBarSettings: @escaping () -> Void,
        selectedCategory: Binding<StudioRibbonCategory>
    ) {
        self.model = model
        self.rhythm = rhythm
        self.pitch = pitch
        self.techniques = techniques
        self.brush = brush
        self.onShowBarSettings = onShowBarSettings
        self._selectedCategory = selectedCategory
    }

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


