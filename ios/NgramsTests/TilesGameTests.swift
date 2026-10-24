import Testing

@testable import Ngrams

@Suite("TilesGame")
struct TilesGameTests {
  @Test("finds a word from selected tiles")
  func findsWord() {
    var game = TilesGame(puzzle: smallPuzzle)
    game.toggle(0)
    game.toggle(1)

    #expect(game.selectedText == "abcd")
    #expect(game.submit() == .found(smallPuzzle.words[2]))
    #expect(game.selection.isEmpty)
    #expect(game.foundWords == ["abcd"])
    #expect(game.score == 2)
  }

  @Test("deselects a tapped tile")
  func deselects() {
    var game = TilesGame(puzzle: smallPuzzle)
    game.toggle(0)
    game.toggle(1)
    game.toggle(0)

    #expect(game.selection == [1])
  }

  @Test("holds at most n tiles")
  func capsSelection() {
    var game = TilesGame(puzzle: smallPuzzle)
    for tile in [0, 1, 2] {
      game.toggle(tile)
    }

    #expect(game.selection == [0, 1])
  }

  @Test("reports words already found")
  func alreadyFound() {
    var game = TilesGame(puzzle: smallPuzzle)
    game.toggle(0)
    _ = game.submit()
    game.toggle(0)

    #expect(game.submit() == .alreadyFound(smallPuzzle.words[0]))
    #expect(game.score == 1)
  }

  @Test("rejects words not on the board's list")
  func notAWord() {
    var game = TilesGame(puzzle: smallPuzzle)
    game.toggle(1)
    game.toggle(0)

    #expect(game.submit() == .notAWord("cdab"))
    #expect(game.found.isEmpty)
  }

  @Test("recognizes a blocked word without scoring it")
  func blocked() {
    var game = TilesGame(puzzle: smallPuzzle)
    game.toggle(2)
    game.toggle(0)

    #expect(game.submit() == .blocked("efab"))
    #expect(game.found.isEmpty)
    #expect(game.score == 0)
  }

  @Test("ignores an empty submission")
  func empty() {
    var game = TilesGame(puzzle: smallPuzzle)

    #expect(game.submit() == .empty)
  }

  @Test("keeps a found target's tiles in play")
  func solvesTarget() {
    var game = TilesGame(puzzle: smallPuzzle)
    game.toggle(2)
    game.toggle(3)
    _ = game.submit()

    #expect(game.solvedTargets == [1])
    #expect(game.solvedTiles == [2, 3])
    game.toggle(2)
    #expect(game.selection == [2])
  }

  @Test("takes a found target's tiles off the board when solved tiles leave")
  func solvedTilesLeave() {
    var game = TilesGame(puzzle: smallPuzzle, foundWords: ["efgh"], solvedTilesLeave: true)

    game.toggle(2)
    #expect(game.selection.isEmpty)
    game.toggle(0)
    #expect(game.selection == [0])
  }

  @Test("adds the bonus once every target is found")
  func bonus() {
    let game = TilesGame(puzzle: smallPuzzle, foundWords: ["abcd", "efgh"])

    #expect(game.allTargetsFound)
    #expect(game.score == 2 + 2 + 40)
    #expect(!game.earnedStar)
  }

  @Test("earns a star with every target and the target score")
  func earnsStar() {
    let game = TilesGame(puzzle: smallPuzzle, foundWords: ["abcd", "efgh", "ab", "ef"])

    #expect(game.score == 46)
    #expect(!game.earnedStar)
    let easier = puzzle(targetScore: 46)
    #expect(TilesGame(puzzle: easier, foundWords: game.foundWords).earnedStar)
  }

  @Test("withholds the star until every target is found")
  func starNeedsTargets() {
    let game = TilesGame(puzzle: puzzle(targetScore: 4), foundWords: ["abcd", "ab", "ef"])

    #expect(game.score >= 4)
    #expect(!game.earnedStar)
  }

  private func puzzle(targetScore: Int) -> TilesPuzzle {
    TilesPuzzle(
      language: .en, n: 2, tiles: smallPuzzle.tiles, targets: smallPuzzle.targets, bonus: 40,
      targetScore: targetScore, words: smallPuzzle.words, blocked: [])
  }

  @Test("restores saved words, dropping repeats and words the board doesn't have")
  func restores() {
    let game = TilesGame(puzzle: smallPuzzle, foundWords: ["ef", "zz", "ef", "abcd"])

    #expect(game.foundWords == ["ef", "abcd"])
    #expect(game.solvedTargets == [0])
  }
}
