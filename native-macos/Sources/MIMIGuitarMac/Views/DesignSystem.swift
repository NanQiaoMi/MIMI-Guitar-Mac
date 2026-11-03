import AppKit
import CoreText
import SwiftUI

enum MIMITheme {
    static let paper = Color(hex: 0xFBFAF6)
    static let paperWhite = Color(hex: 0xFEFFFC)
    static let navigationPaper = Color(hex: 0xFFFFFF)
    static let navigationOutline = Color(hex: 0xE8E0D2)
    static let navigationBorder = Color(hex: 0xE2DACD)
    static let navigationSegment = Color(hex: 0xF2ECE0)
    static let navigationSearch = Color(hex: 0xF8F5EE)
    static let navigationInk = Color(hex: 0x24201D)
    static let navigationBrown = Color(hex: 0x6E5D48)
    static let navigationMuted = Color(hex: 0x8C7C6B)
    static let card = Color.white
    static let ink = Color(hex: 0x24201D)
    static let bodyInk = Color(hex: 0x584A3B)
    static let mutedInk = Color(hex: 0x8C7C6B)
    static let softBorder = Color(hex: 0xE5DDD0)
    static let faintBorder = Color(hex: 0xF0E9DE)
    static let warmGold = Color(hex: 0xC49A45)
    static let darkGold = Color(hex: 0x8F6B28)
    static let terracotta = Color(hex: 0xC84B31)
    static let signalBlue = Color(hex: 0x41A1CF)
    static let green = Color(hex: 0x2E7D32)
    static let cardRadius: CGFloat = 20
    static let navRadius: CGFloat = 50

    static func displayFont(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    static func bodyFont(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }

    static func uiFont(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        bodyFont(size: size, weight: weight)
    }

    static func proseFont(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom("Songti SC", size: size, relativeTo: .body).weight(weight)
    }
}

enum MIMIFontRegistry {
    static let musicSymbolFontName = "Bravura"
    private static var didRegister = false
    static func registerBundledFonts(bundle: Bundle = .main) {
        guard !didRegister, let resourceRoot = bundle.resourceURL else { return }
        didRegister = true
        let designRoot = resourceRoot.appendingPathComponent("Design/Fonts", isDirectory: true)
        if let files = try? FileManager.default.contentsOfDirectory(at: designRoot, includingPropertiesForKeys: nil) {
            for file in files where file.pathExtension.lowercased() == "ttf" || file.pathExtension.lowercased() == "otf" {
                CTFontManagerRegisterFontsForURL(file as CFURL, .process, nil)
            }
        }
        let musicFont = resourceRoot.appendingPathComponent("Player/font/Bravura.otf", isDirectory: false)
        if FileManager.default.fileExists(atPath: musicFont.path) {
            CTFontManagerRegisterFontsForURL(musicFont as CFURL, .process, nil)
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

struct MIMICard: ViewModifier {
    var radius: CGFloat = MIMITheme.cardRadius
    var fill: Color = MIMITheme.card
    var border: Color = MIMITheme.softBorder
    var shadowOpacity: Double = 0.04

    func body(content: Content) -> some View {
        content
            .background {
                let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
                if shadowOpacity > 0.02 {
                    shape
                        .fill(fill)
                        .shadow(color: Color(hex: 0x483620).opacity(shadowOpacity * 0.6), radius: 1, x: 0, y: 0.5)
                } else {
                    shape
                        .fill(fill)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(border, lineWidth: 1)
            }
    }
}

extension View {
    func mimiCard(radius: CGFloat = MIMITheme.cardRadius, fill: Color = MIMITheme.card, border: Color = MIMITheme.softBorder, shadowOpacity: Double = 0.04) -> some View {
        modifier(MIMICard(radius: radius, fill: fill, border: border, shadowOpacity: shadowOpacity))
    }

    func mimiPage() -> some View {
        background(MIMITheme.paper.ignoresSafeArea())
    }
}

struct MIMIPageBackground: View {
    var body: some View {
        MIMITheme.paper.ignoresSafeArea()
    }
}

enum MIMIMotionPreference: String, CaseIterable, Identifiable {
    case system
    case gentle
    case off

    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: return "跟随系统"
        case .gentle: return "轻柔"
        case .off: return "静止"
        }
    }
    var detail: String {
        switch self {
        case .system: return "尊重 macOS 的减少动态效果设置。"
        case .gentle: return "保留轻微淡入与焦点反馈，关闭装饰性移动。"
        case .off: return "停用界面过渡和装饰动画。"
        }
    }
}

enum MIMIMotionPolicy: Equatable {
    case full
    case gentle
    case off

    var rawValue: String {
        switch self {
        case .full: return "full"
        case .gentle: return "gentle"
        case .off: return "off"
        }
    }

    static func resolve(preference: String, reduceMotion: Bool) -> MIMIMotionPolicy {
        switch preference {
        case MIMIMotionPreference.off.rawValue:
            return .off
        case MIMIMotionPreference.gentle.rawValue:
            return .gentle
        default:
            return reduceMotion ? .gentle : .full
        }
    }

    var pageAnimation: Animation? {
        switch self {
        case .full: return .easeInOut(duration: pageDuration)
        case .gentle: return .easeInOut(duration: pageDuration)
        case .off: return nil
        }
    }

    var panelAnimation: Animation? {
        switch self {
        case .full: return .easeInOut(duration: panelDuration)
        case .gentle: return .easeInOut(duration: panelDuration)
        case .off: return nil
        }
    }

    var controlAnimation: Animation? {
        switch self {
        case .full: return .easeInOut(duration: 0.12)
        case .gentle: return .easeInOut(duration: 0.12)
        case .off: return nil
        }
    }

    var navigationAnimation: Animation? {
        switch self {
        case .full: return .easeInOut(duration: 0.20)
        case .gentle: return .easeInOut(duration: 0.14)
        case .off: return nil
        }
    }

    var allowsSpatialMotion: Bool { self == .full }
    var pageDuration: Double { self == .full ? 0.28 : (self == .gentle ? 0.14 : 0) }
    var panelDuration: Double { self == .full ? 0.26 : (self == .gentle ? 0.14 : 0) }
    var pageOffset: CGFloat { allowsSpatialMotion ? 6 : 0 }

    var summary: String {
        switch self {
        case .full: return "完整页面与面板过渡，必要播放位置始终连续。"
        case .gentle: return "页面与面板使用短淡变，不做空间位移；必要播放位置仍连续。"
        case .off: return "关闭界面过渡；必要播放位置仍连续。"
        }
    }
}

final class MIMILogoCache {
    static let shared = MIMILogoCache()
    let image: NSImage?

    private init() {
        if let resourceURL = Bundle.main.resourceURL {
            let bundledLogo = resourceURL.appendingPathComponent("Design/logo.png", isDirectory: false)
            if let img = NSImage(contentsOf: bundledLogo) {
                self.image = img
                return
            }
            let rootLogo = resourceURL.appendingPathComponent("logo.png", isDirectory: false)
            if let img = NSImage(contentsOf: rootLogo) {
                self.image = img
                return
            }
        }

        if let appIcon = NSImage(named: NSImage.applicationIconName), appIcon.isValid {
            self.image = appIcon
            return
        }

        let candidates = [
            "Resources/Design/logo.png",
            "../Resources/Design/logo.png",
            "native-macos/Resources/Design/logo.png",
            "project/native-macos/Resources/Design/logo.png",
            "public/images/logo.png"
        ]
        let fileManager = FileManager.default
        let currentDir = URL(fileURLWithPath: fileManager.currentDirectoryPath)
        for rel in candidates {
            let candidateURL = currentDir.appendingPathComponent(rel)
            if fileManager.fileExists(atPath: candidateURL.path),
               let img = NSImage(contentsOf: candidateURL) {
                self.image = img
                return
            }
        }

        self.image = nil
    }
}

struct MIMILogoView: View {
    var size: CGFloat = 32
    var cornerRadius: CGFloat? = nil

    private var logoImage: NSImage? {
        MIMILogoCache.shared.image
    }

    var body: some View {
        ZStack {
            if let image = logoImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .scaleEffect(1.16)
                    .frame(width: size, height: size)
                    .clipped()
                    .shadow(color: Color(hex: 0x483620).opacity(0.12), radius: 1.5, x: 0, y: 1)
            } else {
                Text("M")
                    .font(MIMITheme.displayFont(size: size * 0.45, weight: .bold))
                    .foregroundStyle(MIMITheme.paper)
                    .frame(width: size, height: size)
                    .background(MIMITheme.ink, in: Circle())
            }
        }
        .frame(width: size, height: size)
        .modify { view in
            if let cornerRadius {
                view.clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            } else {
                view
            }
        }
    }
}

private extension View {
    @ViewBuilder
    func modify<Content: View>(@ViewBuilder _ transform: (Self) -> Content) -> Content {
        transform(self)
    }
}
