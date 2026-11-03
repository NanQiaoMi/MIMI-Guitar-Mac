import AppKit
import ImageIO
import MIMICore
import SwiftUI

struct MIMISectionHeading: View {
    let title: String
    var subtitle: String? = nil
    var trailing: AnyView? = nil

    var body: some View {
        HStack(alignment: .bottom, spacing: 16) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 10) {
                    Capsule().fill(MIMITheme.warmGold.gradient).frame(width: 5, height: 26)
                    Text(title)
                        .font(MIMITheme.displayFont(size: 27, weight: .bold))
                        .foregroundStyle(MIMITheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
                if let subtitle {
                    Text(subtitle)
                        .font(MIMITheme.bodyFont(size: 13))
                        .foregroundStyle(MIMITheme.mutedInk)
                        .padding(.leading, 15)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.vertical, 4)
    }
}

private struct MIMIFooterNavigationActionKey: EnvironmentKey {
    static let defaultValue: (NativeRoute) -> Void = { _ in }
}

extension EnvironmentValues {
    var mimiFooterNavigate: (NativeRoute) -> Void {
        get { self[MIMIFooterNavigationActionKey.self] }
        set { self[MIMIFooterNavigationActionKey.self] = newValue }
    }
}

struct MIMISiteFooter: View {
    @Environment(\.mimiFooterNavigate) private var navigate
    private static let currentYear = Calendar.current.component(.year, from: Date())

    private var links: [(String, NativeRoute)] {
        [
            ("吉他曲库", .catalog(.guitar)),
            ("尤克里里", .catalog(.ukulele)),
            ("制谱工坊", .studio),
            ("专栏", .articles),
            ("我的练习", .practice(scoreID: nil)),
            ("我的谱", .library),
            ("数据与备份", .dataSettings),
            ("交互体验", .motion),
        ]
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            HStack(spacing: 8) {
                Text("MIMI Guitar")
                    .font(MIMITheme.displayFont(size: 13, weight: .bold))
                    .foregroundStyle(Color(hex: 0x24201D))
                Text("· 纸本墨韵 · 专业数字乐谱工坊")
                    .font(MIMITheme.bodyFont(size: 12))
                    .foregroundStyle(MIMITheme.mutedInk)
            }
            .fixedSize(horizontal: true, vertical: false)

            MIMIFooterLinkFlow(horizontalSpacing: 16, verticalSpacing: 8) {
                ForEach(Array(links.enumerated()), id: \.offset) { _, link in
                    Button(link.0) { navigate(link.1) }
                        .font(MIMITheme.bodyFont(size: 12, weight: .medium))
                        .foregroundStyle(MIMITheme.bodyInk)
                        .frame(minHeight: 36)
                        .contentShape(Rectangle())
                        .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity)

            Text("© \(Self.currentYear) MIMI Guitar. All rights reserved.")
                .font(MIMITheme.bodyFont(size: 11))
                .foregroundStyle(MIMITheme.mutedInk)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: 1152)
        .padding(.vertical, 28)
        .frame(maxWidth: .infinity)
        .background(Color(hex: 0xF7F3EB).opacity(0.92))
        .overlay(alignment: .top) {
            Rectangle().fill(MIMITheme.softBorder).frame(height: 1)
        }
    }
}

private struct MIMIFooterLinkFlow: Layout {
    var horizontalSpacing: CGFloat
    var verticalSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let proposedWidth = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        var contentWidth: CGFloat = 0
        var contentHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth > 0, rowWidth + horizontalSpacing + size.width > proposedWidth {
                contentWidth = max(contentWidth, rowWidth)
                contentHeight += rowHeight + verticalSpacing
                rowWidth = 0
                rowHeight = 0
            }
            if rowWidth > 0 { rowWidth += horizontalSpacing }
            rowWidth += size.width
            rowHeight = max(rowHeight, size.height)
        }
        contentWidth = max(contentWidth, rowWidth)
        contentHeight += rowHeight
        return CGSize(width: min(proposedWidth, contentWidth), height: contentHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let proposedWidth = bounds.width
        var rows: [(range: Range<Int>, width: CGFloat, height: CGFloat)] = []
        var start = 0
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0

        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            let nextWidth = rowWidth == 0 ? size.width : rowWidth + horizontalSpacing + size.width
            if rowWidth > 0, nextWidth > proposedWidth {
                rows.append((start..<index, rowWidth, rowHeight))
                start = index
                rowWidth = size.width
                rowHeight = size.height
            } else {
                rowWidth = nextWidth
                rowHeight = max(rowHeight, size.height)
            }
        }
        if start < subviews.count { rows.append((start..<subviews.count, rowWidth, rowHeight)) }

        var y = bounds.minY
        for row in rows {
            var x = bounds.minX + (bounds.width - row.width) / 2
            for index in row.range {
                let subview = subviews[index]
                let size = subview.sizeThatFits(.unspecified)
                subview.place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2), anchor: .topLeading, proposal: ProposedViewSize(width: size.width, height: size.height))
                x += size.width + horizontalSpacing
            }
            y += row.height + verticalSpacing
        }
    }
}

struct StaticPaperAmbience: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            Image(decorative: PaperAmbienceTile.grain, scale: 2, orientation: .up)
                .resizable(resizingMode: .tile)

            HStack(spacing: 0) {
                StaticStaveWing(leading: true)
                Spacer(minLength: 0)
                StaticStaveWing(leading: false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct StaticStaveWing: View {
    let leading: Bool

    var body: some View {
        Image(decorative: leading ? PaperAmbienceTile.stavesLeading : PaperAmbienceTile.stavesTrailing, scale: 5, orientation: .up)
            .resizable(resizingMode: .tile)
            .frame(width: 240)
            .frame(maxHeight: .infinity)
    }
}

enum PaperAmbienceTile {
    static let grain = makeGrainTile()
    static let stavesLeading = makeStaveTile(leading: true)
    static let stavesTrailing = makeStaveTile(leading: false)

    private static func makeGrainTile() -> CGImage {
        let side = 512
        var state: UInt64 = 0x4D494D4950415045
        var bytes = [UInt8](repeating: 0, count: side * side * 4)
        for pixel in 0..<(side * side) {
            state &+= 0x9E3779B97F4A7C15
            var value = state
            value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
            value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
            value ^= value >> 31
            // Pre-multiplied alpha grain so standard source-over blending matches 3.5% multiply without framebuffer readback.
            let darkness = Int(224 - (value & 0xCF))
            let alpha = UInt8(max(0, min(12, (darkness * 9) / 224)))
            let offset = pixel * 4
            bytes[offset] = UInt8((Int(alpha) * 72) / 255)
            bytes[offset + 1] = UInt8((Int(alpha) * 54) / 255)
            bytes[offset + 2] = UInt8((Int(alpha) * 32) / 255)
            bytes[offset + 3] = alpha
        }
        let data = Data(bytes) as CFData
        guard let provider = CGDataProvider(data: data),
              let image = CGImage(
                width: side,
                height: side,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: side * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
              ) else {
            preconditionFailure("Unable to create the static paper grain tile")
        }
        return image
    }

    private static func makeStaveTile(leading: Bool) -> CGImage {
        let width = 1200 // 240pt at scale 5
        let height = 454
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            preconditionFailure("Unable to create the static stave tile")
        }

        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        let lineOffsets: [CGFloat] = [0, 5.2, 10.4, 15.6, 20.8]
        for staffTop in [CGFloat(0), 90.8] {
            for offset in lineOffsets {
                let y = (staffTop + offset) * 5
                context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.75))
                context.fill(CGRect(x: 0, y: y, width: CGFloat(width), height: 5))
                context.setFillColor(CGColor(red: 0.77, green: 0.60, blue: 0.27, alpha: 0.14))
                context.fill(CGRect(x: 0, y: y + 5, width: CGFloat(width), height: 5))
            }
        }
        // Bake horizontal fade mask directly into the tile alpha channel to avoid per-frame offscreen masking.
        context.setBlendMode(.destinationIn)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let colors = [
            CGColor(red: 0, green: 0, blue: 0, alpha: 1.0),
            CGColor(red: 0, green: 0, blue: 0, alpha: 0.75),
            CGColor(red: 0, green: 0, blue: 0, alpha: 0.0),
        ] as CFArray
        let locations: [CGFloat] = [0.0, 0.4, 1.0]
        if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: locations) {
            let start = CGPoint(x: leading ? 0 : CGFloat(width), y: 0)
            let end = CGPoint(x: leading ? CGFloat(width) : 0, y: 0)
            context.drawLinearGradient(gradient, start: start, end: end, options: [])
        }
        guard let image = context.makeImage() else {
            preconditionFailure("Unable to finish the static stave tile")
        }
        return image
    }
}

struct MIMIPill: View {
    let title: String
    var tint: Color = MIMITheme.bodyInk
    var fill: Color = MIMITheme.paper

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(fill, in: Capsule())
            .overlay(Capsule().stroke(MIMITheme.softBorder, lineWidth: 0.8))
    }
}

struct DifficultyBadge: View {
    let difficulty: Int
    private var label: String {
        switch difficulty {
        case 1: return "零基础"
        case 2: return "初级"
        case 3: return "中级"
        case 4: return "高级"
        case 5...: return "专业"
        default: return "未标注"
        }
    }
    private var tint: Color {
        switch difficulty {
        case 1: return Color(hex: 0x2E7D32)
        case 2: return Color(hex: 0x00838F)
        case 3: return Color(hex: 0x1565C0)
        case 4: return Color(hex: 0xE65100)
        case 5...: return Color(hex: 0xB71C1C)
        default: return MIMITheme.mutedInk
        }
    }
    var body: some View { MIMIPill(title: label, tint: tint, fill: tint.opacity(0.08)) }
}

struct CatalogThumbnail: View {
    let reference: String?
    let contentRoot: URL?
    var size: CGSize = CGSize(width: 360, height: 220)
    @State private var loadedImage: CGImage?
    @State private var loadedKey: String?
    @State private var loadFailed = false
    @Environment(\.displayScale) private var displayScale

    private var cacheKey: String { "\(reference ?? ""): \(Int(size.width * displayScale))x\(Int(size.height * displayScale))" }

    private var currentImage: CGImage? {
        if let cached = ThumbnailImageCache.shared.value(for: cacheKey) {
            return cached
        }
        return loadedKey == cacheKey ? loadedImage : nil
    }

    var body: some View {
        ZStack {
            MIMITheme.paper
            if let displayImage = currentImage {
                Image(decorative: displayImage, scale: 1, orientation: .up)
                    .resizable()
                    .scaledToFill()
            } else if !loadFailed {
                Image(systemName: "music.note")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(MIMITheme.warmGold.opacity(0.8))
            } else {
                Image(systemName: "music.note.list")
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(MIMITheme.mutedInk.opacity(0.65))
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .task(id: cacheKey) {
            guard let reference, let contentRoot else { loadFailed = true; return }
            let key = cacheKey
            if ThumbnailImageCache.shared.value(for: key) != nil {
                if loadFailed { loadFailed = false }
                return
            }
            if loadFailed { loadFailed = false }
            let pixelSize = Int(max(size.width, size.height) * displayScale * 1.35)
            let decodeTask = Task.detached(priority: .utility) { () -> CGImage? in
                guard !Task.isCancelled else { return nil }
                do {
                    let url = try AppPaths.resolve(reference: reference, contentRoot: contentRoot)
                    guard !Task.isCancelled else { return nil }
                    return ThumbnailImageCache.shared.load(url: url, maxPixelSize: max(64, pixelSize), key: key)
                } catch { return nil }
            }
            let next = await withTaskCancellationHandler {
                await decodeTask.value
            } onCancel: {
                decodeTask.cancel()
            }
            guard !Task.isCancelled else { return }
            loadedKey = key
            loadedImage = next
            loadFailed = next == nil
        }
    }
}

private final class CGImageStorage: NSObject {
    let image: CGImage
    init(_ image: CGImage) { self.image = image }
}

private final class ThumbnailImageCache {
    static let shared = ThumbnailImageCache()
    private let cache = NSCache<NSString, CGImageStorage>()
    private let decodeSemaphore = DispatchSemaphore(value: 4)

    private init() {
        cache.countLimit = 500
        cache.totalCostLimit = 128 * 1_024 * 1_024
    }

    func value(for key: String) -> CGImage? { cache.object(forKey: key as NSString)?.image }

    func load(url: URL, maxPixelSize: Int, key: String) -> CGImage? {
        if let image = value(for: key) { return image }
        decodeSemaphore.wait()
        defer { decodeSemaphore.signal() }
        if let image = value(for: key) { return image }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let cost = image.bytesPerRow * image.height
        cache.setObject(CGImageStorage(image), forKey: key as NSString, cost: cost)
        return image
    }
}

struct ScoreActionButton: View {
    let title: String
    let symbol: String
    var prominent = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(MIMITheme.bodyFont(size: 12.5, weight: .medium))
                .padding(.horizontal, 14)
                .frame(minHeight: 36)
                .foregroundStyle(prominent ? .white : MIMITheme.bodyInk)
                .background(prominent ? MIMITheme.ink : MIMITheme.paperWhite, in: Capsule())
                .overlay {
                    if !prominent {
                        Capsule().stroke(MIMITheme.softBorder, lineWidth: 1)
                    }
                }
                .shadow(color: Color(hex: 0x483620).opacity(0.03), radius: 6, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }
}

struct PaperMenuOption<T: Hashable>: Identifiable {
    let id: T
    let title: String
    var icon: String? = nil

    init(_ id: T, _ title: String, icon: String? = nil) {
        self.id = id
        self.title = title
        self.icon = icon
    }
}

struct PaperMenuPicker<T: Hashable>: View {
    let title: String
    var icon: String? = nil
    @Binding var selection: T
    let options: [PaperMenuOption<T>]
    var prefix: String = ""

    @State private var isHovered = false

    private var currentOption: PaperMenuOption<T>? {
        options.first { $0.id == selection }
    }

    var body: some View {
        Menu {
            ForEach(options) { opt in
                Button {
                    selection = opt.id
                } label: {
                    if selection == opt.id {
                        Label(opt.title, systemImage: "checkmark")
                    } else if let optIcon = opt.icon {
                        Label(opt.title, systemImage: optIcon)
                    } else {
                        Text(opt.title)
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                if let displayIcon = currentOption?.icon ?? icon {
                    Image(systemName: displayIcon)
                }
                Text("\(prefix)\(currentOption?.title ?? title)")
                    .font(MIMITheme.bodyFont(size: 12, weight: .medium))
            }
            .foregroundStyle(MIMITheme.ink)
        }
        .menuStyle(.borderlessButton)
        .padding(.horizontal, 14)
        .frame(minHeight: 37)
        .background(isHovered ? MIMITheme.paperWhite.opacity(0.95) : MIMITheme.paperWhite, in: Capsule())
        .overlay(Capsule().stroke(isHovered ? MIMITheme.warmGold.opacity(0.6) : MIMITheme.softBorder, lineWidth: 1))
        .shadow(color: Color(hex: 0x483620).opacity(isHovered ? 0.05 : 0.02), radius: 4, x: 0, y: 1.5)
        .contentShape(Capsule())
        .fixedSize(horizontal: true, vertical: false)
        .onHover { isHovered = $0 }
    }
}

extension CatalogItem {
    var sheetFormLabel: String {
        switch sheetForm {
        case 1: return "弹唱谱"
        case 2: return "指弹谱"
        case 3: return "和弦谱"
        case 4, 7: return "六线谱"
        default: return "曲谱"
        }
    }

    var difficultyLabel: String {
        switch difficulty {
        case 1: return "零基础"
        case 2: return "初级"
        case 3: return "中级"
        case 4: return "高级"
        case 5...: return "专业"
        default: return "未标注"
        }
    }

    var displayHeat: String {
        heat >= 10_000 ? String(format: "%.1f万", Double(heat) / 10_000) : heat.formatted()
    }
}
