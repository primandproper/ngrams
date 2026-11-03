// PROTOTYPE: throwaway code for epic #12 (hints, solving, and animation). Nothing in
// ios/Ngrams/Prototype/ or marked "PROTOTYPE" is meant to merge; see NOTES.md beside this file.

import SwiftUI

/// Every animation the prototype tries, each on its own switch so it can be compared on the
/// device with and without. Held in memory: every switch starts on at launch.
@Observable
final class PrototypeSwitches {
  // Password
  var wordFlip = true
  var wordShake = true
  var wordBounce = true
  // Tiles
  var tilesLift = true
  var tilesSpring = true
  var tilesShake = true
  // Pangram
  var pangramPulse = true
  var pangramShake = true
  var pangramFoundPop = true
  // Off after playing: no particle bursts (2026-11-02).
  var pangramBurst = false
  var pangramSpin = true
  // Shared
  var scoreCountUp = true
  var starCelebration = true
  var haptics = true
  /// Slows every prototype animation down, to see what each one is doing.
  var slowMotion = false

  /// Seconds stretched by `slowMotion`.
  func time(_ seconds: Double) -> Double {
    slowMotion ? seconds * 4 : seconds
  }
}

extension EnvironmentValues {
  @Entry var prototype = PrototypeSwitches()
}

/// The panel of switches, opened from the pill on each game screen.
struct PrototypePanel: View {
  @Bindable var switches: PrototypeSwitches
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      Form {
        Section {
          Toggle(isOn: $switches.wordFlip) { Text(verbatim: "Letters flip to show their marks") }
          Toggle(isOn: $switches.wordShake) { Text(verbatim: "Row shakes on a rejected guess") }
          Toggle(isOn: $switches.wordBounce) { Text(verbatim: "Winning row bounces") }
        } header: {
          Text(verbatim: "Password")
        }
        Section {
          Toggle(isOn: $switches.tilesLift) { Text(verbatim: "Selected tiles lift") }
          Toggle(isOn: $switches.tilesSpring) {
            Text(verbatim: "Springy board when targets slide up")
          }
          Toggle(isOn: $switches.tilesShake) { Text(verbatim: "Current word shakes on a miss") }
        } header: {
          Text(verbatim: "Tiles")
        }
        Section {
          Toggle(isOn: $switches.pangramPulse) { Text(verbatim: "Wedges pulse when tapped") }
          Toggle(isOn: $switches.pangramShake) { Text(verbatim: "Current word shakes on a miss") }
          Toggle(isOn: $switches.pangramFoundPop) {
            Text(verbatim: "Found words pop into the list")
          }
          Toggle(isOn: $switches.pangramBurst) { Text(verbatim: "Burst on a pangram") }
          Toggle(isOn: $switches.pangramSpin) { Text(verbatim: "Shuffle spins the ring") }
        } header: {
          Text(verbatim: "Pangram")
        }
        Section {
          Toggle(isOn: $switches.scoreCountUp) { Text(verbatim: "Score counts up") }
          Toggle(isOn: $switches.starCelebration) { Text(verbatim: "Star celebration") }
          Toggle(isOn: $switches.haptics) { Text(verbatim: "Haptics") }
          Toggle(isOn: $switches.slowMotion) { Text(verbatim: "Slow motion (4x)") }
        } header: {
          Text(verbatim: "Everywhere")
        } footer: {
          Text(
            verbatim:
              "Reduce Motion in iOS Settings turns movement into fades. Progress in this build lives in memory only and is gone at the next launch."
          )
        }
      }
      .navigationTitle(Text(verbatim: "Prototype"))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button {
            dismiss()
          } label: {
            Text(verbatim: "Done")
          }
        }
      }
    }
    .presentationDetents([.medium, .large])
  }
}

extension View {
  /// A floating pill, in debug builds only, that opens the prototype's switches.
  func prototypePill() -> some View {
    modifier(PrototypePill())
  }
}

private struct PrototypePill: ViewModifier {
  @Environment(\.prototype) private var switches
  @State private var showing = false

  /// Off once the verdict was in, so the phone build plays like the real thing.
  private static let shown = false

  func body(content: Content) -> some View {
    #if DEBUG
      if Self.shown {
        pill(content)
      } else {
        content
      }
    #else
      content
    #endif
  }

  private func pill(_ content: Content) -> some View {
    content
      .overlay(alignment: .bottomLeading) {
        Button {
          showing = true
        } label: {
          Label {
            Text(verbatim: "Prototype")
          } icon: {
            Image(systemName: "slider.horizontal.3")
          }
          .font(.caption.weight(.bold))
          .padding(.horizontal, 10)
          .padding(.vertical, 6)
          .foregroundStyle(.white)
          .background(.purple, in: .capsule)
          .shadow(radius: 4)
        }
        .padding(.leading, 12)
        .padding(.bottom, 4)
      }
      .sheet(isPresented: $showing) {
        PrototypePanel(switches: switches)
      }
  }
}
