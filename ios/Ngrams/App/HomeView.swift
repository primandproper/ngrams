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

  var body: some View {
    NavigationStack {
      DayList(
        puzzles: bank.tilesPuzzles(on: day).filter {
          languages?.languages.contains($0.language) ?? true
        },
        day: day
      )
      .navigationTitle("N-grams")
      .navigationSubtitle(day == today ? "Today" : day.description)
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

private struct TilesRoute: Hashable {
  let puzzle: TilesPuzzle
  let day: PuzzleDay
}

/// One day's boards, a section per game and size. Starred boards leave their section for a
/// "Completed" section at the bottom.
private struct DayList: View {
  let puzzles: [TilesPuzzle]
  let day: PuzzleDay

  @Query private var progress: [PuzzleProgress]

  init(puzzles: [TilesPuzzle], day: PuzzleDay) {
    self.puzzles = puzzles
    self.day = day
    _progress = Query(filter: PuzzleProgress.matching(kind: .tiles, day: day))
  }

  var body: some View {
    let entries = Dictionary(
      progress.map { ("\($0.language)-\($0.n)", $0.entries) },
      uniquingKeysWith: { first, _ in first })
    let games = puzzles.map { TilesGame(puzzle: $0, foundWords: entries[$0.id] ?? []) }
    let open = games.filter { !$0.earnedStar }
    let completed = games.filter(\.earnedStar)

    List {
      if puzzles.isEmpty {
        Text("No puzzles for \(day.description).")
          .foregroundStyle(.secondary)
      }
      ForEach(Set(open.map(\.puzzle.n)).sorted(), id: \.self) { n in
        Section("Tiles · N=\(n)") {
          rows(open.filter { $0.puzzle.n == n }, showsSize: false)
        }
      }
      if !completed.isEmpty {
        Section("Completed") {
          rows(completed, showsSize: true)
        }
      }
    }
    .animation(.default, value: completed.map(\.puzzle.id))
  }

  private func rows(_ games: [TilesGame], showsSize: Bool) -> some View {
    ForEach(games, id: \.puzzle.id) { game in
      NavigationLink(value: TilesRoute(puzzle: game.puzzle, day: day)) {
        TilesRow(game: game, showsSize: showsSize)
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
        Text(
          showsSize
            ? "\(puzzle.language.flag) Tiles · N=\(puzzle.n)"
            : "\(puzzle.language.flag) \(puzzle.language.name)"
        )
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
