#if DEBUG
  import Foundation
  import SwiftData

  /// Three weeks of made-up play for the App Store screenshots, planted in an in-memory store when
  /// the app launches with `-screenshotSeed YES`. Every entry is picked from the bank at launch
  /// rather than written down, so the seed keeps working after the bank is rebuilt.
  enum ScreenshotSeed {
    static var isOn: Bool {
      UserDefaults.standard.bool(forKey: "screenshotSeed")
    }

    /// Days played before today. Spanish only joins for the last week of them.
    private static let historyDays = 21
    private static let spanishDays = 7

    /// Today's puzzles worth showing: one of each game finished, one of each partway (the ones
    /// the screenshot test opens), and the rest untouched.
    private static let finishedToday: Set<PuzzleLine> = [
      PuzzleLine(language: .en, kind: .word, n: 4),
      PuzzleLine(language: .en, kind: .tiles, n: 3),
      PuzzleLine(language: .en, kind: .pangram, n: 6),
    ]
    private static let partwayToday: Set<PuzzleLine> = [
      PuzzleLine(language: .es, kind: .word, n: 5),
      PuzzleLine(language: .en, kind: .tiles, n: 4),
      PuzzleLine(language: .en, kind: .pangram, n: 7),
    ]

    private enum Play {
      case finished
      /// Still going, which only today's puzzles are.
      case partway
      /// A word puzzle lost, or a board left short of its star.
      case fellShort
    }

    static func plant(bank: PuzzleBank, today: PuzzleDay, in context: ModelContext) throws {
      // Every word puzzle's answer comes from the most common words of its length, so they're
      // the words a player would plausibly guess or find.
      var common: [Language: Set<String>] = [:]
      for day in bank.days {
        for puzzle in bank.wordPuzzles(on: day) {
          common[puzzle.language, default: []].insert(puzzle.answer)
        }
      }

      let history = Array(bank.days.filter { $0 < today }.suffix(historyDays))
      for (index, day) in history.enumerated() {
        let spanish = history.count - index <= spanishDays
        plant(bank, on: day, at: index, common: common, in: context) { line in
          if line.language == .es, !spanish {
            return nil
          }
          // One off day per line, early and in a different place on each, so streaks differ
          // and nothing wins every time.
          let kind = PuzzleKind.allCases.firstIndex(of: line.kind) ?? 0
          return index == (line.n * 3 + kind * 7) % 12 ? .fellShort : .finished
        }
      }
      plant(bank, on: today, at: history.count, common: common, in: context) { line in
        finishedToday.contains(line) ? .finished : partwayToday.contains(line) ? .partway : nil
      }
      try context.save()
    }

    private static func plant(
      _ bank: PuzzleBank, on day: PuzzleDay, at index: Int, common: [Language: Set<String>],
      in context: ModelContext, plays: (PuzzleLine) -> Play?
    ) {
      func insert(_ line: PuzzleLine, _ entries: [String], _ play: Play) {
        // Finished mid-morning on its own day, so it counts toward the streak.
        let finishedAt = play == .partway ? nil : day.start()?.addingTimeInterval(9 * 60 * 60)
        context.insert(
          PuzzleProgress(
            key: ProgressKey(language: line.language, kind: line.kind, n: line.n, day: day),
            entries: entries, completedAt: finishedAt, updatedAt: finishedAt ?? .now))
      }

      for puzzle in bank.wordPuzzles(on: day) {
        let line = PuzzleLine(language: puzzle.language, kind: .word, n: puzzle.n)
        guard let play = plays(line) else {
          continue
        }
        let candidates = (common[puzzle.language] ?? []).filter { $0.count == puzzle.n }.sorted()
        switch play {
        case .partway:
          insert(line, closingIn(on: puzzle, misses: 3, from: candidates, offset: index), play)
        case .fellShort:
          insert(
            line,
            closingIn(on: puzzle, misses: WordGame.maxGuesses, from: candidates, offset: index),
            play)
        case .finished:
          // Solved in two to five guesses, so the guess distribution has some shape.
          let misses = [1, 2, 3, 2, 1, 4, 2][(index + puzzle.n) % 7]
          let guesses = closingIn(on: puzzle, misses: misses, from: candidates, offset: index)
          insert(line, guesses + [puzzle.answer], play)
        }
      }
      for puzzle in bank.tilesPuzzles(on: day) {
        let line = PuzzleLine(language: puzzle.language, kind: .tiles, n: puzzle.n)
        if let play = plays(line) {
          insert(line, foundWords(on: puzzle, play, common: common[puzzle.language] ?? []), play)
        }
      }
      for puzzle in bank.pangramPuzzles(on: day) {
        let line = PuzzleLine(language: puzzle.language, kind: .pangram, n: puzzle.n)
        if let play = plays(line) {
          insert(line, foundWords(on: puzzle, play, common: common[puzzle.language] ?? []), play)
        }
      }
    }

    /// Wrong guesses that close in on the answer as a player would: each finds one more letter
    /// than the last, and from the second on, one more in its spot. Where no word fits exactly,
    /// the nearest does. `offset` starts each puzzle's search somewhere different.
    private static func closingIn(
      on puzzle: WordPuzzle, misses: Int, from candidates: [String], offset: Int
    ) -> [String] {
      var guesses: [String] = []
      for miss in 1...misses {
        let found = min(miss, puzzle.n - 1)
        let placed = min(miss - 1, puzzle.n - 2)
        let unused = candidates.filter { $0 != puzzle.answer && !guesses.contains($0) }
        guard !unused.isEmpty else {
          break
        }
        let start = (offset * 7919 + miss * 104_729) % unused.count
        let rotated = unused[start...] + unused[..<start]
        let guess = rotated.min { left, right in
          distance(left, puzzle, found: found, placed: placed)
            < distance(right, puzzle, found: found, placed: placed)
        }
        if let guess {
          guesses.append(guess)
        }
      }
      return guesses
    }

    private static func distance(_ guess: String, _ puzzle: WordPuzzle, found: Int, placed: Int)
      -> Int
    {
      let marks = WordGame(puzzle: puzzle, guesses: [guess]).marks.first ?? []
      return abs(marks.filter { $0 != .absent }.count - found)
        + abs(marks.filter { $0 == .correct }.count - placed)
    }

    /// Up to `count` words a player would find first: common ones, shortest first. Obscure words
    /// only pad a board with fewer than four common ones.
    private static func likely<Word>(
      _ words: [Word], common: Set<String>, count: Int, spelling: (Word) -> String
    ) -> [String] {
      let spelled = words.map(spelling)
      let preferred = spelled.filter(common.contains).sorted { ($0.count, $0) < ($1.count, $1) }
      let padding = spelled.filter { !common.contains($0) }.prefix(max(0, 4 - preferred.count))
      return Array((preferred + padding).prefix(count))
    }

    /// A finished board has every target, then its best words until the star. One partway, or
    /// short of its star, has a handful of words and one target.
    private static func foundWords(on puzzle: TilesPuzzle, _ play: Play, common: Set<String>)
      -> [String]
    {
      let targets = puzzle.targets.map { $0.map { puzzle.tiles[$0] }.joined() }
      let others = puzzle.words.filter { !targets.contains($0.word) }
      switch play {
      case .partway, .fellShort:
        return likely(others, common: common, count: 6, spelling: \.word) + targets.prefix(1)
      case .finished:
        var found = targets
        for word in others.sorted(by: { $0.points > $1.points })
        where !TilesGame(puzzle: puzzle, foundWords: found).earnedStar {
          found.append(word.word)
        }
        return found
      }
    }

    /// A finished board has every common pangram, then its best words until the star. One
    /// partway, or short of its star, has a pangram and a handful of other words.
    private static func foundWords(on puzzle: PangramPuzzle, _ play: Play, common: Set<String>)
      -> [String]
    {
      let pangrams = puzzle.words.map(\.word).filter(puzzle.pangrams.contains)
      let others = puzzle.words.filter { !puzzle.pangrams.contains($0.word) }
      switch play {
      case .partway, .fellShort:
        return likely(others, common: common, count: 9, spelling: \.word) + pangrams.prefix(1)
      case .finished:
        var found = pangrams
        for word in others.sorted(by: { $0.points > $1.points })
        where !PangramGame(puzzle: puzzle, foundWords: found).earnedStar {
          found.append(word.word)
        }
        return found
      }
    }
  }
#endif
