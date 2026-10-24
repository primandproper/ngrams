/// Arranges a board's tiles so no target reads off it at a glance. A uniform shuffle leaves two
/// of a target's tiles side by side, in order, on about half of all boards.
nonisolated enum TilesLayout {
  /// Enough draws that a board which can be spread effectively always is: the strictest board
  /// (N=4) passes about 1 draw in 300.
  static let maxDraws = 10_000

  /// Orders `tiles` into rows of `puzzle.n` that pass `isSpread`, falling back to the last draw
  /// if none does.
  static func spread(
    _ tiles: [Int], in puzzle: TilesPuzzle, using rng: inout some RandomNumberGenerator
  ) -> [Int] {
    let owners = owners(in: puzzle)
    var order = tiles
    for _ in 0..<maxDraws {
      order.shuffle(using: &rng)
      if isSpread(order, n: puzzle.n, owners: owners) {
        break
      }
    }
    return order
  }

  /// Whether no row holds more of one target's tiles than it must, and no two of a target's
  /// tiles sit side by side in reading order.
  static func isSpread(_ order: [Int], in puzzle: TilesPuzzle) -> Bool {
    isSpread(order, n: puzzle.n, owners: owners(in: puzzle))
  }

  private struct Owner {
    let target: Int
    let position: Int
  }

  private static func owners(in puzzle: TilesPuzzle) -> [Int: Owner] {
    var owners: [Int: Owner] = [:]
    for (target, tiles) in puzzle.targets.enumerated() {
      for (position, tile) in tiles.enumerated() {
        owners[tile] = Owner(target: target, position: position)
      }
    }
    return owners
  }

  private static func isSpread(_ order: [Int], n: Int, owners: [Int: Owner]) -> Bool {
    let targets = Set(order.compactMap { owners[$0]?.target }).count
    guard targets > 0 else {
      return true
    }
    // A row of n tiles from fewer than n targets has to repeat one.
    let perRow = (n + targets - 1) / targets

    for start in stride(from: 0, to: order.count, by: n) {
      let row = order[start..<min(start + n, order.count)].compactMap { owners[$0] }
      var counts: [Int: Int] = [:]
      for owner in row {
        counts[owner.target, default: 0] += 1
        if counts[owner.target, default: 0] > perRow {
          return false
        }
      }
      for (left, right) in zip(row, row.dropFirst())
      where left.target == right.target && right.position == left.position + 1 {
        return false
      }
    }
    return true
  }
}

/// SplitMix64, so a board's first layout comes out the same on every launch. The standard
/// library's generators can't be seeded.
nonisolated struct SeededGenerator: RandomNumberGenerator {
  private var state: UInt64

  init(seed: UInt64) {
    state = seed
  }

  /// Seeds from a string with FNV-1a, which unlike `Hasher` is stable across launches.
  init(seed: String) {
    var hash: UInt64 = 0xcbf2_9ce4_8422_2325
    for byte in seed.utf8 {
      hash = (hash ^ UInt64(byte)) &* 0x100_0000_01b3
    }
    self.init(seed: hash)
  }

  mutating func next() -> UInt64 {
    state &+= 0x9e37_79b9_7f4a_7c15
    var z = state
    z = (z ^ (z >> 30)) &* 0xbf58_476d_1ce4_e5b9
    z = (z ^ (z >> 27)) &* 0x94d0_49bb_1331_11eb
    return z ^ (z >> 31)
  }
}
