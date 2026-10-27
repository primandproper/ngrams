import Foundation

/// Spoiler-free results to paste anywhere: one puzzle's, or every puzzle started on a day. A `*`
/// marks a result played in hard mode, and a ⭐ one that earned its star. Written in the sharer's
/// interface language; testdata/share.json holds both apps to the same text.
nonisolated enum ShareText {
  /// Appended to every share: one page for both stores, so a share works whoever receives it.
  static let link = "https://primandproper.software/ngrams/"

  /// The headline and the guess grid.
  static func word(
    _ game: WordGame, on day: PuzzleDay, in interfaceLanguage: Language = .interface
  ) -> String {
    let puzzle = game.puzzle
    let grid = game.marks.map { String($0.map(\.square)) }
    return finished(
      [headline(.word, puzzle.language, puzzle.n, day, interfaceLanguage) + " · " + result(game)]
        + grid)
  }

  /// The headline, then progress toward the target and the targets found.
  static func tiles(
    _ game: TilesGame, on day: PuzzleDay, in interfaceLanguage: Language = .interface
  ) -> String {
    let puzzle = game.puzzle
    let targets =
      switch interfaceLanguage {
      case .en: "targets"
      case .es: "objetivos"
      }
    return finished([
      headline(.tiles, puzzle.language, puzzle.n, day, interfaceLanguage) + " · " + result(game),
      bar(game.score, of: puzzle.targetScore)
        + " \(game.solvedTargets.count)/\(puzzle.targets.count) \(targets)",
    ])
  }

  /// The headline, then progress toward the target and the common pangrams found.
  static func pangram(
    _ game: PangramGame, on day: PuzzleDay, in interfaceLanguage: Language = .interface
  ) -> String {
    let puzzle = game.puzzle
    let pangrams = puzzle.pangrams.count
    let noun =
      PuzzleKind.pangram.name(in: interfaceLanguage).lowercased() + (pangrams == 1 ? "" : "s")
    return finished([
      headline(.pangram, puzzle.language, puzzle.n, day, interfaceLanguage) + " · " + result(game),
      bar(game.score, of: puzzle.targetScore) + " \(game.foundPangrams)/\(pangrams) \(noun)",
    ])
  }

  /// A line per language and game with the result of each puzzle started, or nil if none was.
  static func day(
    words: [WordGame], tiles: [TilesGame], pangrams: [PangramGame], on day: PuzzleDay,
    in interfaceLanguage: Language = .interface
  ) -> String? {
    var lines: [String] = []
    for language in Language.allCases {
      let results: [(PuzzleKind, [String])] = [
        (
          .word,
          words.filter { $0.puzzle.language == language && !$0.guesses.isEmpty }
            .sorted { $0.puzzle.n < $1.puzzle.n }
            .map { "n=\($0.puzzle.n) \(result($0))" }
        ),
        (
          .tiles,
          tiles.filter { $0.puzzle.language == language && !$0.found.isEmpty }
            .sorted { $0.puzzle.n < $1.puzzle.n }
            .map { "n=\($0.puzzle.n) \(result($0))" }
        ),
        (
          .pangram,
          pangrams.filter { $0.puzzle.language == language && !$0.found.isEmpty }
            .sorted { $0.puzzle.n < $1.puzzle.n }
            .map { "n=\($0.puzzle.n) \(result($0))" }
        ),
      ]
      for (kind, kindResults) in results where !kindResults.isEmpty {
        lines.append(
          "\(language.flag) \(kind.name(in: interfaceLanguage)) · "
            + kindResults.joined(separator: " · "))
      }
    }
    guard !lines.isEmpty else {
      return nil
    }
    return finished(["n-grams · \(day.name(includingYear: false, in: interfaceLanguage))"] + lines)
  }

  private static func headline(
    _ kind: PuzzleKind, _ language: Language, _ n: Int, _ day: PuzzleDay,
    _ interfaceLanguage: Language
  ) -> String {
    "n-grams · \(kind.name(in: interfaceLanguage)) \(language.flag) n=\(n) · "
      + day.name(includingYear: false, in: interfaceLanguage)
  }

  private static func result(_ game: WordGame) -> String {
    let guesses =
      switch game.status {
      case .won(let guesses): "\(guesses)"
      case .lost: "X"
      case .playing: "\(game.guesses.count)"
      }
    return "\(guesses)/\(WordGame.maxGuesses)"
      + marks(hard: game.hardMode, star: game.status != .lost && game.isOver)
  }

  private static func result(_ game: TilesGame) -> String {
    "\(game.score)/\(game.puzzle.targetScore)"
      + marks(hard: game.solvedTilesLeave, star: game.earnedStar)
  }

  private static func result(_ game: PangramGame) -> String {
    "\(game.score)/\(game.puzzle.targetScore)" + marks(hard: game.hardMode, star: game.earnedStar)
  }

  private static func marks(hard: Bool, star: Bool) -> String {
    (hard ? "*" : "") + (star ? " ⭐" : "")
  }

  /// Ten segments, full once `score` reaches `target`.
  private static func bar(_ score: Int, of target: Int) -> String {
    let filled = min(10, score * 10 / max(target, 1))
    return String(repeating: "▰", count: filled) + String(repeating: "▱", count: 10 - filled)
  }

  private static func finished(_ lines: [String]) -> String {
    (lines + [link]).joined(separator: "\n")
  }
}

extension LetterMark {
  /// How a share shows the mark, matching the board: blue in place, grey in the word, and dark
  /// for absent.
  nonisolated var square: Character {
    switch self {
    case .correct: "🟦"
    case .present: "⬜"
    case .absent: "⬛"
    }
  }
}
