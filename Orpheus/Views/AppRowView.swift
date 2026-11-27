import AppKit
import SwiftUI

/// One application in the Apps card: icon, name, volume bar with boost, and value chip.
///
/// Clicking the icon mutes the app; clicking the value chip resets it to 100 %.
struct AppRowView: View {
    let state: AppAudioModel.AppState
    /// The name of the device the app plays on.
    let deviceName: String?
    let onVolumeChange: (Float) -> Void
    let onToggleMute: () -> Void
    let onReset: () -> Void

    @Environment(\.theme) private var theme

    private static let iconSize: CGFloat = 32

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                iconButton
                VStack(alignment: .leading, spacing: 2) {
                    Text(state.app.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(state.isMuted ? theme.textDisabled : theme.textPrimary)
                        .strikethrough(state.isMuted, color: theme.textDisabled)
                        .lineLimit(1)
                    subtitle
                }
                Spacer(minLength: 6)
                valueChip
            }
            VolumeBar(
                value: state.volume,
                maximum: GainProcessor.maxBoost,
                isDimmed: state.isMuted,
                label: "\(state.app.name) volume",
                onChange: onVolumeChange
            )
        }
        .contextMenu {
            Button(state.isMuted ? "Unmute" : "Mute", action: onToggleMute)
            Button("Reset to 100 %", action: onReset)
                .disabled(!state.needsProcessing)
        }
    }

    private var iconButton: some View {
        Button(action: onToggleMute) {
            AppIcon(pid: state.app.pid)
                .frame(width: Self.iconSize, height: Self.iconSize)
                .opacity(state.isMuted ? 0.4 : 1)
                .overlay(alignment: .bottomTrailing) {
                    if state.isMuted {
                        Image(systemName: "speaker.slash.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(theme.surface)
                            .padding(3)
                            .background(Circle().fill(theme.accentAction))
                            .offset(x: 4, y: 4)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(state.isMuted ? "Unmute \(state.app.name)" : "Mute \(state.app.name)")
        .help(state.isMuted ? "Unmute" : "Mute")
    }

    private var subtitle: some View {
        HStack(spacing: 4) {
            if state.app.isPlaying {
                Circle()
                    .fill(theme.accentSuccess)
                    .frame(width: 6, height: 6)
                    .accessibilityHidden(true)
            }
            Image(systemName: "hifispeaker.fill")
                .font(.system(size: 9))
                .accessibilityHidden(true)
            Text(deviceName ?? "No output device")
                .lineLimit(1)
        }
        .font(.system(size: 11))
        .foregroundStyle(theme.textSecondary)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(state.app.isPlaying ? "Playing on \(deviceName ?? "no device")" : "Silent")
    }

    private var valueChip: some View {
        let percent = VolumeBarMath.percent(state.volume)
        let chip: ValueChip = if state.isMuted {
            ValueChip(text: "MUTED", foreground: theme.accentAction, background: theme.surfaceMuted)
        } else if state.isBoosted {
            ValueChip(text: "+\(percent) %", foreground: theme.boostChipText, background: theme.boostChipBackground)
        } else {
            ValueChip(
                text: "\(percent) %",
                foreground: state.needsProcessing ? theme.accentPrimary : theme.textSecondary,
                background: theme.surfaceMuted
            )
        }
        return Button(action: onReset) { chip }
            .buttonStyle(.plain)
            .disabled(!state.needsProcessing)
            .accessibilityLabel("Reset \(state.app.name) to 100 %")
            .accessibilityValue(state.isMuted ? "Muted" : "\(percent) %")
            .help(state.needsProcessing ? "Reset to 100 %" : "Untouched: Orpheus is not processing this app")
    }
}

/// The app's own icon in a rounded tile.
private struct AppIcon: View {
    let pid: pid_t

    @Environment(\.theme) private var theme

    var body: some View {
        Group {
            if let icon = NSRunningApplication(processIdentifier: pid)?.icon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .padding(3)
            } else {
                Image(systemName: "app.dashed")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(theme.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: theme.shape.iconButton, style: .continuous)
                .fill(theme.surfaceMuted)
        )
        .accessibilityHidden(true)
    }
}

/// Small capsules showing a count, green when active (for example apps playing).
struct SegmentIndicator: View {
    let active: Int
    let total: Int

    @Environment(\.theme) private var theme

    private static let maxSegments = 8

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0 ..< min(total, Self.maxSegments), id: \.self) { index in
                RoundedRectangle(cornerRadius: theme.shape.bar, style: .continuous)
                    .fill(index < active ? theme.accentSuccess : theme.surfaceMuted)
                    .frame(width: 10, height: 5)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("\(active) of \(total) apps playing")
    }
}
