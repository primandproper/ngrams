import Testing

@testable import Ngrams

@Suite("ShareText")
struct ShareTextTests {
  @Test("shares a word puzzle's grid")
  func word() {
    let game = WordGame(puzzle: wordPuzzle, guesses: ["plaza", "llama"], hardMode: true)

    #expect(
      ShareText.word(game, on: testDay) == """
        n-grams · Word 🇺🇸 n=5 · Jan 1 · 2/6* ⭐
        ⬛🟦🟦⬛🟦
        🟦🟦🟦🟦🟦
        """)
  }

  @Test("shares a lost word puzzle as X")
  func lostWord() {
    let game = WordGame(puzzle: wordPuzzle, guesses: Array(repeating: "cramp", count: 6))

    #expect(ShareText.word(game, on: testDay).hasPrefix("n-grams · Word 🇺🇸 n=5 · Jan 1 · X/6\n"))
  }

  @Test("shares a tiles board's progress")
  func tiles() {
    let game = TilesGame(puzzle: smallPuzzle, foundWords: ["abcd", "ab"])

    #expect(
      ShareText.tiles(game, on: testDay) == """
        n-grams · Tiles 🇺🇸 n=2 · Jan 1 · 3/50
        ▱▱▱▱▱▱▱▱▱▱ 1/2 targets
        """)
  }

  @Test("shares a pangram board's progress")
  func pangram() {
    let game = PangramGame(puzzle: pangramPuzzle, foundWords: ["plaice"], hardMode: true)

    #expect(
      ShareText.pangram(game, on: testDay) == """
        n-grams · Pangram 🇺🇸 n=6 · Jan 1 · 13/13* ⭐
        ▰▰▰▰▰▰▰▰▰▰ 1/1 pangram
        """)
  }

  @Test("shares every puzzle started on a day, and nothing when none was")
  func day() {
    let words = [
      WordGame(puzzle: wordPuzzle, guesses: ["plaza", "llama"], hardMode: true),
      WordGame(puzzle: WordPuzzle(language: .es, n: 4, answer: "casa", display: nil)),
    ]
    let tiles = [TilesGame(puzzle: smallPuzzle, foundWords: ["abcd", "ab"])]
    let pangrams = [PangramGame(puzzle: pangramPuzzle)]

    #expect(
      ShareText.day(words: words, tiles: tiles, pangrams: pangrams, on: testDay) == """
        n-grams · Jan 1
        🇺🇸 Word · n=5 2/6* ⭐
        🇺🇸 Tiles · n=2 3/50
        """)
    #expect(
      ShareText.day(words: [words[1]], tiles: [], pangrams: pangrams, on: testDay) == nil)
  }
}
