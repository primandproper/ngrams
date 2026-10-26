import Foundation

@testable import Ngrams

/// A two-target board: "abcd" and "efgh", plus the one-tile words "ab" and "ef". "efab" is
/// blocked.
let smallPuzzle = TilesPuzzle(
  language: .en,
  n: 2,
  tiles: ["ab", "cd", "ef", "gh"],
  targets: [[0, 1], [2, 3]],
  bonus: 40,
  targetScore: 50,
  words: [
    TilesWord(word: "ab", display: nil, tiles: [0], points: 1),
    TilesWord(word: "ef", display: "éf", tiles: [2], points: 1),
    TilesWord(word: "abcd", display: nil, tiles: [0, 1], points: 2),
    TilesWord(word: "efgh", display: nil, tiles: [2, 3], points: 2),
  ],
  blocked: ["efab"])

let testDay = PuzzleDay(year: 2027, month: 1, day: 1)

/// Bank JSON in the generator's format, with `puzzles` spliced into one day.
func bankJSON(version: Int = 1, date: String = "2027-01-01", puzzles: [String]) -> Data {
  Data(
    """
    {"version": \(version), "seed": 7, "days": [
      {"date": "\(date)", "puzzles": [\(puzzles.joined(separator: ","))]}
    ]}
    """.utf8)
}

func tilesPuzzleJSON(
  lang: String = "en", n: Int = 2, targets: String = "[[0,1]]", blocked: String? = #"["cdab"]"#
) -> String {
  """
  {"lang":"\(lang)","kind":"tiles","n":\(n),"tiles":["ab","cd"],"targets":\(targets),
   \(blocked.map { #""blocked":\#($0),"# } ?? "")"bonus":40,"target_score":62,"words":[
    {"word":"ab","tiles":[0],"points":1},
    {"word":"abcd","display":"ábcd","tiles":[0,1],"points":2}
  ]}
  """
}

/// A five-letter word puzzle whose answer has a repeated letter, so marking repeats matters.
let wordPuzzle = WordPuzzle(language: .en, n: 5, answer: "llama", display: nil)

let wordList = GuessList(
  accepted: ["llama", "label", "allay", "lolls", "loamy", "cramp", "plaza"], blocked: ["bitch"])

/// A six-letter board centered on p, with one common pangram, "plaice", and one bonus pangram,
/// "epical". "clip" is blocked.
let pangramPuzzle = PangramPuzzle(
  language: .en,
  n: 6,
  letters: Array("aceilp"),
  center: "p",
  targetScore: 13,
  words: [
    PangramWord(word: "pace", display: nil, points: 1),
    PangramWord(word: "pail", display: nil, points: 1),
    PangramWord(word: "place", display: nil, points: 5),
    PangramWord(word: "plaice", display: nil, points: 13),
    PangramWord(word: "epical", display: nil, points: 13),
  ],
  pangrams: ["plaice"],
  blocked: ["clip"])

func pangramPuzzleJSON(
  words: String = #"[{"word":"pace","points":1},{"word":"plaice","points":13}]"#
)
  -> String
{
  """
  {"lang":"en","kind":"pangram","n":6,"letters":["a","c","e","i","l","p"],"center":"p",
   "pangrams":["plaice"],"target_score":9,"words":\(words)}
  """
}
