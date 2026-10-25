import SwiftData
import SwiftUI

extension PuzzleLine {
  var title: String {
    "\(language.flag) \(kind.name) · n=\(n)"
  }
}

extension StatsBook {
  /// Every line's stats as of today, from everything saved.
  static func current(_ progress: [PuzzleProgress], bank: PuzzleBank) -> [PuzzleLine: LineStats] {
    compute(
      records: progress.compactMap(\.record), bank: bank, today: PuzzleDay(containing: .now))
  }
}

/// Every line's stats in the player's languages, grouped by game like home, each opening its
/// full stats.
struct StatsView: View {
  let bank: PuzzleBank

  @Query private var progress: [PuzzleProgress]
  @AppStorage(SettingsKey.languages) private var languages: LanguageSelection?
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    let lines = StatsBook.current(progress, bank: bank).values
      .filter { languages?.languages.contains($0.line.language) ?? true }
    let multilingual = Set(lines.map(\.line.language)).count > 1

    NavigationStack {
      List {
        ForEach(PuzzleKind.allCases, id: \.self) { kind in
          let ofKind = lines.filter { $0.line.kind == kind }
          if !ofKind.isEmpty {
            Section(kind.name) {
              ForEach(
                Language.allCases.filter { l in ofKind.contains { $0.line.language == l } },
                id: \.self
              ) { language in
                if multilingual {
                  Text("\(language.flag) \(language.name)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                }
                ForEach(
                  ofKind.filter { $0.line.language == language }.sorted { $0.line.n < $1.line.n },
                  id: \.line
                ) { stats in
                  NavigationLink {
                    LineStatsView(stats: stats)
                      .navigationTitle(stats.line.title)
                      .navigationBarTitleDisplayMode(.inline)
                  } label: {
                    StatsRow(stats: stats)
                  }
                  .padding(.leading, multilingual ? 16 : 0)
                }
              }
            }
          }
        }
      }
      .navigationTitle("Stats")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { dismiss() }
        }
      }
    }
  }
}

private struct StatsRow: View {
  let stats: LineStats

  var body: some View {
    HStack {
      VStack(alignment: .leading) {
        Text("n=\(stats.line.n)")
          .font(.headline)
        Text(
          "\(stats.played) played · \(percent(stats.successRate)) \(successWord(stats.line.kind))"
        )
        .font(.subheadline)
        .foregroundStyle(.secondary)
      }
      Spacer()
      StreakBadge(streak: stats.currentStreak)
    }
  }
}

/// One line's numbers, and for word puzzles how many guesses each solve took.
struct LineStatsView: View {
  let stats: LineStats
  /// The guesses a just-solved word puzzle took, picked out in the distribution.
  var highlight: Int?

  var body: some View {
    ScrollView {
      VStack(spacing: 28) {
        HStack(alignment: .top) {
          Figure(value: "\(stats.played)", label: "Played")
          Figure(
            value: percent(stats.successRate), label: successWord(stats.line.kind).capitalized)
          Figure(value: "\(stats.currentStreak)", label: "Streak")
          Figure(value: "\(stats.bestStreak)", label: "Best streak")
        }
        if stats.line.kind == .word {
          GuessDistribution(counts: stats.guessCounts, highlight: highlight)
        }
        Text(
          "Streaks count \(stats.line.kind == .word ? "solves" : "stars") on the puzzle's own day."
        )
        .font(.footnote)
        .foregroundStyle(.secondary)
      }
      .padding()
    }
  }

  private struct Figure: View {
    let value: String
    let label: String

    var body: some View {
      VStack(spacing: 4) {
        Text(value)
          .font(.title.weight(.bold).monospacedDigit())
        Text(label)
          .font(.caption)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
      }
      .frame(maxWidth: .infinity)
      .accessibilityElement(children: .combine)
    }
  }
}

private struct GuessDistribution: View {
  let counts: [Int]
  let highlight: Int?

  var body: some View {
    let most = max(counts.max() ?? 0, 1)
    VStack(alignment: .leading, spacing: 6) {
      Text("Guesses")
        .font(.headline)
      ForEach(Array(counts.enumerated()), id: \.offset) { index, count in
        HStack(spacing: 8) {
          Text("\(index + 1)")
            .monospacedDigit()
            .frame(width: 14)
          GeometryReader { geometry in
            Text("\(count)")
              .font(.caption.weight(.bold).monospacedDigit())
              .foregroundStyle(.white)
              .padding(.horizontal, 8)
              .frame(
                width: max(30, geometry.size.width * CGFloat(count) / CGFloat(most)),
                height: geometry.size.height, alignment: .trailing
              )
              .background(
                index + 1 == highlight ? Color.accentColor : Color(.systemGray),
                in: .rect(cornerRadius: 4))
          }
          .frame(height: 22)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(index + 1) guesses: \(count)")
      }
    }
  }
}

/// One line's stats, shown when a puzzle is finished.
struct LineStatsSheet: View {
  let line: PuzzleLine
  var highlight: Int?

  @Query private var progress: [PuzzleProgress]
  @Environment(\.puzzleBank) private var bank
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      Group {
        if let bank, let stats = StatsBook.current(progress, bank: bank)[line] {
          LineStatsView(stats: stats, highlight: highlight)
        } else {
          ContentUnavailableView("No stats yet", systemImage: "chart.bar")
        }
      }
      .navigationTitle(line.title)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { dismiss() }
        }
      }
    }
    .presentationDetents([.medium, .large])
  }
}

/// A flame and the current streak, or nothing without one.
struct StreakBadge: View {
  let streak: Int

  var body: some View {
    if streak > 0 {
      Label("\(streak)", systemImage: "flame.fill")
        .labelStyle(.titleAndIcon)
        .font(.subheadline.weight(.semibold).monospacedDigit())
        .foregroundStyle(.orange)
        .accessibilityLabel("\(streak) day streak")
    }
  }
}

private func percent(_ rate: Double?) -> String {
  rate.map { $0.formatted(.percent.precision(.fractionLength(0))) } ?? "–"
}

private func successWord(_ kind: PuzzleKind) -> String {
  kind == .word ? "won" : "starred"
}
