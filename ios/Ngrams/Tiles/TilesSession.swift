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
      case notAWord(String)
      case saveFailed
      case loadFailed
    }

    let id = UUID()
    let kind: Kind
  }

  let key: ProgressKey
  private(set) var game: TilesGame
  /// The order the board shows tiles in. Shuffling changes only this.
  private(set) var order: [Int]
  private(set) var feedback: Feedback?

  private let store: ProgressStore
  private let logger: any Logger

  init(puzzle: TilesPuzzle, day: PuzzleDay, store: ProgressStore, observer: any Observer) {
    let key = ProgressKey(language: puzzle.language, kind: .tiles, n: puzzle.n, day: day)
    let logger = observer.logger.withValue("day", day.description).withValue("n", puzzle.n)
      .withValue("lang", puzzle.language.rawValue)
    self.key = key
    self.store = store
    self.logger = logger
    self.order = Array(puzzle.tiles.indices)

    do {
      game = TilesGame(puzzle: puzzle, foundWords: try store.entries(for: key))
    } catch {
      logger.error("loading tiles progress", error)
      game = TilesGame(puzzle: puzzle)
      feedback = Feedback(kind: .loadFailed)
    }
  }

  /// Unsolved tiles, in board order.
  var boardTiles: [Int] {
    let solved = game.solvedTiles
    return order.filter { !solved.contains($0) }
  }

  func tap(_ tile: Int) {
    game.toggle(tile)
  }

  func clear() {
    game.clearSelection()
  }

  func shuffle() {
    order.shuffle()
  }

  func submit() {
    switch game.submit() {
    case .empty:
      return
    case .notAWord(let text):
      feedback = Feedback(kind: .notAWord(text))
    case .alreadyFound(let word):
      feedback = Feedback(kind: .alreadyFound(word))
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
