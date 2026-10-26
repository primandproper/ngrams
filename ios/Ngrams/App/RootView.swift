import Observability
import SwiftData
import SwiftUI

/// Loads the bundled bank, then hands it to the home screen.
struct RootView: View {
  private enum LoadState {
    case loading
    case loaded(PuzzleBank)
    case failed(String)
  }

  @Environment(\.pillars) private var pillars
  @Environment(\.modelContext) private var context
  @State private var state = LoadState.loading

  var body: some View {
    switch state {
    case .loading:
      ProgressView()
        .task { await load() }
    case .loaded(let bank):
      HomeView(bank: bank)
        .environment(\.puzzleBank, bank)
    case .failed(let message):
      ContentUnavailableView(
        "No puzzles", systemImage: "exclamationmark.triangle", description: Text(message))
    }
  }

  private func load() async {
    let logger = makeObserver("RootView", pillars).logger
    // Before home, the first screen that reads a hard mode.
    HardModeMigration.run(on: .standard, logger: logger)
    let started = ContinuousClock.now
    do {
      let bank = try await PuzzleBank.loadBundled()
      logger.withValue("days", bank.days.count)
        .withValue("took", "\(ContinuousClock.now - started)")
        .info("loaded puzzle bank")
      #if DEBUG
        if ScreenshotSeed.isOn {
          do {
            try ScreenshotSeed.plant(bank: bank, today: .today, in: context)
          } catch {
            logger.error("planting the screenshot seed", error)
          }
        }
      #endif
      state = .loaded(bank)
    } catch {
      logger.error("loading puzzle bank", error)
      state = .failed(String(describing: error))
    }
  }
}
