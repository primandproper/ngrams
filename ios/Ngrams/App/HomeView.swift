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
  @AppStorage(SettingsKey.homeGrouping) private var grouping = HomeGrouping.game

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
        pangrams: bank.pangramPuzzles(on: day).filter { plays($0.language) },
        day: day,
        grouping: grouping
      )
      .navigationTitle("N-grams")
      .navigationSubtitle(day == today ? "Today" : day.description)
      .navigationDestination(for: WordRoute.self) { route in
        WordScreen(puzzle: route.puzzle, day: route.day)
      }
      .navigationDestination(for: TilesRoute.self) { route in
        TilesScreen(puzzle: route.puzzle, day: route.day)
      }
      .navigationDestination(for: PangramRoute.self) { route in
        PangramScreen(puzzle: route.puzzle, day: route.day)
      }
      .sheet(isPresented: $showingSettings) {
        SettingsView()
      }
      .sheet(isPresented: .constant(needsLanguages)) {
        LanguagePrompt { languages = $0 }
      }
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Menu("Group by", systemImage: "list.bullet.indent") {
            Section("Group by") {
              Picker("Group by", selection: $grouping) {
                ForEach(HomeGrouping.allCases, id: \.self) { Text($0.name) }
              }
            }
          }
        }
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

/// How home sections the day's open puzzles. By N puts every game's puzzles of one size together,
/// though N counts tiles in one game and letters in the others.
enum HomeGrouping: String, CaseIterable {
  case game
  case n

  var name: String {
    switch self {
    case .game: "Game"
    case .n: "N"
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

private struct PangramRoute: Hashable {
  let puzzle: PangramPuzzle
  let day: PuzzleDay
}

/// One puzzle on home, in its saved state.
private enum Entry: Identifiable {
  case word(WordGame)
  case tiles(TilesGame)
  case pangram(PangramGame)

  var id: String { "\(kind.rawValue)-\(language.rawValue)-\(n)" }

  var kind: PuzzleKind {
    switch self {
    case .word: .word
    case .tiles: .tiles
    case .pangram: .pangram
    }
  }

  var language: Language {
    switch self {
    case .word(let game): game.puzzle.language
    case .tiles(let game): game.puzzle.language
    case .pangram(let game): game.puzzle.language
    }
  }

  var n: Int {
    switch self {
    case .word(let game): game.puzzle.n
    case .tiles(let game): game.puzzle.n
    case .pangram(let game): game.puzzle.n
    }
  }

  /// A word puzzle is done once it's over, won or lost; a board once it has its star.
  var isCompleted: Bool {
    switch self {
    case .word(let game): game.isOver
    case .tiles(let game): game.earnedStar
    case .pangram(let game): game.earnedStar
    }
  }

  /// By game: game, then language, then size. By N: size, then game, then language. Games and
  /// languages go in `allCases` order.
  func precedes(_ other: Entry, groupedBy grouping: HomeGrouping) -> Bool {
    func key(_ entry: Entry) -> (Int, Int, Int) {
      let kind = PuzzleKind.allCases.firstIndex(of: entry.kind) ?? 0
      let language = Language.allCases.firstIndex(of: entry.language) ?? 0
      return switch grouping {
      case .game: (kind, language, entry.n)
      case .n: (entry.n, kind, language)
      }
    }
    return key(self) < key(other)
  }
}

/// One day's puzzles, a section per game or per N. By game, each language gets its own group
/// within the section when more than one is on. Completed puzzles leave their section for a
/// "Completed" section at the bottom.
private struct DayList: View {
  let words: [WordPuzzle]
  let tiles: [TilesPuzzle]
  let pangrams: [PangramPuzzle]
  let day: PuzzleDay
  let grouping: HomeGrouping

  @Query private var progress: [PuzzleProgress]

  init(
    words: [WordPuzzle], tiles: [TilesPuzzle], pangrams: [PangramPuzzle], day: PuzzleDay,
    grouping: HomeGrouping
  ) {
    self.words = words
    self.tiles = tiles
    self.pangrams = pangrams
    self.day = day
    self.grouping = grouping
    _progress = Query(filter: PuzzleProgress.matching(day: day))
  }

  /// Every puzzle with its saved progress, in the grouping's order.
  private var all: [Entry] {
    let saved = Dictionary(
      progress.map { ("\($0.kind)-\($0.language)-\($0.n)", $0.entries) },
      uniquingKeysWith: { first, _ in first })
    func entries(_ kind: PuzzleKind, _ language: Language, _ n: Int) -> [String] {
      saved["\(kind.rawValue)-\(language.rawValue)-\(n)"] ?? []
    }
    let all =
      words.map {
        Entry.word(WordGame(puzzle: $0, guesses: entries(.word, $0.language, $0.n)))
      }
      + tiles.map {
        Entry.tiles(TilesGame(puzzle: $0, foundWords: entries(.tiles, $0.language, $0.n)))
      }
      + pangrams.map {
        Entry.pangram(PangramGame(puzzle: $0, foundWords: entries(.pangram, $0.language, $0.n)))
      }
    return all.sorted { $0.precedes($1, groupedBy: grouping) }
  }

  var body: some View {
    let all = self.all
    let open = all.filter { !$0.isCompleted }
    let completed = all.filter(\.isCompleted)
    let multilingual = Set(all.map(\.language)).count > 1

    List {
      if all.isEmpty {
        Text("No puzzles for \(day.description).")
          .foregroundStyle(.secondary)
      }
      switch grouping {
      case .game:
        ForEach(PuzzleKind.allCases, id: \.self) { kind in
          let ofKind = open.filter { $0.kind == kind }
          if !ofKind.isEmpty {
            Section(kind.name) {
              if multilingual {
                ForEach(
                  Language.allCases.filter { l in ofKind.contains { $0.language == l } }, id: \.self
                ) {
                  language in
                  Text("\(language.flag) \(language.name)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                  rows(
                    ofKind.filter { $0.language == language },
                    labeled: RowLabeling(section: .game, showsFlag: false)
                  )
                  .padding(.leading)
                }
              } else {
                rows(ofKind, labeled: RowLabeling(section: .game, showsFlag: false))
              }
            }
          }
        }
      case .n:
        ForEach(Set(open.map(\.n)).sorted(), id: \.self) { n in
          Section("N=\(n)") {
            rows(
              open.filter { $0.n == n }, labeled: RowLabeling(section: .n, showsFlag: multilingual))
          }
        }
      }
      if !completed.isEmpty {
        Section("Completed") {
          rows(completed, labeled: RowLabeling(section: nil, showsFlag: multilingual))
        }
      }
    }
    .animation(.default, value: completed.map(\.id))
    .animation(.default, value: grouping)
  }

  private func rows(_ entries: [Entry], labeled labeling: RowLabeling) -> some View {
    ForEach(entries) { entry in
      switch entry {
      case .word(let game):
        NavigationLink(value: WordRoute(puzzle: game.puzzle, day: day)) {
          WordRow(game: game, labeling: labeling)
        }
      case .tiles(let game):
        NavigationLink(value: TilesRoute(puzzle: game.puzzle, day: day)) {
          TilesRow(game: game, labeling: labeling)
        }
      case .pangram(let game):
        NavigationLink(value: PangramRoute(puzzle: game.puzzle, day: day)) {
          PangramRow(game: game, labeling: labeling)
        }
      }
    }
  }
}

/// What a row's headline says beyond its section header.
private struct RowLabeling {
  /// The grouping whose section the row sits in, or nil in Completed.
  let section: HomeGrouping?
  /// Whether the headline leads with the language's flag: only when more than one language is
  /// on, and not under a language's own group.
  let showsFlag: Bool

  /// Whichever of the game and N the section header doesn't already say.
  func title(_ kind: PuzzleKind, _ language: Language, _ n: Int) -> String {
    let title =
      switch section {
      case .game: "N=\(n)"
      case .n: kind.name
      case nil: "\(kind.name) · N=\(n)"
      }
    return showsFlag ? "\(language.flag) \(title)" : title
  }
}

private struct WordRow: View {
  let game: WordGame
  let labeling: RowLabeling

  var body: some View {
    let puzzle = game.puzzle
    HStack {
      VStack(alignment: .leading) {
        Text(labeling.title(.word, puzzle.language, puzzle.n))
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

private struct PangramRow: View {
  let game: PangramGame
  let labeling: RowLabeling

  var body: some View {
    let puzzle = game.puzzle
    HStack {
      VStack(alignment: .leading) {
        Text(labeling.title(.pangram, puzzle.language, puzzle.n))
          .font(.headline)
        Text("\(puzzle.n) letters")
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

private struct TilesRow: View {
  let game: TilesGame
  let labeling: RowLabeling

  var body: some View {
    let puzzle = game.puzzle
    HStack {
      VStack(alignment: .leading) {
        Text(labeling.title(.tiles, puzzle.language, puzzle.n))
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
