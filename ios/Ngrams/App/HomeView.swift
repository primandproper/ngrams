import SwiftData
import SwiftUI

/// Today's puzzles in the chosen language.
struct HomeView: View {
  let bank: PuzzleBank

  @AppStorage("language") private var language = Language.en
  @Environment(\.scenePhase) private var scenePhase
  @State private var today = PuzzleDay(containing: .now)
  /// Debug builds can step through the whole bank, so a playtest isn't limited to today.
  @State private var pickedDay: PuzzleDay?
  @State private var showingSettings = false

  private var day: PuzzleDay { pickedDay ?? today }

  var body: some View {
    NavigationStack {
      List {
        Section {
          let puzzles = bank.tilesPuzzles(on: day, in: language)
          if puzzles.isEmpty {
            Text("No puzzles for \(day.description).")
              .foregroundStyle(.secondary)
          }
          ForEach(puzzles) { puzzle in
            NavigationLink(value: TilesRoute(puzzle: puzzle, day: day)) {
              TilesRow(puzzle: puzzle, day: day)
            }
          }
        } header: {
          Text(day == today ? "Today" : day.description)
        }
      }
      .navigationTitle("N-grams")
      .navigationDestination(for: TilesRoute.self) { route in
        TilesScreen(puzzle: route.puzzle, day: route.day)
      }
      .sheet(isPresented: $showingSettings) {
        SettingsView()
      }
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button("Settings", systemImage: "gearshape") { showingSettings = true }
        }
        ToolbarItem(placement: .topBarTrailing) {
          Picker("Language", selection: $language) {
            ForEach(Language.allCases, id: \.self) { language in
              Text(language.name).tag(language)
            }
          }
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

private struct TilesRow: View {
  let puzzle: TilesPuzzle

  @Query private var progress: [PuzzleProgress]

  init(puzzle: TilesPuzzle, day: PuzzleDay) {
    self.puzzle = puzzle
    let key = ProgressKey(language: puzzle.language, kind: .tiles, n: puzzle.n, day: day)
    _progress = Query(filter: PuzzleProgress.matching(key))
  }

  var body: some View {
    let game = TilesGame(puzzle: puzzle, foundWords: progress.first?.entries ?? [])
    HStack {
      VStack(alignment: .leading) {
        Text("Tiles · \(puzzle.n)")
          .font(.headline)
        Text("\(puzzle.targets.count) targets of \(puzzle.n) tiles")
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
      Spacer()
      if game.reachedTargetScore {
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
