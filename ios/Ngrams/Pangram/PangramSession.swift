import Foundation
import Observation

// Selective import: Observability also exports `struct Observation`, which shadows the module
// the @Observable macro expands against.
import protocol Observability.Logger
import protocol Observability.Observer

/// One pangram board in play: the game, the order of the outer letters, feedback for the last
/// action, and saving each found word as it's found.
@Observable
final class PangramSession {
  struct Feedback: Equatable, Identifiable {
    enum Kind: Equatable {
      case found(PangramWord, pangram: Bool)
      case alreadyFound(PangramWord)
      case tooShort
      case missingCenter
      case blocked
      case notAWord(String)
      case needsPangram
      case saveFailed
      case loadFailed
    }

    let id = UUID()
    let kind: Kind
  }

  let key: ProgressKey
  private(set) var game: PangramGame
  /// Every letter but the center, in the order the wheel shows them. Shuffling changes only this.
  private(set) var outer: [Character]
  private(set) var feedback: Feedback?

  private let store: ProgressStore
  private let logger: any Logger

  /// `hardMode` is the setting, which applies only until the first word is saved; after that
  /// the board keeps the mode it was saved with.
  init(
    puzzle: PangramPuzzle, day: PuzzleDay, hardMode: Bool, store: ProgressStore,
    observer: any Observer
  ) {
    let key = ProgressKey(language: puzzle.language, kind: .pangram, n: puzzle.n, day: day)
    let logger = observer.logger.withValue("day", day.description).withValue("n", puzzle.n)
      .withValue("lang", puzzle.language.rawValue)
    self.key = key
    self.store = store
    self.logger = logger

    do {
      game = PangramGame(
        puzzle: puzzle, foundWords: try store.entries(for: key),
        hardMode: try store.hardMode(for: key) ?? hardMode)
    } catch {
      logger.error("loading pangram progress", error)
      game = PangramGame(puzzle: puzzle, hardMode: hardMode)
      feedback = Feedback(kind: .loadFailed)
    }
    var rng = SeededGenerator(seed: "\(key.language.rawValue)-\(key.kind.rawValue)-\(key.n)-\(day)")
    outer = puzzle.letters.filter { $0 != puzzle.center }.shuffled(using: &rng)
  }

  func type(_ letter: Character) {
    game.type(letter)
  }

  func deleteLetter() {
    game.deleteLetter()
  }

  func shuffle() {
    outer.shuffle()
  }

  func submit() {
    switch game.submit() {
    case .empty:
      return
    case .tooShort:
      feedback = Feedback(kind: .tooShort)
    case .missingCenter:
      feedback = Feedback(kind: .missingCenter)
    case .notAWord(let text):
      feedback = Feedback(kind: .notAWord(text))
    case .needsPangram:
      feedback = Feedback(kind: .needsPangram)
    case .alreadyFound(let word):
      feedback = Feedback(kind: .alreadyFound(word))
    case .blocked:
      logger.debug("spelled a blocked word")
      feedback = Feedback(kind: .blocked)
    case .found(let word):
      feedback = Feedback(kind: .found(word, pangram: game.puzzle.isPangram(word.word)))
      do {
        try store.append(word.word, for: key, hardMode: game.hardMode)
      } catch {
        logger.withValue("word", word.word).error("saving a found word", error)
        feedback = Feedback(kind: .saveFailed)
      }
    }
  }

  func dismissFeedback(_ shown: Feedback) {
    if feedback == shown {
      feedback = nil
    }
  }
}
