import SwiftUI

/// `@AppStorage` keys for app-wide settings.
enum SettingsKey {
  static let solvedTilesLeave = "solvedTilesLeave"
}

struct SettingsView: View {
  @AppStorage(SettingsKey.solvedTilesLeave) private var solvedTilesLeave = false
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      Form {
        Section {
          Toggle("Hard mode", isOn: $solvedTilesLeave)
        } header: {
          Text("Tiles")
        } footer: {
          Text(
            "Found targets leave the board, so their tiles can't spell other words. Finding the last target ends the board."
          )
        }
      }
      .navigationTitle("Settings")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { dismiss() }
        }
      }
    }
  }
}
