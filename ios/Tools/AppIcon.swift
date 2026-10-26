// Draws the app icon: three tiles stepping down the canvas, reading N, GR, AMS. Writes the iOS
// light, dark, and tinted 1024px variants into the asset catalog directory given first, and the
// Android adaptive icon's layers into the res directory given second, with the 512px Play Store
// icon beside it.

import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

struct Palette {
  let background: CGColor
  let tile: CGColor
  let text: CGColor
}

let side = 1024
let tileHeight: CGFloat = 200
let cornerRadius: CGFloat = 52
/// Each tile's text, left edge, and width, top to bottom.
let tiles: [(text: String, x: CGFloat, width: CGFloat)] = [
  ("N", 140, 240),
  ("GR", 262, 350),
  ("AMS", 424, 460),
]
let tileTops: [CGFloat] = [190, 412, 634]

func color(_ hex: UInt32) -> CGColor {
  CGColor(
    srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
    blue: CGFloat(hex & 0xff) / 255, alpha: 1)
}

let variants: [(file: String, palette: Palette)] = [
  (
    "icon-light.png",
    Palette(background: color(0x0F766E), tile: color(0xFFF8E7), text: color(0x0F3D3A))
  ),
  (
    "icon-dark.png",
    Palette(background: color(0x0B1215), tile: color(0x1E2B30), text: color(0x5EEAD4))
  ),
  (
    "icon-tinted.png",
    Palette(background: color(0x000000), tile: color(0xD9D9D9), text: color(0x000000))
  ),
]

func font() -> CTFont {
  let base = NSFont.systemFont(ofSize: 150, weight: .heavy)
  let rounded = base.fontDescriptor.withDesign(.rounded) ?? base.fontDescriptor
  return NSFont(descriptor: rounded, size: 150) ?? base
}

/// The icon at `pixels` square. iOS wants no alpha channel; Play's store icon wants one.
func draw(_ palette: Palette, pixels: Int = side, alpha: Bool = false) throws -> CGImage {
  guard
    let context = CGContext(
      data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpace(name: CGColorSpace.sRGB)!,
      bitmapInfo: (alpha ? CGImageAlphaInfo.premultipliedLast : .noneSkipLast).rawValue)
  else {
    throw IconError.context
  }
  context.scaleBy(x: CGFloat(pixels) / CGFloat(side), y: CGFloat(pixels) / CGFloat(side))
  context.setFillColor(palette.background)
  context.fill(CGRect(x: 0, y: 0, width: side, height: side))

  let attributes: [NSAttributedString.Key: Any] = [
    .font: font(), .foregroundColor: palette.text,
  ]
  for (tile, top) in zip(tiles, tileTops) {
    // CoreGraphics puts the origin at the bottom left.
    let rect = CGRect(
      x: tile.x, y: CGFloat(side) - top - tileHeight, width: tile.width, height: tileHeight)
    context.setFillColor(palette.tile)
    context.addPath(
      CGPath(
        roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil))
    context.fillPath()

    let line = CTLineCreateWithAttributedString(
      NSAttributedString(string: tile.text, attributes: attributes))
    let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
    context.textPosition = CGPoint(
      x: rect.midX - bounds.midX, y: rect.midY - bounds.midY)
    CTLineDraw(line, context)
  }

  guard let image = context.makeImage() else {
    throw IconError.context
  }
  return image
}

func write(_ image: CGImage, to url: URL) throws {
  guard
    let destination = CGImageDestinationCreateWithURL(
      url as CFURL, UTType.png.identifier as CFString, 1, nil)
  else {
    throw IconError.write(url.path)
  }
  CGImageDestinationAddImage(destination, image, nil)
  guard CGImageDestinationFinalize(destination) else {
    throw IconError.write(url.path)
  }
}

enum IconError: Error {
  case context
  case write(String)
}

/// Android's adaptive icon layers are 108dp squares, of which a launcher's mask may show as little
/// as the 66dp circle in the middle. The tiles are scaled so their whole block fits that circle.
let androidDensities: [(folder: String, side: Int)] = [
  ("mipmap-mdpi", 108), ("mipmap-hdpi", 162), ("mipmap-xhdpi", 216), ("mipmap-xxhdpi", 324),
  ("mipmap-xxxhdpi", 432),
]

/// The tiles alone on a transparent square of `side` pixels, for an adaptive icon layer. The
/// monochrome layer, which Android tints for themed icons, knocks the letters out of the tiles.
func drawAndroidLayer(side: Int, monochrome: Bool) throws -> CGImage {
  guard
    let context = CGContext(
      data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpace(name: CGColorSpace.sRGB)!,
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
  else {
    throw IconError.context
  }
  let left = tiles.map(\.x).min() ?? 0
  let right = tiles.map { $0.x + $0.width }.max() ?? CGFloat(1024)
  let top = tileTops.min() ?? 0
  let bottom = (tileTops.max() ?? 0) + tileHeight
  let block = CGSize(width: right - left, height: bottom - top)
  let safe = CGFloat(side) * 66 / 108
  let scale = safe / (block.width * block.width + block.height * block.height).squareRoot()
  // Center the block, then draw in the 1024pt icon's coordinates, flipped so tops read downward.
  context.translateBy(
    x: (CGFloat(side) - block.width * scale) / 2, y: (CGFloat(side) + block.height * scale) / 2)
  context.scaleBy(x: scale, y: -scale)
  context.translateBy(x: -left, y: -top)

  let palette = variants[0].palette
  for (tile, top) in zip(tiles, tileTops) {
    let rect = CGRect(x: tile.x, y: top, width: tile.width, height: tileHeight)
    context.setFillColor(monochrome ? CGColor(gray: 1, alpha: 1) : palette.tile)
    context.addPath(
      CGPath(
        roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil))
    context.fillPath()

    let line = CTLineCreateWithAttributedString(
      NSAttributedString(
        string: tile.text, attributes: [.font: font(), .foregroundColor: palette.text]))
    let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
    context.saveGState()
    if monochrome {
      context.setBlendMode(.clear)
    }
    // Text draws upward, so flip back around the tile's middle for it.
    context.translateBy(x: rect.midX, y: rect.midY)
    context.scaleBy(x: 1, y: -1)
    context.textPosition = CGPoint(x: -bounds.midX, y: -bounds.midY)
    CTLineDraw(line, context)
    context.restoreGState()
  }

  guard let image = context.makeImage() else {
    throw IconError.context
  }
  return image
}

guard CommandLine.arguments.count == 3 else {
  FileHandle.standardError.write(
    Data("usage: AppIcon.swift <appiconset dir> <android res dir>\n".utf8))
  exit(2)
}
let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
for variant in variants {
  try write(try draw(variant.palette), to: directory.appendingPathComponent(variant.file))
}

let res = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
for density in androidDensities {
  let folder = res.appendingPathComponent(density.folder, isDirectory: true)
  try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
  try write(
    try drawAndroidLayer(side: density.side, monochrome: false),
    to: folder.appendingPathComponent("ic_launcher_foreground.png"))
  try write(
    try drawAndroidLayer(side: density.side, monochrome: true),
    to: folder.appendingPathComponent("ic_launcher_monochrome.png"))
}
// Where Android Studio's own icon tool puts the store icon: next to res, not in it.
try write(
  try draw(variants[0].palette, pixels: 512, alpha: true),
  to: res.deletingLastPathComponent().appendingPathComponent("ic_launcher-playstore.png"))
