import Observability
import SwiftData
import SwiftUI

/// Builds a session for a board once the view has its model context, then shows the board.
struct TilesScreen: View {
  let puzzle: TilesPuzzle
  let day: PuzzleDay

  @Environment(\.modelContext) private var context
  @Environment(\.pillars) private var pillars
  @State private var session: TilesSession?

  var body: some View {
    Group {
      if let session {
        TilesView(session: session)
      } else {
        ProgressView()
      }
    }
    .navigationTitle("Tiles · \(puzzle.n)")
    .navigationBarTitleDisplayMode(.inline)
    .onAppear {
      if session == nil {
        let observer = makeObserver("TilesSession", pillars)
        session = TilesSession(
          puzzle: puzzle, day: day, store: ProgressStore(context: context, observer: observer),
          observer: observer)
      }
    }
  }
}

struct TilesView: View {
  @Bindable var session: TilesSession

  private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)

  var body: some View {
    ScrollView {
      VStack(spacing: 20) {
        ScoreHeader(game: session.game)
        SolvedTargets(game: session.game)
        board
        controls
        FoundWords(words: session.game.found)
      }
      .padding()
    }
    .overlay(alignment: .top) {
      if let feedback = session.feedback {
        FeedbackBanner(feedback: feedback)
          .task(id: feedback.id) {
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation { session.dismissFeedback(feedback) }
          }
          .transition(.move(edge: .top).combined(with: .opacity))
      }
    }
    .animation(.default, value: session.feedback)
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
            position: session.game.selection.firstIndex(of: tile)
          ) {
            session.tap(tile)
          }
        }
      }
      .animation(.default, value: session.boardTiles)
    }
  }

  private var controls: some View {
    HStack {
      Button("Shuffle", systemImage: "shuffle") { session.shuffle() }
      Spacer()
      Button("Clear") { session.clear() }
        .disabled(session.game.selection.isEmpty)
      Button("Submit") { session.submit() }
        .buttonStyle(.borderedProminent)
        .disabled(session.game.selection.isEmpty)
    }
    .buttonStyle(.bordered)
  }
}

private struct ScoreHeader: View {
  let game: TilesGame

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
      if game.reachedTargetScore {
        Label("Target reached", systemImage: "star.fill")
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(.orange)
      }
    }
  }
}

private struct SolvedTargets: View {
  let game: TilesGame

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
                .background(.green.opacity(0.2), in: .rect(cornerRadius: 6))
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
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Text(text)
        .font(.title3.weight(.medium).monospaced())
        .frame(maxWidth: .infinity, minHeight: 56)
        .foregroundStyle(position == nil ? Color.primary : Color.white)
        .background(
          position == nil ? Color(.secondarySystemBackground) : Color.accentColor,
          in: .rect(cornerRadius: 10)
        )
        .overlay(alignment: .topTrailing) {
          if let position {
            Text("\(position + 1)")
              .font(.caption2.weight(.bold))
              .foregroundStyle(.white.opacity(0.8))
              .padding(4)
          }
        }
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(position == nil ? [] : .isSelected)
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

private struct FeedbackBanner: View {
  let feedback: TilesSession.Feedback

  var body: some View {
    Text(message)
      .font(.subheadline.weight(.semibold))
      .padding(.horizontal, 16)
      .padding(.vertical, 8)
      .background(.thinMaterial, in: .capsule)
      .padding(.top, 8)
  }

  private var message: String {
    switch feedback.kind {
    case .found(let word): "\(word.shown) +\(word.points)"
    case .alreadyFound(let word): "Already found \(word.shown)"
    case .notAWord(let text): "\(text) isn't on the list"
    case .saveFailed: "Couldn't save that word"
    case .loadFailed: "Couldn't load saved progress"
    }
  }
}
