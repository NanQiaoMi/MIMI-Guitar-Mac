import AppKit
import CoreText
import SwiftUI

enum MIMITheme {
    static let paper = Color(hex: 0xFBFAF6)
    static let paperWhite = Color(hex: 0xFEFFFC)
    static let navigationPaper = Color(hex: 0xFFFFFF)
    static let navigationOutline = Color(hex: 0xE6DED1)
    static let navigationBorder = Color(hex: 0xDFD6C7)
    static let navigationSegment = Color(hex: 0xEDE5D8)
    static let navigationSearch = Color(hex: 0xF7F3EB)
    static let navigationInk = Color(hex: 0x2C2825)
    static let navigationBrown = Color(hex: 0x705C42)
    static let navigationMuted = Color(hex: 0x8C7B68)
    static let card = Color.white
    static let ink = Color(hex: 0x2D2926)
    static let bodyInk = Color(hex: 0x5C4A38)
    static let mutedInk = Color(hex: 0x8C7B68)
    static let softBorder = Color(hex: 0xE2D8C3)
    static let faintBorder = Color(hex: 0xF0EAE0)
    static let warmGold = Color(hex: 0xC49A45)
    static let darkGold = Color(hex: 0x966B26)
    static let terracotta = Color(hex: 0xC84B31)
    static let signalBlue = Color(hex: 0x41A1CF)
    static let green = Color(hex: 0x2E7D32)
    static let cardRadius: CGFloat = 24
    static let navRadius: CGFloat = 50

    static func displayFont(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        // The bundle ships Fraunces Regular and Medium; Chinese glyphs fall back to the system sans face.
        let name = weight == .medium || weight == .semibold || weight == .bold || weight == .heavy || weight == .black
            ? "Fraunces-Medium"
            : "Fraunces-Regular"
        return .custom(name, size: size, relativeTo: .title).weight(weight)
    }

    static func bodyFont(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let name: String
        switch weight {
        case .medium: name = "Inter-Medium"
        case .semibold: name = "Inter-SemiBold"
        case .bold, .heavy, .black: name = "Inter-Bold"
        default: name = "Inter-Regular"
        }
        return .custom(name, size: size, relativeTo: .body).weight(weight)
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
    var shadowOpacity: Double = 0.045

    func body(content: Content) -> some View {
        content
            .background(fill, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(border, lineWidth: 1)
            }
            .shadow(color: MIMITheme.bodyInk.opacity(shadowOpacity), radius: 14, x: 0, y: 4)
    }
}

extension View {
    func mimiCard(radius: CGFloat = MIMITheme.cardRadius, fill: Color = MIMITheme.card, border: Color = MIMITheme.softBorder, shadowOpacity: Double = 0.045) -> some View {
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
