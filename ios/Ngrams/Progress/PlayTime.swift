import Foundation

/// One stretch of time a puzzle spent on screen with the app in front.
nonisolated struct PlayStretch: Codable, Hashable, Sendable {
  let start: Date
  var end: Date
}

/// What a puzzle's time is worked out from. Only the stretches are saved; the time itself never is.
nonisolated enum PlayTime {
  /// `saved` with `stretches` folded in. A stretch starting when a saved one does keeps the later
  /// of the two ends, so saving an open stretch again only ever extends it; any other is added.
  static func merged(_ saved: [PlayStretch], _ stretches: [PlayStretch]) -> [PlayStretch] {
    var byStart = Dictionary(saved.map { ($0.start, $0) }, uniquingKeysWith: { first, _ in first })
    for stretch in stretches {
      if let existing = byStart[stretch.start] {
        byStart[stretch.start]?.end = max(existing.end, stretch.end)
      } else {
        byStart[stretch.start] = stretch
      }
    }
    return byStart.values.sorted { $0.start < $1.start }
  }

  /// Seconds on screen up to `completedAt`, or all of them for an unfinished puzzle. Play after a
  /// puzzle is finished is kept but doesn't count toward its time.
  static func active(_ stretches: [PlayStretch], until completedAt: Date?) -> TimeInterval {
    stretches.reduce(0) { total, stretch in
      let end = completedAt.map { min(stretch.end, $0) } ?? stretch.end
      return total + max(0, end.timeIntervalSince(stretch.start))
    }
  }
}

/// Times one puzzle's play as stretches: one opens when the puzzle comes on screen and closes when
/// it leaves or the app goes to the background.
nonisolated struct PlayClock: Sendable {
  private(set) var stretches: [PlayStretch]
  private(set) var isRunning = false

  init(saved: [PlayStretch] = []) {
    stretches = saved
  }

  mutating func resume(at now: Date) {
    guard !isRunning else {
      return
    }
    stretches.append(PlayStretch(start: now, end: now))
    isRunning = true
  }

  /// Moves the open stretch's end up to `now`.
  mutating func tick(at now: Date) {
    if isRunning, let last = stretches.indices.last {
      stretches[last].end = max(stretches[last].end, now)
    }
  }

  mutating func pause(at now: Date) {
    tick(at: now)
    isRunning = false
  }
}
