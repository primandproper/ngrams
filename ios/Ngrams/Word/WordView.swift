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

  var body: some View {
    VStack(spacing: 16) {
      GuessGrid(game: session.game)
      Spacer(minLength: 0)
      ResultLine(game: session.game)
      Keyboard(
        language: session.game.puzzle.language, marks: session.game.letterMarks,
        disabled: session.game.isOver || session.solving,
        onLetter: session.type, onDelete: session.deleteLetter, onClear: session.clearLetters,
        onEnter: session.submit)
    }
    .padding()
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
        line: PuzzleLine(language: puzzle.language, kind: .word, n: puzzle.n),
        highlight: solvedIn, time: session.timer.elapsed)
    }
    .toolbar {
      if session.game.isOver {
        ToolbarItem(placement: .topBarTrailing) {
          ShareLink(item: ShareText.word(session.game, on: session.key.day))
        }
      } else {
        ToolbarItem(placement: .topBarTrailing) {
          HelpMenu(
            used: session.game.hints.count, canHint: session.game.nextHint != nil,
            solveWarning: "Solving counts as a loss and ends your streak.",
            onHint: session.takeHint, onSolve: { Task { await session.solve() } }
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

  private var solvedIn: Int? {
    if case .won(let guesses) = session.game.status {
      return guesses
    }
    return nil
  }
}

private struct GuessGrid: View {
  let game: WordGame

  @Environment(\.dsTheme) private var theme

  var body: some View {
    let rows = self.rows
    let marks = rows.map { WordGame.marks(for: $0, answer: game.puzzle.answer) }
    let pencilled = game.isOver ? [:] : game.pencilled
    VStack(spacing: 6) {
      ForEach(0..<WordGame.maxGuesses, id: \.self) { row in
        HStack(spacing: 6) {
          ForEach(0..<game.puzzle.n, id: \.self) { column in
            LetterCell(
              letter: letter(rows, row: row, column: column), mark: mark(marks, row, column),
              hint: row == rows.count ? pencilled[column] : nil)
          }
        }
      }
    }
    .animation(theme.animation.normal, value: rows)
  }

  /// The rows marked so far: the guesses, then the answer once it was solved for the player.
  private var rows: [String] {
    game.gaveUp ? game.guesses + [game.puzzle.answer] : game.guesses
  }

  private func letter(_ rows: [String], row: Int, column: Int) -> Character? {
    let text: String
    if row < rows.count {
      text = rows[row]
    } else if row == rows.count {
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
  /// A hinted letter, pencilled in until a typed letter covers it.
  let hint: Character?

  @Environment(\.dsTheme) private var theme

  private var pencilled: Character? {
    letter == nil ? hint : nil
  }

  var body: some View {
    let fill = mark?.fill(in: theme)
    Text((letter ?? pencilled).map { String($0).uppercased() } ?? " ")
      .font(.title.weight(.bold))
      .frame(width: Self.size, height: Self.size)
      .foregroundStyle(pencilled == nil ? foreground : theme.colors.primary.opacity(0.45))
      .background(fill ?? .clear, in: .rect(cornerRadius: theme.radius.md))
      .overlay {
        if fill == nil {
          RoundedRectangle(cornerRadius: theme.radius.md)
            .strokeBorder(
              pencilled == nil ? border : theme.colors.primary.opacity(0.6),
              style: StrokeStyle(lineWidth: 2, dash: pencilled == nil ? [] : [5, 4]))
        }
      }
      .accessibilityLabel(accessibilityLabel)
  }

  private var accessibilityLabel: String {
    if let letter {
      return "\(String(letter).uppercased())\(mark.map { ", \($0.accessibilityName)" } ?? "")"
    }
    if let pencilled {
      return String(localized: "Hint: \(String(pencilled).uppercased())")
    }
    return String(localized: "empty")
  }

  private var foreground: Color {
    switch mark {
    case .absent: theme.colors.textSecondary
    case .correct, .present: theme.colors.textOnPrimary
    case nil: theme.colors.textPrimary
    }
  }

  private var border: Color {
    if mark == .absent || letter == nil {
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
  let onClear: () -> Void
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
              .simultaneousGesture(LongPressGesture().onEnded { _ in onClear() })
              .accessibilityHint("Hold to clear the row")
              .accessibilityAction(named: "Clear row", onClear)
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
    case .helpSaveFailed: String(localized: "Couldn't save your progress")
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
