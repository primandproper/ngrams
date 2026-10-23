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
}
