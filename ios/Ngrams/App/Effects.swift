import SwiftUI

/// Moves a view side to side, once per whole step `shakes` takes.
private struct Shake: GeometryEffect {
  var shakes: CGFloat
  var distance: CGFloat = 10

  var animatableData: CGFloat {
    get { shakes }
    set { shakes = newValue }
  }

  func effectValue(size: CGSize) -> ProjectionTransform {
    ProjectionTransform(CGAffineTransform(translationX: distance * sin(shakes * .pi * 4), y: 0))
  }
}

private struct ShakeOnChange: ViewModifier {
  let trigger: Int
  let active: Bool

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  func body(content: Content) -> some View {
    content
      .modifier(Shake(shakes: reduceMotion ? 0 : CGFloat(trigger), distance: active ? 10 : 0))
      .animation(.linear(duration: 0.4), value: trigger)
  }
}

private struct Hop: ViewModifier {
  let trigger: Int
  let delay: Double

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  func body(content: Content) -> some View {
    if reduceMotion {
      content
    } else {
      content.keyframeAnimator(initialValue: 0.0, trigger: trigger) { view, lift in
        view.offset(y: -lift)
      } keyframes: { _ in
        LinearKeyframe(0, duration: delay)
        SpringKeyframe(18, duration: 0.15)
        SpringKeyframe(0, duration: 0.35, spring: .bouncy)
      }
    }
  }
}

private struct CountUp: ViewModifier {
  let value: Int

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  func body(content: Content) -> some View {
    content
      .contentTransition(reduceMotion ? .opacity : .numericText(value: Double(value)))
      .animation(reduceMotion ? .easeInOut(duration: 0.2) : .snappy(duration: 0.4), value: value)
  }
}

private struct StarEntrance: ViewModifier {
  let earned: Bool

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  func body(content: Content) -> some View {
    content.animation(
      reduceMotion ? .easeInOut(duration: 0.2) : .bouncy(duration: 0.5, extraBounce: 0.25),
      value: earned)
  }
}

extension View {
  /// Shakes whenever `trigger` goes up while `active`, unless Reduce Motion is on. Views that
  /// take turns shaking share one trigger and pass `active`, so a view turning active never
  /// sees the trigger jump.
  func shake(on trigger: Int, active: Bool = true) -> some View {
    modifier(ShakeOnChange(trigger: trigger, active: active))
  }

  /// Hops up and lands, `delay` seconds after `trigger` changes, unless Reduce Motion is on.
  func hop(on trigger: Int, delay: Double) -> some View {
    modifier(Hop(trigger: trigger, delay: delay))
  }

  /// A number that rolls to its new value, or a bar that springs to it.
  func countingUp(_ value: Int) -> some View {
    modifier(CountUp(value: value))
  }

  /// Bounces in the "Star earned" line when `earned` turns on. The line itself takes
  /// `AnyTransition.starEntrance`.
  func starEntrance(_ earned: Bool) -> some View {
    modifier(StarEntrance(earned: earned))
  }

  /// Goes back to home a moment after `won` turns on. A puzzle opened already won stays open,
  /// and so does one lost or solved for the player, whose answer is still to be read.
  func returnsHome(whenWon won: Bool) -> some View {
    modifier(ReturnHome(won: won))
  }
}

extension AnyTransition {
  /// Grows from small and fades in, or only fades with Reduce Motion on.
  static func pop(reduceMotion: Bool) -> AnyTransition {
    reduceMotion ? .opacity : .scale(scale: 0.2).combined(with: .opacity)
  }
}

/// A button that dips and darkens while pressed and springs back. Reduce Motion keeps the shade
/// and drops the dip.
struct PulseStyle: ButtonStyle {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .scaleEffect(!reduceMotion && configuration.isPressed ? 0.9 : 1)
      .brightness(configuration.isPressed ? -0.08 : 0)
      .animation(.spring(response: 0.25, dampingFraction: 0.5), value: configuration.isPressed)
  }
}

private struct ReturnHome: ViewModifier {
  let won: Bool

  @Environment(\.dismiss) private var dismiss
  @State private var returning = false

  func body(content: Content) -> some View {
    content
      .onChange(of: won) { was, won in
        if !was, won {
          returning = true
        }
      }
      // A task, so leaving first cancels the wait.
      .task(id: returning) {
        guard returning else { return }
        try? await Task.sleep(for: .seconds(1.5))
        if !Task.isCancelled {
          dismiss()
        }
      }
  }
}
