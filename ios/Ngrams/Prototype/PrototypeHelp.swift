// PROTOTYPE: throwaway code for epic #12. Hints and solving, held in memory per puzzle screen.
// Solving plays real moves through each session, so a solved Password puzzle counts as a win
// here; the agreed rule (a loss, no star) is for the real build.

import SwiftUI

/// Hints and solving for a Password puzzle: a hint pencils one correct letter into its spot.
@Observable
final class WordHelp {
  /// Revealed letters by position.
  private(set) var hints: [Int: Character] = [:]
  private(set) var solving = false

  var used: Int { hints.count }

  /// Reveals the leftmost letter not already shown correct or hinted, or nothing when every
  /// letter is known.
  func hint(_ game: WordGame) {
    let answer = Array(game.puzzle.answer)
    var known = Set(hints.keys)
    for (guess, marks) in zip(game.guesses, game.marks) {
      for (i, (_, mark)) in zip(guess, marks).enumerated() where mark == .correct {
        known.insert(i)
      }
    }
    if let position = answer.indices.first(where: { !known.contains($0) }) {
      hints[position] = answer[position]
    }
  }

  /// Types the answer a letter at a time into the next row and submits it.
  func solve(_ session: WordSession, pace: Double) async {
    guard !session.game.isOver, !solving else {
      return
    }
    solving = true
    defer { solving = false }
    while !session.game.current.isEmpty {
      session.deleteLetter()
      try? await Task.sleep(for: .seconds(pace * 0.3))
    }
    for letter in session.game.puzzle.answer {
      session.type(letter)
      try? await Task.sleep(for: .seconds(pace))
    }
    session.submit()
  }
}

/// Hints and solving for a tiles board: a hint lights the next tile of an unfound target.
@Observable
final class TilesHelp {
  /// Tiles lit so far, by target.
  private(set) var revealed: [Int: Int] = [:]
  private(set) var used = 0
  private(set) var solving = false

  /// Tiles to ring on the board.
  func lit(_ game: TilesGame) -> Set<Int> {
    let solved = Set(game.solvedTargets)
    return Set(
      revealed.filter { !solved.contains($0.key) }
        .flatMap { target, count in game.puzzle.targets[target].prefix(count) })
  }

  /// Lights one more tile of the target already hinted, stopping a tile short of giving it away,
  /// then moves on to the next unfound target.
  func hint(_ game: TilesGame) {
    let solved = Set(game.solvedTargets)
    let unfound = game.puzzle.targets.indices.filter { !solved.contains($0) }
    let cap = game.puzzle.n - 1
    guard
      let target = unfound.first(where: { (1..<cap).contains(revealed[$0] ?? 0) })
        ?? unfound.first(where: { (revealed[$0] ?? 0) == 0 })
    else {
      return
    }
    revealed[target, default: 0] += 1
    used += 1
  }

  /// Builds each unfound target a tile at a time, so the board slides between them.
  func solve(_ session: TilesSession, pace: Double) async {
    guard !solving else {
      return
    }
    solving = true
    defer { solving = false }
    let solved = Set(session.game.solvedTargets)
    for target in session.game.puzzle.targets.indices where !solved.contains(target) {
      session.clear()
      for tile in session.game.puzzle.targets[target] {
        session.tap(tile)
        try? await Task.sleep(for: .seconds(pace))
      }
      session.submit()
      try? await Task.sleep(for: .seconds(pace * 3))
    }
  }
}

/// Hints and solving for a pangram board: a hint gives a word's first two letters and length.
@Observable
final class PangramHelp {
  private(set) var clues: [(word: String, text: String)] = []
  private(set) var solving = false

  var used: Int { clues.count }

  /// Clues still standing: the ones whose words haven't been found.
  func open(_ game: PangramGame) -> [String] {
    let found = Set(game.foundWords)
    return clues.filter { !found.contains($0.word) }.map(\.text)
  }

  /// Clues the next unfound word, pangrams first, then the highest scoring.
  func hint(_ game: PangramGame) {
    let taken = Set(game.foundWords).union(clues.map(\.word))
    guard let word = Self.order(game).first(where: { !taken.contains($0.word) }) else {
      return
    }
    let start = String(word.shown.prefix(2)).uppercased()
    clues.append((word.word, "\(start)… · \(word.word.count) letters"))
  }

  /// Spells words until the board has its star: every common pangram, then the highest scoring.
  func solve(_ session: PangramSession, pace: Double) async {
    guard !solving else {
      return
    }
    solving = true
    defer { solving = false }
    while !session.game.current.isEmpty {
      session.deleteLetter()
    }
    for word in Self.order(session.game) where !session.game.earnedStar {
      guard !session.game.foundWords.contains(word.word) else {
        continue
      }
      for letter in word.word {
        session.type(letter)
        try? await Task.sleep(for: .seconds(pace * 0.15))
      }
      session.submit()
      try? await Task.sleep(for: .seconds(pace))
    }
  }

  private static func order(_ game: PangramGame) -> [PangramWord] {
    game.puzzle.words.sorted { a, b in
      let aPangram = game.puzzle.pangrams.contains(a.word)
      let bPangram = game.puzzle.pangrams.contains(b.word)
      return aPangram != bPangram ? aPangram : (a.points, b.word) > (b.points, a.word)
    }
  }
}

/// The help button every game's toolbar gets: Hint, and Solve behind a confirmation.
struct HelpMenu: View {
  let used: Int
  let disabled: Bool
  let onHint: () -> Void
  let onSolve: () -> Void

  @State private var confirming = false

  var body: some View {
    Menu {
      Button(action: onHint) {
        Label {
          Text(verbatim: used == 0 ? "Hint" : "Hint (\(used) used)")
        } icon: {
          Image(systemName: "lightbulb")
        }
      }
      Button(role: .destructive) {
        confirming = true
      } label: {
        Label {
          Text(verbatim: "Solve…")
        } icon: {
          Image(systemName: "wand.and.stars")
        }
      }
    } label: {
      Label {
        Text(verbatim: "Help")
      } icon: {
        Image(systemName: used == 0 ? "lifepreserver" : "lifepreserver.fill")
      }
    }
    .disabled(disabled)
    .confirmationDialog(Text(verbatim: "Solve this puzzle?"), isPresented: $confirming) {
      Button(role: .destructive, action: onSolve) {
        Text(verbatim: "Solve")
      }
    } message: {
      Text(verbatim: "Solving gives up the star. A solved Password puzzle counts as a loss.")
    }
  }
}
