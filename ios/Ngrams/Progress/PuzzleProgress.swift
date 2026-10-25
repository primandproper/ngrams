import Foundation
import SwiftData

// Selective import: Observability also exports `struct Observation`, which shadows the module
// the @Model macro expands against.
import protocol Observability.Logger
import protocol Observability.Observer

/// Identifies one puzzle across the bank and saved progress. See docs/design.md: the bank and
/// progress stores share nothing but this key.
nonisolated struct ProgressKey: Hashable, Sendable {
  let language: Language
  let kind: PuzzleKind
  let n: Int
  let day: PuzzleDay
}

/// What a player has done on one puzzle. Entries are kind-specific and only ever appended: found
/// words for tiles, guesses for word.
@Model
final class PuzzleProgress {
  #Unique<PuzzleProgress>([\.language, \.kind, \.n, \.day])

  var language: String
  var kind: String
  var n: Int
  var day: String
  var entries: [String]
  /// The mode the puzzle was started in, fixed by its first entry. Word and pangram puzzles
  /// keep it; tiles reads its setting live and leaves this false.
  var hardMode = false
  /// When a word puzzle ended or a board earned its star, which decides whether it counts
  /// toward a streak. Nil for puzzles finished before it was saved.
  var completedAt: Date?
  var updatedAt: Date

  init(
    key: ProgressKey, entries: [String] = [], hardMode: Bool = false, completedAt: Date? = nil,
    updatedAt: Date = .now
  ) {
    self.language = key.language.rawValue
    self.kind = key.kind.rawValue
    self.n = key.n
    self.day = key.day.description
    self.entries = entries
    self.hardMode = hardMode
    self.completedAt = completedAt
    self.updatedAt = updatedAt
  }

  /// The plain values stats read, or nil if a field doesn't parse (saved by a build that knew a
  /// language or game this one doesn't).
  var record: PlayRecord? {
    guard let language = Language(rawValue: language), let kind = PuzzleKind(rawValue: kind),
      let day = PuzzleDay(day)
    else {
      return nil
    }
    return PlayRecord(
      key: ProgressKey(language: language, kind: kind, n: n, day: day), entries: entries,
      completedAt: completedAt ?? updatedAt)
  }

  static func matching(_ key: ProgressKey) -> Predicate<PuzzleProgress> {
    let language = key.language.rawValue
    let kind = key.kind.rawValue
    let n = key.n
    let day = key.day.description
    return #Predicate {
      $0.language == language && $0.kind == kind && $0.n == n && $0.day == day
    }
  }

  /// Every kind, language, and size on one day.
  static func matching(day: PuzzleDay) -> Predicate<PuzzleProgress> {
    let day = day.description
    return #Predicate { $0.day == day }
  }
}

/// Reads and writes saved progress.
final class ProgressStore {
  private let context: ModelContext
  private let logger: any Logger

  init(context: ModelContext, observer: any Observer) {
    self.context = context
    self.logger = observer.logger
  }

  func entries(for key: ProgressKey) throws -> [String] {
    try fetch(key)?.entries ?? []
  }

  /// The mode a started puzzle was started in, or nil if nothing's been saved for it yet.
  func hardMode(for key: ProgressKey) throws -> Bool? {
    try fetch(key)?.hardMode
  }

  /// Appends one entry and saves. Appending rather than replacing means a failed read can never
  /// turn into a write that drops earlier entries. The first entry records `hardMode`; later
  /// ones leave it alone, so a puzzle keeps the mode it started in. The first entry that
  /// `completes` the puzzle records when.
  func append(
    _ entry: String, for key: ProgressKey, hardMode: Bool = false, completes: Bool = false
  ) throws {
    let now = Date.now
    if let progress = try fetch(key) {
      progress.entries.append(entry)
      progress.updatedAt = now
      if completes, progress.completedAt == nil {
        progress.completedAt = now
      }
    } else {
      context.insert(
        PuzzleProgress(
          key: key, entries: [entry], hardMode: hardMode, completedAt: completes ? now : nil,
          updatedAt: now))
    }
    try context.save()
    logger.withValue("day", key.day.description).withValue("n", key.n)
      .debug("saved \(key.kind.rawValue) progress")
  }

  private func fetch(_ key: ProgressKey) throws -> PuzzleProgress? {
    var descriptor = FetchDescriptor(predicate: PuzzleProgress.matching(key))
    descriptor.fetchLimit = 1
    return try context.fetch(descriptor).first
  }
}
