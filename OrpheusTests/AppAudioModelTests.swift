import CoreAudio
import Foundation
import Testing
@testable import Orpheus

@MainActor
@Suite("AppAudioModel")
struct AppAudioModelTests {
    private struct Fixture {
        let model: AppAudioModel
        let processes: MockAudioProcessService
        let taps: MockTapFactory
        let settings: SettingsStore
    }

    private static let music = "com.apple.Music"
    private static let chrome = "com.google.Chrome"

    private func makeFixture(saved: (SettingsStore) -> Void = { _ in }) -> Fixture {
        let processes = MockAudioProcessService()
        processes.processes = [
            AudioProcess(id: 1, pid: 10, bundleID: Self.music, isRunningOutput: true),
            AudioProcess(id: 2, pid: 20, bundleID: Self.chrome, isRunningOutput: false),
        ]
        var resolver = MockRunningAppResolver()
        resolver.add(pid: 10, name: "Music", bundleID: Self.music)
        resolver.add(pid: 20, name: "Google Chrome", bundleID: Self.chrome)

        let suite = "OrpheusTests.\(UUID().uuidString)"
        let settings = SettingsStore(defaults: UserDefaults(suiteName: suite)!)  // A fresh suite name always succeeds.
        saved(settings)

        let taps = MockTapFactory()
        let model = AppAudioModel(
            processProvider: processes,
            resolver: resolver,
            tapFactory: taps,
            settings: settings,
            excludedPID: 99,
            permissionCheckDelay: .milliseconds(10)
        )
        model.setOutputDevice(uid: "speakers")
        return Fixture(model: model, processes: processes, taps: taps, settings: settings)
    }

    @Test func appsAtUnityAreNotTapped() {
        let fixture = makeFixture()
        fixture.model.refresh()

        #expect(fixture.model.apps.count == 2)
        #expect(fixture.taps.made.isEmpty)
        #expect(fixture.model.activeApps.map(\.app.name) == ["Music"])
        #expect(fixture.model.otherApps.map(\.app.name) == ["Google Chrome"])
    }

    @Test func changingVolumeCreatesTapWithGain() {
        let fixture = makeFixture()
        fixture.model.refresh()
        fixture.model.setVolume(0.5, for: Self.music)

        #expect(fixture.taps.liveTaps.count == 1)
        #expect(fixture.taps.liveTaps.first?.gain == 0.25)
        #expect(fixture.taps.liveTaps.first?.outputDeviceUID == "speakers")
        #expect(fixture.model.apps.first { $0.id == Self.music }?.isProcessed == true)
    }

    @Test func furtherChangesReuseTheTap() {
        let fixture = makeFixture()
        fixture.model.refresh()
        fixture.model.setVolume(0.5, for: Self.music)
        fixture.model.setVolume(2, for: Self.music)

        #expect(fixture.taps.made.count == 1)
        #expect(fixture.taps.liveTaps.first?.gain == 2)
        #expect(fixture.model.hasBoostedApp)
    }

    @Test func volumeIsClampedToMaxBoost() {
        let fixture = makeFixture()
        fixture.model.refresh()
        fixture.model.setVolume(12, for: Self.music)

        #expect(fixture.model.apps.first { $0.id == Self.music }?.volume == GainProcessor.maxBoost)
    }

    @Test func resetReleasesTheTap() {
        let fixture = makeFixture()
        fixture.model.refresh()
        fixture.model.setVolume(2, for: Self.music)
        fixture.model.reset(Self.music)

        #expect(fixture.taps.liveTaps.isEmpty)
        #expect(fixture.settings.appVolume(for: Self.music) == nil)
        #expect(!fixture.model.hasBoostedApp)
    }

    @Test func muteUsesZeroGainAndIsSaved() {
        let fixture = makeFixture()
        fixture.model.refresh()
        fixture.model.toggleMute(for: Self.music)

        #expect(fixture.taps.liveTaps.first?.gain == 0)
        #expect(fixture.settings.isAppMuted(Self.music))
        #expect(fixture.model.activeApps.first?.isMuted == true)
    }

    @Test func savedSettingsAreAppliedOnRefresh() {
        let fixture = makeFixture { $0.setAppVolume(1.5, for: Self.chrome) }
        fixture.model.refresh()

        #expect(fixture.taps.liveTaps.count == 1)
        #expect(fixture.taps.liveTaps.first?.processObjectIDs == [2])
        // Customised apps stay in the main list even when silent.
        #expect(fixture.model.activeApps.map(\.app.name) == ["Music", "Google Chrome"])
    }

    @Test func quittingAppReleasesItsTap() {
        let fixture = makeFixture()
        fixture.model.refresh()
        fixture.model.setVolume(0.5, for: Self.music)
        fixture.processes.processes.removeAll { $0.bundleID == Self.music }
        fixture.model.refresh()

        #expect(fixture.taps.liveTaps.isEmpty)
    }

    @Test func outputDeviceChangeRebuildsTaps() {
        let fixture = makeFixture()
        fixture.model.refresh()
        fixture.model.setVolume(0.5, for: Self.music)
        fixture.model.setOutputDevice(uid: "headphones")

        #expect(fixture.taps.made.count == 2)
        #expect(fixture.taps.liveTaps.map(\.outputDeviceUID) == ["headphones"])
    }

    @Test func noOutputDeviceMeansNoTap() {
        let fixture = makeFixture()
        fixture.model.setOutputDevice(uid: nil)
        fixture.model.refresh()
        fixture.model.setVolume(0.5, for: Self.music)

        #expect(fixture.taps.liveTaps.isEmpty)
        #expect(fixture.model.apps.first { $0.id == Self.music }?.isProcessed == false)
    }

    @Test func tapFailureIsReported() {
        let fixture = makeFixture()
        fixture.taps.error = AudioError(operation: "capture the app's audio", reason: .status(-1))
        fixture.model.refresh()
        fixture.model.setVolume(0.5, for: Self.music)

        #expect(fixture.model.errorMessage?.contains("capture the app's audio") == true)
        #expect(fixture.model.apps.first { $0.id == Self.music }?.isProcessed == false)
    }

    @Test func silentTapOnPlayingAppAsksForPermission() async throws {
        let fixture = makeFixture()
        fixture.taps.receivesAudio = false
        fixture.model.refresh()
        fixture.model.setVolume(0.5, for: Self.music)

        try await Task.sleep(for: .milliseconds(200))
        #expect(fixture.model.needsCapturePermission)
    }

    @Test func processListErrorIsReported() {
        let fixture = makeFixture()
        fixture.processes.error = AudioError(operation: "list audio processes", reason: .status(-50))
        fixture.model.refresh()

        #expect(fixture.model.apps.isEmpty)
        #expect(fixture.model.errorMessage != nil)
    }

    @Test func stopReleasesEverything() {
        let fixture = makeFixture()
        fixture.model.start()
        fixture.model.setVolume(0.5, for: Self.music)
        fixture.model.stop()

        #expect(!fixture.processes.isObserving)
        #expect(fixture.taps.liveTaps.isEmpty)
    }
}
