import SwiftUI

// Reusable building blocks of the "game HUD" look. Every colour comes from `Theme`.

// MARK: - Card

/// A large rounded card filled with `surface`, with a border when Increase Contrast is on.
struct QuestCard<Content: View>: View {
    var fill: KeyPath<Theme, Color> = \.surface
    @ViewBuilder let content: Content

    @Environment(\.theme) private var theme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        content
            .padding(Theme.Metrics.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.Metrics.cardCornerRadius, style: .continuous)
                    .fill(theme[keyPath: fill])
            )
            .overlay {
                if contrast == .increased {
                    RoundedRectangle(cornerRadius: Theme.Metrics.cardCornerRadius, style: .continuous)
                        .strokeBorder(theme.textSecondary, lineWidth: Theme.Metrics.contrastBorderWidth)
                }
            }
    }
}

/// A thin divider between rows of a card.
struct QuestDivider: View {
    @Environment(\.theme) private var theme

    var body: some View {
        Rectangle()
            .fill(theme.surfaceMuted)
            .frame(height: 2)
            .accessibilityHidden(true)
    }
}

/// An uppercase section title in the display font.
struct SectionTitle: View {
    let text: String
    @Environment(\.theme) private var theme

    var body: some View {
        Text(text.uppercased())
            .font(Theme.display(13, relativeTo: .subheadline))
            .tracking(1.2)
            .foregroundStyle(theme.textSecondary)
            .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Chunky buttons and tiles

/// A rounded shape with a darker bottom edge, so it looks pressable like a game button.
struct ChunkyBackground: View {
    let color: Color
    var cornerRadius: CGFloat = Theme.Metrics.tileCornerRadius
    var isPressed = false

    @Environment(\.theme) private var theme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        ZStack {
            shape
                .fill(Theme.edge(of: color))
                .offset(y: isPressed ? 0 : Theme.Metrics.chunkyDepth)
            shape
                .fill(color)
                .overlay {
                    if contrast == .increased {
                        shape.strokeBorder(theme.textPrimary, lineWidth: Theme.Metrics.contrastBorderWidth)
                    }
                }
        }
        .offset(y: isPressed ? Theme.Metrics.chunkyDepth : 0)
        .padding(.bottom, Theme.Metrics.chunkyDepth)
    }
}

/// A button style that moves down and loses its edge when pressed.
struct ChunkyButtonStyle: ButtonStyle {
    let color: Color
    var foreground: Color?
    var cornerRadius: CGFloat = Theme.Metrics.tileCornerRadius

    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(foreground ?? theme.textPrimary)
            .offset(y: configuration.isPressed ? Theme.Metrics.chunkyDepth : 0)
            .padding(.bottom, Theme.Metrics.chunkyDepth)
            .background(ChunkyBackground(color: color, cornerRadius: cornerRadius, isPressed: configuration.isPressed))
            .contentShape(Rectangle())
            .animation(Theme.motion(reduceMotion: reduceMotion), value: configuration.isPressed)
    }
}

/// A square tile with an SF Symbol, used for device badges.
struct SymbolTile: View {
    let symbolName: String
    let color: Color
    var size: CGFloat = Theme.Metrics.tileSize

    @Environment(\.theme) private var theme

    var body: some View {
        Image(systemName: symbolName)
            .font(.system(size: size * 0.45, weight: .bold))
            .foregroundStyle(theme.background)
            .frame(width: size, height: size)
            .padding(.bottom, Theme.Metrics.chunkyDepth)
            .background(ChunkyBackground(color: color))
            .accessibilityHidden(true)
    }
}

/// A rounded square button in `surfaceMuted` with a white SF Symbol.
struct IconButton: View {
    let symbolName: String
    let label: String
    var tint: Color?
    let action: () -> Void

    @Environment(\.theme) private var theme

    var body: some View {
        Button(action: action) {
            Image(systemName: symbolName)
                .font(.system(size: 13, weight: .bold))
                .frame(width: Theme.Metrics.iconButtonSize, height: Theme.Metrics.iconButtonSize)
        }
        .buttonStyle(ChunkyButtonStyle(
            color: tint ?? theme.surfaceMuted,
            foreground: tint == nil ? theme.textPrimary : theme.background,
            cornerRadius: Theme.Metrics.iconButtonCornerRadius
        ))
        .accessibilityLabel(label)
        .help(label)
    }
}

// MARK: - Chips

/// A value pill: coloured text on a dark background of the same hue.
struct ValueChip: View {
    let text: String
    let foreground: Color
    let background: Color

    var body: some View {
        Text(text)
            .font(Theme.display(12, relativeTo: .caption).monospacedDigit())
            .foregroundStyle(foreground)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(minWidth: 48)
            .background(Capsule().fill(background))
    }
}

// MARK: - Checkbox

/// A rounded square outlined in `accentPrimary`; filled `accentSuccess` with a dark check when on.
struct QuestCheckboxStyle: ToggleStyle {
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let boxSize: CGFloat = 20

    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(configuration.isOn ? theme.accentSuccess : .clear)
                    .overlay {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(configuration.isOn ? theme.accentSuccess : theme.accentPrimary, lineWidth: 2)
                    }
                    .overlay {
                        if configuration.isOn {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .heavy))
                                .foregroundStyle(theme.background)
                        }
                    }
                    .frame(width: Self.boxSize, height: Self.boxSize)
                configuration.label
                    .foregroundStyle(theme.textPrimary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(Theme.motion(reduceMotion: reduceMotion), value: configuration.isOn)
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }
        }
    }
}

// MARK: - Toast

/// A short, bold, yellow pill with a darker bottom edge.
struct ToastView: View {
    let message: ToastMessage

    /// Large enough to turn the rounded rectangle into a pill.
    private static let pillRadius: CGFloat = 100

    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: message.symbolName)
                .font(.system(size: 12, weight: .bold))
            Text(message.text)
                .font(Theme.display(13, relativeTo: .callout))
                .lineLimit(1)
        }
        .foregroundStyle(theme.background)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .padding(.bottom, Theme.Metrics.chunkyDepth)
        .background(ChunkyBackground(color: theme.accentBoost, cornerRadius: Self.pillRadius))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isStaticText)
    }
}

// MARK: - Decoration

/// A few soft coloured squares, as in Today Quest's header. Purely decorative.
struct HeaderDecoration: View {
    @Environment(\.theme) private var theme

    private static let opacity: Double = 0.35

    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            square(theme.accentPrimary, size: 10, angle: 12)
            square(theme.accentBoost, size: 7, angle: -18)
                .offset(y: 8)
            square(theme.accentSuccess, size: 12, angle: 24)
        }
        .accessibilityHidden(true)
    }

    private func square(_ color: Color, size: CGFloat, angle: Double) -> some View {
        RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
            .fill(color.opacity(Self.opacity))
            .frame(width: size, height: size)
            .rotationEffect(.degrees(angle))
    }
}
