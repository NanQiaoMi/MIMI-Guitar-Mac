#!/usr/bin/env swift
import AppKit
import CoreGraphics
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

private func renderIcon(pixels: Int, sourceImage: CGImage) throws -> Data {
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
    context.interpolationQuality = .high
    context.setBlendMode(.normal)
    context.clear(CGRect(x: 0, y: 0, width: pixels, height: pixels))

    let rect = CGRect(x: 0, y: 0, width: pixels, height: pixels)
    context.draw(sourceImage, in: rect)

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

    let defaultLogoURL = resourcesDirectory
        .appendingPathComponent("Design", isDirectory: true)
        .appendingPathComponent("logo.png", isDirectory: false)

    let sourceURL: URL
    if CommandLine.arguments.count > 1 {
        sourceURL = URL(fileURLWithPath: CommandLine.arguments[1])
    } else {
        sourceURL = defaultLogoURL
    }

    guard let imageSource = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
          let sourceImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
        throw NSError(
            domain: "MIMIAppIcon",
            code: 4,
            userInfo: [NSLocalizedDescriptionKey: "Could not load source image from \(sourceURL.path)"]
        )
    }

    let iconsetURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("MIMI-AppIcon-\(UUID().uuidString).iconset", isDirectory: true)

    try FileManager.default.createDirectory(at: resourcesDirectory, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: iconsetURL) }

    for variant in variants {
        let png = try renderIcon(pixels: variant.pixels, sourceImage: sourceImage)
        try png.write(to: iconsetURL.appendingPathComponent(variant.fileName), options: .atomic)
    }

    let iconutil = Process()
    iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    iconutil.arguments = ["-c", "icns", iconsetURL.path, "-o", outputURL.path]
    try iconutil.run()
    iconutil.waitUntilExit()
    guard iconutil.terminationStatus == 0 else {
        throw NSError(
            domain: "MIMIAppIcon",
            code: Int(iconutil.terminationStatus),
            userInfo: [NSLocalizedDescriptionKey: "iconutil failed with exit status \(iconutil.terminationStatus)."]
        )
    }

    print("Generated \(outputURL.path) from \(sourceURL.path)")
}

do {
    try generate()
} catch {
    fputs("Error: \(error.localizedDescription)\n", stderr)
    exit(1)
}
