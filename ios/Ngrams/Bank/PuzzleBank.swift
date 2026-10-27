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

  /// The country whose word list and usage the language follows.
  var flag: String {
    switch self {
    case .en: "🇺🇸"
    case .es: "🇲🇽"
    }
  }

  /// The language the interface is showing: the app's best match for the device's preferred
  /// languages, which also decides the language of game names, dates and share text.
  static var interface: Language {
    Bundle.main.preferredLocalizations.first.flatMap(Language.init(rawValue:)) ?? .en
  }
}

/// The game kinds, as the bank and saved progress name them.
nonisolated enum PuzzleKind: String, CaseIterable, Codable, Sendable {
  case word
  case tiles
  case pangram

  /// The game's name in the interface's language.
  var name: String { name(in: .interface) }

  /// The game's name in `interfaceLanguage`, which share text uses as well as the screens.
  func name(in interfaceLanguage: Language) -> String {
    switch (interfaceLanguage, self) {
    case (.en, .word): "Password"
    case (.en, .tiles): "Tiles"
    case (.en, .pangram): "Pangram"
    case (.es, .word): "Contraseña"
    case (.es, .tiles): "Fichas"
    case (.es, .pangram): "Pangrama"
    }
  }
}

/// Every puzzle the app ships with, built offline by the generator. See docs/design.md.
nonisolated struct PuzzleBank: Sendable {
  static let supportedVersion = 1

  let seed: UInt64
  let days: [PuzzleDay]
  private let tiles: [PuzzleDay: [TilesPuzzle]]
  private let words: [PuzzleDay: [WordPuzzle]]
  private let pangrams: [PuzzleDay: [PangramPuzzle]]

  init(
    seed: UInt64, tiles: [PuzzleDay: [TilesPuzzle]], words: [PuzzleDay: [WordPuzzle]] = [:],
    pangrams: [PuzzleDay: [PangramPuzzle]] = [:]
  ) {
    self.seed = seed
    self.tiles = tiles
    self.words = words
    self.pangrams = pangrams
    self.days = Set(tiles.keys).union(words.keys).union(pangrams.keys).sorted()
  }

  /// The day's tiles puzzles, by language in `Language.allCases` order, then smallest board first.
  func tilesPuzzles(on day: PuzzleDay) -> [TilesPuzzle] {
    Self.sorted(tiles[day] ?? [], by: { ($0.language, $0.n) })
  }

  /// The day's word puzzles, by language in `Language.allCases` order, then shortest first.
  func wordPuzzles(on day: PuzzleDay) -> [WordPuzzle] {
    Self.sorted(words[day] ?? [], by: { ($0.language, $0.n) })
  }

  /// The day's pangram boards, by language in `Language.allCases` order, then fewest letters
  /// first.
  func pangramPuzzles(on day: PuzzleDay) -> [PangramPuzzle] {
    Self.sorted(pangrams[day] ?? [], by: { ($0.language, $0.n) })
  }

  private static func sorted<Puzzle>(
    _ puzzles: [Puzzle], by key: (Puzzle) -> (Language, Int)
  ) -> [Puzzle] {
    let rank = Dictionary(uniqueKeysWithValues: Language.allCases.enumerated().map { ($1, $0) })
    return puzzles.sorted {
      let (left, right) = (key($0), key($1))
      return (rank[left.0] ?? 0, left.1) < (rank[right.0] ?? 0, right.1)
    }
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
    var words: [PuzzleDay: [WordPuzzle]] = [:]
    var pangrams: [PuzzleDay: [PangramPuzzle]] = [:]
    for day in file.days {
      guard let date = PuzzleDay(day.date) else {
        throw BankError.badDate(day.date)
      }
      tiles[date] = day.puzzles.compactMap(\.tiles)
      words[date] = day.puzzles.compactMap(\.word)
      pangrams[date] = day.puzzles.compactMap(\.pangram)
    }
    return PuzzleBank(seed: file.seed, tiles: tiles, words: words, pangrams: pangrams)
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
  case badAnswer(String, n: Int)
  case badPangramWord(String)

  var description: String {
    switch self {
    case .missing: "the app has no puzzle bank"
    case .unsupportedVersion(let version): "bank version \(version) isn't supported"
    case .badDate(let date): "bank date \(date) isn't YYYY-MM-DD"
    case .badTileIndex(let index, let tiles): "tile index \(index) is outside a \(tiles)-tile board"
    case .badAnswer(let answer, let n): "answer \(answer) isn't \(n) letters"
    case .badPangramWord(let word): "\(word) doesn't fit its pangram board"
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

/// A pangram board: spell words of at least four letters from `n` letters, always using the
/// center.
nonisolated struct PangramPuzzle: Sendable, Hashable, Identifiable {
  static let minLength = 4

  let language: Language
  let n: Int
  /// Accent-folded and sorted, the center among them.
  let letters: [Character]
  let center: Character
  let targetScore: Int
  let words: [PangramWord]
  /// Folded spellings of the common pangrams, every one of which the star needs.
  let pangrams: Set<String>
  /// Folded spellings of offensive words the letters can build. They score nothing.
  let blocked: Set<String>

  var id: String { "\(language.rawValue)-\(n)" }

  /// Whether `word` uses every letter.
  func isPangram(_ word: String) -> Bool {
    Set(word) == Set(letters)
  }

  /// Whether `word` uses every letter but isn't one of the common pangrams the star needs. It
  /// scores like any pangram.
  func isBonusPangram(_ word: String) -> Bool {
    isPangram(word) && !pangrams.contains(word)
  }
}

/// A valid word on a pangram board.
nonisolated struct PangramWord: Sendable, Hashable, Decodable {
  let word: String
  /// Accented spelling, present only when it differs from `word`.
  let display: String?
  let points: Int

  var shown: String { display ?? word }
}

/// A word puzzle: guess the `n`-letter answer.
nonisolated struct WordPuzzle: Sendable, Hashable, Identifiable {
  let language: Language
  let n: Int
  /// Accent-folded, so it compares against guesses letter for letter.
  let answer: String
  /// Accented spelling, present only when it differs from `answer`.
  let display: String?

  var id: String { "\(language.rawValue)-\(n)" }
  var shown: String { display ?? answer }
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
  var tiles: TilesPuzzle?
  var word: WordPuzzle?
  var pangram: PangramPuzzle?

  private enum CodingKeys: String, CodingKey {
    case lang, kind, n, tiles, targets, bonus, targetScore, words, blocked, answer, display
    case letters, center, pangrams
  }

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let kind = PuzzleKind(rawValue: try container.decode(String.self, forKey: .kind))
    guard let kind,
      let language = Language(rawValue: try container.decode(String.self, forKey: .lang))
    else {
      return
    }
    let n = try container.decode(Int.self, forKey: .n)

    switch kind {
    case .word:
      let answer = try container.decode(String.self, forKey: .answer)
      guard answer.count == n else {
        throw BankError.badAnswer(answer, n: n)
      }
      word = WordPuzzle(
        language: language, n: n, answer: answer,
        display: try container.decodeIfPresent(String.self, forKey: .display))
    case .tiles:
      tiles = try Self.tiles(from: container, language: language, n: n)
    case .pangram:
      pangram = try Self.pangram(from: container, language: language, n: n)
    }
  }

  private static func pangram(
    from container: KeyedDecodingContainer<CodingKeys>, language: Language, n: Int
  ) throws -> PangramPuzzle {
    let letters = try container.decode([String].self, forKey: .letters).compactMap(\.first)
    let center = try container.decode(String.self, forKey: .center)
    let words = try container.decode([PangramWord].self, forKey: .words)
    let pangrams = try container.decode([String].self, forKey: .pangrams)
    let allowed = Set(letters)
    guard let centerLetter = center.first, allowed.contains(centerLetter) else {
      throw BankError.badPangramWord(center)
    }
    for word in words.map(\.word)
    where !word.contains(centerLetter) || !Set(word).isSubset(of: allowed) {
      throw BankError.badPangramWord(word)
    }

    return PangramPuzzle(
      language: language,
      n: n,
      letters: letters,
      center: centerLetter,
      targetScore: try container.decode(Int.self, forKey: .targetScore),
      words: words,
      pangrams: Set(pangrams),
      blocked: Set(try container.decodeIfPresent([String].self, forKey: .blocked) ?? []))
  }

  private static func tiles(
    from container: KeyedDecodingContainer<CodingKeys>, language: Language, n: Int
  ) throws -> TilesPuzzle {
    let board = try container.decode([String].self, forKey: .tiles)
    let targets = try container.decode([[Int]].self, forKey: .targets)
    let words = try container.decode([TilesWord].self, forKey: .words)
    for index in targets.flatMap(\.self) + words.flatMap(\.tiles)
    where !board.indices.contains(index) {
      throw BankError.badTileIndex(index, tiles: board.count)
    }

    return TilesPuzzle(
      language: language,
      n: n,
      tiles: board,
      targets: targets,
      bonus: try container.decode(Int.self, forKey: .bonus),
      targetScore: try container.decode(Int.self, forKey: .targetScore),
      words: words,
      blocked: Set(try container.decodeIfPresent([String].self, forKey: .blocked) ?? []))
  }
}
