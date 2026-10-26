// Draws the App Store product page header: the app icon's three tiles, larger, in the middle of a
// 21:9 canvas, over a field of faint fragment tiles. Apple keeps the safe area in its templates,
// so everything that matters sits in the center and the edges are only texture. Writes an opaque
// 3840x1646 PNG to the path given as the only argument.

import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let width = 3840
let height = 1646

func color(_ hex: UInt32) -> CGColor {
  CGColor(
    srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
    blue: CGFloat(hex & 0xff) / 255, alpha: 1)
}

/// The light icon's colors, plus a faint tile and text a step off the background.
let background = color(0x0F766E)
let tile = color(0xFFF8E7)
let text = color(0x0F3D3A)
let faintTile = color(0x13847B)
let faintText = color(0x0F6F67)

/// The icon's tiles at the icon's proportions, scaled up and centered.
let scale: CGFloat = 1.55
let iconTiles: [(text: String, x: CGFloat, top: CGFloat, width: CGFloat)] = [
  ("N", 140, 190, 240),
  ("GR", 262, 412, 350),
  ("AMS", 424, 634, 460),
]
let iconTileHeight: CGFloat = 200
let iconBounds = CGRect(x: 140, y: 190, width: 744, height: 644)

/// Fragments for the background, the kind a tiles board deals.
let fragments = [
  "PLA", "ING", "WO", "ER", "TH", "ION", "RE", "ST", "QU", "OD", "MENT", "AIN", "LE", "BR", "US",
  "ED", "CON", "AL", "IVE", "OR", "TI", "EN", "OUS", "NA", "PRE",
]
let rowHeight: CGFloat = 190
let rowGap: CGFloat = 46
let tileGap: CGFloat = 46
let unitWidth: CGFloat = 120

func font(size: CGFloat) -> CTFont {
  let base = NSFont.systemFont(ofSize: size, weight: .heavy)
  let rounded = base.fontDescriptor.withDesign(.rounded) ?? base.fontDescriptor
  return NSFont(descriptor: rounded, size: size) ?? base
}

func drawTile(
  _ label: String, in rect: CGRect, radius: CGFloat, fill: CGColor, ink: CGColor, font: CTFont,
  on context: CGContext
) {
  context.setFillColor(fill)
  context.addPath(
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
  context.fillPath()

  let line = CTLineCreateWithAttributedString(
    NSAttributedString(string: label, attributes: [.font: font, .foregroundColor: ink]))
  let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
  context.textPosition = CGPoint(x: rect.midX - bounds.midX, y: rect.midY - bounds.midY)
  CTLineDraw(line, context)
}

func draw() throws -> CGImage {
  guard
    let context = CGContext(
      data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpace(name: CGColorSpace.sRGB)!,
      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
  else {
    throw HeaderError.context
  }
  context.setFillColor(background)
  context.fill(CGRect(x: 0, y: 0, width: width, height: height))

  // Where the icon's tiles land, in CoreGraphics coordinates (origin at the bottom left).
  let cluster = CGRect(
    x: (CGFloat(width) - iconBounds.width * scale) / 2,
    y: (CGFloat(height) - iconBounds.height * scale) / 2,
    width: iconBounds.width * scale, height: iconBounds.height * scale)
  let clear = cluster.insetBy(dx: -160, dy: -90)

  // Background rows, each starting at a different offset and a different fragment so neither the
  // columns nor the words line up.
  let faintFont = font(size: 110)
  var top: CGFloat = -60
  var row = 0
  while top < CGFloat(height) {
    var x = -CGFloat((row * 137) % 260) - 40
    var index = row * 11
    while x < CGFloat(width) {
      let label = fragments[index % fragments.count]
      index += 7
      let rect = CGRect(
        x: x, y: CGFloat(height) - top - rowHeight,
        width: unitWidth + CGFloat(label.count) * 70, height: rowHeight)
      if !rect.intersects(clear) {
        drawTile(
          label, in: rect, radius: 48, fill: faintTile, ink: faintText, font: faintFont,
          on: context)
      }
      x += rect.width + tileGap
    }
    top += rowHeight + rowGap
    row += 1
  }

  let iconFont = font(size: 150 * scale)
  for icon in iconTiles {
    let rect = CGRect(
      x: cluster.minX + (icon.x - iconBounds.minX) * scale,
      y: cluster.maxY - (icon.top - iconBounds.minY + iconTileHeight) * scale,
      width: icon.width * scale, height: iconTileHeight * scale)
    drawTile(
      icon.text, in: rect, radius: 52 * scale, fill: tile, ink: text, font: iconFont, on: context)
  }

  guard let image = context.makeImage() else {
    throw HeaderError.context
  }
  return image
}

func write(_ image: CGImage, to url: URL) throws {
  guard
    let destination = CGImageDestinationCreateWithURL(
      url as CFURL, UTType.png.identifier as CFString, 1, nil)
  else {
    throw HeaderError.write(url.path)
  }
  CGImageDestinationAddImage(destination, image, nil)
  guard CGImageDestinationFinalize(destination) else {
    throw HeaderError.write(url.path)
  }
}

enum HeaderError: Error {
  case context
  case write(String)
}

guard CommandLine.arguments.count == 2 else {
  FileHandle.standardError.write(Data("usage: AppStoreHeader.swift <output png>\n".utf8))
  exit(2)
}
try write(try draw(), to: URL(fileURLWithPath: CommandLine.arguments[1]))
