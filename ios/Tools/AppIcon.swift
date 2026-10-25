// Draws the app icon: three tiles stepping down the canvas, reading N, GR, AMS. Writes the
// light, dark, and tinted 1024px variants into the asset catalog directory given as the only
// argument.

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

func draw(_ palette: Palette) throws -> CGImage {
  guard
    let context = CGContext(
      data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpace(name: CGColorSpace.sRGB)!,
      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
  else {
    throw IconError.context
  }
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

guard CommandLine.arguments.count == 2 else {
  FileHandle.standardError.write(Data("usage: AppIcon.swift <appiconset dir>\n".utf8))
  exit(2)
}
let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
for variant in variants {
  try write(try draw(variant.palette), to: directory.appendingPathComponent(variant.file))
}
