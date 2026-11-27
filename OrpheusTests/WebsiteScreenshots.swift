import AppKit
import CoreAudio
import SwiftUI
import Testing
@testable import Orpheus

/// Renders the real panel views to PNG files for the website, with sample devices and apps.
///
/// Runs only when `ORPHEUS_SCREENSHOTS_DIR` is set, for example:
///
/// ```sh
/// TEST_RUNNER_ORPHEUS_SCREENSHOTS_DIR="$PWD/screenshots" xcodebuild test \
///   -project Orpheus.xcodeproj -scheme Orpheus -destination 'platform=macOS' \
///   -only-testing:OrpheusTests/WebsiteScreenshots
/// ```
///
/// The views are drawn offscreen in a window, so no Screen Recording permission is needed.
@MainActor
@Suite(
    "Website screenshots",
    .enabled(if: ProcessInfo.processInfo.environment["ORPHEUS_SCREENSHOTS_DIR"] != nil)
)
struct WebsiteScreenshots {
    private var outputDirectory: URL {
        URL(fileURLWithPath: ProcessInfo.processInfo.environment["ORPHEUS_SCREENSHOTS_DIR"] ?? NSTemporaryDirectory())
    }

    @Test(arguments: ThemeID.allCases)
    func panel(_ id: ThemeID) throws {
        let (audio, appAudio) = makeModels()
        let view = MenuContentView(
            audio: audio,
            appAudio: appAudio,
            launchAtLogin: LaunchAtLogin(),
            themeID: .constant(id)
        )
        .environment(\.theme, Theme.theme(for: id))

        try render(view, to: "panel-\(id.rawValue).png")
        appAudio.stop()
    }

    @Test func menuBarIcons() throws {
        for state in [MenuBarIcon.State.normal, .boosted, .muted] {
            for appearance in [NSAppearance.Name.darkAqua, .aqua] {
                let image = MenuBarIcon.image(for: state)
                let view = Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: image.size.width * 4, height: image.size.height * 4)
                    .padding(12)
                let suffix = appearance == .darkAqua ? "dark" : "light"
                try render(view, to: "menubar-\(state)-\(suffix).png", appearance: NSAppearance(named: appearance))
            }
        }
    }

    // MARK: Sample data

    private func makeModels() -> (SystemAudioModel, AppAudioModel) {
        let airPods = AudioDevice(
            id: 20, uid: "airpods", name: "AirPods Pro", transport: .bluetooth,
            outputChannels: 2, inputChannels: 1, sampleRate: 48000
        )
        let speakers = AudioDevice(
            id: 10, uid: "speakers", name: "Mac mini Speakers", transport: .builtIn,
            outputChannels: 2, inputChannels: 0, sampleRate: 48000
        )
        let display = AudioDevice(
            id: 30, uid: "display", name: "Studio Display", transport: .usb,
            outputChannels: 2, inputChannels: 1, sampleRate: 48000
        )
        let devices = MockAudioDeviceService()
        devices.devices = [airPods, speakers, display]
        devices.defaults = [.output: airPods.id, .input: display.id, .soundEffects: speakers.id]
        devices.volumes = [
            .init(id: airPods.id, scope: .output): .settable(0.62),
            .init(id: speakers.id, scope: .output): .settable(0.4),
            .init(id: display.id, scope: .output): .settable(0.5),
            .init(id: display.id, scope: .input): .settable(0.75),
            .init(id: airPods.id, scope: .input): .settable(0.8),
        ]
        let audio = SystemAudioModel(provider: devices)
        audio.refresh()

        // Built-in apps, so their icons exist on every Mac. The PIDs are fake: icons come from
        // the bundle identifier.
        let apps: [(pid: pid_t, name: String, bundleID: String, playing: Bool)] = [
            (9001, "Music", "com.apple.Music", true),
            (9002, "Safari", "com.apple.Safari", true),
            (9003, "FaceTime", "com.apple.FaceTime", false),
            (9004, "Podcasts", "com.apple.podcasts", false),
            (9005, "TV", "com.apple.TV", false),
        ]
        let processes = MockAudioProcessService()
        var resolver = MockRunningAppResolver()
        for (index, app) in apps.enumerated() {
            processes.processes.append(AudioProcess(
                id: AudioObjectID(100 + index), pid: app.pid, bundleID: app.bundleID, isRunningOutput: app.playing
            ))
            resolver.add(pid: app.pid, name: app.name, bundleID: app.bundleID)
        }
        let suite = "OrpheusWebsiteScreenshots"
        let defaults = try! #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let settings = SettingsStore(defaults: defaults)
        settings.setAppVolume(0.85, for: "com.apple.Music")
        settings.setAppVolume(2.2, for: "com.apple.Safari")
        settings.setAppMuted(true, for: "com.apple.FaceTime")

        let appAudio = AppAudioModel(
            processProvider: processes,
            resolver: resolver,
            tapFactory: MockTapFactory(),
            settings: settings,
            excludedPID: 1,
            permissionCheckDelay: .seconds(3600)
        )
        appAudio.refresh()
        appAudio.setOutputDevice(uid: airPods.uid)
        return (audio, appAudio)
    }

    // MARK: Rendering

    /// Draws a view offscreen at 2× and writes it as a PNG.
    private func render(_ view: some View, to fileName: String, appearance: NSAppearance? = nil) throws {
        let hosting = NSHostingView(rootView: view)
        hosting.appearance = appearance
        let size = hosting.fittingSize
        hosting.frame = CGRect(origin: .zero, size: size)

        let window = NSWindow(
            contentRect: CGRect(origin: CGPoint(x: -10000, y: -10000), size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.backgroundColor = .clear
        window.isOpaque = false
        window.appearance = appearance
        window.contentView = hosting
        window.orderFrontRegardless()
        hosting.layoutSubtreeIfNeeded()
        // Let SwiftUI finish its first layout pass and load images.
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        hosting.layoutSubtreeIfNeeded()

        let scale: CGFloat = 2
        let rep = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width * scale),
            pixelsHigh: Int(size.height * scale),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
        rep.size = size
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        window.orderOut(nil)

        let data = try #require(rep.representation(using: .png, properties: [:]))
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        try data.write(to: outputDirectory.appendingPathComponent(fileName))
    }
}
