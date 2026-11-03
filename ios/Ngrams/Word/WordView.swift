import DesignSystem
import Observability
import SwiftData
import SwiftUI

/// Loads the puzzle's guess list and builds a session once the view has its model context,
/// then shows the puzzle.
struct WordScreen: View {
  let puzzle: WordPuzzle
  let day: PuzzleDay

  private enum LoadState {
    case loading
    case loaded(WordSession)
    case failed
  }

  @Environment(\.modelContext) private var context
  @Environment(\.pillars) private var pillars
  @AppStorage(SettingsKey.hardMode(.word)) private var hardModes = LanguageSelection([])
  @State private var state = LoadState.loading

  var body: some View {
    Group {
      switch state {
      case .loading:
        ProgressView()
          .task { await load() }
      case .loaded(let session):
        WordView(session: session)
      case .failed:
        ContentUnavailableView(
          "Couldn't load the word list", systemImage: "exclamationmark.triangle")
      }
    }
    .navigationTitle(
      Text(verbatim: "\(puzzle.language.flag) \(PuzzleKind.word.name) · \(puzzle.n)")
    )
    .navigationBarTitleDisplayMode(.inline)
  }

  private func load() async {
    let observer = makeObserver("WordSession", pillars)
    do {
      let list = try await GuessList.loadBundled(language: puzzle.language, n: puzzle.n)
      state = .loaded(
        WordSession(
          puzzle: puzzle, day: day, list: list,
          hardMode: hardModes.languages.contains(puzzle.language),
          store: ProgressStore(context: context, observer: observer), observer: observer))
    } catch {
      observer.logger.withValue("lang", puzzle.language.rawValue).withValue("n", puzzle.n)
        .error("loading guess list", error)
      state = .failed
    }
  }
}

struct WordView: View {
  @Bindable var session: WordSession

  @Environment(\.dsTheme) private var theme
  @State private var showingStats = false
  // PROTOTYPE
  @Environment(\.prototype) private var prototype
  @State private var help = WordHelp()
  @State private var shakes = 0

  var body: some View {
    VStack(spacing: 16) {
      GuessGrid(game: session.game, hints: help.hints, shakes: shakes)
      Spacer(minLength: 0)
      ResultLine(game: session.game)
      Keyboard(
        language: session.game.puzzle.language, marks: session.game.letterMarks,
        disabled: session.game.isOver || help.solving,
        onLetter: session.type, onDelete: session.deleteLetter, onEnter: session.submit)
    }
    .padding()
    .onChange(of: session.game.isOver) { wasOver, isOver in
      if !wasOver, isOver {
        Task {
          try? await Task.sleep(for: .seconds(1))
          showingStats = true
        }
      }
    }
    .sheet(isPresented: $showingStats) {
      let puzzle = session.game.puzzle
      LineStatsSheet(
        line: PuzzleLine(language: puzzle.language, kind: .word, n: puzzle.n),
        highlight: solvedIn, time: session.timer.elapsed)
    }
    .toolbar {
      if session.game.isOver {
        ToolbarItem(placement: .topBarTrailing) {
          ShareLink(item: ShareText.word(session.game, on: session.key.day))
        }
      } else {
        // PROTOTYPE
        ToolbarItem(placement: .topBarTrailing) {
          HelpMenu(
            used: help.used, disabled: help.solving, onHint: { help.hint(session.game) },
            onSolve: { Task { await help.solve(session, pace: prototype.time(0.25)) } })
        }
      }
    }
    // PROTOTYPE: a rejected guess shakes the row and buzzes.
    .onChange(of: session.feedback) { _, feedback in
      switch feedback?.kind {
      case .tooShort, .notAWord, .missingHint, .blocked: shakes += 1
      default: break
      }
    }
    .sensoryFeedback(trigger: shakes) { _, _ in prototype.haptics ? .error : nil }
    .sensoryFeedback(trigger: session.game.guesses.count) { _, _ in
      prototype.haptics ? (solvedIn != nil ? .success : .impact(weight: .light)) : nil
    }
    .sensoryFeedback(trigger: help.used) { _, _ in prototype.haptics ? .selection : nil }
    .prototypePill()
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

  private var solvedIn: Int? {
    if case .won(let guesses) = session.game.status {
      return guesses
    }
    return nil
  }
}

private struct GuessGrid: View {
  let game: WordGame
  // PROTOTYPE
  let hints: [Int: Character]
  let shakes: Int

  @Environment(\.dsTheme) private var theme
  @Environment(\.prototype) private var prototype

  var body: some View {
    let marks = game.marks
    let won = solvedRow != nil ? 1 : 0
    VStack(spacing: 6) {
      ForEach(0..<WordGame.maxGuesses, id: \.self) { row in
        HStack(spacing: 6) {
          ForEach(0..<game.puzzle.n, id: \.self) { column in
            LetterCell(
              letter: letter(row: row, column: column), mark: mark(marks, row, column),
              hint: row == game.guesses.count && !game.isOver ? hints[column] : nil,
              flipDelay: Double(column) * 0.12
            )
            .prototypeHop(
              row == solvedRow ? won : 0,
              delay: Double(game.puzzle.n) * 0.12 + 0.35 + Double(column) * 0.08,
              enabled: prototype.wordBounce)
          }
        }
        .prototypeShake(row == game.guesses.count ? shakes : 0, enabled: prototype.wordShake)
      }
    }
    .animation(theme.animation.normal, value: game.guesses)
  }

  /// The row that solved the puzzle, if it's solved.
  private var solvedRow: Int? {
    if case .won(let guesses) = game.status {
      return guesses - 1
    }
    return nil
  }

  private func letter(row: Int, column: Int) -> Character? {
    let text: String
    if row < game.guesses.count {
      text = game.guesses[row]
    } else if row == game.guesses.count {
      text = game.current
    } else {
      return nil
    }
    let letters = Array(text)
    return letters.indices.contains(column) ? letters[column] : nil
  }

  private func mark(_ marks: [[LetterMark]], _ row: Int, _ column: Int) -> LetterMark? {
    marks.indices.contains(row) ? marks[row][column] : nil
  }
}

extension LetterMark {
  /// The fill behind a marked letter. Absent letters get none; they fade instead.
  func fill(in theme: DSTheme) -> Color? {
    switch self {
    case .correct: theme.colors.primary
    case .present: theme.colors.secondary
    case .absent: nil
    }
  }

  var accessibilityName: String {
    switch self {
    case .correct: String(localized: "correct")
    case .present: String(localized: "in the word")
    case .absent: String(localized: "not in the word")
    }
  }
}

private struct LetterCell: View {
  /// Fits six cells across the narrowest supported phone.
  static let size: CGFloat = 52

  let letter: Character?
  /// Nil until the letter's guess is submitted.
  let mark: LetterMark?
  // PROTOTYPE: a hinted letter pencilled into an empty cell, and the flip that shows a mark.
  let hint: Character?
  let flipDelay: Double

  @Environment(\.dsTheme) private var theme
  @Environment(\.prototype) private var prototype
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var shownMark: LetterMark?
  @State private var angle = 0.0

  init(letter: Character?, mark: LetterMark?, hint: Character?, flipDelay: Double) {
    self.letter = letter
    self.mark = mark
    self.hint = hint
    self.flipDelay = flipDelay
    _shownMark = State(initialValue: mark)
  }

  var body: some View {
    let mark = shownMark
    let fill = mark?.fill(in: theme)
    Text(letter.map { String($0).uppercased() } ?? hint.map { String($0).uppercased() } ?? " ")
      .font(.title.weight(.bold))
      .frame(width: Self.size, height: Self.size)
      .foregroundStyle(
        letter == nil && hint != nil ? theme.colors.primary.opacity(0.45) : foreground
      )
      .background(fill ?? .clear, in: .rect(cornerRadius: theme.radius.md))
      .overlay {
        if fill == nil {
          RoundedRectangle(cornerRadius: theme.radius.md)
            .strokeBorder(
              letter == nil && hint != nil ? theme.colors.primary.opacity(0.6) : border,
              style: StrokeStyle(lineWidth: 2, dash: letter == nil && hint != nil ? [5, 4] : []))
        }
      }
      .rotation3DEffect(.degrees(angle), axis: (x: 1, y: 0, z: 0))
      .onChange(of: self.mark) { old, new in
        guard old == nil, new != nil, prototype.wordFlip, !reduceMotion else {
          shownMark = new
          return
        }
        Task {
          let half = prototype.time(0.18)
          try? await Task.sleep(for: .seconds(prototype.time(flipDelay)))
          withAnimation(.easeIn(duration: half)) { angle = 90 }
          try? await Task.sleep(for: .seconds(half))
          shownMark = new
          withAnimation(.easeOut(duration: half)) { angle = 0 }
        }
      }
      .accessibilityLabel(
        letter.map { "\(String($0).uppercased())\(mark.map { ", \($0.accessibilityName)" } ?? "")" }
          ?? String(localized: "empty"))
  }

  private var foreground: Color {
    switch shownMark {
    case .absent: theme.colors.textSecondary
    case .correct, .present: theme.colors.textOnPrimary
    case nil: theme.colors.textPrimary
    }
  }

  private var border: Color {
    if shownMark == .absent || letter == nil {
      return theme.colors.border
    }
    return theme.colors.secondary
  }
}

private struct ResultLine: View {
  let game: WordGame

  @Environment(\.dsTheme) private var theme

  var body: some View {
    switch game.status {
    case .playing:
      Text("\(WordGame.maxGuesses - game.guesses.count) guesses left")
        .foregroundStyle(.secondary)
    case .won(let guesses):
      Label("Solved in \(guesses) guesses", systemImage: "star.fill")
        .font(.headline)
        .foregroundStyle(theme.colors.tertiary)
    case .lost:
      Text("The word was \(game.puzzle.shown.uppercased())")
        .font(.headline)
    }
  }
}

private struct Keyboard: View {
  let language: Language
  let marks: [Character: LetterMark]
  let disabled: Bool
  let onLetter: (Character) -> Void
  let onDelete: () -> Void
  let onEnter: () -> Void

  private var rows: [[Character]] {
    let middle = language == .es ? "asdfghjklñ" : "asdfghjkl"
    return ["qwertyuiop", middle, "zxcvbnm"].map(Array.init)
  }

  var body: some View {
    VStack(spacing: 8) {
      ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
        HStack(spacing: 5) {
          if index == rows.count - 1 {
            ActionKey(title: "Enter", systemImage: "return", action: onEnter)
              .accessibilityIdentifier("enter")
          }
          ForEach(row, id: \.self) { letter in
            LetterKey(letter: letter, mark: marks[letter]) { onLetter(letter) }
          }
          if index == rows.count - 1 {
            ActionKey(title: "Delete", systemImage: "delete.left", action: onDelete)
          }
        }
      }
    }
    .disabled(disabled)
  }
}

private struct LetterKey: View {
  let letter: Character
  let mark: LetterMark?
  let action: () -> Void

  @Environment(\.dsTheme) private var theme

  var body: some View {
    Button(action: action) {
      Text(String(letter).uppercased())
        .font(.title3.weight(.semibold))
        .frame(maxWidth: .infinity, minHeight: 52)
        .foregroundStyle(foreground)
        .background(background, in: .rect(cornerRadius: theme.radius.sm))
    }
    .buttonStyle(.plain)
    .accessibilityLabel(
      "\(String(letter).uppercased())\(mark.map { ", \($0.accessibilityName)" } ?? "")")
  }

  private var foreground: Color {
    switch mark {
    case .absent: theme.colors.textTertiary
    case .correct, .present: theme.colors.textOnPrimary
    case nil: theme.colors.textPrimary
    }
  }

  private var background: Color {
    mark?.fill(in: theme)
      ?? (mark == .absent ? theme.colors.cardBackground : theme.colors.cardBackgroundElevated)
  }
}

private struct ActionKey: View {
  let title: LocalizedStringKey
  let systemImage: String
  let action: () -> Void

  @Environment(\.dsTheme) private var theme

  var body: some View {
    Button(action: action) {
      Image(systemName: systemImage)
        .font(.title3)
        .frame(minWidth: 48, minHeight: 52)
        .background(theme.colors.borderSubtle, in: .rect(cornerRadius: theme.radius.sm))
    }
    .buttonStyle(.plain)
    .accessibilityLabel(title)
  }
}

private struct FeedbackBanner: View {
  let feedback: WordSession.Feedback

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
    case .tooShort: String(localized: "Not enough letters")
    case .blocked: String(localized: "How dare you")
    case .notAWord(let text): String(localized: "\(text.uppercased()) isn't on the list")
    case .missingHint(.position(let letter, let index)):
      String(localized: "\(ordinal(index + 1)) letter must be \(String(letter).uppercased())")
    case .missingHint(.letter(let letter)):
      String(localized: "Guess must contain \(String(letter).uppercased())")
    case .saveFailed: String(localized: "Couldn't save that guess")
    case .loadFailed: String(localized: "Couldn't load saved progress")
    }
  }
}

/// Ordinals for letter positions, correct through 20th in English: "1st", or "1.ª" in Spanish,
/// which agrees with the feminine "letra".
private func ordinal(_ n: Int) -> String {
  switch (Language.interface, n) {
  case (.es, _): "\(n).ª"
  case (.en, 1): "1st"
  case (.en, 2): "2nd"
  case (.en, 3): "3rd"
  case (.en, _): "\(n)th"
  }
}
