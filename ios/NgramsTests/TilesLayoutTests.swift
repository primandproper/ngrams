import Testing

@testable import Ngrams

/// A board of `targets` targets of `n` tiles each, with target i on tiles i*n through i*n+n-1.
private func board(n: Int, targets: Int) -> TilesPuzzle {
  TilesPuzzle(
    language: .en, n: n, tiles: (0..<n * targets).map { "t\($0)" },
    targets: (0..<targets).map { target in Array(target * n..<target * n + n) }, bonus: 40,
    targetScore: 100, words: [], blocked: [])
}

@Suite("TilesLayout")
struct TilesLayoutTests {
  @Test("spreads every board size", arguments: [(3, 7), (4, 5), (5, 4)])
  func spreads(n: Int, targets: Int) {
    let puzzle = board(n: n, targets: targets)
    var rng = SeededGenerator(seed: 1)

    for _ in 0..<20 {
      let order = TilesLayout.spread(Array(puzzle.tiles.indices), in: puzzle, using: &rng)
      #expect(order.sorted() == Array(puzzle.tiles.indices))
      #expect(TilesLayout.isSpread(order, in: puzzle))
    }
  }

  @Test("spreads what's left once targets are solved")
  func spreadsRemainder() {
    let puzzle = board(n: 4, targets: 5)
    var rng = SeededGenerator(seed: 1)

    let order = TilesLayout.spread(Array(0..<4), in: puzzle, using: &rng)
    #expect(TilesLayout.isSpread(order, in: puzzle))
  }

  @Test("rejects a target's tiles crowding a row")
  func rejectsCrowding() {
    let puzzle = board(n: 4, targets: 5)

    // Rows of 4: tiles 0 and 2 of target 0 share the first row.
    #expect(
      !TilesLayout.isSpread(
        [0, 4, 2, 8, 1, 5, 9, 12, 3, 6, 10, 13, 7, 11, 14, 16, 15, 17, 18, 19], in: puzzle))
  }

  @Test("rejects a target's tiles side by side in order")
  func rejectsInOrder() {
    let puzzle = board(n: 5, targets: 4)

    // Rows of 5: tiles 1 and 2 of target 0 lead the first row, in order.
    #expect(
      !TilesLayout.isSpread(
        [1, 2, 5, 10, 15, 0, 3, 6, 11, 16, 4, 7, 12, 17, 8, 9, 13, 14, 18, 19], in: puzzle))
  }

  @Test("lays a board out the same way for the same seed")
  func deterministic() {
    let puzzle = board(n: 3, targets: 7)
    var first = SeededGenerator(seed: "en-tiles-3-2027-01-01")
    var second = SeededGenerator(seed: "en-tiles-3-2027-01-01")

    #expect(
      TilesLayout.spread(Array(puzzle.tiles.indices), in: puzzle, using: &first)
        == TilesLayout.spread(Array(puzzle.tiles.indices), in: puzzle, using: &second))
  }
}
