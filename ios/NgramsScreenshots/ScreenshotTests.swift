import UIKit
import UniformTypeIdentifiers
import XCTest

/// Walks the app through its App Store screenshots on a seeded, pinned day. `make screenshots` runs
/// this and pulls the images out of the result bundle; `make test` leaves it out.
final class ScreenshotTests: XCTestCase {
  /// Three weeks into the bank, so the seeded history has room for streaks.
  private static let today = "2026-11-12"

  @MainActor
  func testScreenshots() throws {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = [
      "-screenshotSeed", "YES",
      "-pinnedToday", Self.today,
      // Every setting, so whatever a simulator saved from earlier play can't show through.
      "-languages", "en,es",
      "-homeGrouping", "game",
      "-wordHardMode", "YES",
      "-solvedTilesLeave", "NO",
      "-pangramHardMode", "NO",
      "-pangramFoundOrder", "alphabetical",
      "-AppleLanguages", "(en)",
      "-AppleLocale", "en_US",
    ]
    app.launch()

    let password = row("word-es-5", in: app)
    try snap("01-home")

    password.tap()
    XCTAssertTrue(app.buttons["Enter"].waitForExistence(timeout: 10))
    try snap("02-password")
    back(in: app)

    row("tiles-en-4", in: app).tap()
    XCTAssertTrue(app.buttons["Submit"].waitForExistence(timeout: 10))
    try snap("03-tiles")
    back(in: app)

    row("pangram-en-7", in: app).tap()
    XCTAssertTrue(app.buttons["Shuffle"].waitForExistence(timeout: 10))
    try snap("04-pangram")
    back(in: app)

    app.buttons["Stats"].tap()
    XCTAssertTrue(app.navigationBars["Stats"].waitForExistence(timeout: 10))
    try snap("05-stats")
    app.buttons["Done"].tap()

    app.buttons["Settings"].tap()
    XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 10))
    try snap("06-settings")
  }

  /// A home row by its puzzle's id, scrolled clear of the floating bottom toolbar. A row under the
  /// toolbar still counts as hittable, but a tap on it lands on the toolbar.
  @MainActor
  private func row(_ id: String, in app: XCUIApplication) -> XCUIElement {
    let row = app.buttons[id]
    let window = app.windows.firstMatch
    let clear = window.frame.maxY * 0.8
    func reachable() -> Bool {
      row.waitForExistence(timeout: 5) && row.isHittable && row.frame.maxY < clear
    }
    for _ in 0..<10 where !reachable() {
      // A short drag rather than swipeUp, which can fling the row off the top.
      window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
        .press(
          forDuration: 0.05,
          thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)))
    }
    XCTAssertTrue(reachable(), "no reachable home row \(id)")
    return row
  }

  @MainActor
  private func back(in app: XCUIApplication) {
    app.navigationBars.buttons.element(boundBy: 0).tap()
  }

  @MainActor
  private func snap(_ name: String) throws {
    let attachment = XCTAttachment(
      uniformTypeIdentifier: UTType.png.identifier, name: "\(name).png",
      payload: try opaquePNG(XCUIScreen.main.screenshot().image), userInfo: nil)
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  /// The screenshot redrawn into a bitmap with no alpha channel, which App Store Connect requires.
  /// UIKit's own PNG encoding keeps the channel even for an opaque image.
  @MainActor
  private func opaquePNG(_ image: UIImage) throws -> Data {
    let cgImage = try XCTUnwrap(image.cgImage, "screenshot has no bitmap")
    let space = cgImage.colorSpace ?? CGColorSpaceCreateDeviceRGB()
    let context = try XCTUnwrap(
      CGContext(
        data: nil, width: cgImage.width, height: cgImage.height, bitsPerComponent: 8,
        bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue),
      "couldn't make an opaque bitmap")
    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
    let flattened = try XCTUnwrap(context.makeImage(), "couldn't flatten the screenshot")

    let data = NSMutableData()
    let destination = try XCTUnwrap(
      CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil),
      "couldn't start a PNG")
    CGImageDestinationAddImage(destination, flattened, nil)
    return try XCTUnwrap(
      CGImageDestinationFinalize(destination) ? data as Data : nil, "couldn't write the PNG")
  }
}
