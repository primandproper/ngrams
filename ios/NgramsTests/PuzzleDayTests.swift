import Foundation
import Testing

@testable import Ngrams

@Suite("PuzzleDay")
struct PuzzleDayTests {
  @Test("parses and prints YYYY-MM-DD")
  func roundTrips() throws {
    let day = try #require(PuzzleDay("2027-03-09"))

    #expect(day == PuzzleDay(year: 2027, month: 3, day: 9))
    #expect(day.description == "2027-03-09")
  }

  @Test("rejects anything else", arguments: ["2027-3-9", "2027-13-01", "2027-01-32", "x", ""])
  func rejects(text: String) {
    #expect(PuzzleDay(text) == nil)
  }

  @Test("rolls over at midnight in the calendar's time zone")
  func localMidnight() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(identifier: "America/Chicago"))
    // 2027-01-02 03:30 UTC is still 2027-01-01 in Chicago.
    let instant = Date(timeIntervalSince1970: 1_798_860_600)

    #expect(PuzzleDay(containing: instant, calendar: calendar) == testDay)
  }

  @Test("starts at midnight in the calendar's time zone")
  func start() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(identifier: "America/Chicago"))
    let start = try #require(testDay.start(in: calendar))

    // 2027-01-01 00:00 in Chicago is 06:00 UTC.
    #expect(start == Date(timeIntervalSince1970: 1_798_783_200))
    #expect(PuzzleDay(containing: start, calendar: calendar) == testDay)
  }

  @Test("names the day in English, with or without the year")
  func names() {
    #expect(testDay.name(includingYear: false) == "Jan 1")
    #expect(PuzzleDay(year: 2026, month: 10, day: 25).name(includingYear: true) == "Oct 25, 2026")
  }

  @Test("orders by date")
  func orders() {
    let days = [
      PuzzleDay(year: 2027, month: 2, day: 1), PuzzleDay(year: 2026, month: 12, day: 31), testDay,
    ]

    #expect(days.sorted().map(\.description) == ["2026-12-31", "2027-01-01", "2027-02-01"])
  }
}
