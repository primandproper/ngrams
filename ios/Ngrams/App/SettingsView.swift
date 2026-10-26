import SwiftUI

/// `@AppStorage` keys for app-wide settings.
enum SettingsKey {
  static let wordHardMode = "wordHardMode"
  static let solvedTilesLeave = "solvedTilesLeave"
  static let pangramHardMode = "pangramHardMode"
  static let pangramFoundOrder = "pangramFoundOrder"
  static let languages = "languages"
  static let homeGrouping = "homeGrouping"
}

struct SettingsView: View {
  @AppStorage(SettingsKey.wordHardMode) private var wordHardMode = false
  @AppStorage(SettingsKey.solvedTilesLeave) private var solvedTilesLeave = false
  @AppStorage(SettingsKey.pangramHardMode) private var pangramHardMode = false
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
          Toggle("Hard mode", isOn: $wordHardMode)
        } header: {
          Text("Password")
        } footer: {
          Text(
            "Every guess uses the hints so far: green letters stay put and yellow letters appear somewhere. A puzzle keeps the mode it had at its first guess."
          )
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
        Section {
          Toggle("Hard mode", isOn: $pangramHardMode)
        } header: {
          Text("Pangram")
        } footer: {
          Text(
            "The first word on a board has to be a pangram. A board keeps the mode it had at its first word."
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
