import Observability
import SwiftUI

/// Loads the bundled bank, then hands it to the home screen.
struct RootView: View {
  private enum LoadState {
    case loading
    case loaded(PuzzleBank)
    case failed(String)
  }

  @Environment(\.pillars) private var pillars
  @State private var state = LoadState.loading

  var body: some View {
    switch state {
    case .loading:
      ProgressView()
        .task { await load() }
    case .loaded(let bank):
      HomeView(bank: bank)
    case .failed(let message):
      ContentUnavailableView(
        "No puzzles", systemImage: "exclamationmark.triangle", description: Text(message))
    }
  }

  private func load() async {
    let logger = makeObserver("RootView", pillars).logger
    let started = ContinuousClock.now
    do {
      let bank = try await PuzzleBank.loadBundled()
      logger.withValue("days", bank.days.count)
        .withValue("took", "\(ContinuousClock.now - started)")
        .info("loaded puzzle bank")
      state = .loaded(bank)
    } catch {
      logger.error("loading puzzle bank", error)
      state = .failed(String(describing: error))
    }
  }
}
