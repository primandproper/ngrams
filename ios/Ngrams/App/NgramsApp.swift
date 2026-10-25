import Observability
import SwiftData
import SwiftUI

@main
struct NgramsApp: App {
  private let pillars = ObservabilityConfig(serviceName: "ngrams").bootstrap()

  var body: some Scene {
    WindowGroup {
      RootView()
        .environment(\.pillars, pillars)
    }
    .modelContainer(for: PuzzleProgress.self)
  }
}

extension EnvironmentValues {
  @Entry var pillars: Pillars = .noop
  /// The loaded bank, for screens below home that need more than their own puzzle.
  @Entry var puzzleBank: PuzzleBank?
}
