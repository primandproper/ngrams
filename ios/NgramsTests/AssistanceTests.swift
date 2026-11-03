import Foundation
import Observability
import SwiftData
import Testing

@testable import Ngrams

@Suite("Hints and solving")
struct AssistanceTests {
  @Test("counts a Password puzzle solved for the player as a loss, keeping its guesses")
  func wordGivesUp() {
    var game = WordGame(puzzle: wordPuzzle, guesses: ["plaza"])

    game.type("l")
    game.giveUp()
    game.type("l")

    #expect(game.status == .lost)
    #expect(game.guesses == ["plaza"])
    #expect(game.current.isEmpty)
  }

  @Test("leaves a won Password puzzle won")
  func wonStaysWon() {
    var game = WordGame(puzzle: wordPuzzle, guesses: ["llama"])

    game.giveUp()

    #expect(game.status == .won(guesses: 1))
    #expect(
      WordGame(puzzle: wordPuzzle, guesses: ["llama"], gaveUp: true).status == .won(guesses: 1))
  }

  @Test("takes hints only while a Password puzzle is in play")
  func wordHints() {
    var game = WordGame(puzzle: wordPuzzle, hints: ["0"])

    game.take(hint: "1")
    #expect(game.hints == ["0", "1"])
    #expect(game.status == .playing)

    game.giveUp()
    game.take(hint: "2")
    #expect(game.hints == ["0", "1"])
  }

  @Test("gives up a board's star even with every target found")
  func tilesGivesUp() {
    var game = TilesGame(puzzle: smallPuzzle, foundWords: ["ab", "abcd"])

    game.giveUp(finding: ["abcd", "efgh"])

    #expect(game.foundWords == ["ab", "abcd", "efgh"])
    #expect(game.allTargetsFound)
    #expect(!game.earnedStar)
  }

  @Test("gives up a pangram board's star even past the target")
  func pangramGivesUp() {
    var game = PangramGame(puzzle: pangramPuzzle, hints: ["plaice"])

    game.giveUp(finding: ["plaice", "place"])

    #expect(game.score >= pangramPuzzle.targetScore)
    #expect(!game.earnedStar)
    #expect(game.hints == ["plaice"])
  }
}

@Suite("ProgressStore hints and solving")
struct AssistanceStoreTests {
  private let key = ProgressKey(language: .en, kind: .word, n: 5, day: testDay)

  private func store() throws -> (ProgressStore, ModelContext) {
    let container = try ModelContainer(
      for: PuzzleProgress.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let context = ModelContext(container)
    return (ProgressStore(context: context, observer: recordingObserver("test")), context)
  }

  @Test("starts a puzzle with its first hint, timed and in the mode it was taken in")
  func hintStarts() throws {
    let (store, _) = try store()
    let stretch = PlayStretch(start: testInstant, end: testInstant.addingTimeInterval(10))

    try store.take(hint: "2", for: key, hardMode: true, stretches: [stretch], at: stretch.end)
    try store.take(hint: "0", for: key, hardMode: false)

    #expect(try store.assistance(for: key) == Assistance(hints: ["2", "0"], gaveUp: false))
    #expect(try store.hardMode(for: key) == true)
    #expect(try store.entries(for: key).isEmpty)
    #expect(try store.timing(for: key)?.stretches == [stretch])
    #expect(try store.timing(for: key)?.timed == true)
  }

  @Test("records solving as finishing the puzzle, with the entries that finish it")
  func givesUp() throws {
    let (store, _) = try store()
    try store.append("plaza", for: key)

    try store.giveUp(adding: ["llama"], for: key, at: testInstant)

    #expect(try store.entries(for: key) == ["plaza", "llama"])
    #expect(try store.assistance(for: key) == Assistance(hints: [], gaveUp: true))
    #expect(try store.timing(for: key)?.completedAt == testInstant)
  }

  @Test("keeps when a finished puzzle was first completed")
  func keepsCompletion() throws {
    let (store, _) = try store()
    try store.append("llama", for: key, completes: true, at: testInstant)

    try store.giveUp(for: key, at: testInstant.addingTimeInterval(60))

    #expect(try store.timing(for: key)?.completedAt == testInstant)
  }

  @Test("restores hints and solving into a session's game")
  func restores() throws {
    let (store, _) = try store()
    try store.take(hint: "1", for: key)
    try store.giveUp(for: key)

    let session = WordSession(
      puzzle: wordPuzzle, day: testDay, list: wordList, hardMode: false, store: store,
      observer: recordingObserver("test"))

    #expect(session.game.hints == ["1"])
    #expect(session.game.status == .lost)
  }
}
