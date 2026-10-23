/// The rules of one tiles board: which tiles are selected, what's been found, and the score.
nonisolated struct TilesGame: Sendable {
  enum Submission: Equatable, Sendable {
    case found(TilesWord)
    case alreadyFound(TilesWord)
    case notAWord(String)
    case empty
  }

  let puzzle: TilesPuzzle
  /// Words found so far, oldest first.
  private(set) var found: [TilesWord] = []
  /// Selected tile indices, in the order they were tapped.
  private(set) var selection: [Int] = []

  private let words: [String: TilesWord]
  private let targetIndex: [String: Int]

  /// Starts a board, restoring `foundWords` from saved progress. Saved words the board doesn't
  /// have (the bank was rebuilt since) are dropped.
  init(puzzle: TilesPuzzle, foundWords: [String] = []) {
    self.puzzle = puzzle
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

  /// Tiles belonging to a found target. They leave the board.
  var solvedTiles: Set<Int> {
    Set(solvedTargets.flatMap { puzzle.targets[$0] })
  }

  var allTargetsFound: Bool {
    solvedTargets.count == puzzle.targets.count
  }

  var score: Int {
    found.reduce(0) { $0 + $1.points } + (allTargetsFound ? puzzle.bonus : 0)
  }

  var reachedTargetScore: Bool {
    score >= puzzle.targetScore
  }

  /// Selects a tile, or deselects it if it's already selected. Solved tiles can't be selected,
  /// and a word holds at most `n` tiles.
  mutating func toggle(_ tile: Int) {
    if let position = selection.firstIndex(of: tile) {
      selection.remove(at: position)
    } else if selection.count < puzzle.n, puzzle.tiles.indices.contains(tile),
      !solvedTiles.contains(tile)
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
