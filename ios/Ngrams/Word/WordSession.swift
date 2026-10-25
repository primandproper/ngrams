import Foundation
import Observation

// Selective import: Observability also exports `struct Observation`, which shadows the module
// the @Observable macro expands against.
import protocol Observability.Logger
import protocol Observability.Observer

/// One word puzzle in play: the game, feedback for the last action, and saving each guess as
/// it's made.
@Observable
final class WordSession {
  struct Feedback: Equatable, Identifiable {
    enum Kind: Equatable {
      case tooShort
      case blocked
      case notAWord(String)
      case missingHint(WordGame.Hint)
      case saveFailed
      case loadFailed
    }

    let id = UUID()
    let kind: Kind
  }

  let key: ProgressKey
  private(set) var game: WordGame
  private(set) var feedback: Feedback?

  private let list: GuessList
  private let store: ProgressStore
  private let logger: any Logger

  /// `hardMode` is the setting, which applies only until the first guess is saved; after that
  /// the puzzle keeps the mode it was saved with.
  init(
    puzzle: WordPuzzle, day: PuzzleDay, list: GuessList, hardMode: Bool, store: ProgressStore,
    observer: any Observer
  ) {
    let key = ProgressKey(language: puzzle.language, kind: .word, n: puzzle.n, day: day)
    let logger = observer.logger.withValue("day", day.description).withValue("n", puzzle.n)
      .withValue("lang", puzzle.language.rawValue)
    self.key = key
    self.list = list
    self.store = store
    self.logger = logger

    do {
      game = WordGame(
        puzzle: puzzle, guesses: try store.entries(for: key),
        hardMode: try store.hardMode(for: key) ?? hardMode)
    } catch {
      logger.error("loading word progress", error)
      game = WordGame(puzzle: puzzle, hardMode: hardMode)
      feedback = Feedback(kind: .loadFailed)
    }
  }

  func type(_ letter: Character) {
    game.type(letter)
  }

  func deleteLetter() {
    game.deleteLetter()
  }

  func submit() {
    switch game.submit(against: list) {
    case .over:
      return
    case .tooShort:
      feedback = Feedback(kind: .tooShort)
    case .notAWord(let text):
      feedback = Feedback(kind: .notAWord(text))
    case .missingHint(let hint):
      feedback = Feedback(kind: .missingHint(hint))
    case .blocked:
      logger.debug("guessed a blocked word")
      feedback = Feedback(kind: .blocked)
    case .guessed(let guess):
      do {
        try store.append(guess, for: key, hardMode: game.hardMode)
      } catch {
        logger.error("saving a guess", error)
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
