import Foundation
import Testing

@testable import Ngrams

@Suite("StatsBook")
struct StatsTests {
  private let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/Chicago")!
    return calendar
  }()

  private let line = PuzzleLine(language: .en, kind: .word, n: 5)
  private let days = (1...5).map { PuzzleDay(year: 2027, month: 1, day: $0) }

  private var bank: PuzzleBank {
    PuzzleBank(
      seed: 1, tiles: [:], words: Dictionary(uniqueKeysWithValues: days.map { ($0, [wordPuzzle]) }),
      pangrams: [days[0]: [pangramPuzzle]])
  }

  /// A word record for day `index`, finished at noon on day `finishedOn` (the same day unless
  /// given).
  private func word(_ index: Int, _ guesses: [String], finishedOn: Int? = nil) -> PlayRecord {
    let day = days[finishedOn ?? index]
    return PlayRecord(
      key: ProgressKey(language: .en, kind: .word, n: 5, day: days[index]), entries: guesses,
      completedAt: day.start(in: calendar)!.addingTimeInterval(12 * 3600))
  }

  /// Solved in one, solved in two, lost, solved in one.
  private var fourDays: [PlayRecord] {
    [
      word(0, ["llama"]), word(1, ["plaza", "llama"]),
      word(2, Array(repeating: "cramp", count: 6)), word(3, ["llama"]),
    ]
  }

  private func stats(_ records: [PlayRecord], today: Int = 4) -> LineStats? {
    StatsBook.compute(records: records, bank: bank, today: days[today], calendar: calendar)[line]
  }

  @Test("counts plays, wins, guesses, and streaks, with today still to play")
  func counts() throws {
    let stats = try #require(stats(fourDays))

    #expect(stats.played == 4)
    #expect(stats.decided == 4)
    #expect(stats.successes == 3)
    #expect(stats.successRate == 0.75)
    #expect(stats.currentStreak == 1)
    #expect(stats.bestStreak == 2)
    #expect(stats.guessCounts == [2, 1, 0, 0, 0, 0])
  }

  @Test("extends the streak with today's solve and keeps it while today is unfinished")
  func today() throws {
    #expect(try #require(stats(fourDays + [word(4, ["llama"])])).currentStreak == 2)
    #expect(try #require(stats(fourDays + [word(4, ["plaza"])])).currentStreak == 1)
  }

  @Test("ends the streak when today is lost")
  func lostToday() throws {
    let lost = word(4, Array(repeating: "cramp", count: 6))

    #expect(try #require(stats(fourDays + [lost])).currentStreak == 0)
  }

  @Test("counts a solve from an earlier day, but not toward the streak")
  func archive() throws {
    let records = Array(fourDays.prefix(3)) + [word(3, ["llama"], finishedOn: 4)]
    let stats = try #require(stats(records))

    #expect(stats.successes == 3)
    #expect(stats.currentStreak == 0)
  }

  @Test("ignores days after today")
  func future() throws {
    let stats = try #require(stats(fourDays, today: 1))

    #expect(stats.played == 2)
    #expect(stats.currentStreak == 2)
  }

  @Test("counts a board's star as its success")
  func boards() throws {
    let record = PlayRecord(
      key: ProgressKey(language: .en, kind: .pangram, n: 6, day: days[0]), entries: ["plaice"],
      completedAt: days[0].start(in: calendar))
    let stats = try #require(
      StatsBook.compute(records: [record], bank: bank, today: days[1], calendar: calendar)[
        PuzzleLine(language: .en, kind: .pangram, n: 6)])

    #expect(stats.successes == 1)
    #expect(stats.currentStreak == 1)
  }
}
