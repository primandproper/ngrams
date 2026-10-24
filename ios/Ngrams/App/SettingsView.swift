import SwiftUI

/// `@AppStorage` keys for app-wide settings.
enum SettingsKey {
  static let solvedTilesLeave = "solvedTilesLeave"
  static let languages = "languages"
}

struct SettingsView: View {
  @AppStorage(SettingsKey.solvedTilesLeave) private var solvedTilesLeave = false
  @AppStorage(SettingsKey.languages) private var languages: LanguageSelection?
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      Form {
        Section("Languages") {
          LanguageToggles(
            selection: Binding(
              get: { languages ?? LanguageSelection(Set(Language.allCases)) },
              set: { languages = $0 }))
        }
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
