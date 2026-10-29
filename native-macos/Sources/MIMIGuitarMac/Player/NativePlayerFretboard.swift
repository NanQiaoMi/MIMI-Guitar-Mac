import AppKit
import ImageIO
import SwiftUI

private struct DecodedManuscriptThumbnail: @unchecked Sendable {
    let image: CGImage
    let logicalSize: CGSize
}

struct NativeFretboardView: View {
    let track: NativePlayerTrack?
    let notes: [NativeFretNote]
    let capo: Int
    let currentChord: String
    let scoreKey: String
    let playedBeatSequence: Int
    let onFretClick: (Int, Int) -> Void
    let onChordPreview: ([NativeFretNote]) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var displayMode = FretboardDisplay.pitch
    @State private var finish = FretboardFinish.rosewood
    @State private var chordChoice = "FOLLOW"
    @State private var vibratingStrings: Set<Int> = []

    private let frets = Array(0...15)

    private var stringCount: Int { max(4, min(6, track?.tuning.count ?? 6)) }
    private var tuning: [Int] {
        let standard = stringCount == 4 ? [69, 64, 60, 67] : [64, 59, 55, 50, 45, 40]
        guard let track, track.tuning.count == stringCount else { return standard }
        return track.tuning
    }
    private var isUkulele: Bool { stringCount == 4 || track?.program == 24 }
    private var instrumentFlavor: String { isUkulele ? "ukulele" : "gm" }
    private var selectedChord: String {
        if chordChoice == "FOLLOW" { return currentChord }
        return chordChoice == "NONE" ? "" : chordChoice
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Label(track?.name ?? "吉他指板", systemImage: "guitars")
                    .font(MIMITheme.bodyFont(size: 12, weight: .semibold))
                    .foregroundStyle(MIMITheme.ink)
                if capo > 0 {
                    Text("变调夹 (capo) 品").font(MIMITheme.bodyFont(size: 10, weight: .medium))
                        .foregroundStyle(MIMITheme.darkGold).padding(.horizontal, 7).padding(.vertical, 3)
                        .background(MIMITheme.warmGold.opacity(0.14), in: Capsule())
                }
                Menu {
                    ForEach(FretboardDisplay.allCases) { mode in
                        Button(mode.label) { displayMode = mode }
                    }
                } label: {
                    Label(displayMode.label, systemImage: "textformat")
                }.menuStyle(.borderlessButton).fixedSize()
                Menu {
                    ForEach(FretboardFinish.allCases) { value in
                        Button(value.label) { finish = value }
                    }
                } label: {
                    Label(finish.label, systemImage: "circle.lefthalf.filled")
                }.menuStyle(.borderlessButton).fixedSize()
                Menu {
                    Button("🎵 跟随乐谱（实时）") { chordChoice = "FOLLOW" }
                    Divider()
                    ForEach(Self.chordNames, id: \.self) { chord in
                        Button(chord) { chordChoice = chord }
                    }
                    Divider()
                    Button("✨ 全板自由探索") { chordChoice = "NONE" }
                } label: {
                    Label(selectedChord.isEmpty ? "自由探索" : selectedChord, systemImage: "music.note.list")
                }.menuStyle(.borderlessButton).fixedSize()
                Button { onChordPreview(chordNotes(for: selectedChord)) } label: {
                    Label("扫弦试听", systemImage: "waveform")
                }
                .buttonStyle(.borderedProminent)
                .tint(MIMITheme.terracotta)
                .disabled(track?.percussion == true || (selectedChord.isEmpty && notes.isEmpty))
                Spacer(minLength: 0)
                Text("点击品位可真实试听音符")
                    .font(MIMITheme.bodyFont(size: 10)).foregroundStyle(MIMITheme.mutedInk)
            }

            ScrollView(.horizontal) {
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        Text("弦").frame(width: 32)
                        ForEach(frets, id: \.self) { fret in
                            Text(fret == 0 ? "空弦" : String(fret))
                                .font(.system(size: 9, weight: fret == 12 ? .bold : .regular, design: .rounded).monospacedDigit())
                                .foregroundStyle(fret == capo ? MIMITheme.terracotta : MIMITheme.mutedInk)
                                .frame(width: fret == 0 ? 42 : 42, height: 18)
                        }
                    }
                    ForEach(1...stringCount, id: \.self) { string in
                        HStack(spacing: 0) {
                            Text("\(string)")
                                .font(.system(size: 10, weight: .semibold, design: .rounded).monospacedDigit())
                                .foregroundStyle(MIMITheme.ink.opacity(0.78))
                                .frame(width: 32, height: 22)
                            ForEach(frets, id: \.self) { fret in
                                let active = isActive(string: string, fret: fret)
                                let midi = noteMidi(string: string, fret: fret)
                                Button { onFretClick(string, fret) } label: {
                                    ZStack {
                                        Rectangle().fill(finish.wood.opacity(0.72))
                                        Rectangle().fill(Color.black.opacity(0.15)).frame(height: stringThickness(string))
                                        if Self.positionMarkers.contains(fret), string == markerString {
                                            Circle().fill(Color.white.opacity(0.30)).frame(width: 7, height: 7)
                                        }
                                        if active {
                                            Circle().fill(MIMITheme.terracotta)
                                                .frame(width: 20, height: 20)
                                                .overlay {
                                                    Text(activeLabel(string: string, fret: fret, midi: midi))
                                                        .font(.system(size: 8, weight: .bold, design: .rounded))
                                                        .foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.7)
                                                }
                                                .shadow(color: MIMITheme.terracotta.opacity(0.35), radius: 3)
                                        } else {
                                            Text(cellLabel(string: string, fret: fret, midi: midi))
                                                .font(.system(size: 8, weight: .medium, design: .rounded))
                                                .foregroundStyle(MIMITheme.ink.opacity(displayMode == .fret ? 0.36 : 0.55))
                                                .lineLimit(1).minimumScaleFactor(0.65)
                                        }
                                    }
                                    .frame(width: 42, height: 22)
                                    .overlay(alignment: .trailing) { Rectangle().fill(Color.black.opacity(fret == 0 ? 0.32 : 0.16)).frame(width: fret == 0 ? 3 : 1) }
                                    .offset(x: vibratingStrings.contains(string) && !reduceMotion ? (playedBeatSequence.isMultiple(of: 2) ? 1 : -1) : 0)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .help("\(string) 弦 · \(fret == 0 ? "空弦" : "第 \(fret) 品") · \(pitchName(midi)) · MIDI \(midi)")
                                .accessibilityLabel("\(string) 弦，\(fret) 品，\(pitchName(midi))，点击试听")
                            }
                        }
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(Color.white.opacity(0.68)).frame(height: stringThickness(string))
                                .padding(.leading, 32).padding(.trailing, 2)
                        }
                    }
                }
                .padding(.vertical, 5)
                .background {
                    ZStack {
                        finish.base
                        Canvas { context, size in
                            for line in 0..<Int(size.height / 14) {
                                var path = Path()
                                let y = CGFloat(line) * 14 + 4
                                path.move(to: CGPoint(x: 0, y: y))
                                path.addCurve(to: CGPoint(x: size.width, y: y + 2), control1: CGPoint(x: size.width * 0.30, y: y - 4), control2: CGPoint(x: size.width * 0.68, y: y + 5))
                                context.stroke(path, with: .color(.white.opacity(0.07)), lineWidth: 1)
                            }
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(MIMITheme.softBorder, lineWidth: 1))
            }
            .scrollIndicators(.visible)
            .frame(height: CGFloat(24 * (stringCount + 1) + 10))
        }
        .padding(10)
        .background(MIMITheme.paperWhite, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(MIMITheme.softBorder, lineWidth: 1))
        .onChange(of: playedBeatSequence) { _ in animatePlayedStrings() }
        .onChange(of: notes) { _ in
            guard !notes.isEmpty else { return }
            // Highlighting follows position updates; string motion only comes from playedBeatChanged.
        }
    }

    private var markerString: Int { stringCount <= 4 ? 2 : 3 }

    private func isActive(string: Int, fret: Int) -> Bool {
        notes.contains { note in
            let adjusted = note.string == 0 ? 1 : note.string
            return adjusted == string && note.fret == fret
        }
    }

    private func noteMidi(string: Int, fret: Int) -> Int {
        let raw = tuning.indices.contains(string - 1) ? tuning[string - 1] : 64
        return raw + fret + (fret > 0 ? capo : 0)
    }

    private func pitchName(_ midi: Int) -> String {
        let names = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]
        return "\(names[((midi % 12) + 12) % 12])\(midi / 12 - 1)"
    }

    private func cellLabel(string: Int, fret: Int, midi: Int) -> String {
        switch displayMode {
        case .pitch: return pitchName(midi)
        case .numbered: return numberedPitch(midi)
        case .finger: return isActive(string: string, fret: fret) ? "指" : ""
        case .fret: return fret == 0 ? "○" : String(fret)
        }
    }

    private func activeLabel(string: Int, fret: Int, midi: Int) -> String {
        if displayMode == .finger, let note = notes.first(where: { ($0.string == 0 ? 1 : $0.string) == string && $0.fret == fret }), let finger = note.finger {
            return String(finger)
        }
        return displayMode == .fret ? String(fret) : (displayMode == .numbered ? numberedPitch(midi) : pitchName(midi))
    }

    private func numberedPitch(_ midi: Int) -> String {
        let root = FretboardDisplay.keyRoot(scoreKey)
        let semitone = (midi - root + 120) % 12
        let degrees = ["1", "♭2", "2", "♭3", "3", "4", "♯4", "5", "♭6", "6", "♭7", "7"]
        return degrees[semitone]
    }

    private func stringThickness(_ string: Int) -> CGFloat {
        CGFloat(max(0.7, Double(stringCount - string + 1) * 0.25))
    }

    private func chordNotes(for chord: String) -> [NativeFretNote] {
        if chord == "FOLLOW" || chord.isEmpty { return notes }
        let guitar: [String: [(Int, Int)]] = [
            "C": [(5, 3), (4, 2), (3, 0), (2, 1), (1, 0)], "G": [(6, 3), (5, 2), (4, 0), (3, 0), (2, 0), (1, 3)],
            "Am": [(5, 0), (4, 2), (3, 2), (2, 1), (1, 0)], "Em": [(6, 0), (5, 2), (4, 2), (3, 0), (2, 0), (1, 0)],
            "F": [(6, 1), (5, 3), (4, 3), (3, 2), (2, 1), (1, 1)], "D": [(4, 0), (3, 2), (2, 3), (1, 2)],
            "Dm": [(4, 0), (3, 2), (2, 3), (1, 1)], "E": [(6, 0), (5, 2), (4, 2), (3, 1), (2, 0), (1, 0)],
            "A": [(5, 0), (4, 2), (3, 2), (2, 2), (1, 0)], "Bm": [(5, 2), (4, 4), (3, 4), (2, 3), (1, 2)],
            "C7": [(5, 3), (4, 2), (3, 3), (2, 1), (1, 0)], "G7": [(6, 3), (5, 2), (4, 0), (3, 0), (2, 0), (1, 1)],
            "D7": [(4, 0), (3, 2), (2, 1), (1, 2)], "Em7": [(6, 0), (5, 2), (4, 0), (3, 0), (2, 0), (1, 0)],
            "Am7": [(5, 0), (4, 2), (3, 0), (2, 1), (1, 0)], "Fmaj7": [(5, 0), (4, 3), (3, 2), (2, 1), (1, 0)],
            "Dsus4": [(4, 0), (3, 2), (2, 3), (1, 3)], "Asus4": [(5, 0), (4, 2), (3, 2), (2, 3), (1, 0)],
        ]
        let ukulele: [String: [(Int, Int)]] = ["C": [(1, 3), (2, 0), (3, 0), (4, 0)], "G": [(1, 2), (2, 3), (3, 2), (4, 0)], "Am": [(1, 0), (2, 0), (3, 0), (4, 2)], "F": [(1, 0), (2, 1), (3, 0), (4, 2)], "Dm": [(1, 1), (2, 2), (3, 2), (4, 0)]]
        let positions = (isUkulele ? ukulele[chord] : guitar[chord]) ?? []
        return positions.map { NativeFretNote(string: $0.0, fret: $0.1, midi: 0) }
    }

    private func animatePlayedStrings() {
        guard !reduceMotion else { return }
        let strings = Set(notes.map { $0.string == 0 ? 1 : $0.string })
        guard !strings.isEmpty else { return }
        withAnimation(.easeOut(duration: 0.12)) { vibratingStrings = strings }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.34) {
            withAnimation(.easeOut(duration: 0.16)) { vibratingStrings.subtract(strings) }
        }
    }

    static let chordNames = ["C", "G", "Am", "Em", "F", "D", "Dm", "E", "A", "Bm", "C7", "G7", "D7", "Em7", "Am7", "Fmaj7", "Dsus4", "Asus4"]
    static let positionMarkers: Set<Int> = [3, 5, 7, 9, 12, 15]
}

private enum FretboardDisplay: String, CaseIterable, Identifiable {
    case pitch, numbered, finger, fret
    var id: String { rawValue }
    var label: String {
        switch self {
        case .pitch: return "音名"
        case .numbered: return "简谱音级"
        case .finger: return "指法"
        case .fret: return "品位"
        }
    }
    static func keyRoot(_ key: String) -> Int {
        ["C": 0, "C#": 1, "Db": 1, "D": 2, "D#": 3, "Eb": 3, "E": 4, "F": 5, "F#": 6, "Gb": 6, "G": 7, "G#": 8, "Ab": 8, "A": 9, "A#": 10, "Bb": 10, "B": 11][key] ?? 0
    }
}

private enum FretboardFinish: String, CaseIterable, Identifiable {
    case rosewood, ebony, maple, parchment
    var id: String { rawValue }
    var label: String {
        switch self {
        case .rosewood: return "玫瑰木"
        case .ebony: return "乌木"
        case .maple: return "枫木"
        case .parchment: return "羊皮纸"
        }
    }
    var base: LinearGradient {
        let colors: [Color]
        switch self {
        case .rosewood: colors = [Color(red: 0.38, green: 0.20, blue: 0.13), Color(red: 0.20, green: 0.10, blue: 0.07)]
        case .ebony: colors = [Color(red: 0.20, green: 0.18, blue: 0.16), Color(red: 0.09, green: 0.08, blue: 0.07)]
        case .maple: colors = [Color(red: 0.67, green: 0.48, blue: 0.29), Color(red: 0.43, green: 0.28, blue: 0.15)]
        case .parchment: colors = [Color(red: 0.85, green: 0.79, blue: 0.67), Color(red: 0.66, green: 0.58, blue: 0.44)]
        }
        return LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
    }
    var wood: Color { Color.white.opacity(self == .parchment ? 0.16 : 0.12) }
}

struct NativeManuscriptPanel: View {
    @ObservedObject var model: NativePlayerModel
    let openGallery: () -> Void
    @State private var targetBar = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 10) {
                Label("矢量总谱", systemImage: "doc.text.image").font(MIMITheme.bodyFont(size: 12, weight: .semibold))
                Spacer()
                Button { model.scrollToPage(model.currentPage - 1) } label: { Image(systemName: "chevron.left") }
                    .disabled(!model.scoreReady || model.currentPage <= 1)
                Text("第 \(model.currentPage) / \(model.pageCount) 页")
                    .font(.system(size: 11, weight: .medium, design: .rounded).monospacedDigit()).frame(minWidth: 84)
                Button { model.scrollToPage(model.currentPage + 1) } label: { Image(systemName: "chevron.right") }
                    .disabled(!model.scoreReady || model.currentPage >= model.pageCount)
                Divider().frame(height: 19)
                Button { model.zoom = max(0.6, model.zoom - 0.1); model.applyZoom() } label: { Image(systemName: "minus.magnifyingglass") }
                Text("\(Int((model.zoom * 100).rounded()))%")
                    .font(.system(size: 10, design: .rounded).monospacedDigit()).frame(width: 42)
                Button { model.zoom = min(1.6, model.zoom + 0.1); model.applyZoom() } label: { Image(systemName: "plus.magnifyingglass") }
                Button("高清手稿…", action: openGallery).buttonStyle(.bordered)
            }
            HStack(spacing: 10) {
                Text("小节定位").font(MIMITheme.bodyFont(size: 11)).foregroundStyle(MIMITheme.mutedInk)
                Stepper(value: $targetBar, in: 1...max(1, model.barCount)) {
                    Text("第 \(targetBar) 小节").font(.system(size: 11, weight: .medium, design: .rounded).monospacedDigit())
                }.frame(width: 165).disabled(!model.scoreReady)
                Button("定位并播放") { model.seekToBar(targetBar - 1) }.buttonStyle(.borderedProminent).tint(MIMITheme.terracotta).disabled(!model.canPlay)
                Text("点击谱面音符也会跳到对应小节。")
                    .font(MIMITheme.bodyFont(size: 10)).foregroundStyle(MIMITheme.mutedInk)
                Spacer()
                if model.isXhe {
                    Text("XHE 文本谱使用和弦图与歌词锚点视图")
                        .font(MIMITheme.bodyFont(size: 10)).foregroundStyle(MIMITheme.mutedInk)
                }
            }
        }
        .padding(12)
        .background(MIMITheme.paperWhite, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(MIMITheme.softBorder, lineWidth: 1))
        .onChange(of: model.currentBar) { value in if value > 0 { targetBar = value } }
        .onChange(of: model.barCount) { value in targetBar = min(max(1, targetBar), max(1, value)) }
    }
}

struct NativeManuscriptGalleryView: View {
    @ObservedObject var model: NativePlayerModel
    @Environment(\.dismiss) private var dismiss
    @State private var zoom = 1.0
    @State private var image: NSImage?
    @State private var loadError: String?
    @State private var isLoadingImage = false
    @State private var hasImageSource = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Label("谱面高清原稿与实体手稿展台", systemImage: "scroll")
                    .font(MIMITheme.displayFont(size: 18, weight: .semibold))
                Spacer()
                Button { zoom = max(0.5, zoom - 0.25) } label: { Image(systemName: "minus.magnifyingglass") }
                Text("\(Int((zoom * 100).rounded()))%")
                    .font(.system(size: 11, design: .rounded).monospacedDigit()).frame(width: 48)
                Button { zoom = min(3, zoom + 0.25) } label: { Image(systemName: "plus.magnifyingglass") }
                Button("原比例") { zoom = 1 }
                Button("另存原图…") { model.exportScreenshot() }.disabled(model.manuscriptScreenshotURL == nil)
                Button("在预览中打开") { model.openScreenshot() }.disabled(model.manuscriptScreenshotURL == nil)
                Button("关闭") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(16)
            Divider()
            HStack(spacing: 0) {
                if let image {
                    ScrollView([.horizontal, .vertical]) {
                        Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                            .frame(width: max(420, image.size.width * zoom), height: max(320, image.size.height * zoom))
                            .padding(28)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(red: 0.11, green: 0.10, blue: 0.09))
                } else if isLoadingImage {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("正在读取原稿扫描件…")
                            .font(MIMITheme.bodyFont(size: 12)).foregroundStyle(MIMITheme.mutedInk)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let loadError {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle").font(.system(size: 32)).foregroundStyle(MIMITheme.darkGold)
                        Text("原稿扫描件加载失败").font(MIMITheme.displayFont(size: 17, weight: .semibold))
                        Text(loadError)
                            .font(MIMITheme.bodyFont(size: 12)).foregroundStyle(MIMITheme.mutedInk)
                            .multilineTextAlignment(.center).frame(maxWidth: 440)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "doc.viewfinder").font(.system(size: 32)).foregroundStyle(MIMITheme.darkGold)
                        Text("没有可用的原稿扫描件").font(MIMITheme.displayFont(size: 17, weight: .semibold))
                        Text(hasImageSource ? "原稿扫描件尚未载入。" : "此曲目没有登记本地手稿扫描文件；矢量谱仍可在播放器中浏览。")
                            .font(MIMITheme.bodyFont(size: 12)).foregroundStyle(MIMITheme.mutedInk)
                            .multilineTextAlignment(.center).frame(maxWidth: 440)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.metadataTitle.isEmpty ? "原版手稿" : model.metadataTitle).font(MIMITheme.bodyFont(size: 12, weight: .semibold))
                    Text("本地原始扫描件 · 支持 50%–300% 放大查看 · 原件按曲库资源路径只读访问")
                        .font(MIMITheme.bodyFont(size: 10)).foregroundStyle(MIMITheme.mutedInk)
                }
                Spacer()
                Text(model.metadataArtist).font(MIMITheme.bodyFont(size: 11)).foregroundStyle(MIMITheme.mutedInk)
            }.padding(14)
        }
        .frame(minWidth: 850, minHeight: 620)
        .background(MIMITheme.paper)
        .task(id: model.manuscriptScreenshotURL) {
            await loadImage(from: model.manuscriptScreenshotURL)
        }
    }

    @MainActor
    private func loadImage(from url: URL?) async {
        image = nil
        loadError = nil
        isLoadingImage = false
        hasImageSource = url != nil
        guard let url else { return }
        isLoadingImage = true

        do {
            let thumbnail = try await Task.detached(priority: .userInitiated) {
                try Self.decodeThumbnail(from: url)
            }.value
            guard !Task.isCancelled else { return }
            image = NSImage(cgImage: thumbnail.image, size: thumbnail.logicalSize)
        } catch {
            guard !Task.isCancelled else { return }
            loadError = "本地扫描件无法读取：\(error.localizedDescription)"
        }
        guard !Task.isCancelled else { return }
        isLoadingImage = false
    }

    nonisolated private static func decodeThumbnail(from url: URL) throws -> DecodedManuscriptThumbnail {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let pixelWidth = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
              let pixelHeight = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue,
              pixelWidth > 0, pixelHeight > 0 else {
            throw CocoaError(.fileReadCorruptFile)
        }

        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 2_048,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let decoded = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary) else {
            throw CocoaError(.fileReadCorruptFile)
        }

        let rawDPIWidth = (properties[kCGImagePropertyDPIWidth] as? NSNumber)?.doubleValue ?? 72
        let rawDPIHeight = (properties[kCGImagePropertyDPIHeight] as? NSNumber)?.doubleValue ?? 72
        let dpiWidth = rawDPIWidth.isFinite && rawDPIWidth > 0 ? rawDPIWidth : 72
        let dpiHeight = rawDPIHeight.isFinite && rawDPIHeight > 0 ? rawDPIHeight : 72
        var logicalWidth = pixelWidth * 72 / dpiWidth
        var logicalHeight = pixelHeight * 72 / dpiHeight
        if let rawOrientation = properties[kCGImagePropertyOrientation] as? NSNumber,
           [5, 6, 7, 8].contains(rawOrientation.intValue) {
            swap(&logicalWidth, &logicalHeight)
        }
        return DecodedManuscriptThumbnail(
            image: decoded,
            logicalSize: CGSize(width: logicalWidth, height: logicalHeight)
        )
    }
}
