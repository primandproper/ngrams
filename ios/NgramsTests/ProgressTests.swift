import Observability
import SwiftData
import Testing

@testable import Ngrams

private func inMemoryContext() throws -> ModelContext {
  let container = try ModelContainer(
    for: PuzzleProgress.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
  return ModelContext(container)
}

private let key = ProgressKey(language: .en, kind: .tiles, n: 2, day: testDay)

@Suite("ProgressStore")
struct ProgressStoreTests {
  @Test("appends entries in order")
  func appends() throws {
    let store = ProgressStore(context: try inMemoryContext(), observer: recordingObserver("test"))

    try store.append("ab", for: key)
    try store.append("abcd", for: key)

    #expect(try store.entries(for: key) == ["ab", "abcd"])
  }

  @Test("keeps each puzzle's entries apart")
  func separatesKeys() throws {
    let store = ProgressStore(context: try inMemoryContext(), observer: recordingObserver("test"))
    let otherDay = ProgressKey(
      language: .en, kind: .tiles, n: 2, day: PuzzleDay(year: 2027, month: 1, day: 2))
    let otherLanguage = ProgressKey(language: .es, kind: .tiles, n: 2, day: testDay)

    try store.append("ab", for: key)
    try store.append("ef", for: otherDay)

    #expect(try store.entries(for: key) == ["ab"])
    #expect(try store.entries(for: otherDay) == ["ef"])
    #expect(try store.entries(for: otherLanguage).isEmpty)
  }
}

@Suite("TilesSession")
struct TilesSessionTests {
  @Test("saves each found word and restores it")
  func savesAndRestores() throws {
    let store = ProgressStore(context: try inMemoryContext(), observer: recordingObserver("test"))
    let session = TilesSession(
      puzzle: smallPuzzle, day: testDay, store: store, observer: recordingObserver("test"))

    session.tap(0)
    session.tap(1)
    session.submit()

    #expect(session.feedback?.kind == .found(smallPuzzle.words[2]))
    #expect(try store.entries(for: key) == ["abcd"])
    let restored = TilesSession(
      puzzle: smallPuzzle, day: testDay, store: store, observer: recordingObserver("test"))
    #expect(restored.game.foundWords == ["abcd"])
    #expect(restored.boardTiles == [2, 3])
  }

  @Test("doesn't save words that aren't on the list")
  func skipsMisses() throws {
    let store = ProgressStore(context: try inMemoryContext(), observer: recordingObserver("test"))
    let session = TilesSession(
      puzzle: smallPuzzle, day: testDay, store: store, observer: recordingObserver("test"))

    session.tap(1)
    session.submit()

    #expect(session.feedback?.kind == .notAWord("cd"))
    #expect(try store.entries(for: key).isEmpty)
  }

  @Test("shuffles without losing tiles")
  func shuffles() throws {
    let store = ProgressStore(context: try inMemoryContext(), observer: recordingObserver("test"))
    let session = TilesSession(
      puzzle: smallPuzzle, day: testDay, store: store, observer: recordingObserver("test"))

    session.shuffle()

    #expect(session.boardTiles.sorted() == [0, 1, 2, 3])
  }
}
