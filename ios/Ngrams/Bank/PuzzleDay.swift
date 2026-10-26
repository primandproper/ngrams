import Foundation

/// A calendar day, as the bank and saved progress key it: `YYYY-MM-DD` in the device's time zone,
/// so the day rolls over at local midnight.
nonisolated struct PuzzleDay: Hashable, Comparable, Sendable, CustomStringConvertible {
  let year: Int
  let month: Int
  let day: Int

  init(year: Int, month: Int, day: Int) {
    self.year = year
    self.month = month
    self.day = day
  }

  /// Parses `YYYY-MM-DD`, or returns nil for anything else.
  init?(_ text: String) {
    let parts = text.split(separator: "-", omittingEmptySubsequences: false)
    guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
      let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
      (1...12).contains(month), (1...31).contains(day)
    else {
      return nil
    }
    self.init(year: year, month: month, day: day)
  }

  /// The day containing `date` on `calendar`, which carries the time zone.
  init(containing date: Date, calendar: Calendar = .current) {
    let parts = calendar.dateComponents([.year, .month, .day], from: date)
    self.init(year: parts.year ?? 0, month: parts.month ?? 0, day: parts.day ?? 0)
  }

  private static let monthNames = [
    "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
  ]

  /// "Oct 25", or "Oct 25, 2026" with the year. Always English, like the rest of the app's text.
  func name(includingYear: Bool) -> String {
    guard Self.monthNames.indices.contains(month - 1) else {
      return description
    }
    let name = "\(Self.monthNames[month - 1]) \(day)"
    return includingYear ? "\(name), \(year)" : name
  }

  /// The midnight that starts the day on `calendar`, or nil if the calendar has no such date.
  func start(in calendar: Calendar = .current) -> Date? {
    calendar.date(from: DateComponents(year: year, month: month, day: day))
  }

  var description: String {
    String(format: "%04d-%02d-%02d", year, month, day)
  }

  static func < (lhs: PuzzleDay, rhs: PuzzleDay) -> Bool {
    (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
  }
}

extension PuzzleDay {
  /// The day it is on the device. Debug builds take a `YYYY-MM-DD` from the `pinnedToday` default
  /// instead (launch with `-pinnedToday 2026-11-12`), so screenshots don't depend on when they're
  /// taken.
  static var today: PuzzleDay {
    #if DEBUG
      if let pinned = UserDefaults.standard.string(forKey: "pinnedToday").flatMap(PuzzleDay.init) {
        return pinned
      }
    #endif
    return PuzzleDay(containing: .now)
  }
}
