import Foundation
import Testing

@testable import Ngrams

/// Runs testdata/, the cases the Android tests run too, so the two apps play the same game.
@Suite("Shared fixtures")
struct SharedFixturesTests {
  private typealias Object = [String: Any]

  private let day = PuzzleDay(year: 2027, month: 1, day: 1)

  private func fixture(_ name: String) throws -> Object {
    let url = try #require(
      Bundle(for: FixtureBundle.self).url(
        forResource: name, withExtension: "json", subdirectory: "testdata"))
    return try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? Object)
  }

  private func bank(_ fixture: Object) throws -> PuzzleBank {
    try PuzzleBank.decode(JSONSerialization.data(withJSONObject: try #require(fixture["bank"])))
  }

  private func cases(_ fixture: Object, _ key: String) throws -> [Object] {
    try #require(fixture[key] as? [Object])
  }

  @Test("lays boards out the way the Android app does")
  func layouts() throws {
    let fixture = try fixture("layouts")

    for testCase in try cases(fixture, "generator") {
      let seed = try #require(testCase["seed"] as? String)
      let outputs = try #require(testCase["outputs"] as? [String])
      var rng = SeededGenerator(seed: seed)
      #expect(outputs.map { _ in String(rng.next()) } == outputs, "seed '\(seed)'")
    }
    for testCase in try cases(fixture, "shuffles") {
      let seed = try #require(testCase["seed"] as? String)
      var rng = SeededGenerator(seed: seed)
      var order = Array(0..<(try #require(testCase["count"] as? Int)))
      order.shuffle(using: &rng)
      #expect(order == testCase["order"] as? [Int], "seed '\(seed)'")
    }
    for testCase in try cases(fixture, "tiles") {
      let seed = try #require(testCase["seed"] as? String)
      let n = try #require(testCase["n"] as? Int)
      let targets = try #require(testCase["targets"] as? Int)
      let puzzle = TilesPuzzle(
        language: .en, n: n, tiles: (0..<n * targets).map { "t\($0)" },
        targets: (0..<targets).map { target in Array(target * n..<target * n + n) }, bonus: 40,
        targetScore: 100, words: [], blocked: [])
      var rng = SeededGenerator(seed: seed)
      let order = TilesLayout.spread(Array(puzzle.tiles.indices), in: puzzle, using: &rng)
      #expect(order == testCase["order"] as? [Int], "seed '\(seed)'")
      #expect(TilesLayout.isSpread(order, in: puzzle))
    }
    for testCase in try cases(fixture, "wheels") {
      let seed = try #require(testCase["seed"] as? String)
      let center = try #require((testCase["center"] as? String)?.first)
      let letters = try #require(testCase["letters"] as? String)
      var rng = SeededGenerator(seed: seed)
      let outer = letters.filter { $0 != center }.shuffled(using: &rng)
      #expect(String(outer) == testCase["outer"] as? String, "seed '\(seed)'")
    }
  }

  @Test("plays tiles the way the Android app does")
  func tiles() throws {
    let fixture = try fixture("tiles")
    let bank = try bank(fixture)
    func puzzle(_ testCase: Object) throws -> TilesPuzzle {
      try #require(
        bank.tilesPuzzles(on: day).first { $0.language.rawValue == testCase["lang"] as? String })
    }

    for testCase in try cases(fixture, "states") {
      let found = try #require(testCase["found"] as? [String])
      let game = TilesGame(puzzle: try puzzle(testCase), foundWords: found)
      #expect(game.foundWords == testCase["foundWords"] as? [String], "\(found)")
      #expect(game.score == testCase["score"] as? Int, "\(found)")
      #expect(game.solvedTargets == testCase["solvedTargets"] as? [Int], "\(found)")
      #expect(game.allTargetsFound == testCase["allTargetsFound"] as? Bool, "\(found)")
      #expect(game.earnedStar == testCase["earnedStar"] as? Bool, "\(found)")
    }
    for testCase in try cases(fixture, "submissions") {
      let found = try #require(testCase["found"] as? [String])
      let taps = try #require(testCase["taps"] as? [Int])
      var game = TilesGame(
        puzzle: try puzzle(testCase), foundWords: found,
        solvedTilesLeave: try #require(testCase["solvedTilesLeave"] as? Bool))
      for tile in taps {
        game.toggle(tile)
      }
      #expect(game.selection == testCase["selection"] as? [Int], "taps \(taps) after \(found)")

      let (result, text): (String, String) =
        switch game.submit() {
        case .found(let word): ("found", word.word)
        case .alreadyFound(let word): ("alreadyFound", word.word)
        case .blocked(let text): ("blocked", text)
        case .notAWord(let text): ("notAWord", text)
        case .empty: ("empty", "")
        }
      #expect(result == testCase["result"] as? String, "taps \(taps) after \(found)")
      #expect(text == testCase["text"] as? String, "taps \(taps) after \(found)")
      #expect(game.foundWords == testCase["foundAfter"] as? [String], "taps \(taps) after \(found)")
      #expect(game.selection.isEmpty)
    }
  }

  @Test("plays pangrams the way the Android app does")
  func pangrams() throws {
    let fixture = try fixture("pangram")
    let puzzle = try #require(try bank(fixture).pangramPuzzles(on: day).first)

    for testCase in try cases(fixture, "states") {
      let found = try #require(testCase["found"] as? [String])
      let game = PangramGame(puzzle: puzzle, foundWords: found)
      #expect(game.foundWords == testCase["foundWords"] as? [String], "\(found)")
      #expect(game.score == testCase["score"] as? Int, "\(found)")
      #expect(game.foundPangrams == testCase["foundPangrams"] as? Int, "\(found)")
      #expect(game.foundBonusPangrams == testCase["foundBonusPangrams"] as? Int, "\(found)")
      #expect(game.earnedStar == testCase["earnedStar"] as? Bool, "\(found)")
      #expect(
        game.found(sortedBy: .alphabetical).map(\.word) == testCase["alphabetical"] as? [String],
        "\(found)")
      #expect(
        game.found(sortedBy: .recent).map(\.word) == testCase["recent"] as? [String], "\(found)")
    }
    for testCase in try cases(fixture, "submissions") {
      let found = try #require(testCase["found"] as? [String])
      let typed = try #require(testCase["typed"] as? String)
      var game = PangramGame(
        puzzle: puzzle, foundWords: found,
        hardMode: try #require(testCase["hardMode"] as? Bool))
      for letter in typed {
        game.type(letter)
      }

      let (result, text): (String, String) =
        switch game.submit() {
        case .found(let word): ("found", word.word)
        case .alreadyFound(let word): ("alreadyFound", word.word)
        case .blocked(let text): ("blocked", text)
        case .notAWord(let text): ("notAWord", text)
        case .tooShort: ("tooShort", "")
        case .missingCenter: ("missingCenter", "")
        case .needsPangram: ("needsPangram", "")
        case .empty: ("empty", "")
        }
      #expect(result == testCase["result"] as? String, "'\(typed)' after \(found)")
      #expect(text == testCase["text"] as? String, "'\(typed)' after \(found)")
      #expect(game.current.isEmpty)
    }
  }

  @Test("hints hard mode guesses the way the Android app does")
  func hints() throws {
    let fixture = try fixture("word_hints")
    let answer = try #require(fixture["answer"] as? String)
    let puzzle = WordPuzzle(language: .en, n: answer.count, answer: answer, display: nil)

    for testCase in try cases(fixture, "cases") {
      let guesses = try #require(testCase["guesses"] as? [String])
      let guess = try #require(testCase["guess"] as? String)
      let expected: WordGame.Hint? =
        if let hint = testCase["hint"] as? Object, let letter = (hint["letter"] as? String)?.first {
          if hint["kind"] as? String == "position", let index = hint["index"] as? Int {
            .position(letter, index)
          } else {
            .letter(letter)
          }
        } else {
          nil
        }
      let game = WordGame(puzzle: puzzle, guesses: guesses, hardMode: true)
      #expect(game.missingHint(in: guess) == expected, "\(guess) after \(guesses)")
    }
  }

  @Test("keeps stats and streaks the way the Android app does")
  func stats() throws {
    let fixture = try fixture("stats")
    let bank = try bank(fixture)
    var calendar = Calendar(identifier: .gregorian)
    let zone = try #require(fixture["timeZone"] as? String)
    calendar.timeZone = try #require(TimeZone(identifier: zone))
    let instants = ISO8601DateFormatter()

    for scenario in try cases(fixture, "scenarios") {
      let name = try #require(scenario["name"] as? String)
      let records = try #require(scenario["records"] as? [Object]).map { record in
        PlayRecord(
          key: ProgressKey(
            language: try #require(Language(rawValue: record["lang"] as? String ?? "")),
            kind: try #require(PuzzleKind(rawValue: record["kind"] as? String ?? "")),
            n: try #require(record["n"] as? Int),
            day: try #require(PuzzleDay(record["day"] as? String ?? ""))),
          entries: try #require(record["entries"] as? [String]),
          completedAt: (record["completedAt"] as? String).flatMap(instants.date(from:)))
      }
      let today = try #require(PuzzleDay(scenario["today"] as? String ?? ""))
      let stats = StatsBook.compute(records: records, bank: bank, today: today, calendar: calendar)

      for expected in try #require(scenario["lines"] as? [Object]) {
        let line = PuzzleLine(
          language: try #require(Language(rawValue: expected["lang"] as? String ?? "")),
          kind: try #require(PuzzleKind(rawValue: expected["kind"] as? String ?? "")),
          n: try #require(expected["n"] as? Int))
        let actual = try #require(stats[line], "\(name)")
        #expect(actual.played == expected["played"] as? Int, "\(name)")
        #expect(actual.decided == expected["decided"] as? Int, "\(name)")
        #expect(actual.successes == expected["successes"] as? Int, "\(name)")
        #expect(actual.currentStreak == expected["currentStreak"] as? Int, "\(name)")
        #expect(actual.bestStreak == expected["bestStreak"] as? Int, "\(name)")
        #expect(actual.guessCounts == expected["guessCounts"] as? [Int], "\(name)")
      }
    }
  }

  @Test("shares the way the Android app does")
  func share() throws {
    let fixture = try fixture("share")
    let bank = try bank(fixture)
    let day = try #require(PuzzleDay(fixture["day"] as? String ?? ""))
    func matches(_ game: Object, _ language: Language, _ n: Int) -> Bool {
      game["lang"] as? String == language.rawValue && game["n"] as? Int == n
    }
    func entries(_ game: Object) -> [String] { game["entries"] as? [String] ?? [] }
    func hard(_ game: Object) -> Bool { game["hardMode"] as? Bool ?? false }
    func word(_ game: Object) throws -> WordGame {
      WordGame(
        puzzle: try #require(bank.wordPuzzles(on: day).first { matches(game, $0.language, $0.n) }),
        guesses: entries(game), hardMode: hard(game))
    }
    func tiles(_ game: Object) throws -> TilesGame {
      TilesGame(
        puzzle: try #require(bank.tilesPuzzles(on: day).first { matches(game, $0.language, $0.n) }),
        foundWords: entries(game), solvedTilesLeave: hard(game))
    }
    func pangram(_ game: Object) throws -> PangramGame {
      PangramGame(
        puzzle: try #require(
          bank.pangramPuzzles(on: day).first { matches(game, $0.language, $0.n) }),
        foundWords: entries(game), hardMode: hard(game))
    }

    func interface(_ testCase: Object) -> Language {
      (testCase["interface"] as? String).flatMap(Language.init(rawValue:)) ?? .en
    }

    for testCase in try cases(fixture, "puzzles") {
      let language = interface(testCase)
      let text =
        switch testCase["kind"] as? String {
        case "word": ShareText.word(try word(testCase), on: day, in: language)
        case "tiles": ShareText.tiles(try tiles(testCase), on: day, in: language)
        default: ShareText.pangram(try pangram(testCase), on: day, in: language)
        }
      #expect(text == testCase["text"] as? String)
    }
    for testCase in try cases(fixture, "days") {
      let games = try #require(testCase["games"] as? [Object])
      let text = ShareText.day(
        words: try games.filter { $0["kind"] as? String == "word" }.map(word),
        tiles: try games.filter { $0["kind"] as? String == "tiles" }.map(tiles),
        pangrams: try games.filter { $0["kind"] as? String == "pangram" }.map(pangram),
        on: day, in: interface(testCase))
      #expect(text == testCase["text"] as? String)
    }
    for testCase in try cases(fixture, "dayNames") {
      let name = try #require(PuzzleDay(testCase["day"] as? String ?? ""))
        .name(
          includingYear: try #require(testCase["includingYear"] as? Bool), in: interface(testCase))
      #expect(name == testCase["name"] as? String)
    }
  }

  @Test("stores and moves hard modes the way the Android app does")
  func settings() throws {
    let fixture = try fixture("settings")
    func byKind<Value>(_ object: Any?, _ value: (Any) -> Value?) throws -> [PuzzleKind: Value] {
      let object = try #require(object as? Object)
      return try Dictionary(
        uniqueKeysWithValues: object.map { code, raw in
          (try #require(PuzzleKind(rawValue: code)), try #require(value(raw)))
        })
    }
    func languages(_ raw: Any) -> LanguageSelection? {
      (raw as? String).flatMap(LanguageSelection.init(rawValue:))
    }

    let keys = try byKind(fixture["keys"]) { $0 as? String }
    let legacyKeys = try byKind(fixture["legacyKeys"]) { $0 as? String }
    for kind in PuzzleKind.allCases {
      #expect(SettingsKey.hardMode(kind) == keys[kind])
      #expect(SettingsKey.legacyHardMode(kind) == legacyKeys[kind])
    }

    for testCase in try cases(fixture, "migrations") {
      let after = HardModeMigration.migrated(
        legacy: try byKind(testCase["legacy"]) { $0 as? Bool },
        current: try byKind(testCase["current"], languages))
      let expected = try byKind(testCase["after"]) { $0 as? String }
      #expect(after.mapValues(\.rawValue) == expected, "\(testCase["name"] ?? "")")
    }
  }
}

/// Finds the test bundle, which carries testdata/.
private final class FixtureBundle {}
