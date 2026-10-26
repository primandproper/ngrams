import SwiftData
import SwiftUI

/// Every one of the day's puzzles, in every language.
struct HomeView: View {
  let bank: PuzzleBank

  @Environment(\.scenePhase) private var scenePhase
  @State private var today = PuzzleDay.today
  /// An earlier day the player went back to, or nil for today.
  @State private var pickedDay: PuzzleDay?
  @State private var choosingDay = false
  @State private var showingSettings = false
  @State private var showingStats = false
  /// Every saved puzzle, for the streaks on each row.
  @Query private var allProgress: [PuzzleProgress]
  @AppStorage(SettingsKey.languages) private var languages: LanguageSelection?
  @AppStorage(SettingsKey.homeGrouping) private var grouping = HomeGrouping.game

  private var day: PuzzleDay { pickedDay ?? today }

  /// The days a player can open: today and every day before it. Debug builds open the days ahead
  /// too, so a playtest isn't limited to what's out.
  private var days: [PuzzleDay] {
    #if DEBUG
      bank.days
    #else
      bank.days.filter { $0 <= today }
    #endif
  }

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
        grouping: grouping,
        streaks: StatsBook.current(allProgress, bank: bank).mapValues(\.currentStreak)
      )
      .navigationTitle("n-grams")
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
      .sheet(isPresented: $showingStats) {
        StatsView(bank: bank)
      }
      .sheet(isPresented: $choosingDay) {
        DayCalendar(days: days, today: today, picked: $pickedDay)
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
        ToolbarItem(placement: .topBarLeading) {
          Button("Stats", systemImage: "chart.bar") { showingStats = true }
        }
        ToolbarItemGroup(placement: .bottomBar) {
          DayPicker(days: days, today: today, picked: $pickedDay, choosing: $choosingDay)
        }
      }
    }
    .onChange(of: scenePhase) {
      if scenePhase == .active {
        today = PuzzleDay.today
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
      today = PuzzleDay.today
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
    case .n: "n"
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

  var line: PuzzleLine { PuzzleLine(language: language, kind: kind, n: n) }

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
  /// Each line's current streak, as of today rather than the day shown.
  let streaks: [PuzzleLine: Int]

  @Query private var progress: [PuzzleProgress]
  @AppStorage(SettingsKey.hardMode(.tiles)) private var tilesHardModes = LanguageSelection([])

  init(
    words: [WordPuzzle], tiles: [TilesPuzzle], pangrams: [PangramPuzzle], day: PuzzleDay,
    grouping: HomeGrouping, streaks: [PuzzleLine: Int]
  ) {
    self.words = words
    self.tiles = tiles
    self.pangrams = pangrams
    self.day = day
    self.grouping = grouping
    self.streaks = streaks
    _progress = Query(filter: PuzzleProgress.matching(day: day))
  }

  /// Every puzzle with its saved progress, in the grouping's order.
  private var all: [Entry] {
    let byKey = Dictionary(
      progress.map { ("\($0.kind)-\($0.language)-\($0.n)", $0) },
      uniquingKeysWith: { first, _ in first })
    func saved(_ kind: PuzzleKind, _ language: Language, _ n: Int) -> PuzzleProgress? {
      byKey["\(kind.rawValue)-\(language.rawValue)-\(n)"]
    }
    let wordEntries: [Entry] = words.map { puzzle in
      let record = saved(.word, puzzle.language, puzzle.n)
      return .word(
        WordGame(
          puzzle: puzzle, guesses: record?.entries ?? [], hardMode: record?.hardMode ?? false))
    }
    let tilesEntries: [Entry] = tiles.map { puzzle in
      .tiles(
        TilesGame(
          puzzle: puzzle, foundWords: saved(.tiles, puzzle.language, puzzle.n)?.entries ?? [],
          solvedTilesLeave: tilesHardModes.languages.contains(puzzle.language)))
    }
    let pangramEntries: [Entry] = pangrams.map { puzzle in
      let record = saved(.pangram, puzzle.language, puzzle.n)
      return .pangram(
        PangramGame(
          puzzle: puzzle, foundWords: record?.entries ?? [], hardMode: record?.hardMode ?? false))
    }
    let all = wordEntries + tilesEntries + pangramEntries
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
          Section("n=\(n)") {
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
    .toolbar {
      if let text = shareText(all) {
        ToolbarItem(placement: .topBarTrailing) {
          ShareLink(item: text)
        }
      }
    }
  }

  private func shareText(_ entries: [Entry]) -> String? {
    var words: [WordGame] = []
    var tiles: [TilesGame] = []
    var pangrams: [PangramGame] = []
    for entry in entries {
      switch entry {
      case .word(let game): words.append(game)
      case .tiles(let game): tiles.append(game)
      case .pangram(let game): pangrams.append(game)
      }
    }
    return ShareText.day(words: words, tiles: tiles, pangrams: pangrams, on: day)
  }

  private func rows(_ entries: [Entry], labeled labeling: RowLabeling) -> some View {
    ForEach(entries) { entry in
      Group {
        switch entry {
        case .word(let game):
          NavigationLink(value: WordRoute(puzzle: game.puzzle, day: day)) {
            WordRow(game: game, labeling: labeling, streak: streaks[entry.line] ?? 0)
          }
        case .tiles(let game):
          NavigationLink(value: TilesRoute(puzzle: game.puzzle, day: day)) {
            TilesRow(game: game, labeling: labeling, streak: streaks[entry.line] ?? 0)
          }
        case .pangram(let game):
          NavigationLink(value: PangramRoute(puzzle: game.puzzle, day: day)) {
            PangramRow(game: game, labeling: labeling, streak: streaks[entry.line] ?? 0)
          }
        }
      }
      // The screenshot test finds rows by this, since their titles repeat across sections.
      .accessibilityIdentifier(entry.id)
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
      case .game: "n=\(n)"
      case .n: kind.name
      case nil: "\(kind.name) · n=\(n)"
      }
    return showsFlag ? "\(language.flag) \(title)" : title
  }
}

private struct WordRow: View {
  let game: WordGame
  let labeling: RowLabeling
  let streak: Int

  var body: some View {
    let puzzle = game.puzzle
    HStack {
      VStack(alignment: .leading) {
        Text(labeling.title(.word, puzzle.language, puzzle.n))
          .font(.headline)
        HStack(spacing: 8) {
          Text("\(puzzle.n) letters")
            .foregroundStyle(.secondary)
          StreakBadge(streak: streak)
        }
        .font(.subheadline)
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
  let streak: Int

  var body: some View {
    let puzzle = game.puzzle
    HStack {
      VStack(alignment: .leading) {
        Text(labeling.title(.pangram, puzzle.language, puzzle.n))
          .font(.headline)
        HStack(spacing: 8) {
          Text("\(puzzle.n) letters")
            .foregroundStyle(.secondary)
          StreakBadge(streak: streak)
        }
        .font(.subheadline)
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
  let streak: Int

  var body: some View {
    let puzzle = game.puzzle
    HStack {
      VStack(alignment: .leading) {
        Text(labeling.title(.tiles, puzzle.language, puzzle.n))
          .font(.headline)
        HStack(spacing: 8) {
          Text("\(puzzle.targets.count) targets")
            .foregroundStyle(.secondary)
          StreakBadge(streak: streak)
        }
        .font(.subheadline)
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

/// Today's day stored as nil, so the list follows the date when midnight passes.
private func pick(_ day: PuzzleDay?, today: PuzzleDay) -> PuzzleDay? {
  day == today ? nil : day
}

/// Steps a day at a time, with the day shown between the arrows opening a calendar.
private struct DayPicker: View {
  let days: [PuzzleDay]
  let today: PuzzleDay
  @Binding var picked: PuzzleDay?
  @Binding var choosing: Bool

  private var current: PuzzleDay { picked ?? today }
  private var earlier: PuzzleDay? { days.last { $0 < current } }
  private var later: PuzzleDay? { days.first { $0 > current } }

  private var title: String {
    current == today ? "Today" : current.name(includingYear: current.year != today.year)
  }

  var body: some View {
    Button("Earlier", systemImage: "chevron.left") { picked = pick(earlier, today: today) }
      .disabled(earlier == nil)
    Spacer()
    // A bar button with an icon shows only the icon, so the label is drawn by hand.
    Button {
      choosing = true
    } label: {
      HStack(spacing: 6) {
        Image(systemName: "calendar")
        Text(title)
      }
    }
    .accessibilityLabel("Choose a day, \(title)")
    Spacer()
    Button("Later", systemImage: "chevron.right") { picked = pick(later, today: today) }
      .disabled(later == nil)
  }
}

/// A month calendar of the days a player can open. Choosing one closes it.
private struct DayCalendar: View {
  let days: [PuzzleDay]
  let today: PuzzleDay
  @Binding var picked: PuzzleDay?

  @Environment(\.dismiss) private var dismiss

  private var range: ClosedRange<Date> {
    guard let first = days.first?.start(), let last = days.last?.start() else {
      return Date.now...Date.now
    }
    return first...last
  }

  private var selection: Binding<Date> {
    Binding(
      get: { (picked ?? today).start() ?? .now },
      set: {
        picked = pick(PuzzleDay(containing: $0), today: today)
        dismiss()
      })
  }

  var body: some View {
    NavigationStack {
      DatePicker("Day", selection: selection, in: range, displayedComponents: .date)
        .datePickerStyle(.graphical)
        .padding(.horizontal)
        .navigationTitle("Choose a day")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .topBarLeading) {
            Button("Today") {
              picked = nil
              dismiss()
            }
            .disabled(picked == nil)
          }
          ToolbarItem(placement: .confirmationAction) {
            Button("Done") { dismiss() }
          }
        }
    }
    .presentationDetents([.medium, .large])
  }
}
