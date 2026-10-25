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
        LetterWheel(
          center: session.game.puzzle.center, outer: session.outer, onLetter: session.type)
        controls
        FoundWords(game: session.game)
      }
      .padding()
    }
    .toolbar {
      if !session.game.found.isEmpty {
        ToolbarItem(placement: .topBarTrailing) {
          ShareLink(item: ShareText.pangram(session.game, on: session.key.day))
        }
      }
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
    HStack(spacing: 12) {
      Button {
        session.deleteLetter()
      } label: {
        Label("Delete", systemImage: "delete.left")
          .frame(maxWidth: .infinity)
      }
      .disabled(session.game.current.isEmpty)
      Button("Shuffle", systemImage: "shuffle") {
        withAnimation { session.shuffle() }
      }
      .labelStyle(.iconOnly)
      .buttonBorderShape(.circle)
      Button {
        session.submit()
      } label: {
        Text("Enter")
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(.borderedProminent)
      .disabled(session.game.current.isEmpty)
    }
    .buttonStyle(.bordered)
    .controlSize(.extraLarge)
    .font(.title3.weight(.semibold))
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

/// The center letter in a circle, ringed by a wheel cut into a wedge per other letter, so every
/// board size gets the same shape.
private struct LetterWheel: View {
  let center: Character
  let outer: [Character]
  let onLetter: (Character) -> Void

  static let centerRadius: CGFloat = 46
  static let ringWidth: CGFloat = 90
  static let gap: CGFloat = 6
  static let radius = centerRadius + gap + ringWidth

  var body: some View {
    let span = Angle.degrees(360 / Double(max(outer.count, 1)))
    ZStack {
      ForEach(Array(outer.enumerated()), id: \.element) { index, letter in
        WedgeKey(letter: letter, span: span, rotation: span * Double(index)) { onLetter(letter) }
      }
      Button {
        onLetter(center)
      } label: {
        Text(String(center).uppercased())
          .font(.title.weight(.bold))
          .foregroundStyle(.white)
          .frame(width: 2 * Self.centerRadius, height: 2 * Self.centerRadius)
          .background(Color.accentColor, in: .circle)
          .contentShape(.circle)
      }
      .buttonStyle(.plain)
      .accessibilityLabel("\(String(center).uppercased()), center")
    }
    .frame(width: 2 * Self.radius, height: 2 * Self.radius)
  }

  /// A wedge drawn pointing up and turned into place, so shuffling swings it around the ring.
  /// The letter turns back the other way to stay upright.
  private struct WedgeKey: View {
    let letter: Character
    let span: Angle
    let rotation: Angle
    let action: () -> Void

    var body: some View {
      let wedge = Wedge(
        span: span, inner: LetterWheel.centerRadius + LetterWheel.gap, outer: LetterWheel.radius,
        gap: LetterWheel.gap)
      Button(action: action) {
        wedge
          .fill(Color(.secondarySystemBackground))
          .overlay {
            Text(String(letter).uppercased())
              .font(.title.weight(.bold))
              .foregroundStyle(.primary)
              .rotationEffect(-rotation)
              .offset(y: -(LetterWheel.radius - LetterWheel.ringWidth / 2))
          }
          .contentShape([.interaction, .accessibility], wedge)
      }
      .buttonStyle(.plain)
      .rotationEffect(rotation)
      .accessibilityLabel(String(letter).uppercased())
    }
  }
}

/// One wedge of a ring centered in its rect, pointing up and `span` wide. Its straight sides are
/// inset by half of `gap`, so neighboring wedges sit `gap` apart along their whole length.
nonisolated private struct Wedge: Shape {
  let span: Angle
  let inner: CGFloat
  let outer: CGFloat
  let gap: CGFloat

  func path(in rect: CGRect) -> Path {
    let center = CGPoint(x: rect.midX, y: rect.midY)
    let start = -Double.pi / 2 - span.radians / 2
    let end = start + span.radians
    func inset(_ radius: CGFloat) -> Double { asin(gap / 2 / radius) }
    return Path { path in
      path.addArc(
        center: center, radius: outer, startAngle: .radians(start + inset(outer)),
        endAngle: .radians(end - inset(outer)), clockwise: false)
      path.addArc(
        center: center, radius: inner, startAngle: .radians(end - inset(inner)),
        endAngle: .radians(start + inset(inner)), clockwise: true)
      path.closeSubpath()
    }
  }
}

private struct FoundWords: View {
  let game: PangramGame

  @AppStorage(SettingsKey.pangramFoundOrder) private var order = FoundWordOrder.alphabetical

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text("\(game.found.count) found")
          .font(.headline)
        Spacer()
        Button {
          withAnimation { order = order == .alphabetical ? .recent : .alphabetical }
        } label: {
          Image(systemName: order == .alphabetical ? "textformat.abc" : "clock")
            .frame(minWidth: 44, minHeight: 44)
        }
        .accessibilityLabel(order == .alphabetical ? "Sorted A to Z" : "Sorted newest first")
        .accessibilityHint("Changes how found words are sorted")
      }
      LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), alignment: .leading)], spacing: 6) {
        ForEach(game.found(sortedBy: order), id: \.word) { word in
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
