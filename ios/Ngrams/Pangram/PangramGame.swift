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
  /// Words found so far, oldest first.
  private(set) var found: [PangramWord] = []
  /// Letters typed toward the next word.
  private(set) var current = ""

  private let words: [String: PangramWord]

  /// Starts a board, restoring `foundWords` from saved progress. Saved words the board doesn't
  /// have (the bank was rebuilt since) are dropped.
  init(puzzle: PangramPuzzle, foundWords: [String] = [], hardMode: Bool = false) {
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

  /// A star takes every common pangram and the target score.
  var earnedStar: Bool {
    foundPangrams == puzzle.pangrams.count && score >= puzzle.targetScore
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
