import Foundation
import Observability
import SwiftData
import Testing

@testable import Ngrams

/// A clock the test moves by hand.
private final class TestClock {
  var now = testInstant

  func advance(_ seconds: TimeInterval) {
    now = now.addingTimeInterval(seconds)
  }
}

private let key = ProgressKey(language: .en, kind: .tiles, n: 2, day: testDay)

private func store() throws -> ProgressStore {
  let container = try ModelContainer(
    for: PuzzleProgress.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
  return ProgressStore(context: ModelContext(container), observer: recordingObserver("test"))
}

@Suite("PlayClock")
struct PlayClockTests {
  @Test("opens a stretch on resume and closes it on pause")
  func stretches() {
    var clock = PlayClock()

    clock.resume(at: testInstant)
    clock.tick(at: testInstant.addingTimeInterval(10))
    clock.pause(at: testInstant.addingTimeInterval(20))
    clock.tick(at: testInstant.addingTimeInterval(30))

    #expect(
      clock.stretches == [PlayStretch(start: testInstant, end: testInstant.addingTimeInterval(20))])
    #expect(!clock.isRunning)
  }

  @Test("keeps one stretch open when resumed twice")
  func resumesOnce() {
    var clock = PlayClock()

    clock.resume(at: testInstant)
    clock.resume(at: testInstant.addingTimeInterval(5))

    #expect(clock.stretches.count == 1)
  }

  @Test("adds to the stretches already saved")
  func continuesSaved() {
    let saved = PlayStretch(start: testInstant, end: testInstant.addingTimeInterval(60))
    var clock = PlayClock(saved: [saved])

    clock.resume(at: testInstant.addingTimeInterval(3600))

    #expect(clock.stretches.count == 2)
    #expect(clock.stretches.first == saved)
  }
}

@Suite("PuzzleTimer")
struct PuzzleTimerTests {
  private func timer(_ store: ProgressStore, _ clock: TestClock) -> PuzzleTimer {
    PuzzleTimer(key: key, store: store, logger: recordingObserver("test").logger) { clock.now }
  }

  @Test("counts time on screen and saves it with the first entry")
  func timesPlay() throws {
    let store = try store()
    let clock = TestClock()
    let timer = timer(store, clock)

    timer.resume()
    clock.advance(45)
    timer.tick()
    #expect(timer.elapsed == 45)
    #expect(try store.timing(for: key) == nil)

    let (stretches, now) = timer.entry(completing: false)
    try store.append("ab", for: key, stretches: stretches, at: now)

    #expect(
      try store.timing(for: key)?.stretches.map(\.end) == [testInstant.addingTimeInterval(45)])
  }

  @Test("leaves out time off screen")
  func pauses() throws {
    let clock = TestClock()
    let timer = timer(try store(), clock)

    timer.resume()
    clock.advance(30)
    timer.pause()
    clock.advance(600)
    timer.resume()
    clock.advance(15)
    timer.tick()

    #expect(timer.elapsed == 45)
  }

  @Test("stops the time when the puzzle is finished")
  func stopsAtCompletion() throws {
    let store = try store()
    let clock = TestClock()
    let timer = timer(store, clock)

    timer.resume()
    clock.advance(20)
    let (stretches, now) = timer.entry(completing: true)
    try store.append("ab", for: key, completes: true, stretches: stretches, at: now)
    clock.advance(100)
    timer.tick()

    #expect(timer.elapsed == 20)
    #expect(self.timer(store, clock).elapsed == 20)
  }

  @Test("saves an open stretch every checkpoint")
  func checkpoints() throws {
    let store = try store()
    let clock = TestClock()
    try store.append("ab", for: key)
    let timer = timer(store, clock)

    timer.resume()
    timer.tick()
    clock.advance(PuzzleTimer.checkpointInterval - 1)
    timer.tick()
    #expect(try store.timing(for: key)?.stretches.last?.end == testInstant)

    clock.advance(1)
    timer.tick()
    #expect(
      try store.timing(for: key)?.stretches.last?.end
        == testInstant.addingTimeInterval(PuzzleTimer.checkpointInterval))
  }

  @Test("shows no time for a puzzle started before timing existed")
  func untimed() throws {
    let context = try ModelContext(
      ModelContainer(
        for: PuzzleProgress.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
    context.insert(PuzzleProgress(key: key, entries: ["ab"]))
    try context.save()
    let oldStore = ProgressStore(context: context, observer: recordingObserver("test"))
    let clock = TestClock()

    let timer = timer(oldStore, clock)
    timer.resume()
    clock.advance(30)
    timer.pause()

    #expect(timer.elapsed == nil)
    #expect(try oldStore.timing(for: key)?.stretches.count == 1)
  }
}

@Suite("Formatted time")
struct FormattedTimeTests {
  @Test("reads like a clock")
  func formats() {
    #expect(formattedTime(5) == "0:05")
    #expect(formattedTime(245) == "4:05")
    #expect(formattedTime(3723) == "1:02:03")
  }
}
