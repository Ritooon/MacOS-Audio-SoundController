import AppKit
import SwiftUI

/// The panel opened from the menu-bar item.
struct MenuContentView: View {
    let audio: SystemAudioModel
    let appAudio: AppAudioModel
    let launchAtLogin: LaunchAtLogin
    /// The selected theme; the panel itself reads its colours from `\.theme`.
    @Binding var themeID: ThemeID

    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsOtherApps = false

    /// System Settings › Privacy & Security › Screen & System Audio Recording.
    private static let audioCaptureSettingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture"
    )

    /// System Settings › Sound.
    private static let soundSettingsURL = URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension")

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Metrics.sectionSpacing) {
            header
            if let message = audio.errorMessage {
                ErrorBanner(message: message) { audio.dismissError() }
            }
            systemCard
            appsCard
            if let device = audio.output.selectedDevice {
                DeviceInfoCard(device: device)
            }
            footer
        }
        .padding(Theme.Metrics.panelPadding)
        .frame(width: Theme.Metrics.panelWidth)
        .background(panelBackground)
        .overlay(alignment: .top) { toast }
        .environment(\.colorScheme, theme.isLight ? .light : .dark)
        .onAppear { launchAtLogin.refresh() }
    }

    /// The theme background with a soft glow in the top-trailing corner.
    private var panelBackground: some View {
        theme.background
            .overlay {
                RadialGradient(
                    colors: [theme.backgroundGlow, theme.background.opacity(0)],
                    center: .topTrailing,
                    startRadius: 0,
                    endRadius: Theme.Metrics.panelWidth
                )
            }
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
                    .font(theme.display(22, relativeTo: .title2))
                    .tracking(theme.tracking(1.5))
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

    // MARK: Apps card

    private var appsCard: some View {
        QuestCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    SectionTitle(text: "Apps")
                    Spacer()
                    SegmentIndicator(
                        active: appAudio.apps.filter(\.app.isPlaying).count,
                        total: appAudio.apps.count
                    )
                }
                if let message = appAudio.errorMessage {
                    ErrorBanner(message: message) { appAudio.dismissError() }
                }
                if appAudio.needsCapturePermission {
                    capturePermissionHint
                }
                if appAudio.activeApps.isEmpty {
                    Text("No app is playing sound right now.")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.textSecondary)
                } else {
                    ForEach(Array(appAudio.activeApps.enumerated()), id: \.element.id) { index, state in
                        if index > 0 {
                            QuestDivider()
                        }
                        appRow(state)
                    }
                }
                if !appAudio.otherApps.isEmpty {
                    otherAppsSection
                }
            }
        }
    }

    private func appRow(_ state: AppAudioModel.AppState) -> some View {
        AppRowView(
            state: state,
            deviceName: audio.output.selectedDevice?.name,
            onVolumeChange: { appAudio.setVolume($0, for: state.id) },
            onToggleMute: { appAudio.toggleMute(for: state.id) },
            onReset: { appAudio.reset(state.id) }
        )
    }

    private var otherAppsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(Theme.motion(reduceMotion: reduceMotion)) { showsOtherApps.toggle() }
            } label: {
                HStack(spacing: 8) {
                    SectionTitle(text: "Other apps")
                    ValueChip(
                        text: "\(appAudio.otherApps.count)",
                        foreground: theme.accentPrimary,
                        background: theme.surfaceMuted
                    )
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(theme.textSecondary)
                        .rotationEffect(.degrees(showsOtherApps ? 180 : 0))
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: theme.shape.tile, style: .continuous)
                        .fill(theme.surfaceMuted)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Other apps, \(appAudio.otherApps.count)")
            .accessibilityHint(showsOtherApps ? "Hides apps that are not playing" : "Shows apps that are not playing")

            if showsOtherApps {
                ForEach(appAudio.otherApps) { state in
                    appRow(state)
                }
                .transition(.opacity)
            }
        }
    }

    private var capturePermissionHint: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No sound reaches Orpheus. Allow it under Privacy & Security › Screen & System Audio Recording, or reset the app to 100 %.")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme.accentInfo)
                .fixedSize(horizontal: false, vertical: true)
            Button("Open Privacy settings") {
                if let url = Self.audioCaptureSettingsURL {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(theme.accentPrimary)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: theme.shape.control, style: .continuous)
                .fill(theme.infoSurface)
        )
    }

    // MARK: Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            ThemePicker(selection: Binding(
                get: { themeID },
                set: { newValue in
                    withAnimation(Theme.motion(reduceMotion: reduceMotion)) { themeID = newValue }
                }
            ))
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
                        .font(theme.display(13, relativeTo: .callout))
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
                    .font(theme.display(11, relativeTo: .caption))
                    .tracking(theme.tracking(1))
                Text(details)
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
            }
            Spacer()
        }
        .foregroundStyle(theme.accentInfo)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: theme.shape.control, style: .continuous)
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
            RoundedRectangle(cornerRadius: theme.shape.control, style: .continuous)
                .fill(theme.surfaceMuted)
        )
    }
}
