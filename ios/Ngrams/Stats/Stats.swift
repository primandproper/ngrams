import Foundation

/// One puzzle a player can play every day: a game at one size, in one language. Stats and
/// streaks are kept per line.
nonisolated struct PuzzleLine: Hashable, Sendable {
  let language: Language
  let kind: PuzzleKind
  let n: Int
}

/// What a player did on one puzzle, apart from SwiftData so stats are plain values.
nonisolated struct PlayRecord: Sendable {
  let key: ProgressKey
  let entries: [String]
  /// When a word puzzle ended or a board earned its star. Puzzles finished before this was
  /// saved carry the last time they were played instead, which for a word puzzle is the same.
  let completedAt: Date?
}

/// A line's results across every day up to today.
nonisolated struct LineStats: Equatable, Sendable {
  let line: PuzzleLine
  /// Puzzles with at least one guess or word.
  var played = 0
  /// What the success rate is out of: word puzzles that are over, won or lost, and boards
  /// played.
  var decided = 0
  /// Word puzzles solved, or boards that earned their star.
  var successes = 0
  /// Successes on their own day, one day after another, through today. An unfinished puzzle
  /// today doesn't break the streak until the day is over; a lost one does.
  var currentStreak = 0
  var bestStreak = 0
  /// Word puzzles solved in each number of guesses: the first count is for one guess.
  var guessCounts = Array(repeating: 0, count: WordGame.maxGuesses)

  init(line: PuzzleLine) {
    self.line = line
  }

  var successRate: Double? {
    decided == 0 ? nil : Double(successes) / Double(decided)
  }
}

nonisolated enum StatsBook {
  /// Every line the bank holds through `today`, with what `records` say was played on it. Days
  /// after today don't count, and `calendar` decides which day a completion fell on.
  static func compute(
    records: [PlayRecord], bank: PuzzleBank, today: PuzzleDay, calendar: Calendar = .current
  ) -> [PuzzleLine: LineStats] {
    let byKey = Dictionary(records.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
    var stats: [PuzzleLine: LineStats] = [:]
    var runs: [PuzzleLine: Int] = [:]

    for day in bank.days where day <= today {
      let outcomes =
        bank.wordPuzzles(on: day).map { outcome($0, byKey, day) }
        + bank.tilesPuzzles(on: day).map { outcome($0, byKey, day) }
        + bank.pangramPuzzles(on: day).map { outcome($0, byKey, day) }
      for (line, outcome) in outcomes {
        var lineStats = stats[line] ?? LineStats(line: line)
        if outcome.started {
          lineStats.played += 1
        }
        if outcome.decided {
          lineStats.decided += 1
        }
        if outcome.succeeded {
          lineStats.successes += 1
        }
        if let guesses = outcome.guesses, lineStats.guessCounts.indices.contains(guesses - 1) {
          lineStats.guessCounts[guesses - 1] += 1
        }

        let onTime =
          outcome.succeeded
          && outcome.completedAt.map { PuzzleDay(containing: $0, calendar: calendar) == day }
            ?? false
        if onTime {
          runs[line, default: 0] += 1
        } else if day < today || outcome.lost {
          runs[line] = 0
        }
        lineStats.bestStreak = max(lineStats.bestStreak, runs[line, default: 0])
        stats[line] = lineStats
      }
    }
    for line in stats.keys {
      stats[line]?.currentStreak = runs[line, default: 0]
    }
    return stats
  }

  private struct Outcome {
    var started = false
    var decided = false
    var succeeded = false
    /// A word puzzle that ran out of guesses.
    var lost = false
    /// Guesses used, for a solved word puzzle.
    var guesses: Int?
    var completedAt: Date?
  }

  private static func outcome(
    _ puzzle: WordPuzzle, _ records: [ProgressKey: PlayRecord], _ day: PuzzleDay
  ) -> (PuzzleLine, Outcome) {
    let line = PuzzleLine(language: puzzle.language, kind: .word, n: puzzle.n)
    var outcome = Outcome()
    if let record = records[
      ProgressKey(language: puzzle.language, kind: .word, n: puzzle.n, day: day)]
    {
      let game = WordGame(puzzle: puzzle, guesses: record.entries)
      outcome.started = !game.guesses.isEmpty
      outcome.decided = game.isOver
      switch game.status {
      case .won(let guesses):
        outcome.succeeded = true
        outcome.guesses = guesses
      case .lost:
        outcome.lost = true
      case .playing:
        break
      }
      outcome.completedAt = record.completedAt
    }
    return (line, outcome)
  }

  private static func outcome(
    _ puzzle: TilesPuzzle, _ records: [ProgressKey: PlayRecord], _ day: PuzzleDay
  ) -> (PuzzleLine, Outcome) {
    let line = PuzzleLine(language: puzzle.language, kind: .tiles, n: puzzle.n)
    var outcome = Outcome()
    if let record = records[
      ProgressKey(language: puzzle.language, kind: .tiles, n: puzzle.n, day: day)]
    {
      let game = TilesGame(puzzle: puzzle, foundWords: record.entries)
      outcome.started = !game.found.isEmpty
      outcome.decided = outcome.started
      outcome.succeeded = game.earnedStar
      outcome.completedAt = record.completedAt
    }
    return (line, outcome)
  }

  private static func outcome(
    _ puzzle: PangramPuzzle, _ records: [ProgressKey: PlayRecord], _ day: PuzzleDay
  ) -> (PuzzleLine, Outcome) {
    let line = PuzzleLine(language: puzzle.language, kind: .pangram, n: puzzle.n)
    var outcome = Outcome()
    if let record = records[
      ProgressKey(language: puzzle.language, kind: .pangram, n: puzzle.n, day: day)]
    {
      let game = PangramGame(puzzle: puzzle, foundWords: record.entries)
      outcome.started = !game.found.isEmpty
      outcome.decided = outcome.started
      outcome.succeeded = game.earnedStar
      outcome.completedAt = record.completedAt
    }
    return (line, outcome)
  }
}
