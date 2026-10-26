import Foundation
import SwiftUI

/// A set of languages, stored as comma-separated codes: the languages a player wants puzzles in,
/// under `SettingsKey.languages` and absent until they first choose, and the languages each hard
/// mode is on for, under `SettingsKey.hardMode(_:)`.
nonisolated struct LanguageSelection: RawRepresentable, Equatable, Sendable {
  var languages: Set<Language>

  init(_ languages: Set<Language>) {
    self.languages = languages
  }

  /// Comma-separated codes. Codes this build doesn't know are dropped.
  init?(rawValue: String) {
    languages = Set(rawValue.split(separator: ",").compactMap { Language(rawValue: String($0)) })
  }

  var rawValue: String {
    Language.allCases.filter(languages.contains).map(\.rawValue).joined(separator: ",")
  }

  /// The languages the device is set up for, as a first guess.
  static func suggested(from preferred: [String] = Locale.preferredLanguages) -> LanguageSelection {
    let codes = Set(
      preferred.compactMap { Locale.Language(identifier: $0).languageCode?.identifier })
    return LanguageSelection(Set(Language.allCases.filter { codes.contains($0.rawValue) }))
  }
}

/// One switch per language.
struct LanguageToggles: View {
  @Binding var selection: LanguageSelection
  /// Whether the last language left on can be switched off.
  var allowsNone = false

  var body: some View {
    ForEach(Language.allCases, id: \.self) { language in
      let isOn = selection.languages.contains(language)
      Toggle(
        "\(language.flag) \(language.name)",
        isOn: Binding(
          get: { isOn },
          set: { on in
            if on {
              selection.languages.insert(language)
            } else {
              selection.languages.remove(language)
            }
          })
      )
      .disabled(isOn && selection.languages.count == 1 && !allowsNone)
    }
  }
}

/// Asked once, before the first puzzle, so nobody is handed puzzles in a language they don't play.
struct LanguagePrompt: View {
  let choose: (LanguageSelection) -> Void

  @State private var draft = LanguageSelection.suggested()

  var body: some View {
    NavigationStack {
      Form {
        Section {
          LanguageToggles(selection: $draft, allowsNone: true)
        } header: {
          Text("Which languages do you want puzzles in?")
        } footer: {
          Text("You can change this any time in Settings.")
        }
      }
      .navigationTitle("Languages")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Continue") { choose(draft) }
            .disabled(draft.languages.isEmpty)
        }
      }
    }
    .interactiveDismissDisabled()
  }
}
