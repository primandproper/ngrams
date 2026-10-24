import Foundation
import Observation

// Selective import: Observability also exports `struct Observation`, which shadows the module
// the @Observable macro expands against.
import protocol Observability.Logger
import protocol Observability.Observer

/// One tiles board in play: the game, the board's tile order, feedback for the last action, and
/// saving each found word as it's found.
@Observable
final class TilesSession {
  struct Feedback: Equatable, Identifiable {
    enum Kind: Equatable {
      case found(TilesWord)
      case alreadyFound(TilesWord)
      case blocked
      case notAWord(String)
      case saveFailed
      case loadFailed
    }

    let id = UUID()
    let kind: Kind
  }

  let key: ProgressKey
  private(set) var game: TilesGame
  /// The order the board shows tiles in, unsolved tiles first. Shuffling changes only this.
  private(set) var order: [Int]
  private(set) var feedback: Feedback?

  private let store: ProgressStore
  private let logger: any Logger

  init(
    puzzle: TilesPuzzle, day: PuzzleDay, solvedTilesLeave: Bool, store: ProgressStore,
    observer: any Observer
  ) {
    let key = ProgressKey(language: puzzle.language, kind: .tiles, n: puzzle.n, day: day)
    let logger = observer.logger.withValue("day", day.description).withValue("n", puzzle.n)
      .withValue("lang", puzzle.language.rawValue)
    self.key = key
    self.store = store
    self.logger = logger

    var game: TilesGame
    do {
      game = TilesGame(
        puzzle: puzzle, foundWords: try store.entries(for: key),
        solvedTilesLeave: solvedTilesLeave)
    } catch {
      logger.error("loading tiles progress", error)
      game = TilesGame(puzzle: puzzle, solvedTilesLeave: solvedTilesLeave)
      feedback = Feedback(kind: .loadFailed)
    }
    self.game = game
    var rng = SeededGenerator(seed: "\(key.language.rawValue)-\(key.kind.rawValue)-\(key.n)-\(day)")
    self.order = Self.arranged(game, using: &rng)
  }

  /// Spreads the unsolved tiles, then appends the solved ones, which `boardTiles` places itself.
  private static func arranged(
    _ game: TilesGame, using rng: inout some RandomNumberGenerator
  ) -> [Int] {
    let solved = game.solvedTiles
    let unsolved = game.puzzle.tiles.indices.filter { !solved.contains($0) }
    return TilesLayout.spread(unsolved, in: game.puzzle, using: &rng) + solved.sorted()
  }

  /// Tiles on the board, `n` to a row: solved targets first in the order they were found, unless
  /// solved tiles leave the board, then the rest in board order.
  var boardTiles: [Int] {
    let solved = game.solvedTiles
    let solvedRows =
      game.solvedTilesLeave ? [] : game.solvedTargets.flatMap { game.puzzle.targets[$0] }
    return solvedRows + order.filter { !solved.contains($0) }
  }

  func tap(_ tile: Int) {
    game.toggle(tile)
  }

  func clear() {
    game.clearSelection()
  }

  func shuffle() {
    var rng = SystemRandomNumberGenerator()
    order = Self.arranged(game, using: &rng)
  }

  func submit() {
    switch game.submit() {
    case .empty:
      return
    case .notAWord(let text):
      feedback = Feedback(kind: .notAWord(text))
    case .alreadyFound(let word):
      feedback = Feedback(kind: .alreadyFound(word))
    case .blocked:
      logger.debug("spelled a blocked word")
      feedback = Feedback(kind: .blocked)
    case .found(let word):
      feedback = Feedback(kind: .found(word))
      do {
        try store.append(word.word, for: key)
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
