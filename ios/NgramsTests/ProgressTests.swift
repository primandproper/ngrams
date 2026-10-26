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

  @Test("records when a puzzle is first completed")
  func recordsCompletion() throws {
    let context = try inMemoryContext()
    let store = ProgressStore(context: context, observer: recordingObserver("test"))

    try store.append("ab", for: key)
    #expect(try context.fetch(FetchDescriptor<PuzzleProgress>()).first?.completedAt == nil)
    try store.append("abcd", for: key, completes: true)
    let completedAt = try context.fetch(FetchDescriptor<PuzzleProgress>()).first?.completedAt
    try store.append("ef", for: key, completes: true)

    #expect(completedAt != nil)
    #expect(try context.fetch(FetchDescriptor<PuzzleProgress>()).first?.completedAt == completedAt)
  }

  @Test("keeps the mode a puzzle's first entry recorded")
  func keepsMode() throws {
    let store = ProgressStore(context: try inMemoryContext(), observer: recordingObserver("test"))
    #expect(try store.hardMode(for: key) == nil)

    try store.append("ab", for: key, hardMode: true)
    try store.append("abcd", for: key, hardMode: false)

    #expect(try store.hardMode(for: key) == true)
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

  private func session(_ store: ProgressStore, hardMode: Bool = false) -> WordSession {
    WordSession(
      puzzle: wordPuzzle, day: testDay, list: wordList, hardMode: hardMode, store: store,
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

  @Test("records when the puzzle ends")
  func recordsCompletion() throws {
    let context = try inMemoryContext()
    let session = self.session(ProgressStore(context: context, observer: recordingObserver("test")))

    guess("plaza", in: session)
    #expect(try context.fetch(FetchDescriptor<PuzzleProgress>()).first?.completedAt == nil)
    guess("llama", in: session)

    #expect(try context.fetch(FetchDescriptor<PuzzleProgress>()).first?.completedAt != nil)
  }

  @Test("takes the setting until the first guess, then keeps the puzzle's mode")
  func locksMode() throws {
    let store = ProgressStore(context: try inMemoryContext(), observer: recordingObserver("test"))
    #expect(self.session(store, hardMode: true).game.hardMode)

    guess("plaza", in: self.session(store, hardMode: true))
    let session = self.session(store, hardMode: false)
    #expect(session.game.hardMode)

    guess("label", in: session)
    #expect(session.feedback?.kind == .missingHint(.position("l", 1)))
    #expect(try store.entries(for: wordKey) == ["plaza"])
  }
}

@Suite("PangramSession")
struct PangramSessionTests {
  private let pangramKey = ProgressKey(language: .en, kind: .pangram, n: 6, day: testDay)

  private func session(_ store: ProgressStore, hardMode: Bool = false) -> PangramSession {
    PangramSession(
      puzzle: pangramPuzzle, day: testDay, hardMode: hardMode, store: store,
      observer: recordingObserver("test"))
  }

  private func spell(_ text: String, in session: PangramSession) {
    for letter in text {
      session.type(letter)
    }
    session.submit()
  }

  @Test("saves each found word and restores it")
  func savesAndRestores() throws {
    let store = ProgressStore(context: try inMemoryContext(), observer: recordingObserver("test"))
    let session = self.session(store)

    spell("plaice", in: session)

    #expect(session.feedback?.kind == .found(pangramPuzzle.words[3], pangram: true))
    #expect(try store.entries(for: pangramKey) == ["plaice"])
    #expect(self.session(store).game.foundWords == ["plaice"])
  }

  @Test("tells a bonus pangram apart from a common one")
  func bonusFeedback() throws {
    let store = ProgressStore(context: try inMemoryContext(), observer: recordingObserver("test"))
    let session = self.session(store)

    spell("epical", in: session)

    #expect(session.feedback?.kind == .foundBonusPangram(pangramPuzzle.words[4]))
    #expect(try store.entries(for: pangramKey) == ["epical"])
  }

  @Test("doesn't save rejected words")
  func skipsRejected() throws {
    let store = ProgressStore(context: try inMemoryContext(), observer: recordingObserver("test"))
    let session = self.session(store)

    spell("clip", in: session)
    #expect(session.feedback?.kind == .blocked)
    spell("lace", in: session)

    #expect(session.feedback?.kind == .missingCenter)
    #expect(try store.entries(for: pangramKey).isEmpty)
  }

  @Test("takes the setting until the first word, then keeps the board's mode")
  func locksMode() throws {
    let store = ProgressStore(context: try inMemoryContext(), observer: recordingObserver("test"))
    let session = self.session(store, hardMode: true)

    spell("place", in: session)
    #expect(session.feedback?.kind == .needsPangram)
    #expect(!self.session(store, hardMode: false).game.hardMode)

    spell("plaice", in: session)
    #expect(self.session(store, hardMode: false).game.hardMode)
    #expect(try store.entries(for: pangramKey) == ["plaice"])
  }

  @Test("shuffles only the outer letters, starting from a stable order")
  func shuffles() throws {
    let store = ProgressStore(context: try inMemoryContext(), observer: recordingObserver("test"))
    let session = self.session(store)

    #expect(session.outer == self.session(store).outer)
    session.shuffle()

    #expect(session.outer.sorted() == Array("aceil"))
  }
}
