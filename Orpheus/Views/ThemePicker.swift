import SwiftUI

/// A row of round swatches, one per theme, to change the look of the panel.
struct ThemePicker: View {
    @Binding var selection: ThemeID

    @Environment(\.theme) private var theme

    private static let swatchSize: CGFloat = 28

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionTitle(text: "Theme")
                Spacer()
                Text(Theme.theme(for: selection).name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.textSecondary)
            }
            HStack(spacing: 0) {
                ForEach(Theme.all) { option in
                    swatch(option)
                    if option.id != Theme.all.last?.id {
                        Spacer(minLength: 4)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Theme")
    }

    private func swatch(_ option: Theme) -> some View {
        let isSelected = option.id == selection
        return Button {
            selection = option.id
        } label: {
            ZStack {
                Circle()
                    .fill(option.background)
                Circle()
                    .fill(option.accentPrimary)
                    .frame(width: 10, height: 10)
                    .offset(x: -4, y: -3)
                Circle()
                    .fill(option.accentBoost)
                    .frame(width: 8, height: 8)
                    .offset(x: 5, y: 4)
            }
            .frame(width: Self.swatchSize, height: Self.swatchSize)
            .overlay {
                Circle()
                    .strokeBorder(isSelected ? theme.accentPrimary : theme.surfaceMuted, lineWidth: isSelected ? 2.5 : 1.5)
                    .padding(isSelected ? -4 : 0)
            }
            .padding(4)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.name)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .help(option.name)
    }
}
