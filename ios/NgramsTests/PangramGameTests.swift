import Testing

@testable import Ngrams

@Suite("PangramGame")
struct PangramGameTests {
  private func submit(_ text: String, in game: inout PangramGame) -> PangramGame.Submission {
    for letter in text {
      game.type(letter)
    }
    return game.submit()
  }

  @Test("finds a word and scores it")
  func findsWord() {
    var game = PangramGame(puzzle: pangramPuzzle)

    #expect(submit("place", in: &game) == .found(pangramPuzzle.words[2]))
    #expect(game.current.isEmpty)
    #expect(game.foundWords == ["place"])
    #expect(game.score == 5)
  }

  @Test("needs every pangram and the target score for the star")
  func star() {
    var game = PangramGame(puzzle: pangramPuzzle, foundWords: ["pace", "pail", "place"])
    #expect(!game.earnedStar)

    _ = submit("plaice", in: &game)

    #expect(game.foundPangrams == 1)
    #expect(game.earnedStar)
    #expect(pangramPuzzle.isPangram("plaice"))
    #expect(!pangramPuzzle.isPangram("place"))
  }

  @Test("rejects short, centerless, blocked, unknown, and repeated words")
  func rejects() {
    var game = PangramGame(puzzle: pangramPuzzle, foundWords: ["pace"])

    #expect(submit("pal", in: &game) == .tooShort)
    #expect(submit("lace", in: &game) == .missingCenter)
    #expect(submit("clip", in: &game) == .blocked("clip"))
    #expect(submit("pple", in: &game) == .notAWord("pple"))
    #expect(submit("pace", in: &game) == .alreadyFound(pangramPuzzle.words[0]))
    #expect(game.score == 1)
  }

  @Test("makes hard mode's first word a pangram")
  func hardStartsWithPangram() {
    var game = PangramGame(puzzle: pangramPuzzle, hardMode: true)

    #expect(submit("place", in: &game) == .needsPangram)
    #expect(submit("plaice", in: &game) == .found(pangramPuzzle.words[3]))
    #expect(submit("place", in: &game) == .found(pangramPuzzle.words[2]))

    var easy = PangramGame(puzzle: pangramPuzzle)
    #expect(submit("place", in: &easy) == .found(pangramPuzzle.words[2]))
  }

  @Test("lists found words alphabetically or newest first")
  func sortsFound() {
    let game = PangramGame(puzzle: pangramPuzzle, foundWords: ["place", "pace", "plaice"])

    #expect(game.found(sortedBy: .alphabetical).map(\.word) == ["pace", "place", "plaice"])
    #expect(game.found(sortedBy: .recent).map(\.word) == ["plaice", "pace", "place"])
  }

  @Test("deletes typed letters")
  func deletes() {
    var game = PangramGame(puzzle: pangramPuzzle)
    game.type("p")
    game.type("a")
    game.deleteLetter()

    #expect(game.current == "p")
  }

  @Test("drops saved words the board doesn't have")
  func dropsUnknownSaves() {
    let game = PangramGame(puzzle: pangramPuzzle, foundWords: ["pace", "zzzz", "pace"])

    #expect(game.foundWords == ["pace"])
  }
}
