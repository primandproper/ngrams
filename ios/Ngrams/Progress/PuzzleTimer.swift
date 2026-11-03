import Foundation
import Observation
import SwiftUI

// Selective import: Observability also exports `struct Observation`, which shadows the module
// the @Observable macro expands against.
import protocol Observability.Logger

/// Times one puzzle in play and saves its stretches. Until the puzzle's first entry they stay in
/// memory and are saved with it, so opening a puzzle and leaving never starts it.
@Observable
final class PuzzleTimer {
  /// How often an open stretch is saved, which is the most a crash can lose.
  static let checkpointInterval: TimeInterval = 30

  private(set) var clock: PlayClock
  /// When the puzzle was finished, which stops its time.
  private(set) var completedAt: Date?
  /// Whether the puzzle has a time to show: false for one started before timing existed.
  private(set) var timed: Bool

  @ObservationIgnored private let key: ProgressKey
  @ObservationIgnored private let store: ProgressStore
  @ObservationIgnored private let logger: any Logger
  @ObservationIgnored private let now: () -> Date
  @ObservationIgnored private var lastSaved: Date?

  init(
    key: ProgressKey, store: ProgressStore, logger: any Logger,
    now: @escaping () -> Date = { .now }
  ) {
    self.key = key
    self.store = store
    self.logger = logger
    self.now = now
    do {
      let saved = try store.timing(for: key)
      clock = PlayClock(saved: saved?.stretches ?? [])
      completedAt = saved?.completedAt
      timed = saved?.timed ?? true
    } catch {
      // Without the saved stretches, any time shown would be wrong, so none is.
      logger.error("loading play time", error)
      clock = PlayClock()
      completedAt = nil
      timed = false
    }
  }

  /// The puzzle's time as of the last tick, or nil if it has none to show.
  var elapsed: TimeInterval? {
    timed ? PlayTime.active(clock.stretches, until: completedAt) : nil
  }

  func resume() {
    clock.resume(at: now())
  }

  func pause() {
    clock.pause(at: now())
    save()
  }

  /// Brings the open stretch up to now, saving it once `checkpointInterval` has passed.
  func tick() {
    let now = now()
    clock.tick(at: now)
    if let lastSaved, now.timeIntervalSince(lastSaved) < Self.checkpointInterval {
      return
    }
    save()
  }

  /// Brings the open stretch up to now for an entry about to be saved, and returns what to save
  /// with it and when. An entry that `completes` the puzzle stops its time.
  func entry(completing completes: Bool) -> (stretches: [PlayStretch], at: Date) {
    let now = now()
    clock.tick(at: now)
    if completes, completedAt == nil {
      completedAt = now
    }
    lastSaved = now
    return (clock.stretches, now)
  }

  private func save() {
    let now = now()
    lastSaved = now
    do {
      try store.save(clock.stretches, for: key)
    } catch {
      logger.error("saving play time", error)
    }
  }
}

/// Formats a puzzle's time as a clock reads: 4:05, or 1:02:03 past an hour.
func formattedTime(_ seconds: TimeInterval) -> String {
  let duration = Duration.seconds(Int(seconds))
  return seconds < 3600
    ? duration.formatted(.time(pattern: .minuteSecond))
    : duration.formatted(.time(pattern: .hourMinuteSecond))
}

extension View {
  /// Runs `timer` while this puzzle is on screen with the app in front, and shows its time under
  /// the title unless the player has hidden it.
  func timed(by timer: PuzzleTimer) -> some View {
    modifier(TimedPuzzle(timer: timer))
  }
}

private struct TimedPuzzle: ViewModifier {
  let timer: PuzzleTimer

  @Environment(\.scenePhase) private var scenePhase
  @AppStorage(SettingsKey.showTimer) private var showTimer = true

  func body(content: Content) -> some View {
    content
      .navigationSubtitle(subtitle)
      // Restarts when the app comes and goes, and is cancelled when the puzzle leaves the screen;
      // either way the loop ends and the stretch closes.
      .task(id: scenePhase == .active) {
        guard scenePhase == .active else {
          return
        }
        timer.resume()
        while !Task.isCancelled {
          try? await Task.sleep(for: .seconds(1))
          timer.tick()
        }
        timer.pause()
      }
  }

  private var subtitle: String {
    guard showTimer, let elapsed = timer.elapsed else {
      return ""
    }
    return formattedTime(elapsed)
  }
}
