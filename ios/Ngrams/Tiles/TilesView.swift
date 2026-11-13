import DesignSystem
import Observability
import SwiftData
import SwiftUI

/// Builds a session for a board once the view has its model context, then shows the board.
struct TilesScreen: View {
  let puzzle: TilesPuzzle
  let day: PuzzleDay

  @Environment(\.modelContext) private var context
  @Environment(\.pillars) private var pillars
  @AppStorage(SettingsKey.hardMode(.tiles)) private var hardModes = LanguageSelection([])
  @State private var session: TilesSession?

  var body: some View {
    Group {
      if let session {
        TilesView(session: session)
      } else {
        ProgressView()
      }
    }
    .navigationTitle(
      Text(verbatim: "\(puzzle.language.flag) \(PuzzleKind.tiles.name) · \(puzzle.n)")
    )
    .navigationBarTitleDisplayMode(.inline)
    .onAppear {
      if session == nil {
        let observer = makeObserver("TilesSession", pillars)
        session = TilesSession(
          puzzle: puzzle, day: day,
          solvedTilesLeave: hardModes.languages.contains(puzzle.language),
          store: ProgressStore(context: context, observer: observer), observer: observer)
      }
    }
  }
}

struct TilesView: View {
  @Bindable var session: TilesSession

  @Environment(\.dsTheme) private var theme
  @State private var showingStats = false

  /// One column per tile in a target, so every board is a full rectangle and a solved target
  /// fills exactly one row.
  private var columns: [GridItem] {
    Array(repeating: GridItem(.flexible(), spacing: 8), count: session.game.puzzle.n)
  }

  var body: some View {
    ScrollView {
      VStack(spacing: 20) {
        ScoreHeader(game: session.game)
        if session.game.solvedTilesLeave {
          SolvedTargets(game: session.game)
        }
        board
        controls
        FoundWords(words: session.game.found)
      }
      .padding()
    }
    .onChange(of: session.finished) { wasFinished, finished in
      if !wasFinished, finished {
        Task {
          try? await Task.sleep(for: .seconds(1))
          showingStats = true
        }
      }
    }
    .sheet(isPresented: $showingStats) {
      let puzzle = session.game.puzzle
      LineStatsSheet(
        line: PuzzleLine(language: puzzle.language, kind: .tiles, n: puzzle.n),
        time: session.timer.elapsed)
    }
    .toolbar {
      if !session.game.found.isEmpty {
        ToolbarItem(placement: .topBarTrailing) {
          ShareLink(item: ShareText.tiles(session.game, on: session.key.day))
        }
      }
      if !session.game.isOver || session.solving {
        ToolbarItem(placement: .topBarTrailing) {
          HelpMenu(
            used: session.game.hints.count, canHint: session.game.nextHint != nil,
            solveWarning: "Solving gives up the star.", onHint: session.takeHint,
            onSolve: { Task { await session.solve() } }
          )
          .disabled(session.solving)
        }
      }
    }
    .overlay(alignment: .top) {
      if let feedback = session.feedback {
        FeedbackBanner(feedback: feedback)
          .task(id: feedback.id) {
            try? await Task.sleep(for: .seconds(feedback.kind.isStarNotice ? 3 : 1.5))
            withAnimation(theme.animation.normal) { session.dismissFeedback(feedback) }
          }
          .transition(.move(edge: .top).combined(with: .opacity))
      }
    }
    .animation(theme.animation.normal, value: session.feedback)
    .timed(by: session.timer)
  }

  private var board: some View {
    VStack(spacing: 12) {
      Text(session.game.selectedText.isEmpty ? " " : session.game.selectedText)
        .font(.title2.weight(.semibold).monospaced())
        .frame(maxWidth: .infinity)
        .accessibilityLabel("Current word")

      LazyVGrid(columns: columns, spacing: 8) {
        ForEach(session.boardTiles, id: \.self) { tile in
          TileButton(
            text: session.game.puzzle.tiles[tile],
            position: session.game.selection.firstIndex(of: tile),
            solved: session.game.solvedTiles.contains(tile),
            hinted: session.game.lit.contains(tile)
          ) {
            session.tap(tile)
          }
        }
      }
      .animation(theme.animation.normal, value: session.boardTiles)
      .disabled(session.solving)
    }
  }

  private var controls: some View {
    HStack {
      Button("Shuffle", systemImage: "shuffle") { session.shuffle() }
        .disabled(session.solving)
      Spacer()
      Button("Clear") { session.clear() }
        .disabled(session.game.selection.isEmpty || session.solving)
      Button("Submit") { session.submit() }
        .accessibilityIdentifier("submit")
        .buttonStyle(.borderedProminent)
        .disabled(session.game.selection.isEmpty || session.solving)
    }
    .buttonStyle(.bordered)
  }
}

private struct ScoreHeader: View {
  let game: TilesGame

  @Environment(\.dsTheme) private var theme

  var body: some View {
    VStack(spacing: 6) {
      HStack(alignment: .firstTextBaseline) {
        Text("\(game.score)")
          .font(.largeTitle.weight(.bold).monospacedDigit())
        Text("/ \(game.puzzle.targetScore)")
          .foregroundStyle(.secondary)
        Spacer()
        Text("\(game.solvedTargets.count) of \(game.puzzle.targets.count) targets")
          .foregroundStyle(.secondary)
      }
      ProgressView(value: min(Double(game.score) / Double(game.puzzle.targetScore), 1))
      if game.earnedStar {
        Label("Star earned", systemImage: "star.fill")
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(theme.colors.tertiary)
      } else if !game.hasWordsLeft {
        Text("No words left")
          .font(.subheadline)
          .foregroundStyle(.secondary)
      } else if game.targetsEarnStar {
        Text("Find every target for the star")
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
    }
  }
}

private struct SolvedTargets: View {
  let game: TilesGame

  @Environment(\.dsTheme) private var theme

  var body: some View {
    if !game.solvedTargets.isEmpty {
      VStack(spacing: 6) {
        ForEach(game.solvedTargets, id: \.self) { target in
          HStack(spacing: 4) {
            ForEach(game.puzzle.targets[target], id: \.self) { tile in
              Text(game.puzzle.tiles[tile])
                .font(.callout.monospaced())
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                  theme.colors.success.opacity(0.2), in: .rect(cornerRadius: theme.radius.sm))
            }
            Spacer()
            Text(shownWord(target))
              .font(.callout.weight(.semibold))
          }
        }
      }
    }
  }

  private func shownWord(_ target: Int) -> String {
    let folded = game.puzzle.targets[target].map { game.puzzle.tiles[$0] }.joined()
    return game.found.first { $0.word == folded }?.shown ?? folded
  }
}

private struct TileButton: View {
  let text: String
  /// Where this tile sits in the current word, if it's selected.
  let position: Int?
  let solved: Bool
  /// Whether a hint has lit this tile.
  let hinted: Bool
  let action: () -> Void

  @Environment(\.dsTheme) private var theme
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private var background: Color {
    if position != nil {
      return theme.colors.primary
    }
    return solved ? theme.colors.success.opacity(0.2) : theme.colors.cardBackground
  }

  var body: some View {
    Button(action: action) {
      Text(text)
        .font(.title3.weight(.medium).monospaced())
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .frame(maxWidth: .infinity, minHeight: 56)
        .foregroundStyle(
          position == nil ? theme.colors.textPrimary : theme.colors.textOnPrimary
        )
        .background(background, in: .rect(cornerRadius: theme.radius.lg))
        .overlay(alignment: .topTrailing) {
          if let position {
            Text("\(position + 1)")
              .font(.caption2.weight(.bold))
              .foregroundStyle(theme.colors.textOnPrimary.opacity(0.8))
              .padding(4)
          }
        }
        .overlay {
          if hinted, position == nil {
            RoundedRectangle(cornerRadius: theme.radius.lg)
              .strokeBorder(theme.colors.tertiary, style: StrokeStyle(lineWidth: 3, dash: [6, 4]))
              .phaseAnimator([0.4, 1.0]) { ring, opacity in
                ring.opacity(reduceMotion ? 1 : opacity)
              } animation: { _ in
                .easeInOut(duration: 0.7)
              }
          }
        }
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(position == nil ? [] : .isSelected)
    .accessibilityHint(hinted ? Text("Hinted") : Text(verbatim: ""))
  }
}

private struct FoundWords: View {
  let words: [TilesWord]

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("\(words.count) found")
        .font(.headline)
      LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), alignment: .leading)], spacing: 6) {
        ForEach(words.reversed(), id: \.word) { word in
          HStack(spacing: 4) {
            Text(word.shown)
            Text("\(word.points)")
              .font(.caption2)
              .foregroundStyle(.secondary)
          }
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

extension TilesSession.Feedback.Kind {
  /// Whether this feedback also says the targets left would earn the star.
  var isStarNotice: Bool {
    if case .found(_, targetsEarnStar: true) = self {
      return true
    }
    return false
  }
}

private struct FeedbackBanner: View {
  let feedback: TilesSession.Feedback

  var body: some View {
    VStack(spacing: 2) {
      Text(message)
      if feedback.kind.isStarNotice {
        Text("Every target now earns the star")
      }
    }
    .font(.subheadline.weight(.semibold))
    .multilineTextAlignment(.center)
    .padding(.horizontal, 16)
    .padding(.vertical, 8)
    .background(.thinMaterial, in: .capsule)
    .padding(.top, 8)
  }

  private var message: String {
    switch feedback.kind {
    case .found(let word, _): "\(word.shown) +\(word.points)"
    case .helpSaveFailed: String(localized: "Couldn't save your progress")
    case .alreadyFound(let word): String(localized: "Already found \(word.shown)")
    case .blocked: String(localized: "How dare you")
    case .notAWord(let text): String(localized: "\(text) isn't on the list")
    case .saveFailed: String(localized: "Couldn't save that word")
    case .loadFailed: String(localized: "Couldn't load saved progress")
    }
  }
}
