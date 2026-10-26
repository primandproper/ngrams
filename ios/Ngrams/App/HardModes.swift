import Foundation
import Observability

/// Moves each game's hard mode from the single switch it used to be to the languages it's on for.
nonisolated enum HardModeMigration {
  /// Each game's languages after the move. A game with only its old switch gets every language if
  /// the switch was on and none if it was off; a game already stored per language keeps that.
  static func migrated(
    legacy: [PuzzleKind: Bool], current: [PuzzleKind: LanguageSelection]
  ) -> [PuzzleKind: LanguageSelection] {
    var result = current
    for (kind, on) in legacy where result[kind] == nil {
      result[kind] = LanguageSelection(on ? Set(Language.allCases) : [])
    }
    return result
  }

  /// Runs the move on `defaults` and drops the old switches. Does nothing once they're gone.
  static func run(on defaults: UserDefaults, logger: any Logger) {
    var legacy: [PuzzleKind: Bool] = [:]
    var current: [PuzzleKind: LanguageSelection] = [:]
    for kind in PuzzleKind.allCases {
      if let on = defaults.object(forKey: SettingsKey.legacyHardMode(kind)) as? Bool {
        legacy[kind] = on
      }
      if let selection = defaults.string(forKey: SettingsKey.hardMode(kind))
        .flatMap(LanguageSelection.init(rawValue:))
      {
        current[kind] = selection
      }
    }
    guard !legacy.isEmpty else { return }

    for (kind, selection) in migrated(legacy: legacy, current: current) {
      defaults.set(selection.rawValue, forKey: SettingsKey.hardMode(kind))
    }
    for kind in legacy.keys {
      defaults.removeObject(forKey: SettingsKey.legacyHardMode(kind))
    }
    logger.withValue("games", legacy.keys.map(\.rawValue).sorted().joined(separator: ","))
      .info("moved hard modes to per language")
  }
}
