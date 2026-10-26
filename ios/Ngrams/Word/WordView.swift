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
  @AppStorage(SettingsKey.wordHardMode) private var hardMode = false
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
    .navigationTitle("\(puzzle.language.flag) Password · \(puzzle.n)")
    .navigationBarTitleDisplayMode(.inline)
  }

  private func load() async {
    let observer = makeObserver("WordSession", pillars)
    do {
      let list = try await GuessList.loadBundled(language: puzzle.language, n: puzzle.n)
      state = .loaded(
        WordSession(
          puzzle: puzzle, day: day, list: list, hardMode: hardMode,
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

  @State private var showingStats = false

  var body: some View {
    VStack(spacing: 16) {
      GuessGrid(game: session.game)
      Spacer(minLength: 0)
      ResultLine(game: session.game)
      Keyboard(
        language: session.game.puzzle.language, marks: session.game.letterMarks,
        disabled: session.game.isOver,
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
        highlight: solvedIn)
    }
    .toolbar {
      if session.game.isOver {
        ToolbarItem(placement: .topBarTrailing) {
          ShareLink(item: ShareText.word(session.game, on: session.key.day))
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

  private var solvedIn: Int? {
    if case .won(let guesses) = session.game.status {
      return guesses
    }
    return nil
  }
}

private struct GuessGrid: View {
  let game: WordGame

  var body: some View {
    let marks = game.marks
    VStack(spacing: 6) {
      ForEach(0..<WordGame.maxGuesses, id: \.self) { row in
        HStack(spacing: 6) {
          ForEach(0..<game.puzzle.n, id: \.self) { column in
            LetterCell(letter: letter(row: row, column: column), mark: mark(marks, row, column))
          }
        }
      }
    }
    .animation(.default, value: game.guesses)
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
  var fill: Color? {
    switch self {
    case .correct: .accentColor
    case .present: Color(.systemGray)
    case .absent: nil
    }
  }

  var accessibilityName: String {
    switch self {
    case .correct: "correct"
    case .present: "in the word"
    case .absent: "not in the word"
    }
  }
}

private struct LetterCell: View {
  /// Fits six cells across the narrowest supported phone.
  static let size: CGFloat = 52

  let letter: Character?
  /// Nil until the letter's guess is submitted.
  let mark: LetterMark?

  var body: some View {
    Text(letter.map { String($0).uppercased() } ?? " ")
      .font(.title.weight(.bold))
      .frame(width: Self.size, height: Self.size)
      .foregroundStyle(foreground)
      .background(mark?.fill ?? .clear, in: .rect(cornerRadius: 8))
      .overlay {
        if mark?.fill == nil {
          RoundedRectangle(cornerRadius: 8)
            .strokeBorder(border, lineWidth: 2)
        }
      }
      .accessibilityLabel(
        letter.map { "\(String($0).uppercased())\(mark.map { ", \($0.accessibilityName)" } ?? "")" }
          ?? "empty")
  }

  private var foreground: Color {
    switch mark {
    case .absent: .secondary
    case .correct, .present: .white
    case nil: .primary
    }
  }

  private var border: Color {
    if mark == .absent || letter == nil {
      return Color(.systemGray5)
    }
    return Color(.systemGray)
  }
}

private struct ResultLine: View {
  let game: WordGame

  var body: some View {
    switch game.status {
    case .playing:
      Text("\(WordGame.maxGuesses - game.guesses.count) guesses left")
        .foregroundStyle(.secondary)
    case .won(let guesses):
      Label(
        guesses == 1 ? "Solved in 1 guess" : "Solved in \(guesses) guesses",
        systemImage: "star.fill"
      )
      .font(.headline)
      .foregroundStyle(.orange)
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

  var body: some View {
    Button(action: action) {
      Text(String(letter).uppercased())
        .font(.title3.weight(.semibold))
        .frame(maxWidth: .infinity, minHeight: 52)
        .foregroundStyle(foreground)
        .background(background, in: .rect(cornerRadius: 6))
    }
    .buttonStyle(.plain)
    .accessibilityLabel(
      "\(String(letter).uppercased())\(mark.map { ", \($0.accessibilityName)" } ?? "")")
  }

  private var foreground: Color {
    switch mark {
    case .absent: Color(.tertiaryLabel)
    case .correct, .present: .white
    case nil: .primary
    }
  }

  private var background: Color {
    mark?.fill ?? Color(mark == .absent ? .systemGray6 : .systemGray5)
  }
}

private struct ActionKey: View {
  let title: String
  let systemImage: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: systemImage)
        .font(.title3)
        .frame(minWidth: 48, minHeight: 52)
        .background(Color(.systemGray4), in: .rect(cornerRadius: 6))
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
    case .tooShort: "Not enough letters"
    case .blocked: "How dare you"
    case .notAWord(let text): "\(text.uppercased()) isn't on the list"
    case .missingHint(.position(let letter, let index)):
      "\(ordinal(index + 1)) letter must be \(String(letter).uppercased())"
    case .missingHint(.letter(let letter)): "Guess must contain \(String(letter).uppercased())"
    case .saveFailed: "Couldn't save that guess"
    case .loadFailed: "Couldn't load saved progress"
    }
  }
}

/// English ordinals, correct through 20th.
private func ordinal(_ n: Int) -> String {
  switch n {
  case 1: "1st"
  case 2: "2nd"
  case 3: "3rd"
  default: "\(n)th"
  }
}
