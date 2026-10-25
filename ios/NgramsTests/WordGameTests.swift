import Testing

@testable import Ngrams

@Suite("WordGame")
struct WordGameTests {
  private func typed(_ text: String, into game: inout WordGame) {
    for letter in text {
      game.type(letter)
    }
  }

  @Test("solves with the answer")
  func solves() {
    var game = WordGame(puzzle: wordPuzzle)
    typed("cramp", into: &game)
    #expect(game.submit(against: wordList) == .guessed("cramp"))
    typed("llama", into: &game)

    #expect(game.submit(against: wordList) == .guessed("llama"))
    #expect(game.status == .won(guesses: 2))
    #expect(game.marks.last == Array(repeating: .correct, count: 5))
    #expect(game.current.isEmpty)
  }

  @Test("loses after the last guess")
  func loses() {
    var game = WordGame(puzzle: wordPuzzle, guesses: Array(repeating: "cramp", count: 5))
    typed("plaza", into: &game)
    _ = game.submit(against: wordList)

    #expect(game.status == .lost)
    typed("llama", into: &game)
    #expect(game.current.isEmpty)
    #expect(game.submit(against: wordList) == .over)
  }

  @Test("marks a repeated letter only as often as the answer has it")
  func marksRepeats() {
    // LLAMA has two Ls and two As; LOLLS guesses three Ls, LABEL two.
    #expect(
      WordGame.marks(for: "lolls", answer: "llama") == [
        .correct, .absent, .present, .absent, .absent,
      ])
    #expect(
      WordGame.marks(for: "label", answer: "llama") == [
        .correct, .present, .absent, .absent, .present,
      ])
    #expect(
      WordGame.marks(for: "allay", answer: "llama") == [
        .present, .correct, .present, .present, .absent,
      ])
  }

  @Test("keeps the best mark per letter for the keyboard")
  func letterMarks() {
    let game = WordGame(puzzle: wordPuzzle, guesses: ["plaza", "label"])

    #expect(game.letterMarks["l"] == .correct)
    #expect(game.letterMarks["a"] == .correct)
    #expect(game.letterMarks["p"] == .absent)
  }

  @Test("refuses short, unknown, and blocked guesses and keeps them typed")
  func rejects() {
    var game = WordGame(puzzle: wordPuzzle)
    typed("lla", into: &game)
    #expect(game.submit(against: wordList) == .tooShort)

    typed("mz", into: &game)
    #expect(game.submit(against: wordList) == .notAWord("llamz"))
    #expect(game.current == "llamz")

    for _ in 0..<5 {
      game.deleteLetter()
    }
    typed("bitch", into: &game)
    #expect(game.submit(against: wordList) == .blocked("bitch"))
    #expect(game.guesses.isEmpty)
  }

  @Test("types at most n letters")
  func capsTyping() {
    var game = WordGame(puzzle: wordPuzzle)
    typed("llamas", into: &game)

    #expect(game.current == "llama")
  }

  @Test("drops saved guesses it can't hold")
  func dropsBadSaves() {
    let game = WordGame(puzzle: wordPuzzle, guesses: ["cramp", "lla", "llama", "plaza"])

    #expect(game.guesses == ["cramp", "llama"])
    #expect(game.status == .won(guesses: 2))
  }
}

@Suite("GuessList")
struct GuessListTests {
  @Test("parses one word per line")
  func parses() {
    let list = GuessList(accepted: "lamp\ntree\n", blocked: "")

    #expect(list.accepted == ["lamp", "tree"])
    #expect(list.blocked.isEmpty)
  }

  @Test("loads every bundled list")
  func loadsBundled() async throws {
    for language in Language.allCases {
      for n in [4, 5, 6] {
        let list = try await GuessList.loadBundled(language: language, n: n)
        #expect(list.accepted.count > 1000)
        #expect(list.accepted.allSatisfy { $0.count == n })
      }
    }
  }
}
