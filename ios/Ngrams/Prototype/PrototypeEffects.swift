// PROTOTYPE: throwaway code for epic #12. Candidates for a shared animation layer in
// platform-ui-swift once we know which ones stay.

import SwiftUI

/// Shakes side to side once for each step `shakes` takes.
struct Shake: GeometryEffect {
  var shakes: CGFloat
  var distance: CGFloat = 10

  var animatableData: CGFloat {
    get { shakes }
    set { shakes = newValue }
  }

  func effectValue(size: CGSize) -> ProjectionTransform {
    ProjectionTransform(
      CGAffineTransform(translationX: distance * sin(shakes * .pi * 4), y: 0))
  }
}

extension View {
  /// Shakes whenever `trigger` goes up, or does nothing when `enabled` is off or Reduce Motion
  /// is on.
  func prototypeShake(_ trigger: Int, enabled: Bool) -> some View {
    modifier(ShakeOnChange(trigger: trigger, enabled: enabled))
  }
}

private struct ShakeOnChange: ViewModifier {
  let trigger: Int
  let enabled: Bool

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.prototype) private var switches

  func body(content: Content) -> some View {
    content
      .modifier(Shake(shakes: enabled && !reduceMotion ? CGFloat(trigger) : 0))
      .animation(.linear(duration: switches.time(0.4)), value: trigger)
  }
}

/// Dots that fly out from the middle and fade, each time `trigger` goes up. Reduce Motion gets
/// a soft glow instead.
struct Burst: View {
  let trigger: Int
  var color: Color = .orange
  var count = 18
  var radius: CGFloat = 150

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.prototype) private var switches

  var body: some View {
    ZStack {
      if reduceMotion {
        Circle()
          .fill(color.opacity(0.25))
          .frame(width: radius, height: radius)
          .keyframeAnimator(initialValue: 0.0, trigger: trigger) { view, opacity in
            view.opacity(opacity)
          } keyframes: { _ in
            LinearKeyframe(1, duration: switches.time(0.2))
            LinearKeyframe(0, duration: switches.time(0.6))
          }
      } else {
        ForEach(0..<count, id: \.self) { index in
          let angle = Double(index) / Double(count) * 2 * .pi
          Circle()
            .fill(index.isMultiple(of: 3) ? color : color.opacity(0.6))
            .frame(width: index.isMultiple(of: 2) ? 10 : 7)
            .keyframeAnimator(initialValue: BurstFrame(), trigger: trigger) { view, frame in
              view
                .offset(
                  x: cos(angle) * frame.distance * radius,
                  y: sin(angle) * frame.distance * radius
                )
                .scaleEffect(frame.scale)
                .opacity(frame.opacity)
            } keyframes: { _ in
              KeyframeTrack(\.distance) {
                CubicKeyframe(0, duration: 0.01)
                SpringKeyframe(1, duration: switches.time(0.7), spring: .bouncy)
              }
              KeyframeTrack(\.opacity) {
                LinearKeyframe(1, duration: 0.01)
                LinearKeyframe(1, duration: switches.time(0.4))
                LinearKeyframe(0, duration: switches.time(0.4))
              }
              KeyframeTrack(\.scale) {
                LinearKeyframe(1.4, duration: switches.time(0.2))
                LinearKeyframe(0.4, duration: switches.time(0.6))
              }
            }
        }
      }
    }
    .allowsHitTesting(false)
  }
}

private struct BurstFrame {
  var distance: CGFloat = 0
  var opacity: Double = 0
  var scale: CGFloat = 1
}

extension View {
  /// Hops up and back down each time `trigger` goes up, after `delay`.
  func prototypeHop(_ trigger: Int, delay: Double, enabled: Bool) -> some View {
    modifier(Hop(trigger: trigger, delay: delay, enabled: enabled))
  }
}

private struct Hop: ViewModifier {
  let trigger: Int
  let delay: Double
  let enabled: Bool

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.prototype) private var switches

  func body(content: Content) -> some View {
    if enabled, !reduceMotion {
      content.keyframeAnimator(initialValue: 0.0, trigger: trigger) { view, lift in
        view.offset(y: -lift)
      } keyframes: { _ in
        LinearKeyframe(0, duration: switches.time(delay))
        SpringKeyframe(18, duration: switches.time(0.15))
        SpringKeyframe(0, duration: switches.time(0.35), spring: .bouncy)
      }
    } else {
      content
    }
  }
}

extension View {
  /// A score that rolls to its new value, and a bar that springs to it.
  func prototypeCountUp(_ value: Int) -> some View {
    modifier(CountUp(value: value))
  }

  /// A burst and a bouncy entrance for whatever appears when `earned` turns on.
  func prototypeStar(_ earned: Bool) -> some View {
    modifier(StarCelebration(earned: earned))
  }
}

private struct CountUp: ViewModifier {
  let value: Int

  @Environment(\.prototype) private var switches

  func body(content: Content) -> some View {
    if switches.scoreCountUp {
      content
        .contentTransition(.numericText(value: Double(value)))
        .animation(.snappy(duration: switches.time(0.4)), value: value)
    } else {
      content
    }
  }
}

private struct StarCelebration: ViewModifier {
  let earned: Bool

  @Environment(\.prototype) private var switches
  @Environment(\.dsTheme) private var theme

  func body(content: Content) -> some View {
    if switches.starCelebration {
      content
        .animation(.bouncy(duration: switches.time(0.5), extraBounce: 0.25), value: earned)
        .overlay {
          Burst(trigger: earned ? 1 : 0, color: theme.colors.tertiary, count: 24, radius: 180)
        }
    } else {
      content
    }
  }
}

/// A button that dips while pressed and springs back.
struct PulseStyle: ButtonStyle {
  let enabled: Bool

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.prototype) private var switches

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .scaleEffect(enabled && !reduceMotion && configuration.isPressed ? 0.9 : 1)
      .brightness(enabled && configuration.isPressed ? -0.08 : 0)
      .animation(
        .spring(response: switches.time(0.25), dampingFraction: 0.5), value: configuration.isPressed
      )
  }
}
