import DesignSystem
import Observability
import SwiftData
import SwiftUI

@main
struct NgramsApp: App {
  private let pillars = ObservabilityConfig(serviceName: "ngrams").bootstrap()
  // PROTOTYPE: one set of switches for the whole app.
  @State private var prototype = PrototypeSwitches()

  var body: some Scene {
    WindowGroup {
      RootView()
        .environment(\.pillars, pillars)
        .dsTheme(.ngrams)
        .environment(\.prototype, prototype)
    }
    .modelContainer(for: PuzzleProgress.self, inMemory: Self.inMemory)
  }

  /// Screenshot runs keep their seeded history out of the real store.
  private static var inMemory: Bool {
    #if DEBUG
      // PROTOTYPE: every debug build plays in memory, so solving on the prototype never touches
      // the progress saved on the phone.
      true
    #else
      false
    #endif
  }
}

extension EnvironmentValues {
  @Entry var pillars: Pillars = .noop
  /// The loaded bank, for screens below home that need more than their own puzzle.
  @Entry var puzzleBank: PuzzleBank?
}
