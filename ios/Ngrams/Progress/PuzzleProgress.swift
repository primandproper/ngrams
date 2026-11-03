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
  /// Every stretch of play, kept even after the puzzle is finished. See `PlayTime`.
  var stretches: [PlayStretch] = []
  /// Whether play was timed from the first entry. Puzzles started before timing existed stay
  /// untimed, so they never show a time that leaves out their start.
  var timed = false
  /// Hints taken, oldest first, in each game's own terms. Kept apart from `entries`, which stats
  /// read as guesses or found words.
  var hints: [String] = []
  /// Whether the player had the puzzle solved for them, which gives up the win or the star.
  var gaveUp = false

  init(
    key: ProgressKey, entries: [String] = [], hardMode: Bool = false, completedAt: Date? = nil,
    updatedAt: Date = .now, stretches: [PlayStretch] = [], timed: Bool = false,
    hints: [String] = [], gaveUp: Bool = false
  ) {
    self.language = key.language.rawValue
    self.kind = key.kind.rawValue
    self.n = key.n
    self.day = key.day.description
    self.entries = entries
    self.hardMode = hardMode
    self.completedAt = completedAt
    self.updatedAt = updatedAt
    self.stretches = stretches
    self.timed = timed
    self.hints = hints
    self.gaveUp = gaveUp
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
      completedAt: completedAt ?? updatedAt, stretches: stretches, timed: timed, hints: hints,
      gaveUp: gaveUp)
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

  /// What a puzzle's time is worked out from, or nil if nothing's been saved for it yet.
  func timing(for key: ProgressKey) throws -> PuzzleTiming? {
    try fetch(key).map {
      PuzzleTiming(stretches: $0.stretches, completedAt: $0.completedAt, timed: $0.timed)
    }
  }

  /// Appends one entry and saves, folding in `stretches`. Appending rather than replacing means a
  /// failed read can never turn into a write that drops earlier entries. The first entry records
  /// `hardMode` and starts the puzzle timed; later ones leave both alone, so a puzzle keeps the
  /// mode it started in. The first entry that `completes` the puzzle records when.
  func append(
    _ entry: String, for key: ProgressKey, hardMode: Bool = false, completes: Bool = false,
    stretches: [PlayStretch] = [], at now: Date = .now
  ) throws {
    if let progress = try fetch(key) {
      progress.entries.append(entry)
      progress.stretches = PlayTime.merged(progress.stretches, stretches)
      progress.updatedAt = now
      if completes, progress.completedAt == nil {
        progress.completedAt = now
      }
    } else {
      context.insert(
        PuzzleProgress(
          key: key, entries: [entry], hardMode: hardMode, completedAt: completes ? now : nil,
          updatedAt: now, stretches: PlayTime.merged([], stretches), timed: true))
    }
    try context.save()
    logger.withValue("day", key.day.description).withValue("n", key.n)
      .debug("saved \(key.kind.rawValue) progress")
  }

  /// The hints a puzzle has taken and whether it was solved for the player, or nil if nothing's
  /// been saved for it yet.
  func assistance(for key: ProgressKey) throws -> Assistance? {
    try fetch(key).map { Assistance(hints: $0.hints, gaveUp: $0.gaveUp) }
  }

  /// Saves a hint, folding in `stretches`. A hint starts the puzzle the way a first entry does:
  /// with nothing saved yet, it records `hardMode` and starts the puzzle timed.
  func take(
    hint: String, for key: ProgressKey, hardMode: Bool = false, stretches: [PlayStretch] = [],
    at now: Date = .now
  ) throws {
    let progress = try fetchOrStart(key, hardMode: hardMode, at: now)
    progress.hints.append(hint)
    progress.stretches = PlayTime.merged(progress.stretches, stretches)
    progress.updatedAt = now
    try context.save()
    logger.withValue("day", key.day.description).withValue("n", key.n)
      .debug("saved a \(key.kind.rawValue) hint")
  }

  /// Saves that the player had the puzzle solved for them, appending the `entries` that finish
  /// it (a board's remaining words; none for Password) and recording when, as a finishing entry
  /// would.
  func giveUp(
    adding entries: [String] = [], for key: ProgressKey, hardMode: Bool = false,
    stretches: [PlayStretch] = [], at now: Date = .now
  ) throws {
    let progress = try fetchOrStart(key, hardMode: hardMode, at: now)
    progress.entries.append(contentsOf: entries)
    progress.gaveUp = true
    progress.stretches = PlayTime.merged(progress.stretches, stretches)
    progress.updatedAt = now
    if progress.completedAt == nil {
      progress.completedAt = now
    }
    try context.save()
    logger.withValue("day", key.day.description).withValue("n", key.n)
      .info("solved \(key.kind.rawValue) for the player")
  }

  /// Folds `stretches` into a started puzzle's and saves. A puzzle with nothing saved yet keeps
  /// its stretches in memory until its first entry, so opening a puzzle never starts it.
  func save(_ stretches: [PlayStretch], for key: ProgressKey) throws {
    guard let progress = try fetch(key) else {
      return
    }
    progress.stretches = PlayTime.merged(progress.stretches, stretches)
    try context.save()
  }

  /// The puzzle's saved progress, or new progress inserted for it, started the way a first
  /// entry starts it.
  private func fetchOrStart(_ key: ProgressKey, hardMode: Bool, at now: Date) throws
    -> PuzzleProgress
  {
    if let progress = try fetch(key) {
      return progress
    }
    let progress = PuzzleProgress(key: key, hardMode: hardMode, updatedAt: now, timed: true)
    context.insert(progress)
    return progress
  }

  private func fetch(_ key: ProgressKey) throws -> PuzzleProgress? {
    var descriptor = FetchDescriptor(predicate: PuzzleProgress.matching(key))
    descriptor.fetchLimit = 1
    return try context.fetch(descriptor).first
  }
}
