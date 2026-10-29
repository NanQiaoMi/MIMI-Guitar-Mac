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
                    Capsule().fill(MIMITheme.warmGold.gradient).frame(width: 5, height: 24)
                    Text(title)
                        .font(MIMITheme.displayFont(size: 27, weight: .bold))
                        .foregroundStyle(MIMITheme.ink)
                }
                if let subtitle {
                    Text(subtitle)
                        .font(MIMITheme.bodyFont(size: 13))
                        .foregroundStyle(MIMITheme.mutedInk)
                        .padding(.leading, 15)
                }
            }
            Spacer(minLength: 8)
            trailing
        }
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
                    .font(MIMITheme.proseFont(size: 12, weight: .bold))
                    .foregroundStyle(Color(hex: 0x2C2825))
                Text("· 纸本墨韵 · 专业数字乐谱工坊")
                    .font(MIMITheme.proseFont(size: 12))
                    .foregroundStyle(Color(hex: 0x8C7B68))
            }
            .fixedSize(horizontal: true, vertical: false)

            MIMIFooterLinkFlow(horizontalSpacing: 16, verticalSpacing: 8) {
                ForEach(Array(links.enumerated()), id: \.offset) { _, link in
                    Button(link.0) { navigate(link.1) }
                        .font(MIMITheme.proseFont(size: 11))
                        .foregroundStyle(Color(hex: 0x705C42))
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                        .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity)

            Text("© \(Calendar.current.component(.year, from: Date())) MIMI Guitar. All rights reserved.")
                .font(MIMITheme.proseFont(size: 10))
                .foregroundStyle(Color(hex: 0xA89B8A))
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: 1152)
        .padding(.vertical, 32)
        .frame(maxWidth: .infinity)
        .background(Color(hex: 0xF7F3EB).opacity(0.9))
        .overlay(alignment: .top) {
            Rectangle().fill(Color(hex: 0xE8DFD2)).frame(height: 1)
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
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let wingWidth = min(max(width * 0.17, 190), 240)

            ZStack(alignment: .topLeading) {
                Image(decorative: PaperAmbienceTile.grain, scale: 2, orientation: .up)
                    .resizable(resizingMode: .tile)
                    .frame(width: width, height: height)
                    .opacity(0.035)
                    .blendMode(.multiply)

                HStack(spacing: 0) {
                    StaticStaveWing(width: wingWidth, height: height, leading: true)
                    Spacer(minLength: 0)
                    StaticStaveWing(width: wingWidth, height: height, leading: false)
                }
                .frame(width: width, height: height)
            }
            .frame(width: width, height: height, alignment: .topLeading)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct StaticStaveWing: View {
    let width: CGFloat
    let height: CGFloat
    let leading: Bool

    var body: some View {
        Image(decorative: PaperAmbienceTile.staves, scale: 5, orientation: .up)
            .resizable(resizingMode: .tile)
            .frame(width: width, height: height)
            .mask {
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black.opacity(0.75), location: 0.4),
                        .init(color: .clear, location: 1),
                    ],
                    startPoint: leading ? .leading : .trailing,
                    endPoint: leading ? .trailing : .leading
                )
            }
    }
}

private enum PaperAmbienceTile {
    static let grain = makeGrainTile()
    static let staves = makeStaveTile()

    private static func makeGrainTile() -> CGImage {
        let side = 512
        var state: UInt64 = 0x4D494D4950415045
        var bytes = [UInt8](repeating: 255, count: side * side * 4)
        for pixel in 0..<(side * side) {
            state &+= 0x9E3779B97F4A7C15
            var value = state
            value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
            value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
            value ^= value >> 31
            let grain = UInt8(32 + (value & 0xCF))
            let offset = pixel * 4
            bytes[offset] = grain
            bytes[offset + 1] = UInt8(max(0, Int(grain) - 7))
            bytes[offset + 2] = UInt8(max(0, Int(grain) - 15))
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
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
              ) else {
            preconditionFailure("Unable to create the static paper grain tile")
        }
        return image
    }

    private static func makeStaveTile() -> CGImage {
        let width = 1280
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
    @State private var image: CGImage?
    @State private var loadFailed = false
    @Environment(\.displayScale) private var displayScale

    private var cacheKey: String { "\(reference ?? ""): \(Int(size.width * displayScale))x\(Int(size.height * displayScale))" }

    var body: some View {
        ZStack {
            MIMITheme.paper
            if let image {
                Image(decorative: image, scale: 1, orientation: .up)
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
            if let cached = ThumbnailImageCache.shared.value(for: cacheKey) { image = cached; return }
            loadFailed = false
            let pixelSize = Int(max(size.width, size.height) * displayScale * 1.35)
            let next = await Task.detached(priority: .utility) { () -> CGImage? in
                do {
                    let url = try AppPaths.resolve(reference: reference, contentRoot: contentRoot)
                    return ThumbnailImageCache.shared.load(url: url, maxPixelSize: max(64, pixelSize), key: cacheKey)
                } catch { return nil }
            }.value
            guard !Task.isCancelled else { return }
            image = next
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

    private init() {
        cache.countLimit = 72
        cache.totalCostLimit = 36 * 1_024 * 1_024
    }

    func value(for key: String) -> CGImage? { cache.object(forKey: key as NSString)?.image }

    func load(url: URL, maxPixelSize: Int, key: String) -> CGImage? {
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
                .font(MIMITheme.bodyFont(size: 12, weight: .semibold))
                .padding(.horizontal, 13)
                .frame(minHeight: 38)
                .foregroundStyle(prominent ? .white : MIMITheme.bodyInk)
                .background(prominent ? MIMITheme.ink : MIMITheme.paperWhite, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    if !prominent { RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(MIMITheme.softBorder, lineWidth: 1) }
                }
        }
        .buttonStyle(.plain)
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
