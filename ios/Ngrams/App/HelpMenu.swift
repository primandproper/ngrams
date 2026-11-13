import SwiftUI

/// A game's help button: Hint, and Solve behind a confirmation that says what solving costs.
struct HelpMenu: View {
  /// Hints taken so far.
  let used: Int
  /// Whether a hint has anything left to reveal.
  let canHint: Bool
  /// What solving costs, said before the player confirms.
  let solveWarning: LocalizedStringKey
  let onHint: () -> Void
  let onSolve: () -> Void

  @State private var confirming = false

  var body: some View {
    Menu {
      Button(action: onHint) {
        Label {
          if used == 0 {
            Text("Hint")
          } else {
            Text("Hint (\(used) used)")
          }
        } icon: {
          Image(systemName: "lightbulb")
        }
      }
      .disabled(!canHint)
      Button("Solve…", systemImage: "wand.and.stars", role: .destructive) {
        confirming = true
      }
    } label: {
      Label("Help", systemImage: used == 0 ? "lifepreserver" : "lifepreserver.fill")
    }
    .accessibilityIdentifier("help")
    .confirmationDialog("Solve this puzzle?", isPresented: $confirming, titleVisibility: .visible) {
      Button("Solve", role: .destructive, action: onSolve)
    } message: {
      Text(solveWarning)
    }
  }
}
