import SwiftUI

/// The entry point: a menu-bar item that opens the Orpheus panel.
@main
struct OrpheusApp: App {
    @State private var audio: SystemAudioModel
    @State private var launchAtLogin = LaunchAtLogin()

    init() {
        // Start right away so the menu-bar symbol reflects the volume before the panel opens.
        let audio = SystemAudioModel(provider: AudioDeviceService())
        audio.start()
        _audio = State(initialValue: audio)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(audio: audio, launchAtLogin: launchAtLogin)
        } label: {
            Image(systemName: menuBarSymbol)
                .accessibilityLabel("Orpheus")
        }
        .menuBarExtraStyle(.window)
    }

    /// A native template symbol that follows the output volume.
    private var menuBarSymbol: String {
        guard let volume = audio.output.volume else { return "speaker.wave.2.fill" }
        if volume.isMuted == true || volume.level == 0 {
            return "speaker.slash.fill"
        }
        switch volume.level {
        case ..<0.34: return "speaker.wave.1.fill"
        case ..<0.67: return "speaker.wave.2.fill"
        default: return "speaker.wave.3.fill"
        }
    }
}
