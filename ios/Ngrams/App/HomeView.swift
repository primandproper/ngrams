import SwiftData
import SwiftUI

/// Every one of the day's puzzles, in every language.
struct HomeView: View {
  let bank: PuzzleBank

  @Environment(\.scenePhase) private var scenePhase
  @State private var today = PuzzleDay(containing: .now)
  /// Debug builds can step through the whole bank, so a playtest isn't limited to today.
  @State private var pickedDay: PuzzleDay?
  @State private var showingSettings = false
  @AppStorage(SettingsKey.languages) private var languages: LanguageSelection?

  private var day: PuzzleDay { pickedDay ?? today }

  private var needsLanguages: Bool {
    languages?.languages.isEmpty ?? true
  }

  private func plays(_ language: Language) -> Bool {
    languages?.languages.contains(language) ?? true
  }

  var body: some View {
    NavigationStack {
      DayList(
        words: bank.wordPuzzles(on: day).filter { plays($0.language) },
        tiles: bank.tilesPuzzles(on: day).filter { plays($0.language) },
        day: day
      )
      .navigationTitle("N-grams")
      .navigationSubtitle(day == today ? "Today" : day.description)
      .navigationDestination(for: WordRoute.self) { route in
        WordScreen(puzzle: route.puzzle, day: route.day)
      }
      .navigationDestination(for: TilesRoute.self) { route in
        TilesScreen(puzzle: route.puzzle, day: route.day)
      }
      .sheet(isPresented: $showingSettings) {
        SettingsView()
      }
      .sheet(isPresented: .constant(needsLanguages)) {
        LanguagePrompt { languages = $0 }
      }
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Settings", systemImage: "gearshape") { showingSettings = true }
        }
        #if DEBUG
          ToolbarItemGroup(placement: .bottomBar) {
            DayPicker(days: bank.days, today: today, picked: $pickedDay)
          }
        #endif
      }
    }
    .onChange(of: scenePhase) {
      if scenePhase == .active {
        today = PuzzleDay(containing: .now)
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
      today = PuzzleDay(containing: .now)
    }
  }
}

private struct WordRoute: Hashable {
  let puzzle: WordPuzzle
  let day: PuzzleDay
}

private struct TilesRoute: Hashable {
  let puzzle: TilesPuzzle
  let day: PuzzleDay
}

/// One puzzle on home, in its saved state.
private enum Entry: Identifiable {
  case word(WordGame)
  case tiles(TilesGame)

  var id: String { "\(kind.rawValue)-\(language.rawValue)-\(n)" }

  var kind: PuzzleKind {
    switch self {
    case .word: .word
    case .tiles: .tiles
    }
  }

  var language: Language {
    switch self {
    case .word(let game): game.puzzle.language
    case .tiles(let game): game.puzzle.language
    }
  }

  var n: Int {
    switch self {
    case .word(let game): game.puzzle.n
    case .tiles(let game): game.puzzle.n
    }
  }

  /// A word puzzle is done once it's over, won or lost; a tiles board once it has its star.
  var isCompleted: Bool {
    switch self {
    case .word(let game): game.isOver
    case .tiles(let game): game.earnedStar
    }
  }
}

/// One day's puzzles, a section per game and size. Completed puzzles leave their section for a
/// "Completed" section at the bottom.
private struct DayList: View {
  let words: [WordPuzzle]
  let tiles: [TilesPuzzle]
  let day: PuzzleDay

  @Query private var progress: [PuzzleProgress]

  init(words: [WordPuzzle], tiles: [TilesPuzzle], day: PuzzleDay) {
    self.words = words
    self.tiles = tiles
    self.day = day
    _progress = Query(filter: PuzzleProgress.matching(day: day))
  }

  /// Every puzzle with its saved progress, words first.
  private var all: [Entry] {
    let saved = Dictionary(
      progress.map { ("\($0.kind)-\($0.language)-\($0.n)", $0.entries) },
      uniquingKeysWith: { first, _ in first })
    func entries(_ kind: PuzzleKind, _ language: Language, _ n: Int) -> [String] {
      saved["\(kind.rawValue)-\(language.rawValue)-\(n)"] ?? []
    }
    return words.map {
      Entry.word(WordGame(puzzle: $0, guesses: entries(.word, $0.language, $0.n)))
    }
      + tiles.map {
        Entry.tiles(TilesGame(puzzle: $0, foundWords: entries(.tiles, $0.language, $0.n)))
      }
  }

  var body: some View {
    let all = self.all
    let open = all.filter { !$0.isCompleted }
    let completed = all.filter(\.isCompleted)

    List {
      if all.isEmpty {
        Text("No puzzles for \(day.description).")
          .foregroundStyle(.secondary)
      }
      ForEach(PuzzleKind.allCases, id: \.self) { kind in
        let ofKind = open.filter { $0.kind == kind }
        ForEach(Set(ofKind.map(\.n)).sorted(), id: \.self) { n in
          Section("\(kind.name) · N=\(n)") {
            rows(ofKind.filter { $0.n == n }, showsSize: false)
          }
        }
      }
      if !completed.isEmpty {
        Section("Completed") {
          rows(completed, showsSize: true)
        }
      }
    }
    .animation(.default, value: completed.map(\.id))
  }

  private func rows(_ entries: [Entry], showsSize: Bool) -> some View {
    ForEach(entries) { entry in
      switch entry {
      case .word(let game):
        NavigationLink(value: WordRoute(puzzle: game.puzzle, day: day)) {
          WordRow(game: game, showsSize: showsSize)
        }
      case .tiles(let game):
        NavigationLink(value: TilesRoute(puzzle: game.puzzle, day: day)) {
          TilesRow(game: game, showsSize: showsSize)
        }
      }
    }
  }
}

/// A row's headline: the language, or the game and size too when the section doesn't say.
private func rowTitle(_ kind: PuzzleKind, _ language: Language, _ n: Int, showsSize: Bool)
  -> String
{
  showsSize ? "\(language.flag) \(kind.name) · N=\(n)" : "\(language.flag) \(language.name)"
}

private struct WordRow: View {
  let game: WordGame
  let showsSize: Bool

  var body: some View {
    let puzzle = game.puzzle
    HStack {
      VStack(alignment: .leading) {
        Text(rowTitle(.word, puzzle.language, puzzle.n, showsSize: showsSize))
          .font(.headline)
        Text("\(puzzle.n) letters")
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
      Spacer()
      switch game.status {
      case .won(let guesses):
        Image(systemName: "star.fill")
          .foregroundStyle(.orange)
        Text("\(guesses)/\(WordGame.maxGuesses)")
          .monospacedDigit()
          .foregroundStyle(.secondary)
      case .lost:
        Text("X/\(WordGame.maxGuesses)")
          .monospacedDigit()
          .foregroundStyle(.secondary)
      case .playing:
        if !game.guesses.isEmpty {
          Text("\(game.guesses.count)/\(WordGame.maxGuesses)")
            .monospacedDigit()
            .foregroundStyle(.secondary)
        }
      }
    }
  }
}

private struct TilesRow: View {
  let game: TilesGame
  /// Whether the row names its game and size, which a size's own section already does.
  let showsSize: Bool

  var body: some View {
    let puzzle = game.puzzle
    HStack {
      VStack(alignment: .leading) {
        Text(rowTitle(.tiles, puzzle.language, puzzle.n, showsSize: showsSize))
          .font(.headline)
        Text("\(puzzle.targets.count) targets")
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
      Spacer()
      if game.earnedStar {
        Image(systemName: "star.fill")
          .foregroundStyle(.orange)
      }
      Text("\(game.score) / \(puzzle.targetScore)")
        .monospacedDigit()
        .foregroundStyle(.secondary)
    }
  }
}

#if DEBUG
  private struct DayPicker: View {
    let days: [PuzzleDay]
    let today: PuzzleDay
    @Binding var picked: PuzzleDay?

    private var current: PuzzleDay { picked ?? today }
    private var earlier: PuzzleDay? { days.last { $0 < current } }
    private var later: PuzzleDay? { days.first { $0 > current } }

    var body: some View {
      Button("Earlier", systemImage: "chevron.left") { picked = earlier }
        .disabled(earlier == nil)
      Spacer()
      Button("Today") { picked = nil }
        .disabled(picked == nil)
      Spacer()
      Button("Later", systemImage: "chevron.right") { picked = later }
        .disabled(later == nil)
    }
  }
#endif
