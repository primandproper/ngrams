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
  private func session(_ store: ProgressStore, solvedTilesLeave: Bool = false) -> TilesSession {
    TilesSession(
      puzzle: smallPuzzle, day: testDay, solvedTilesLeave: solvedTilesLeave, store: store,
      observer: recordingObserver("test"))
  }

  @Test("saves each found word and restores it")
  func savesAndRestores() throws {
    let store = ProgressStore(context: try inMemoryContext(), observer: recordingObserver("test"))
    let session = self.session(store)

    session.tap(0)
    session.tap(1)
    session.submit()

    #expect(session.feedback?.kind == .found(smallPuzzle.words[2]))
    #expect(try store.entries(for: key) == ["abcd"])
    let restored = self.session(store)
    #expect(restored.game.foundWords == ["abcd"])
  }

  @Test("puts solved targets first on the board")
  func solvedRowsFirst() throws {
    let store = ProgressStore(context: try inMemoryContext(), observer: recordingObserver("test"))
    try store.append("efgh", for: key)

    // "abcd" alone is left, so its tiles can only be spread out of order.
    #expect(session(store).boardTiles == [2, 3, 1, 0])
    #expect(session(store, solvedTilesLeave: true).boardTiles == [1, 0])
  }

  @Test("answers a blocked word without saving it")
  func blocked() throws {
    let store = ProgressStore(context: try inMemoryContext(), observer: recordingObserver("test"))
    let session = self.session(store)

    session.tap(2)
    session.tap(0)
    session.submit()

    #expect(session.feedback?.kind == .blocked)
    #expect(try store.entries(for: key).isEmpty)
  }

  @Test("doesn't save words that aren't on the list")
  func skipsMisses() throws {
    let store = ProgressStore(context: try inMemoryContext(), observer: recordingObserver("test"))
    let session = self.session(store)

    session.tap(1)
    session.submit()

    #expect(session.feedback?.kind == .notAWord("cd"))
    #expect(try store.entries(for: key).isEmpty)
  }

  @Test("shuffles without losing tiles")
  func shuffles() throws {
    let store = ProgressStore(context: try inMemoryContext(), observer: recordingObserver("test"))
    let session = self.session(store)

    session.shuffle()

    #expect(session.boardTiles.sorted() == [0, 1, 2, 3])
    #expect(TilesLayout.isSpread(session.boardTiles, in: smallPuzzle))
  }
}

@Suite("WordSession")
struct WordSessionTests {
  private let wordKey = ProgressKey(language: .en, kind: .word, n: 5, day: testDay)

  private func session(_ store: ProgressStore) -> WordSession {
    WordSession(
      puzzle: wordPuzzle, day: testDay, list: wordList, store: store,
      observer: recordingObserver("test"))
  }

  private func guess(_ text: String, in session: WordSession) {
    for letter in text {
      session.type(letter)
    }
    session.submit()
  }

  @Test("saves each guess and restores it")
  func savesAndRestores() throws {
    let store = ProgressStore(context: try inMemoryContext(), observer: recordingObserver("test"))
    let session = self.session(store)

    guess("cramp", in: session)
    guess("llama", in: session)

    #expect(try store.entries(for: wordKey) == ["cramp", "llama"])
    #expect(self.session(store).game.status == .won(guesses: 2))
  }

  @Test("doesn't save rejected guesses")
  func skipsRejected() throws {
    let store = ProgressStore(context: try inMemoryContext(), observer: recordingObserver("test"))
    let session = self.session(store)

    guess("llamz", in: session)
    #expect(session.feedback?.kind == .notAWord("llamz"))
    for _ in 0..<5 {
      session.deleteLetter()
    }
    guess("bitch", in: session)

    #expect(session.feedback?.kind == .blocked)
    #expect(try store.entries(for: wordKey).isEmpty)
  }
}
