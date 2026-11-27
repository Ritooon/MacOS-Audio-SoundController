import AppKit
import SwiftUI

/// The panel opened from the menu-bar item.
struct MenuContentView: View {
    let audio: SystemAudioModel
    let launchAtLogin: LaunchAtLogin

    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// System Settings › Sound.
    private static let soundSettingsURL = URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension")

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Metrics.sectionSpacing) {
            header
            if let message = audio.errorMessage {
                ErrorBanner(message: message) { audio.dismissError() }
            }
            systemCard
            if let device = audio.output.selectedDevice {
                DeviceInfoCard(device: device)
            }
            footer
        }
        .padding(Theme.Metrics.panelPadding)
        .frame(width: Theme.Metrics.panelWidth)
        .background(theme.background)
        .overlay(alignment: .top) { toast }
        .environment(\.colorScheme, .dark)
        .onAppear { launchAtLogin.refresh() }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            SymbolTile(
                symbolName: audio.output.selectedDevice?.transport.symbolName(for: .output) ?? "speaker.slash.fill",
                color: theme.accentPrimary
            )
            VStack(alignment: .leading, spacing: 0) {
                Text("ORPHEUS")
                    .font(Theme.display(22, relativeTo: .title2))
                    .tracking(1.5)
                    .foregroundStyle(theme.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text("Sound control")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.textSecondary)
            }
            Spacer()
            HeaderDecoration()
            IconButton(symbolName: "gearshape.fill", label: "Open Sound settings") {
                if let url = Self.soundSettingsURL {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }

    // MARK: System card

    private var systemCard: some View {
        QuestCard {
            VStack(alignment: .leading, spacing: 14) {
                SectionTitle(text: "System")
                ForEach(Array(DeviceRole.allCases.enumerated()), id: \.element) { index, role in
                    if index > 0 {
                        QuestDivider()
                    }
                    DeviceSectionView(
                        role: role,
                        state: audio.state(for: role),
                        onSelect: { audio.selectDevice($0, for: role) },
                        onVolumeChange: { audio.setVolume($0, for: role) },
                        onToggleMute: { audio.toggleMute(for: role) }
                    )
                }
            }
        }
    }

    // MARK: Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let message = launchAtLogin.errorMessage {
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(theme.accentAction)
            }
            HStack(spacing: 12) {
                Toggle("Open at login", isOn: Binding(
                    get: { launchAtLogin.isEnabled },
                    set: { launchAtLogin.setEnabled($0) }
                ))
                .toggleStyle(QuestCheckboxStyle())
                .font(.system(size: 13, weight: .medium))
                .help("Start Orpheus automatically when you log in")
                Spacer()
                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Text("Quit")
                        .font(Theme.display(13, relativeTo: .callout))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                }
                .buttonStyle(ChunkyButtonStyle(color: theme.surfaceMuted))
                .keyboardShortcut("q")
                .help("Quit Orpheus")
            }
            if launchAtLogin.requiresApproval {
                Button("Approve Orpheus in Login Items settings") { launchAtLogin.openSystemSettings() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.accentPrimary)
            }
        }
        .padding(.horizontal, 4)
    }

    // MARK: Toast

    @ViewBuilder
    private var toast: some View {
        if let message = audio.toast {
            ToastView(message: message)
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
                .task(id: message.id) {
                    try? await Task.sleep(for: Theme.Metrics.toastDuration)
                    withAnimation(Theme.motion(reduceMotion: reduceMotion)) { audio.dismissToast() }
                }
        }
    }
}

/// Details about the current output device, in the info colours.
private struct DeviceInfoCard: View {
    let device: AudioDevice

    @Environment(\.theme) private var theme

    private var details: String {
        var parts = [device.transport.displayName]
        if let rate = device.sampleRate {
            parts.append(rate.formatted(.number.precision(.fractionLength(0 ... 1)).scale(0.001)) + " kHz")
        }
        parts.append("\(device.outputChannels) ch")
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "info.circle.fill")
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("NOW PLAYING ON")
                    .font(Theme.display(11, relativeTo: .caption))
                    .tracking(1)
                Text(details)
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
            }
            Spacer()
        }
        .foregroundStyle(theme.accentInfo)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: Theme.Metrics.tileCornerRadius + 4, style: .continuous)
                .fill(theme.infoSurface)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Current output: \(device.name), \(details)")
    }
}

/// An inline error message with a dismiss button.
private struct ErrorBanner: View {
    let message: String
    let onDismiss: () -> Void

    @Environment(\.theme) private var theme

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(theme.accentAction)
                .accessibilityHidden(true)
            Text(message)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(theme.textSecondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss error")
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: Theme.Metrics.tileCornerRadius + 4, style: .continuous)
                .fill(theme.surfaceMuted)
        )
    }
}
