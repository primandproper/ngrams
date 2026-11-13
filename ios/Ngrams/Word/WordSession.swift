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
      case helpSaveFailed
      case loadFailed
    }

    let id = UUID()
    let kind: Kind
  }

  let key: ProgressKey
  private(set) var game: WordGame
  private(set) var feedback: Feedback?
  /// Whether the puzzle is being solved for the player, a letter at a time.
  private(set) var solving = false
  let timer: PuzzleTimer

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
    timer = PuzzleTimer(key: key, store: store, logger: logger)

    do {
      let assistance = try store.assistance(for: key)
      game = WordGame(
        puzzle: puzzle, guesses: try store.entries(for: key),
        hardMode: try store.hardMode(for: key) ?? hardMode, hints: assistance?.hints ?? [],
        gaveUp: assistance?.gaveUp ?? false)
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

  func clearLetters() {
    game.clearLetters()
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
        let (stretches, now) = timer.entry(completing: game.isOver)
        try store.append(
          guess, for: key, hardMode: game.hardMode, completes: game.isOver, stretches: stretches,
          at: now)
      } catch {
        logger.error("saving a guess", error)
        feedback = Feedback(kind: .saveFailed)
      }
    }
  }

  /// Whether the puzzle is over and done showing how, which opens its stats.
  var finished: Bool {
    game.isOver && !solving
  }

  /// Pencils in the next letter the player doesn't know, if there is one.
  func takeHint() {
    guard !solving, let spot = game.nextHint else {
      return
    }
    let hint = String(spot)
    game.take(hint: hint)
    do {
      let (stretches, now) = timer.entry(completing: false)
      try store.take(
        hint: hint, for: key, hardMode: game.hardMode, stretches: stretches, at: now)
    } catch {
      logger.withValue("spot", spot).error("saving a hint", error)
      feedback = Feedback(kind: .helpSaveFailed)
    }
  }

  /// Solves the puzzle for the player, as a loss: clears the row, types the answer `pace` apart,
  /// then reveals it. The answer isn't saved as a guess.
  func solve(pace: Duration = .milliseconds(250)) async {
    guard !solving, !game.isOver else {
      return
    }
    solving = true
    defer { solving = false }
    while !game.current.isEmpty {
      game.deleteLetter()
      try? await Task.sleep(for: pace / 2)
    }
    for letter in game.puzzle.answer {
      game.type(letter)
      try? await Task.sleep(for: pace)
    }
    game.giveUp()
    do {
      let (stretches, now) = timer.entry(completing: true)
      try store.giveUp(for: key, hardMode: game.hardMode, stretches: stretches, at: now)
    } catch {
      logger.error("saving a solve", error)
      feedback = Feedback(kind: .helpSaveFailed)
    }
  }

  func dismissFeedback(_ shown: Feedback) {
    if feedback == shown {
      feedback = nil
    }
  }
}
