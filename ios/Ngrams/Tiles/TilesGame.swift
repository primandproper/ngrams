/// The rules of one tiles board: which tiles are selected, what's been found, and the score.
nonisolated struct TilesGame: Sendable {
  enum Submission: Equatable, Sendable {
    case found(TilesWord)
    case alreadyFound(TilesWord)
    case blocked(String)
    case notAWord(String)
    case empty
  }

  let puzzle: TilesPuzzle
  /// Hints taken, oldest first, each in the game's own terms. A hint never changes the result.
  private(set) var hints: [String] = []
  /// Whether the player had the puzzle solved for them, which gives up the star.
  private(set) var gaveUp = false
  /// Words found so far, oldest first.
  private(set) var found: [TilesWord] = []
  /// Selected tile indices, in the order they were tapped.
  private(set) var selection: [Int] = []
  /// Whether a found target's tiles leave the board, so no other word can use them. Quartiles
  /// keeps them in play; this is the harder variant.
  let solvedTilesLeave: Bool

  private let words: [String: TilesWord]
  private let targetIndex: [String: Int]

  /// Starts a board, restoring `foundWords`, `hints` and `gaveUp` from saved progress. Saved
  /// words the board doesn't have (the bank was rebuilt since) are dropped.
  init(
    puzzle: TilesPuzzle, foundWords: [String] = [], solvedTilesLeave: Bool = false,
    hints: [String] = [], gaveUp: Bool = false
  ) {
    self.hints = hints
    self.gaveUp = gaveUp
    self.puzzle = puzzle
    self.solvedTilesLeave = solvedTilesLeave
    let words = Dictionary(
      puzzle.words.map { ($0.word, $0) }, uniquingKeysWith: { first, _ in first })
    self.words = words
    var targetIndex: [String: Int] = [:]
    for (i, target) in puzzle.targets.enumerated() {
      targetIndex[target.map { puzzle.tiles[$0] }.joined()] = i
    }
    self.targetIndex = targetIndex

    var seen: Set<String> = []
    for word in foundWords where seen.insert(word).inserted {
      if let match = words[word] {
        found.append(match)
      }
    }
  }

  var selectedText: String {
    selection.map { puzzle.tiles[$0] }.joined()
  }

  /// Folded spellings of the found words, oldest first, for saving.
  var foundWords: [String] {
    found.map(\.word)
  }

  /// Indices into `puzzle.targets` of the targets found, oldest first.
  var solvedTargets: [Int] {
    found.compactMap { targetIndex[$0.word] }
  }

  /// Tiles belonging to a found target.
  var solvedTiles: Set<Int> {
    Set(solvedTargets.flatMap { puzzle.targets[$0] })
  }

  var allTargetsFound: Bool {
    solvedTargets.count == puzzle.targets.count
  }

  var score: Int {
    found.reduce(0) { $0 + $1.points } + (allTargetsFound ? puzzle.bonus : 0)
  }

  /// A star takes every target and the target score.
  var earnedStar: Bool {
    !gaveUp && allTargetsFound && score >= puzzle.targetScore
  }

  /// Whether finding every target still unfound would earn the star: the score so far, those
  /// targets' points, and the bonus reach the target score. It never turns false while targets
  /// are left, since finding one moves its points from what's left into the score.
  var targetsEarnStar: Bool {
    guard !gaveUp, !allTargetsFound else {
      return false
    }
    let solved = Set(solvedTargets)
    let left = puzzle.targets.indices.filter { !solved.contains($0) }.reduce(0) { sum, target in
      sum + (words[targetText(target)]?.points ?? 0)
    }
    return score + left + puzzle.bonus >= puzzle.targetScore
  }

  /// A target's folded spelling: its tiles joined in order.
  func targetText(_ target: Int) -> String {
    puzzle.targets[target].map { puzzle.tiles[$0] }.joined()
  }

  /// Whether an unfound word can still be spelled from the tiles left on the board. Once solved
  /// tiles leave, finding every target leaves none.
  var hasWordsLeft: Bool {
    let found = Set(foundWords)
    let gone = solvedTilesLeave ? solvedTiles : []
    return puzzle.words.contains { !found.contains($0.word) && gone.isDisjoint(with: $0.tiles) }
  }

  /// A board is over once it has its star, was solved for the player, or has no words left.
  var isOver: Bool {
    earnedStar || gaveUp || !hasWordsLeft
  }

  /// Hinted tiles, from the saved hints. Hints are saved as tiles; any that isn't a tile on
  /// this board is skipped.
  private var hintedTiles: [Int] {
    hints.compactMap(Int.init).filter(puzzle.tiles.indices.contains)
  }

  /// The tiles hints have lit whose targets are still unfound.
  var lit: Set<Int> {
    let solved = solvedTiles
    return Set(hintedTiles.filter { !solved.contains($0) })
  }

  /// The tile the next hint lights. A hint keeps lighting the first unfound target already lit,
  /// in the target's own order, until all but one of its tiles are lit, so a hint never gives a
  /// target away; then it starts on the first unfound target with none lit. Nil once there's
  /// nothing left to light or the board is over.
  var nextHint: Int? {
    guard !isOver else {
      return nil
    }
    let lit = self.lit
    let unfound = unfoundTargets
    func litCount(_ target: Int) -> Int {
      puzzle.targets[target].count(where: lit.contains)
    }
    let target =
      unfound.first { litCount($0) > 0 && litCount($0) < puzzle.n - 1 }
      ?? unfound.first { litCount($0) == 0 }
    return target.flatMap { target in puzzle.targets[target].first { !lit.contains($0) } }
  }

  /// Indices into `puzzle.targets` of the targets still unfound, in target order.
  var unfoundTargets: [Int] {
    let solved = Set(solvedTargets)
    return puzzle.targets.indices.filter { !solved.contains($0) }
  }

  /// The words solving finds: every unfound target, in target order.
  var solution: [String] {
    unfoundTargets.map(targetText)
  }

  mutating func take(hint: String) {
    hints.append(hint)
  }

  /// Solves the board for the player, finding `words`, and gives up its star.
  mutating func giveUp(finding words: [String]) {
    selection.removeAll()
    var seen = Set(foundWords)
    for word in words where seen.insert(word).inserted {
      if let match = self.words[word] {
        found.append(match)
      }
    }
    gaveUp = true
  }

  /// Selects a tile, or deselects it if it's already selected. A word holds at most `n` tiles,
  /// and solved tiles can't be selected once they've left the board.
  mutating func toggle(_ tile: Int) {
    if let position = selection.firstIndex(of: tile) {
      selection.remove(at: position)
    } else if selection.count < puzzle.n, puzzle.tiles.indices.contains(tile),
      !(solvedTilesLeave && solvedTiles.contains(tile))
    {
      selection.append(tile)
    }
  }

  mutating func clearSelection() {
    selection.removeAll()
  }

  /// Checks the selected tiles as a word and clears the selection.
  mutating func submit() -> Submission {
    let text = selectedText
    guard !text.isEmpty else {
      return .empty
    }
    selection.removeAll()

    if puzzle.blocked.contains(text) {
      return .blocked(text)
    }
    guard let word = words[text] else {
      return .notAWord(text)
    }
    if found.contains(word) {
      return .alreadyFound(word)
    }
    found.append(word)
    return .found(word)
  }
}
