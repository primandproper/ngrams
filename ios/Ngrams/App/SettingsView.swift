import SwiftUI

/// `@AppStorage` keys for app-wide settings.
nonisolated enum SettingsKey {
  static let pangramFoundOrder = "pangramFoundOrder"
  static let languages = "languages"
  static let homeGrouping = "homeGrouping"

  /// The languages a game's hard mode is on for, as a `LanguageSelection`.
  static func hardMode(_ kind: PuzzleKind) -> String {
    "\(legacyHardMode(kind))Languages"
  }

  /// The single switch a game's hard mode was before it went per language. `HardModeMigration`
  /// moves it over.
  static func legacyHardMode(_ kind: PuzzleKind) -> String {
    switch kind {
    case .word: "wordHardMode"
    case .tiles: "solvedTilesLeave"
    case .pangram: "pangramHardMode"
    }
  }
}

struct SettingsView: View {
  @AppStorage(SettingsKey.hardMode(.word)) private var wordHardMode = LanguageSelection([])
  @AppStorage(SettingsKey.hardMode(.tiles)) private var tilesHardMode = LanguageSelection([])
  @AppStorage(SettingsKey.hardMode(.pangram)) private var pangramHardMode = LanguageSelection([])
  @AppStorage(SettingsKey.languages) private var languages: LanguageSelection?
  @Environment(\.dismiss) private var dismiss

  private var played: [Language] {
    let on = languages?.languages ?? Set(Language.allCases)
    return Language.allCases.filter(on.contains)
  }

  var body: some View {
    NavigationStack {
      Form {
        Section("Languages") {
          LanguageToggles(
            selection: Binding(
              get: { languages ?? LanguageSelection(Set(Language.allCases)) },
              set: { languages = $0 }))
        }
        // One language keeps a section per game; more get a section per language, so each can
        // be harder or easier than the others.
        if played.count == 1, let language = played.first {
          ForEach(PuzzleKind.allCases, id: \.self) { kind in
            Section {
              Toggle("Hard mode", isOn: hardMode(kind, language))
            } header: {
              Text(kind.name)
            } footer: {
              Text(rule(kind))
            }
          }
        } else {
          ForEach(played, id: \.self) { language in
            Section("\(language.flag) \(language.name)") {
              ForEach(PuzzleKind.allCases, id: \.self) { kind in
                Toggle(isOn: hardMode(kind, language)) {
                  Text("\(kind.name) hard mode")
                  Text(rule(kind))
                }
              }
            }
          }
        }
        Section {
          NavigationLink("Acknowledgements") { AcknowledgementsView() }
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

  /// Whether `kind`'s hard mode is on for `language`.
  private func hardMode(_ kind: PuzzleKind, _ language: Language) -> Binding<Bool> {
    let stored: Binding<LanguageSelection> =
      switch kind {
      case .word: $wordHardMode
      case .tiles: $tilesHardMode
      case .pangram: $pangramHardMode
      }
    return Binding(
      get: { stored.wrappedValue.languages.contains(language) },
      set: { on in
        if on {
          stored.wrappedValue.languages.insert(language)
        } else {
          stored.wrappedValue.languages.remove(language)
        }
      })
  }

  /// What a game's hard mode changes.
  private func rule(_ kind: PuzzleKind) -> String {
    switch kind {
    case .word:
      "Every guess uses the hints so far: green letters stay put and yellow letters appear somewhere. A puzzle keeps the mode it had at its first guess."
    case .tiles:
      "Found targets leave the board, so their tiles can't spell other words. Finding the last target ends the board."
    case .pangram:
      "The first word on a board has to be a pangram. A board keeps the mode it had at its first word."
    }
  }
}
