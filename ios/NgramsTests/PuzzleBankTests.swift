import Foundation
import Testing

@testable import Ngrams

@Suite("PuzzleBank")
struct PuzzleBankTests {
  @Test("decodes tiles puzzles")
  func decodes() throws {
    let bank = try PuzzleBank.decode(bankJSON(puzzles: [tilesPuzzleJSON()]))

    #expect(bank.seed == 7)
    #expect(bank.days == [testDay])
    let puzzle = try #require(bank.tilesPuzzles(on: testDay).first)
    #expect(puzzle.tiles == ["ab", "cd"])
    #expect(puzzle.targets == [[0, 1]])
    #expect(puzzle.targetScore == 62)
    #expect(puzzle.words.map(\.shown) == ["ab", "ábcd"])
    #expect(puzzle.blocked == ["cdab"])
  }

  @Test("decodes a board with no blocked words")
  func decodesWithoutBlocked() throws {
    let bank = try PuzzleBank.decode(bankJSON(puzzles: [tilesPuzzleJSON(blocked: nil)]))

    let puzzle = try #require(bank.tilesPuzzles(on: testDay).first)
    #expect(puzzle.blocked.isEmpty)
  }

  @Test("sorts by language, then size")
  func sorts() throws {
    let bank = try PuzzleBank.decode(
      bankJSON(puzzles: [
        tilesPuzzleJSON(lang: "es"), tilesPuzzleJSON(n: 3, targets: "[]"),
        tilesPuzzleJSON(n: 2),
      ]))

    #expect(bank.tilesPuzzles(on: testDay).map(\.id) == ["en-2", "en-3", "es-2"])
    #expect(bank.tilesPuzzles(on: PuzzleDay(year: 2027, month: 1, day: 2)).isEmpty)
  }

  @Test("skips kinds and languages it doesn't know")
  func skipsUnknown() throws {
    let bank = try PuzzleBank.decode(
      bankJSON(puzzles: [
        #"{"lang":"en","kind":"word","n":4,"answer":"lamp"}"#,
        tilesPuzzleJSON(lang: "fr"),
      ]))

    #expect(bank.tilesPuzzles(on: testDay).isEmpty)
  }

  @Test("rejects an unsupported version")
  func rejectsVersion() {
    #expect(throws: BankError.unsupportedVersion(2)) {
      try PuzzleBank.decode(bankJSON(version: 2, puzzles: []))
    }
  }

  @Test("rejects a malformed date")
  func rejectsDate() {
    #expect(throws: BankError.badDate("2027-1-1")) {
      try PuzzleBank.decode(bankJSON(date: "2027-1-1", puzzles: []))
    }
  }

  @Test("rejects a tile index outside the board")
  func rejectsTileIndex() {
    #expect(throws: BankError.badTileIndex(5, tiles: 2)) {
      try PuzzleBank.decode(bankJSON(puzzles: [tilesPuzzleJSON(targets: "[[0,5]]")]))
    }
  }

  /// The app hosts the tests, so the main bundle's bank is the one the app ships.
  @Test("loads the bundled bank with three boards per language per day")
  func loadsBundled() async throws {
    let bank = try await PuzzleBank.loadBundled()

    #expect(!bank.days.isEmpty)
    for day in bank.days {
      #expect(
        bank.tilesPuzzles(on: day).map(\.id) == ["en-3", "en-4", "en-5", "es-3", "es-4", "es-5"])
    }
  }
}
