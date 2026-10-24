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

  private var day: PuzzleDay { pickedDay ?? today }

  var body: some View {
    NavigationStack {
      DayList(puzzles: bank.tilesPuzzles(on: day), day: day, isToday: day == today)
        .navigationTitle("N-grams")
        .navigationDestination(for: TilesRoute.self) { route in
          TilesScreen(puzzle: route.puzzle, day: route.day)
        }
        .sheet(isPresented: $showingSettings) {
          SettingsView()
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

/// One day's boards. Starred boards drop to a section of their own at the bottom.
private struct DayList: View {
  let puzzles: [TilesPuzzle]
  let day: PuzzleDay
  let isToday: Bool

  @Query private var progress: [PuzzleProgress]

  init(puzzles: [TilesPuzzle], day: PuzzleDay, isToday: Bool) {
    self.puzzles = puzzles
    self.day = day
    self.isToday = isToday
    _progress = Query(filter: PuzzleProgress.matching(kind: .tiles, day: day))
  }

  var body: some View {
    let entries = Dictionary(
      progress.map { ("\($0.language)-\($0.n)", $0.entries) },
      uniquingKeysWith: { first, _ in first })
    let games = puzzles.map { TilesGame(puzzle: $0, foundWords: entries[$0.id] ?? []) }
    let starred = games.filter(\.earnedStar)

    List {
      Section {
        if puzzles.isEmpty {
          Text("No puzzles for \(day.description).")
            .foregroundStyle(.secondary)
        }
        rows(games.filter { !$0.earnedStar })
      } header: {
        Text(isToday ? "Today" : day.description)
      }
      if !starred.isEmpty {
        Section("Starred") {
          rows(starred)
        }
      }
    }
    .animation(.default, value: starred.map(\.puzzle.id))
  }

  private func rows(_ games: [TilesGame]) -> some View {
    ForEach(games, id: \.puzzle.id) { game in
      NavigationLink(value: TilesRoute(puzzle: game.puzzle, day: day)) {
        TilesRow(game: game)
      }
    }
  }
}

private struct TilesRow: View {
  let game: TilesGame

  var body: some View {
    let puzzle = game.puzzle
    HStack {
      VStack(alignment: .leading) {
        Text("\(puzzle.language.flag) Tiles · \(puzzle.n)")
          .font(.headline)
        Text("\(puzzle.targets.count) targets of \(puzzle.n) tiles")
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
