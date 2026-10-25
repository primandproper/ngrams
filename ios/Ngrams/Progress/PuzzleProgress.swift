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
  var updatedAt: Date

  init(
    key: ProgressKey, entries: [String] = [], hardMode: Bool = false, updatedAt: Date = .now
  ) {
    self.language = key.language.rawValue
    self.kind = key.kind.rawValue
    self.n = key.n
    self.day = key.day.description
    self.entries = entries
    self.hardMode = hardMode
    self.updatedAt = updatedAt
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
  /// ones leave it alone, so a puzzle keeps the mode it started in.
  func append(_ entry: String, for key: ProgressKey, hardMode: Bool = false) throws {
    if let progress = try fetch(key) {
      progress.entries.append(entry)
      progress.updatedAt = .now
    } else {
      context.insert(PuzzleProgress(key: key, entries: [entry], hardMode: hardMode))
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
