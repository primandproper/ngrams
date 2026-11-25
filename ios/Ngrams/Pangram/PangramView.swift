import DesignSystem
import Observability
import SwiftData
import SwiftUI

/// Builds a session for a board once the view has its model context, then shows the board.
struct PangramScreen: View {
  let puzzle: PangramPuzzle
  let day: PuzzleDay

  @Environment(\.modelContext) private var context
  @Environment(\.pillars) private var pillars
  @AppStorage(SettingsKey.hardMode(.pangram)) private var hardModes = LanguageSelection([])
  @AppStorage(SettingsKey.curseWords) private var curseWords = false
  @State private var session: PangramSession?

  var body: some View {
    Group {
      if let session {
        PangramView(session: session)
      } else {
        ProgressView()
      }
    }
    .navigationTitle(
      Text(verbatim: "\(puzzle.language.flag) \(PuzzleKind.pangram.name) · \(puzzle.n)")
    )
    .navigationBarTitleDisplayMode(.inline)
    .onAppear {
      if session == nil {
        let observer = makeObserver("PangramSession", pillars)
        session = PangramSession(
          puzzle: puzzle, day: day, hardMode: hardModes.languages.contains(puzzle.language),
          curseWords: SettingsKey.curseWordsAvailable && curseWords,
          store: ProgressStore(context: context, observer: observer),
          observer: observer)
      }
    }
  }
}

struct PangramView: View {
  @Bindable var session: PangramSession

  @Environment(\.dsTheme) private var theme
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  /// Words rejected since the view opened, each of which shakes the current word.
  @State private var rejections = 0
  /// Full turns the ring has spun through, one per shuffle.
  @State private var spins = 0

  var body: some View {
    ScrollView {
      VStack(spacing: 20) {
        ScoreHeader(game: session.game)
        CurrentWord(game: session.game)
          .shake(on: rejections)
        Clues(words: session.game.clues)
        LetterWheel(
          center: session.game.puzzle.center, outer: session.outer, spins: spins,
          onLetter: session.type
        )
        .disabled(session.solving)
        controls
          .disabled(session.solving)
        FoundWords(game: session.game)
      }
      .padding()
    }
    .onChange(of: session.feedback) { _, feedback in
      if feedback?.kind.isRejection == true {
        rejections += 1
      }
    }
    .sensoryFeedback(.error, trigger: rejections)
    .returnsHome(whenWon: session.game.earnedStar)
    .sensoryFeedback(trigger: session.game.found.count) { old, new in
      new > old && !session.solving ? .success : nil
    }
    .sensoryFeedback(trigger: session.game.current) { old, new in
      new.count > old.count && !session.solving ? .selection : nil
    }
    .sensoryFeedback(.impact(weight: .light), trigger: session.game.hints.count)
    .toolbar {
      if !session.game.found.isEmpty {
        ToolbarItem(placement: .topBarTrailing) {
          ShareLink(item: ShareText.pangram(session.game, on: session.key.day))
        }
      }
      if !(session.game.earnedStar || session.game.gaveUp) || session.solving {
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
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation(theme.animation.normal) { session.dismissFeedback(feedback) }
          }
          .transition(.move(edge: .top).combined(with: .opacity))
      }
    }
    .animation(theme.animation.normal, value: session.feedback)
    .timed(by: session.timer)
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
        // The ring spins once around while the letters swap places. With Reduce Motion on, they
        // swap in place.
        if reduceMotion {
          session.shuffle()
        } else {
          withAnimation(.spring(response: 0.7, dampingFraction: 0.8)) {
            spins += 1
            session.shuffle()
          }
        }
      }
      .accessibilityIdentifier("shuffle")
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

  @Environment(\.dsTheme) private var theme
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    VStack(spacing: 6) {
      HStack(alignment: .firstTextBaseline) {
        Text("\(game.score)")
          .font(.largeTitle.weight(.bold).monospacedDigit())
          .countingUp(game.score)
        Text("/ \(game.puzzle.targetScore)")
          .foregroundStyle(.secondary)
        Spacer()
        Text(pangramCount)
          .foregroundStyle(.secondary)
      }
      ProgressView(value: min(Double(game.score) / Double(max(game.puzzle.targetScore, 1)), 1))
        .countingUp(game.score)
      if game.earnedStar {
        Label("Star earned", systemImage: "star.fill")
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(theme.colors.tertiary)
          .transition(.pop(reduceMotion: reduceMotion))
      } else if game.score >= game.puzzle.targetScore {
        Text("Find every pangram for the star")
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
    }
    .starEntrance(game.earnedStar)
  }

  /// The common pangrams the star needs, then any bonus ones apart, so a bonus find never looks
  /// like it went uncounted.
  private var pangramCount: String {
    let count = String(localized: "\(game.foundPangrams) of \(game.puzzle.pangrams.count) pangrams")
    let bonus = game.foundBonusPangrams
    return bonus == 0 ? count : String(localized: "\(count) · \(bonus) bonus")
  }
}

/// A chip per clued word still unfound: its first two letters and its length.
private struct Clues: View {
  let words: [PangramWord]

  @Environment(\.dsTheme) private var theme

  var body: some View {
    if !words.isEmpty {
      LazyVGrid(columns: [GridItem(.adaptive(minimum: 120))], spacing: 6) {
        ForEach(words, id: \.word) { word in
          Text("\(String(word.shown.prefix(2)).uppercased())… · \(word.shown.count) letters")
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(theme.colors.tertiary.opacity(0.2), in: .capsule)
        }
      }
      .transition(.opacity)
    }
  }
}

private struct CurrentWord: View {
  let game: PangramGame

  @Environment(\.dsTheme) private var theme

  var body: some View {
    var text = AttributedString()
    for letter in game.current {
      var run = AttributedString(String(letter).uppercased())
      run.foregroundColor =
        letter == game.puzzle.center ? theme.colors.primary : theme.colors.textPrimary
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
  /// Full turns the ring has spun through.
  let spins: Int
  let onLetter: (Character) -> Void

  @Environment(\.dsTheme) private var theme

  static let centerRadius: CGFloat = 46
  static let ringWidth: CGFloat = 90
  static let gap: CGFloat = 6
  static let radius = centerRadius + gap + ringWidth

  var body: some View {
    let span = Angle.degrees(360 / Double(max(outer.count, 1)))
    ZStack {
      ZStack {
        ForEach(Array(outer.enumerated()), id: \.element) { index, letter in
          WedgeKey(letter: letter, span: span, rotation: span * Double(index)) { onLetter(letter) }
        }
      }
      .rotationEffect(.degrees(Double(spins) * 360))
      Button {
        onLetter(center)
      } label: {
        Text(String(center).uppercased())
          .font(.title.weight(.bold))
          .foregroundStyle(theme.colors.textOnPrimary)
          .frame(width: 2 * Self.centerRadius, height: 2 * Self.centerRadius)
          .background(theme.colors.primary, in: .circle)
          .contentShape(.circle)
      }
      .buttonStyle(PulseStyle())
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

    @Environment(\.dsTheme) private var theme

    var body: some View {
      let wedge = Wedge(
        span: span, inner: LetterWheel.centerRadius + LetterWheel.gap, outer: LetterWheel.radius,
        gap: LetterWheel.gap)
      Button(action: action) {
        wedge
          .fill(theme.colors.cardBackground)
          .overlay {
            Text(String(letter).uppercased())
              .font(.title.weight(.bold))
              .foregroundStyle(theme.colors.textPrimary)
              .rotationEffect(-rotation)
              .offset(y: -(LetterWheel.radius - LetterWheel.ringWidth / 2))
          }
          .contentShape([.interaction, .accessibility], wedge)
      }
      .buttonStyle(PulseStyle())
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
  @Environment(\.dsTheme) private var theme
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text("\(game.found.count) found")
          .font(.headline)
        Spacer()
        Button {
          withAnimation(theme.animation.normal) {
            order = order == .alphabetical ? .recent : .alphabetical
          }
        } label: {
          Image(systemName: order == .alphabetical ? "textformat.abc" : "clock")
            .frame(minWidth: 44, minHeight: 44)
        }
        .accessibilityLabel(
          order == .alphabetical
            ? String(localized: "Sorted A to Z") : String(localized: "Sorted newest first")
        )
        .accessibilityHint("Changes how found words are sorted")
      }
      LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), alignment: .leading)], spacing: 6) {
        ForEach(game.found(sortedBy: order), id: \.word) { word in
          HStack(spacing: 4) {
            // Common pangrams bold, bonus ones bold and italic.
            Text(word.shown)
              .fontWeight(game.puzzle.isPangram(word.word) ? .bold : .regular)
              .italic(game.puzzle.isBonusPangram(word.word))
            Text("\(word.points)")
              .font(.caption2)
              .foregroundStyle(.secondary)
          }
          .transition(.pop(reduceMotion: reduceMotion))
        }
      }
      .animation(
        reduceMotion ? .easeInOut(duration: 0.2) : .bouncy(duration: 0.45, extraBounce: 0.2),
        value: game.found.count)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

extension PangramSession.Feedback.Kind {
  /// Whether this feedback turns a word away.
  var isRejection: Bool {
    switch self {
    case .alreadyFound, .tooShort, .missingCenter, .blocked, .notAWord, .needsPangram: true
    case .found, .foundBonusPangram, .saveFailed, .helpSaveFailed, .loadFailed: false
    }
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
      pangram
        ? String(localized: "Pangram! \(word.shown) +\(word.points)")
        : "\(word.shown) +\(word.points)"
    case .foundBonusPangram(let word):
      String(localized: "Bonus pangram! \(word.shown) +\(word.points)")
    case .alreadyFound(let word): String(localized: "Already found \(word.shown)")
    case .tooShort: String(localized: "Too short")
    case .missingCenter: String(localized: "Missing the center letter")
    case .blocked: String(localized: "How dare you")
    case .notAWord(let text): String(localized: "\(text.uppercased()) isn't on the list")
    case .needsPangram: String(localized: "Start with a pangram")
    case .saveFailed: String(localized: "Couldn't save that word")
    case .helpSaveFailed: String(localized: "Couldn't save your progress")
    case .loadFailed: String(localized: "Couldn't load saved progress")
    }
  }
}
