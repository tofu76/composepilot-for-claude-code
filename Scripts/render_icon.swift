#!/usr/bin/env swift
import AppKit

// アイコン素材(SVGまたはPNG)を .iconset の各サイズへ書き出す。
//
// 使い方: swift Scripts/render_icon.swift <入力ファイル> <出力ディレクトリ>
//
// なぜ外部ツールを使わないか: rsvg-convert / ImageMagick / Inkscape のいずれも
// 標準では入っていない。macOS 11以降の`NSImage`はSVGを読めるため、AppKitだけで
// ベクターから各サイズを直接描ける。Homebrew依存を増やさずに済む。

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    FileHandle.standardError.write(
        "使い方: swift Scripts/render_icon.swift <入力ファイル> <出力ディレクトリ>\n"
            .data(using: .utf8)!
    )
    exit(2)
}

let inputURL = URL(fileURLWithPath: arguments[1])
let outputDirectory = URL(fileURLWithPath: arguments[2])

guard let image = NSImage(contentsOf: inputURL) else {
    FileHandle.standardError.write(
        "入力ファイルを画像として読み込めませんでした: \(inputURL.path)\n".data(using: .utf8)!
    )
    exit(1)
}

try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

// iconutil が要求する命名規則。@2x は同じピクセル数でも別ファイルとして必要。
let variants: [(name: String, pixels: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

for variant in variants {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: variant.pixels,
        pixelsHigh: variant.pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        FileHandle.standardError.write("ビットマップを作成できませんでした\n".data(using: .utf8)!)
        exit(1)
    }
    rep.size = NSSize(width: variant.pixels, height: variant.pixels)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    // .copy は透過をそのまま書き込む(.sourceOver だと下地の黒が残る場合がある)。
    image.draw(
        in: NSRect(x: 0, y: 0, width: variant.pixels, height: variant.pixels),
        from: .zero,
        operation: .copy,
        fraction: 1.0
    )
    NSGraphicsContext.restoreGraphicsState()

    guard let data = rep.representation(using: .png, properties: [:]) else {
        FileHandle.standardError.write("PNGへの変換に失敗しました: \(variant.name)\n".data(using: .utf8)!)
        exit(1)
    }
    try data.write(to: outputDirectory.appendingPathComponent("\(variant.name).png"))
}

print("\(variants.count)個のPNGを書き出しました: \(outputDirectory.path)")
