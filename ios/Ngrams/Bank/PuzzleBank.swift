import Foundation

/// The languages the bank carries puzzles for.
nonisolated enum Language: String, CaseIterable, Codable, Sendable {
  case en
  case es

  var name: String {
    switch self {
    case .en: "English"
    case .es: "Español"
    }
  }
}

/// The game kinds, as the bank and saved progress name them.
nonisolated enum PuzzleKind: String, Codable, Sendable {
  case word
  case tiles
}

/// Every puzzle the app ships with, built offline by the generator. See docs/design.md.
nonisolated struct PuzzleBank: Sendable {
  static let supportedVersion = 1

  let seed: UInt64
  let days: [PuzzleDay]
  private let tiles: [PuzzleDay: [TilesPuzzle]]

  init(seed: UInt64, tiles: [PuzzleDay: [TilesPuzzle]]) {
    self.seed = seed
    self.tiles = tiles
    self.days = tiles.keys.sorted()
  }

  /// The day's tiles puzzles in one language, smallest board first.
  func tilesPuzzles(on day: PuzzleDay, in language: Language) -> [TilesPuzzle] {
    (tiles[day] ?? []).filter { $0.language == language }.sorted { $0.n < $1.n }
  }

  /// Decodes a bank from the generator's JSON.
  static func decode(_ data: Data) throws -> PuzzleBank {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    let file = try decoder.decode(BankFile.self, from: data)
    guard file.version == supportedVersion else {
      throw BankError.unsupportedVersion(file.version)
    }

    var tiles: [PuzzleDay: [TilesPuzzle]] = [:]
    for day in file.days {
      guard let date = PuzzleDay(day.date) else {
        throw BankError.badDate(day.date)
      }
      tiles[date] = day.puzzles.compactMap(\.tiles)
    }
    return PuzzleBank(seed: file.seed, tiles: tiles)
  }

  /// Reads and decodes the bank bundled with the app, off the main actor.
  @concurrent
  static func loadBundled(from bundle: Bundle = .main) async throws -> PuzzleBank {
    guard let url = bundle.url(forResource: "puzzles", withExtension: "json") else {
      throw BankError.missing
    }
    return try decode(try Data(contentsOf: url))
  }
}

nonisolated enum BankError: Error, Equatable, CustomStringConvertible {
  case missing
  case unsupportedVersion(Int)
  case badDate(String)
  case badTileIndex(Int, tiles: Int)

  var description: String {
    switch self {
    case .missing: "the app has no puzzle bank"
    case .unsupportedVersion(let version): "bank version \(version) isn't supported"
    case .badDate(let date): "bank date \(date) isn't YYYY-MM-DD"
    case .badTileIndex(let index, let tiles): "tile index \(index) is outside a \(tiles)-tile board"
    }
  }
}

/// A tiles board: build words from 1 to `n` tiles, and find the targets that use every tile.
nonisolated struct TilesPuzzle: Sendable, Hashable, Identifiable {
  let language: Language
  let n: Int
  /// Fragments, accent-folded, in the order the board first shows them.
  let tiles: [String]
  /// Each target's tile indices, in reading order.
  let targets: [[Int]]
  let bonus: Int
  let targetScore: Int
  let words: [TilesWord]
  /// Folded spellings of offensive words the tiles can build. They score nothing.
  let blocked: Set<String>

  var id: String { "\(language.rawValue)-\(n)" }
}

/// A valid word on a tiles board.
nonisolated struct TilesWord: Sendable, Hashable, Decodable {
  /// Folded spelling: the tiles joined in order.
  let word: String
  /// Accented spelling, present only when it differs from `word`.
  let display: String?
  let tiles: [Int]
  let points: Int

  var shown: String { display ?? word }
}

// MARK: - Wire format

nonisolated private struct BankFile: Decodable {
  let version: Int
  let seed: UInt64
  let days: [DayFile]
}

nonisolated private struct DayFile: Decodable {
  let date: String
  let puzzles: [PuzzleFile]
}

/// One puzzle of any kind. Kinds and languages this build doesn't know decode to nothing, so a
/// newer bank still loads in an older app.
nonisolated private struct PuzzleFile: Decodable {
  let tiles: TilesPuzzle?

  private enum CodingKeys: String, CodingKey {
    case lang, kind, n, tiles, targets, bonus, targetScore, words, blocked
  }

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let kind = PuzzleKind(rawValue: try container.decode(String.self, forKey: .kind))
    let language = Language(rawValue: try container.decode(String.self, forKey: .lang))
    guard kind == .tiles, let language else {
      tiles = nil
      return
    }

    let board = try container.decode([String].self, forKey: .tiles)
    let targets = try container.decode([[Int]].self, forKey: .targets)
    let words = try container.decode([TilesWord].self, forKey: .words)
    for index in targets.flatMap(\.self) + words.flatMap(\.tiles)
    where !board.indices.contains(index) {
      throw BankError.badTileIndex(index, tiles: board.count)
    }

    tiles = TilesPuzzle(
      language: language,
      n: try container.decode(Int.self, forKey: .n),
      tiles: board,
      targets: targets,
      bonus: try container.decode(Int.self, forKey: .bonus),
      targetScore: try container.decode(Int.self, forKey: .targetScore),
      words: words,
      blocked: Set(try container.decodeIfPresent([String].self, forKey: .blocked) ?? []))
  }
}
