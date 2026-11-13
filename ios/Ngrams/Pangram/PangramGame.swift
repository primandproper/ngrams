/// How a board lists the words found on it.
nonisolated enum FoundWordOrder: String, Sendable {
  case alphabetical
  /// Newest first.
  case recent
}

/// The rules of one pangram board: the letters typed so far, what's been found, and the score.
nonisolated struct PangramGame: Sendable {
  enum Submission: Equatable, Sendable {
    case found(PangramWord)
    case alreadyFound(PangramWord)
    case tooShort
    case missingCenter
    case blocked(String)
    case notAWord(String)
    case needsPangram
    case empty
  }

  let puzzle: PangramPuzzle
  /// Whether the first word found has to be a pangram.
  let hardMode: Bool
  /// Hints taken, oldest first, each in the game's own terms. A hint never changes the result.
  private(set) var hints: [String] = []
  /// Whether the player had the puzzle solved for them, which gives up the star.
  private(set) var gaveUp = false
  /// Words found so far, oldest first.
  private(set) var found: [PangramWord] = []
  /// Letters typed toward the next word.
  private(set) var current = ""

  private let words: [String: PangramWord]

  /// Starts a board, restoring `foundWords`, `hints` and `gaveUp` from saved progress. Saved
  /// words the board doesn't have (the bank was rebuilt since) are dropped.
  init(
    puzzle: PangramPuzzle, foundWords: [String] = [], hardMode: Bool = false,
    hints: [String] = [], gaveUp: Bool = false
  ) {
    self.hints = hints
    self.gaveUp = gaveUp
    self.puzzle = puzzle
    self.hardMode = hardMode
    let words = Dictionary(
      puzzle.words.map { ($0.word, $0) }, uniquingKeysWith: { first, _ in first })
    self.words = words

    var seen: Set<String> = []
    for word in foundWords where seen.insert(word).inserted {
      if let match = words[word] {
        found.append(match)
      }
    }
  }

  /// Folded spellings of the found words, oldest first, for saving.
  var foundWords: [String] {
    found.map(\.word)
  }

  func found(sortedBy order: FoundWordOrder) -> [PangramWord] {
    switch order {
    case .alphabetical: found.sorted { $0.word < $1.word }
    case .recent: found.reversed()
    }
  }

  var score: Int {
    found.reduce(0) { $0 + $1.points }
  }

  var foundPangrams: Int {
    found.filter { puzzle.pangrams.contains($0.word) }.count
  }

  var foundBonusPangrams: Int {
    found.filter { puzzle.isBonusPangram($0.word) }.count
  }

  /// A star takes every common pangram and the target score.
  var earnedStar: Bool {
    !gaveUp && foundPangrams == puzzle.pangrams.count && score >= puzzle.targetScore
  }

  /// Whether the board has every common pangram and the target score, star or not.
  private var reachedStar: Bool {
    foundPangrams == puzzle.pangrams.count && score >= puzzle.targetScore
  }

  /// The order hints clue words and solving spells them: common pangrams first, then by points,
  /// highest first, ties alphabetical.
  private var helpOrder: [PangramWord] {
    puzzle.words.sorted { a, b in
      let aPangram = puzzle.pangrams.contains(a.word)
      let bPangram = puzzle.pangrams.contains(b.word)
      if aPangram != bPangram {
        return aPangram
      }
      return a.points != b.points ? a.points > b.points : a.word < b.word
    }
  }

  /// The word the next hint clues: the first in help order not found or clued already. Nil
  /// once there's none left or the board is over.
  var nextHint: String? {
    guard !earnedStar, !gaveUp else {
      return nil
    }
    let taken = Set(foundWords).union(hints)
    return helpOrder.first { !taken.contains($0.word) }?.word
  }

  /// The clued words still unfound, oldest clue first.
  var clues: [PangramWord] {
    let found = Set(foundWords)
    var seen: Set<String> = []
    return hints.compactMap { hint in
      guard !found.contains(hint), seen.insert(hint).inserted else {
        return nil
      }
      return words[hint]
    }
  }

  /// The words solving spells, in help order, until the board has every common pangram and the
  /// target score.
  var solution: [String] {
    var board = self
    var spelled: [String] = []
    for word in helpOrder where !board.reachedStar && !board.found.contains(word) {
      board.found.append(word)
      spelled.append(word.word)
    }
    return spelled
  }

  mutating func take(hint: String) {
    hints.append(hint)
  }

  /// Solves the board for the player, finding `words`, and gives up its star.
  mutating func giveUp(finding words: [String]) {
    current = ""
    var seen = Set(foundWords)
    for word in words where seen.insert(word).inserted {
      if let match = self.words[word] {
        found.append(match)
      }
    }
    gaveUp = true
  }

  mutating func type(_ letter: Character) {
    current.append(letter)
  }

  mutating func deleteLetter() {
    if !current.isEmpty {
      current.removeLast()
    }
  }

  /// Checks the typed letters as a word and clears them.
  mutating func submit() -> Submission {
    let text = current
    guard !text.isEmpty else {
      return .empty
    }
    current = ""

    guard text.count >= PangramPuzzle.minLength else {
      return .tooShort
    }
    guard text.contains(puzzle.center) else {
      return .missingCenter
    }
    if puzzle.blocked.contains(text) {
      return .blocked(text)
    }
    guard let word = words[text] else {
      return .notAWord(text)
    }
    if found.contains(word) {
      return .alreadyFound(word)
    }
    if hardMode, found.isEmpty, !puzzle.isPangram(text) {
      return .needsPangram
    }
    found.append(word)
    return .found(word)
  }
}
