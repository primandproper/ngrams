/// How a guessed letter compares with the answer.
nonisolated enum LetterMark: Int, Comparable, Sendable {
  case absent
  case present
  case correct

  static func < (lhs: LetterMark, rhs: LetterMark) -> Bool {
    lhs.rawValue < rhs.rawValue
  }
}

/// The rules of one word puzzle: the letters typed so far, the guesses made, and whether the
/// puzzle is over.
nonisolated struct WordGame: Sendable {
  static let maxGuesses = 6

  enum Submission: Equatable, Sendable {
    case guessed(String)
    case tooShort
    case blocked(String)
    case notAWord(String)
    case missingHint(Hint)
    case over
  }

  /// A revealed hint that hard mode makes every later guess use.
  enum Hint: Equatable, Sendable {
    /// A correct letter has to stay in its spot, counted from zero.
    case position(Character, Int)
    /// A found letter has to appear at least as often as an earlier guess showed it.
    case letter(Character)
  }

  enum Status: Equatable, Sendable {
    case playing
    case won(guesses: Int)
    case lost
  }

  let puzzle: WordPuzzle
  /// Whether each guess has to use every hint revealed so far.
  let hardMode: Bool
  /// Submitted guesses, oldest first.
  private(set) var guesses: [String] = []
  /// Letters typed toward the next guess.
  private(set) var current = ""

  /// Starts a puzzle, restoring `guesses` from saved progress. Saved guesses the puzzle can't
  /// hold (the wrong length, or past the end) are dropped.
  init(puzzle: WordPuzzle, guesses: [String] = [], hardMode: Bool = false) {
    self.puzzle = puzzle
    self.hardMode = hardMode
    for guess in guesses where status == .playing && guess.count == puzzle.n {
      self.guesses.append(guess)
    }
  }

  var status: Status {
    if guesses.last == puzzle.answer {
      return .won(guesses: guesses.count)
    }
    return guesses.count >= Self.maxGuesses ? .lost : .playing
  }

  var isOver: Bool { status != .playing }

  /// Each guess's marks, in the order guessed.
  var marks: [[LetterMark]] {
    guesses.map { Self.marks(for: $0, answer: puzzle.answer) }
  }

  /// The best mark each guessed letter has earned, for the keyboard.
  var letterMarks: [Character: LetterMark] {
    var best: [Character: LetterMark] = [:]
    for (guess, marks) in zip(guesses, marks) {
      for (letter, mark) in zip(guess, marks) {
        best[letter] = max(best[letter] ?? .absent, mark)
      }
    }
    return best
  }

  mutating func type(_ letter: Character) {
    if !isOver, current.count < puzzle.n {
      current.append(letter)
    }
  }

  mutating func deleteLetter() {
    if !current.isEmpty {
      current.removeLast()
    }
  }

  /// Checks the typed letters against `list`. A guess the list rejects stays typed, so it can
  /// be corrected.
  mutating func submit(against list: GuessList) -> Submission {
    guard !isOver else {
      return .over
    }
    guard current.count == puzzle.n else {
      return .tooShort
    }
    let guess = current
    if list.blocked.contains(guess) {
      return .blocked(guess)
    }
    guard guess == puzzle.answer || list.accepted.contains(guess) else {
      return .notAWord(guess)
    }
    if hardMode, let hint = missingHint(in: guess) {
      return .missingHint(hint)
    }
    current = ""
    guesses.append(guess)
    return .guessed(guess)
  }

  /// The first hint `guess` leaves out: correct letters out of their spot first, then found
  /// letters it has too few copies of, both in the order they were revealed.
  func missingHint(in guess: String) -> Hint? {
    let letters = Array(guess)
    let marks = self.marks
    for (previous, marks) in zip(guesses, marks) {
      for (i, (letter, mark)) in zip(previous, marks).enumerated()
      where mark == .correct && letters[i] != letter {
        return .position(letter, i)
      }
    }

    var required: [Character: Int] = [:]
    for (previous, marks) in zip(guesses, marks) {
      var found: [Character: Int] = [:]
      for (letter, mark) in zip(previous, marks) where mark != .absent {
        found[letter, default: 0] += 1
      }
      required.merge(found, uniquingKeysWith: max)
    }
    for letter in guesses.joined()
    where letters.count(where: { $0 == letter }) < required[letter, default: 0] {
      return .letter(letter)
    }
    return nil
  }

  /// Marks `guess` against `answer`. Correct letters are marked first, then a misplaced letter
  /// is present only while the answer has copies of it left over, so guessing a letter twice
  /// doesn't mark it twice against an answer that has it once.
  static func marks(for guess: String, answer: String) -> [LetterMark] {
    let guess = Array(guess)
    let answer = Array(answer)
    var marks = Array(repeating: LetterMark.absent, count: guess.count)
    var leftover: [Character: Int] = [:]
    for (i, letter) in answer.enumerated() where guess.indices.contains(i) && guess[i] != letter {
      leftover[letter, default: 0] += 1
    }
    for (i, letter) in guess.enumerated() {
      if answer.indices.contains(i), answer[i] == letter {
        marks[i] = .correct
      } else if let count = leftover[letter], count > 0 {
        marks[i] = .present
        leftover[letter] = count - 1
      }
    }
    return marks
  }
}
