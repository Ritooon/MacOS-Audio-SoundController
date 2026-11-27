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
                RoundedRectangle(cornerRadius: theme.shape.card, style: .continuous)
                    .fill(theme[keyPath: fill])
            )
            .overlay {
                if contrast == .increased {
                    RoundedRectangle(cornerRadius: theme.shape.card, style: .continuous)
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
            .font(theme.display(13, relativeTo: .subheadline))
            .tracking(theme.tracking(1.2))
            .foregroundStyle(theme.textSecondary)
            .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Chunky buttons and tiles

/// A rounded shape with a darker bottom edge, so it looks pressable like a game button.
struct ChunkyBackground: View {
    let color: Color
    /// The corner radius; `nil` uses the theme's tile radius.
    var cornerRadius: CGFloat?
    var isPressed = false

    @Environment(\.theme) private var theme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius ?? theme.shape.tile, style: .continuous)
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
    /// The corner radius; `nil` uses the theme's tile radius.
    var cornerRadius: CGFloat?

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
            .foregroundStyle(theme.onAccent)
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
            foreground: tint == nil ? theme.textPrimary : theme.onAccent,
            cornerRadius: theme.shape.iconButton
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

    @Environment(\.theme) private var theme

    var body: some View {
        Text(text)
            .font(theme.display(12, relativeTo: .caption).monospacedDigit())
            .foregroundStyle(foreground)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(minWidth: 48)
            .background(RoundedRectangle(cornerRadius: theme.shape.chip, style: .continuous).fill(background))
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
                RoundedRectangle(cornerRadius: theme.shape.checkbox, style: .continuous)
                    .fill(configuration.isOn ? theme.accentSuccess : .clear)
                    .overlay {
                        RoundedRectangle(cornerRadius: theme.shape.checkbox, style: .continuous)
                            .strokeBorder(configuration.isOn ? theme.accentSuccess : theme.accentPrimary, lineWidth: 2)
                    }
                    .overlay {
                        if configuration.isOn {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .heavy))
                                .foregroundStyle(theme.onAccent)
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

/// A short, bold pill in the boost colour with a darker bottom edge.
struct ToastView: View {
    let message: ToastMessage

    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: message.symbolName)
                .font(.system(size: 12, weight: .bold))
            Text(message.text)
                .font(theme.display(13, relativeTo: .callout))
                .lineLimit(1)
        }
        .foregroundStyle(theme.onAccent)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .padding(.bottom, Theme.Metrics.chunkyDepth)
        .background(ChunkyBackground(color: theme.accentBoost, cornerRadius: theme.shape.chip))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isStaticText)
    }
}

// MARK: - Decoration

/// A small ornament in the header, drawn from the theme. Purely decorative and static.
struct HeaderDecoration: View {
    @Environment(\.theme) private var theme

    private static let opacity: Double = 0.4
    private static let size = CGSize(width: 44, height: 30)

    var body: some View {
        ornament
            .frame(width: Self.size.width, height: Self.size.height)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var ornament: some View {
        switch theme.decoration {
        case .squares:
            HStack(alignment: .top, spacing: 4) {
                square(theme.accentPrimary, size: 10, angle: 12)
                square(theme.accentBoost, size: 7, angle: -18).offset(y: 8)
                square(theme.accentSuccess, size: 12, angle: 24)
            }
        case .pixels:
            ZStack {
                pixel(theme.accentPrimary, x: -12, y: -8)
                pixel(theme.accentBoost, x: 0, y: 0)
                pixel(theme.accentAction, x: -12, y: 8)
                pixel(theme.accentSuccess, x: 12, y: -8)
            }
        case .planet:
            ZStack {
                Circle()
                    .fill(RadialGradient(
                        colors: [theme.accentBoost, theme.accentAction],
                        center: UnitPoint(x: 0.35, y: 0.35), startRadius: 0, endRadius: 14
                    ))
                    .frame(width: 22, height: 22)
                Ellipse()
                    .stroke(theme.accentBoost.opacity(0.6), lineWidth: 1.5)
                    .frame(width: 40, height: 10)
                    .rotationEffect(.degrees(-18))
                Circle().fill(theme.textPrimary).frame(width: 2, height: 2).offset(x: -18, y: -11)
                Circle().fill(theme.textPrimary).frame(width: 1.5, height: 1.5).offset(x: 17, y: 11)
            }
        case .leaves:
            HStack(alignment: .top, spacing: 3) {
                leaf(theme.accentPrimary, size: 13, angle: 0)
                leaf(theme.accentBoost, size: 9, angle: 40).offset(y: 10)
                leaf(theme.accentSuccess, size: 11, angle: -20)
            }
        case .embers:
            ZStack {
                ember(x: -12, y: 8, size: 5)
                ember(x: 0, y: -4, size: 4)
                ember(x: 10, y: 6, size: 6)
                ember(x: 16, y: -10, size: 3)
            }
        case .crystals:
            HStack(alignment: .top, spacing: 5) {
                square(theme.accentPrimary, size: 11, angle: 45, radius: 2)
                square(theme.accentBoost, size: 7, angle: 45, radius: 2).offset(y: 10)
                square(theme.accentInfo, size: 9, angle: 45, radius: 2)
            }
        case .bubbles:
            ZStack {
                bubble(size: 14, x: -6, y: -4)
                bubble(size: 8, x: 10, y: 8)
                bubble(size: 6, x: 14, y: -10)
            }
        }
    }

    private func square(_ color: Color, size: CGFloat, angle: Double, radius: CGFloat? = nil) -> some View {
        RoundedRectangle(cornerRadius: radius ?? size * 0.3, style: .continuous)
            .fill(color.opacity(Self.opacity))
            .frame(width: size, height: size)
            .rotationEffect(.degrees(angle))
    }

    private func pixel(_ color: Color, x: CGFloat, y: CGFloat) -> some View {
        Rectangle()
            .fill(color.opacity(Self.opacity + 0.2))
            .frame(width: 8, height: 8)
            .offset(x: x, y: y)
    }

    private func leaf(_ color: Color, size: CGFloat, angle: Double) -> some View {
        UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: size, bottomTrailingRadius: 0, topTrailingRadius: size)
            .fill(color.opacity(Self.opacity + 0.1))
            .frame(width: size, height: size)
            .rotationEffect(.degrees(angle))
    }

    private func ember(x: CGFloat, y: CGFloat, size: CGFloat) -> some View {
        Circle()
            .fill(theme.accentBoost)
            .frame(width: size, height: size)
            .shadow(color: theme.accentPrimary, radius: 3)
            .offset(x: x, y: y)
    }

    private func bubble(size: CGFloat, x: CGFloat, y: CGFloat) -> some View {
        Circle()
            .stroke(theme.accentSuccess.opacity(Self.opacity + 0.1), lineWidth: 1.5)
            .frame(width: size, height: size)
            .offset(x: x, y: y)
    }
}
