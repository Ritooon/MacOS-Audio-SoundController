import SwiftUI

extension DeviceRole {
    /// The section title shown in the panel.
    var title: String {
        switch self {
        case .output: "Output"
        case .input: "Input"
        case .soundEffects: "Sound effects"
        }
    }

    /// Shown when no device can fill the role.
    var emptyMessage: String {
        switch self {
        case .output, .soundEffects: "No output device"
        case .input: "No input device"
        }
    }
}

/// One row of the system card: the device assigned to a role, its volume bar,
/// and a collapsible list to pick another device.
struct DeviceSectionView: View {
    let role: DeviceRole
    let state: SystemAudioModel.RoleState
    let onSelect: (AudioDevice.ID) -> Void
    let onVolumeChange: (Float) -> Void
    let onToggleMute: () -> Void

    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if let volume = state.volume {
                volumeRow(volume)
            }
            if isExpanded {
                deviceList
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    // MARK: Header

    private var header: some View {
        Button {
            withAnimation(Theme.motion(reduceMotion: reduceMotion)) { isExpanded.toggle() }
        } label: {
            HStack(spacing: 12) {
                SymbolTile(
                    symbolName: deviceSymbol(state.selectedDevice),
                    color: state.selectedDevice == nil ? theme.textDisabled : theme.accentPrimary
                )
                VStack(alignment: .leading, spacing: 2) {
                    SectionTitle(text: role.title)
                    Text(state.selectedDevice?.name ?? role.emptyMessage)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(state.selectedDevice == nil ? theme.textDisabled : theme.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Spacer(minLength: 8)
                if state.devices.count > 1 {
                    ValueChip(
                        text: "\(state.devices.count)",
                        foreground: theme.accentPrimary,
                        background: theme.surfaceMuted
                    )
                    .accessibilityHidden(true)
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(theme.textSecondary)
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(state.devices.isEmpty)
        .accessibilityLabel("\(role.title) device")
        .accessibilityValue(state.selectedDevice?.name ?? role.emptyMessage)
        .accessibilityHint(isExpanded ? "Hides the device list" : "Shows the available devices")
        .help("Choose the \(role.title.lowercased()) device")
    }

    // MARK: Volume

    private func volumeRow(_ volume: VolumeState) -> some View {
        let isMuted = volume.isMuted == true
        return HStack(spacing: 10) {
            if volume.isMuted != nil {
                IconButton(
                    symbolName: muteSymbol(isMuted: isMuted),
                    label: isMuted ? "Unmute \(role.title.lowercased())" : "Mute \(role.title.lowercased())",
                    tint: isMuted ? theme.accentAction : nil,
                    action: onToggleMute
                )
                .disabled(!volume.isMuteSettable)
            }
            VolumeBar(
                value: volume.level,
                isDimmed: isMuted,
                label: "\(role.title) volume",
                onChange: onVolumeChange
            )
            .disabled(!volume.isSettable)
            ValueChip(
                text: "\(VolumeBarMath.percent(volume.level)) %",
                foreground: isMuted ? theme.textDisabled : theme.accentBoost,
                background: isMuted ? theme.surfaceMuted : theme.boostChipBackground
            )
            .accessibilityHidden(true)
        }
    }

    // MARK: Device list

    private var deviceList: some View {
        VStack(spacing: 4) {
            ForEach(state.devices) { device in
                DeviceOptionRow(
                    device: device,
                    scope: role.scope,
                    isSelected: device.id == state.selectedID
                ) {
                    onSelect(device.id)
                    withAnimation(Theme.motion(reduceMotion: reduceMotion)) { isExpanded = false }
                }
            }
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: theme.shape.control, style: .continuous)
                .fill(theme.surfaceMuted)
        )
    }

    private func deviceSymbol(_ device: AudioDevice?) -> String {
        guard let device else { return role.scope == .input ? "mic.slash.fill" : "speaker.slash.fill" }
        return device.transport.symbolName(for: role.scope)
    }

    private func muteSymbol(isMuted: Bool) -> String {
        switch (role.scope, isMuted) {
        case (.output, false): "speaker.wave.2.fill"
        case (.output, true): "speaker.slash.fill"
        case (.input, false): "mic.fill"
        case (.input, true): "mic.slash.fill"
        }
    }
}

/// One selectable device in an expanded device list.
private struct DeviceOptionRow: View {
    let device: AudioDevice
    let scope: DeviceScope
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.theme) private var theme
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: device.transport.symbolName(for: scope))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isSelected ? theme.accentSuccess : theme.textSecondary)
                    .frame(width: 18)
                    .accessibilityHidden(true)
                Text(device.name)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(theme.accentSuccess)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: theme.shape.tile, style: .continuous)
                    .fill(isHovered || isSelected ? theme.surface : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityLabel(device.name)
        .accessibilityValue(device.transport.displayName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
