import Observability
import SwiftData
import SwiftUI

/// Builds a session for a board once the view has its model context, then shows the board.
struct PangramScreen: View {
  let puzzle: PangramPuzzle
  let day: PuzzleDay

  @Environment(\.modelContext) private var context
  @Environment(\.pillars) private var pillars
  @AppStorage(SettingsKey.pangramHardMode) private var hardMode = false
  @State private var session: PangramSession?

  var body: some View {
    Group {
      if let session {
        PangramView(session: session)
      } else {
        ProgressView()
      }
    }
    .navigationTitle("\(puzzle.language.flag) Pangram · \(puzzle.n)")
    .navigationBarTitleDisplayMode(.inline)
    .onAppear {
      if session == nil {
        let observer = makeObserver("PangramSession", pillars)
        session = PangramSession(
          puzzle: puzzle, day: day, hardMode: hardMode,
          store: ProgressStore(context: context, observer: observer),
          observer: observer)
      }
    }
  }
}

struct PangramView: View {
  @Bindable var session: PangramSession

  var body: some View {
    ScrollView {
      VStack(spacing: 20) {
        ScoreHeader(game: session.game)
        CurrentWord(game: session.game)
        Hive(center: session.game.puzzle.center, outer: session.outer, onLetter: session.type)
        controls
        FoundWords(game: session.game)
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

  private var controls: some View {
    HStack {
      Button("Delete", systemImage: "delete.left") { session.deleteLetter() }
        .disabled(session.game.current.isEmpty)
      Spacer()
      Button("Shuffle", systemImage: "shuffle") {
        withAnimation { session.shuffle() }
      }
      .labelStyle(.iconOnly)
      Spacer()
      Button("Enter") { session.submit() }
        .buttonStyle(.borderedProminent)
        .disabled(session.game.current.isEmpty)
    }
    .buttonStyle(.bordered)
  }
}

private struct ScoreHeader: View {
  let game: PangramGame

  var body: some View {
    VStack(spacing: 6) {
      HStack(alignment: .firstTextBaseline) {
        Text("\(game.score)")
          .font(.largeTitle.weight(.bold).monospacedDigit())
        Text("/ \(game.puzzle.targetScore)")
          .foregroundStyle(.secondary)
        Spacer()
        Text(
          game.puzzle.pangrams.count == 1
            ? "\(game.foundPangrams) of 1 pangram"
            : "\(game.foundPangrams) of \(game.puzzle.pangrams.count) pangrams"
        )
        .foregroundStyle(.secondary)
      }
      ProgressView(value: min(Double(game.score) / Double(max(game.puzzle.targetScore, 1)), 1))
      if game.earnedStar {
        Label("Star earned", systemImage: "star.fill")
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(.orange)
      } else if game.score >= game.puzzle.targetScore {
        Text("Find every pangram for the star")
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
    }
  }
}

private struct CurrentWord: View {
  let game: PangramGame

  var body: some View {
    var text = AttributedString()
    for letter in game.current {
      var run = AttributedString(String(letter).uppercased())
      run.foregroundColor = letter == game.puzzle.center ? .accentColor : .primary
      text += run
    }
    return Text(game.current.isEmpty ? AttributedString(" ") : text)
      .font(.title.weight(.semibold))
      .lineLimit(1)
      .minimumScaleFactor(0.5)
      .frame(maxWidth: .infinity)
      .accessibilityLabel("Current word")
      .accessibilityValue(game.current)
  }
}

/// The center letter ringed by the others. Six outer letters tile as a honeycomb; five or
/// seven sit on the same ring, spaced so they don't overlap.
private struct Hive: View {
  let center: Character
  let outer: [Character]
  let onLetter: (Character) -> Void

  private static let width: CGFloat = 92
  private static let height = width * 3.squareRoot() / 2
  private static let gap: CGFloat = 6

  private var radius: CGFloat {
    let spacing = Self.height + Self.gap
    guard outer.count > 1 else {
      return spacing
    }
    return max(spacing, spacing / (2 * sin(.pi / CGFloat(outer.count))))
  }

  var body: some View {
    let radius = self.radius
    let side = 2 * radius + Self.width
    ZStack {
      HexKey(letter: center, isCenter: true) { onLetter(center) }
      ForEach(Array(outer.enumerated()), id: \.element) { index, letter in
        let angle = -CGFloat.pi / 2 + 2 * .pi * CGFloat(index) / CGFloat(outer.count)
        HexKey(letter: letter, isCenter: false) { onLetter(letter) }
          .offset(x: radius * cos(angle), y: radius * sin(angle))
      }
    }
    .frame(width: Self.width, height: Self.height)
    .frame(width: side, height: side)
  }

  private struct HexKey: View {
    let letter: Character
    let isCenter: Bool
    let action: () -> Void

    var body: some View {
      Button(action: action) {
        Text(String(letter).uppercased())
          .font(.title.weight(.bold))
          .foregroundStyle(isCenter ? Color.white : Color.primary)
          .frame(width: Hive.width, height: Hive.height)
          .background(
            isCenter ? Color.accentColor : Color(.secondarySystemBackground), in: Hexagon()
          )
          .contentShape(Hexagon())
      }
      .buttonStyle(.plain)
      .accessibilityLabel(
        isCenter ? "\(String(letter).uppercased()), center" : String(letter).uppercased())
    }
  }
}

/// A flat-topped hexagon filling its rect.
nonisolated private struct Hexagon: Shape {
  func path(in rect: CGRect) -> Path {
    Path { path in
      path.move(to: CGPoint(x: rect.minX, y: rect.midY))
      path.addLine(to: CGPoint(x: rect.minX + rect.width / 4, y: rect.minY))
      path.addLine(to: CGPoint(x: rect.maxX - rect.width / 4, y: rect.minY))
      path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
      path.addLine(to: CGPoint(x: rect.maxX - rect.width / 4, y: rect.maxY))
      path.addLine(to: CGPoint(x: rect.minX + rect.width / 4, y: rect.maxY))
      path.closeSubpath()
    }
  }
}

private struct FoundWords: View {
  let game: PangramGame

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("\(game.found.count) found")
        .font(.headline)
      LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), alignment: .leading)], spacing: 6) {
        ForEach(game.found.sorted { $0.word < $1.word }, id: \.word) { word in
          HStack(spacing: 4) {
            Text(word.shown)
              .fontWeight(game.puzzle.isPangram(word.word) ? .bold : .regular)
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
  let feedback: PangramSession.Feedback

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
    case .found(let word, let pangram):
      pangram ? "Pangram! \(word.shown) +\(word.points)" : "\(word.shown) +\(word.points)"
    case .alreadyFound(let word): "Already found \(word.shown)"
    case .tooShort: "Too short"
    case .missingCenter: "Missing the center letter"
    case .blocked: "How dare you"
    case .notAWord(let text): "\(text.uppercased()) isn't on the list"
    case .needsPangram: "Start with a pangram"
    case .saveFailed: "Couldn't save that word"
    case .loadFailed: "Couldn't load saved progress"
    }
  }
}
