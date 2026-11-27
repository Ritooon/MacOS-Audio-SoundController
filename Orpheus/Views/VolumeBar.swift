import SwiftUI

/// The pure logic behind ``VolumeBar``, kept separate so it can be unit-tested.
enum VolumeBarMath {
    /// The amount one arrow key or VoiceOver adjustment changes the value.
    static let step: Float = 0.05

    /// Converts a horizontal position on the bar into a value.
    /// - Parameters:
    ///   - location: The x position in points, from the leading edge.
    ///   - width: The width of the bar in points.
    ///   - maximum: The value at the trailing edge (1 for 100 %, more for boost).
    /// - Returns: A value clamped to `0...maximum`.
    static func value(at location: CGFloat, width: CGFloat, maximum: Float) -> Float {
        guard width > 0 else { return 0 }
        let fraction = min(max(location / width, 0), 1)
        return Float(fraction) * maximum
    }

    /// Moves a value by a number of steps.
    /// - Parameters:
    ///   - value: The current value.
    ///   - steps: Positive to increase, negative to decrease.
    ///   - maximum: The largest allowed value.
    /// - Returns: The new value, snapped to the step grid and clamped to `0...maximum`.
    static func stepped(_ value: Float, by steps: Int, maximum: Float) -> Float {
        let snapped = (value / step).rounded() * step
        return min(max(snapped + Float(steps) * step, 0), maximum)
    }

    /// How close to 100 % a dragged boost bar snaps back to exactly 100 %.
    static let unitySnapTolerance: Float = 0.05

    /// Snaps a value to 100 % when it is close, so the user can return to "untouched" easily.
    /// - Parameters:
    ///   - value: The dragged value.
    ///   - tolerance: The distance within which the value snaps.
    /// - Returns: 1 when `value` is within `tolerance` of 1, otherwise `value`.
    static func snappedToUnity(_ value: Float, tolerance: Float = unitySnapTolerance) -> Float {
        abs(value - 1) <= tolerance ? 1 : value
    }

    /// The value as a whole percentage, for display.
    /// - Parameter value: A value where 1 means 100 %.
    /// - Returns: The rounded percentage.
    static func percent(_ value: Float) -> Int {
        Int((value * 100).rounded())
    }
}

/// A thick capsule volume bar that behaves like a slider.
///
/// The part above 100 % (boost) is drawn brighter, with a glow unless Reduce Transparency is on.
/// It works with the mouse, the arrow keys and VoiceOver.
struct VolumeBar: View {
    /// The current value; 1 means 100 %.
    let value: Float
    /// The value at the trailing edge.
    var maximum: Float = 1
    /// Whether to draw the bar dimmed (for example when muted).
    var isDimmed = false
    /// The accessibility label, for example "Output volume".
    let label: String
    /// Called with the new value while the user drags or presses keys.
    let onChange: (Float) -> Void

    @Environment(\.theme) private var theme
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var dragValue: Float?
    @FocusState private var isFocused: Bool

    private static let boostThreshold: Float = 1

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let shown = dragValue ?? value
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(theme.surfaceMuted)
                Capsule()
                    .fill(isDimmed || !isEnabled ? theme.textDisabled : theme.accentBoost)
                    .frame(width: fillWidth(for: min(shown, Self.boostThreshold), in: width))
                if shown > Self.boostThreshold {
                    boostSegment(from: fillWidth(for: Self.boostThreshold, in: width), to: fillWidth(for: shown, in: width))
                }
                if maximum > Self.boostThreshold {
                    // Marks 100 %: everything to the right is boost.
                    Capsule()
                        .fill(theme.textSecondary)
                        .frame(width: 2, height: Theme.Metrics.barThickness + 6)
                        .offset(x: fillWidth(for: Self.boostThreshold, in: width) - 1)
                }
            }
            .frame(height: Theme.Metrics.barThickness)
            .overlay {
                if isFocused || contrast == .increased {
                    Capsule()
                        .strokeBorder(isFocused ? theme.accentPrimary : theme.textSecondary, lineWidth: isFocused ? 2 : 1)
                        .padding(-2)
                }
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let rawValue = VolumeBarMath.value(at: gesture.location.x, width: width, maximum: maximum)
                        let newValue = maximum > Self.boostThreshold ? VolumeBarMath.snappedToUnity(rawValue) : rawValue
                        dragValue = newValue
                        onChange(newValue)
                    }
                    .onEnded { _ in dragValue = nil }
            )
        }
        .frame(height: Theme.Metrics.barHitHeight)
        .animation(dragValue == nil ? Theme.motion(reduceMotion: reduceMotion) : nil, value: value)
        .focusable(isEnabled)
        .focusEffectDisabled()
        .focused($isFocused)
        .onKeyPress(.leftArrow) { adjust(by: -1) }
        .onKeyPress(.downArrow) { adjust(by: -1) }
        .onKeyPress(.rightArrow) { adjust(by: 1) }
        .onKeyPress(.upArrow) { adjust(by: 1) }
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityValue("\(VolumeBarMath.percent(value)) %")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onChange(VolumeBarMath.stepped(value, by: 1, maximum: maximum))
            case .decrement: onChange(VolumeBarMath.stepped(value, by: -1, maximum: maximum))
            @unknown default: break
            }
        }
        .help("\(label): \(VolumeBarMath.percent(value)) %")
    }

    private func fillWidth(for value: Float, in width: CGFloat) -> CGFloat {
        guard maximum > 0 else { return 0 }
        return width * CGFloat(min(max(value / maximum, 0), 1))
    }

    private func boostSegment(from start: CGFloat, to end: CGFloat) -> some View {
        Capsule()
            .fill(theme.accentBoost)
            .brightness(0.15)
            .frame(width: max(end - start, 0))
            .offset(x: start)
            .shadow(color: reduceTransparency ? .clear : theme.accentBoost, radius: Theme.Metrics.glowRadius)
    }

    private func adjust(by steps: Int) -> KeyPress.Result {
        guard isEnabled else { return .ignored }
        onChange(VolumeBarMath.stepped(value, by: steps, maximum: maximum))
        return .handled
    }
}
