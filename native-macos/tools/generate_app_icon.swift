#!/usr/bin/env swift
import AppKit
import CoreGraphics
import CoreText
import Foundation

private struct IconVariant {
    let fileName: String
    let pixels: Int
}

private let variants = [
    IconVariant(fileName: "icon_16x16.png", pixels: 16),
    IconVariant(fileName: "icon_16x16@2x.png", pixels: 32),
    IconVariant(fileName: "icon_32x32.png", pixels: 32),
    IconVariant(fileName: "icon_32x32@2x.png", pixels: 64),
    IconVariant(fileName: "icon_128x128.png", pixels: 128),
    IconVariant(fileName: "icon_128x128@2x.png", pixels: 256),
    IconVariant(fileName: "icon_256x256.png", pixels: 256),
    IconVariant(fileName: "icon_256x256@2x.png", pixels: 512),
    IconVariant(fileName: "icon_512x512.png", pixels: 512),
    IconVariant(fileName: "icon_512x512@2x.png", pixels: 1024),
]

private func renderIcon(pixels: Int) throws -> Data {
    let side = CGFloat(pixels)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
        data: nil,
        width: pixels,
        height: pixels,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        throw NSError(domain: "MIMIAppIcon", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not create the icon bitmap context."])
    }

    context.setShouldAntialias(true)
    context.setAllowsAntialiasing(true)
    context.setBlendMode(.normal)
    context.clear(CGRect(x: 0, y: 0, width: side, height: side))

    // Mirrors public/favicon.svg: 32×32 viewBox, 8-unit rounded corners,
    // #171717 background and a centered #fefffc “谱” in Georgia/serif at 18px.
    let iconRect = CGRect(x: 0, y: 0, width: side, height: side)
    let cornerRadius = side * 8 / 32
    let roundedRect = CGPath(roundedRect: iconRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
    context.addPath(roundedRect)
    context.setFillColor(CGColor(red: 23 / 255, green: 23 / 255, blue: 23 / 255, alpha: 1))
    context.fillPath()

    let text = "谱"
    let baseFont = CTFontCreateWithName("Georgia" as CFString, side * 18 / 32, nil)
    let fallbackFont = CTFontCreateForString(baseFont, text as CFString, CFRange(location: 0, length: text.utf16.count))
    let textColor = CGColor(red: 254 / 255, green: 255 / 255, blue: 252 / 255, alpha: 1)
    let attributes: [NSAttributedString.Key: Any] = [
        NSAttributedString.Key(kCTFontAttributeName as String): fallbackFont,
        NSAttributedString.Key(kCTForegroundColorAttributeName as String): textColor,
    ]
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
    let textWidth = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))

    // SVG text y=22 is a baseline measured from the top of its 32-unit viewBox.
    context.textPosition = CGPoint(x: (side - textWidth) / 2, y: side * (32 - 22) / 32)
    CTLineDraw(line, context)

    guard let image = context.makeImage() else {
        throw NSError(domain: "MIMIAppIcon", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not create the icon image."])
    }
    let bitmap = NSBitmapImageRep(cgImage: image)
    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "MIMIAppIcon", code: 3, userInfo: [NSLocalizedDescriptionKey: "Could not encode an icon PNG."])
    }
    return png
}

private func generate() throws {
    let scriptURL = URL(fileURLWithPath: #filePath).standardizedFileURL
    let nativeMacRoot = scriptURL.deletingLastPathComponent().deletingLastPathComponent()
    let resourcesDirectory = nativeMacRoot.appendingPathComponent("Resources", isDirectory: true)
    let outputURL = resourcesDirectory.appendingPathComponent("AppIcon.icns", isDirectory: false)
    let iconsetURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("MIMI-AppIcon-\(UUID().uuidString).iconset", isDirectory: true)

    try FileManager.default.createDirectory(at: resourcesDirectory, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: iconsetURL) }

    for variant in variants {
        let png = try renderIcon(pixels: variant.pixels)
        try png.write(to: iconsetURL.appendingPathComponent(variant.fileName), options: .atomic)
    }

    let iconutil = Process()
    iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    iconutil.arguments = ["-c", "icns", iconsetURL.path, "-o", outputURL.path]
    try iconutil.run()
    iconutil.waitUntilExit()
    guard iconutil.terminationStatus == 0 else {
        throw NSError(domain: "MIMIAppIcon", code: Int(iconutil.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "iconutil failed with exit status \(iconutil.terminationStatus)."])
    }

    print("Generated \(outputURL.path)")
}

do {
    try generate()
} catch {
    fputs("App icon generation failed: \(error.localizedDescription)\n", stderr)
    exit(EXIT_FAILURE)
}
