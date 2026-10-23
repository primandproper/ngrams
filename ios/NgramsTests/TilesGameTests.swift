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

  @Test("ignores an empty submission")
  func empty() {
    var game = TilesGame(puzzle: smallPuzzle)

    #expect(game.submit() == .empty)
  }

  @Test("takes a found target's tiles off the board")
  func solvesTarget() {
    var game = TilesGame(puzzle: smallPuzzle)
    game.toggle(2)
    game.toggle(3)
    _ = game.submit()

    #expect(game.solvedTargets == [1])
    #expect(game.solvedTiles == [2, 3])
    game.toggle(2)
    #expect(game.selection.isEmpty)
  }

  @Test("adds the bonus once every target is found")
  func bonus() {
    let game = TilesGame(puzzle: smallPuzzle, foundWords: ["abcd", "efgh"])

    #expect(game.allTargetsFound)
    #expect(game.score == 2 + 2 + 40)
    #expect(!game.reachedTargetScore)
  }

  @Test("reaches the target score")
  func reachesTarget() {
    let game = TilesGame(puzzle: smallPuzzle, foundWords: ["abcd", "efgh", "ab", "ef"])

    #expect(game.score == 46)
    #expect(!game.reachedTargetScore)
    let easier = TilesPuzzle(
      language: .en, n: 2, tiles: smallPuzzle.tiles, targets: smallPuzzle.targets, bonus: 40,
      targetScore: 46, words: smallPuzzle.words)
    #expect(TilesGame(puzzle: easier, foundWords: game.foundWords).reachedTargetScore)
  }

  @Test("restores saved words, dropping repeats and words the board doesn't have")
  func restores() {
    let game = TilesGame(puzzle: smallPuzzle, foundWords: ["ef", "zz", "ef", "abcd"])

    #expect(game.foundWords == ["ef", "abcd"])
    #expect(game.solvedTargets == [0])
  }
}
