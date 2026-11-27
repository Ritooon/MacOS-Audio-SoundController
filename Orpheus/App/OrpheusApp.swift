import SwiftUI

/// The entry point: a menu-bar item that opens the Orpheus panel.
@main
struct OrpheusApp: App {
    @State private var audio: SystemAudioModel
    @State private var appAudio: AppAudioModel
    @State private var launchAtLogin = LaunchAtLogin()
    @AppStorage(SettingsKey.themeID.rawValue) private var savedThemeID = ThemeID.neon.rawValue

    init() {
        let audio = SystemAudioModel(provider: AudioDeviceService())
        let appAudio = AppAudioModel(
            processProvider: AudioProcessService(),
            resolver: SystemRunningAppResolver(),
            tapFactory: ProcessTapFactory(),
            settings: SettingsStore()
        )
        // Processed apps follow the system output device.
        audio.onOutputDeviceChange = { [weak appAudio] device in
            appAudio?.setOutputDevice(uid: device?.uid)
        }
        // Start right away so the menu-bar icon reflects the state before the panel opens,
        // and saved per-app volumes are applied at login.
        audio.start()
        appAudio.start()
        _audio = State(initialValue: audio)
        _appAudio = State(initialValue: appAudio)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(audio: audio, appAudio: appAudio, launchAtLogin: launchAtLogin, themeID: themeID)
                .environment(\.theme, Theme.theme(for: themeID.wrappedValue))
        } label: {
            Image(nsImage: MenuBarIcon.image(for: menuBarState))
                .accessibilityLabel("Orpheus")
        }
        .menuBarExtraStyle(.window)
    }

    /// The saved theme, falling back to Néon for unknown values.
    private var themeID: Binding<ThemeID> {
        Binding(
            get: { ThemeID.resolve(savedThemeID) },
            set: { savedThemeID = $0.rawValue }
        )
    }

    /// Pink when the output is muted, yellow when an app is boosted, purple otherwise.
    private var menuBarState: MenuBarIcon.State {
        if let volume = audio.output.volume, volume.isMuted == true || volume.level == 0 {
            return .muted
        }
        return appAudio.hasBoostedApp ? .boosted : .normal
    }
}
