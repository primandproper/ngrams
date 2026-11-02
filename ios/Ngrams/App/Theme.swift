import DesignSystem
import SwiftUI

extension DSTheme {
  /// The ngrams look, over platform-ui's base. Its values are recorded in docs/design.md so the
  /// Android theme can match.
  ///
  /// The theme has no room for an app's own roles, so the games borrow the tokens nearest them:
  /// - `primary`: a correct letter, a selected tile, the center letter, a highlighted bar
  /// - `secondary`: a letter in the word, a typed letter's cell, the other bars
  /// - `tertiary`: the star and the streak flame
  /// - `success`: solved tiles, at 20% opacity
  /// - `cardBackground`: tiles, wedges, and absent keys
  /// - `cardBackgroundElevated`: letter keys
  /// - `border`: an empty or absent letter's cell
  /// - `borderSubtle`: the Enter and Delete keys
  static let ngrams: DSTheme = {
    var theme = DSTheme.default
    theme.colors.primary = .accentColor
    theme.colors.secondary = Color(.systemGray)
    theme.colors.tertiary = .orange
    theme.colors.success = .green
    theme.colors.cardBackground = Color(.secondarySystemBackground)
    theme.colors.cardBackgroundElevated = Color(.systemGray5)
    theme.colors.border = Color(.systemGray5)
    theme.colors.borderSubtle = Color(.systemGray4)
    theme.colors.textOnPrimary = .white

    theme.radius.xs = 4
    theme.radius.sm = 6
    theme.radius.md = 8
    theme.radius.lg = 10

    theme.animation.normal = .default
    return theme
  }()
}
