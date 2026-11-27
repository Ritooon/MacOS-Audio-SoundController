import CoreAudio
import Testing
@testable import Orpheus

@Suite("AppGrouping")
struct AppGroupingTests {
    private static let ownPID: pid_t = 99

    private func process(_ id: AudioObjectID, pid: pid_t, playing: Bool = false, bundleID: String? = nil) -> AudioProcess {
        AudioProcess(id: id, pid: pid, bundleID: bundleID, isRunningOutput: playing)
    }

    @Test func regularAppIsItsOwnGroup() {
        var resolver = MockRunningAppResolver()
        resolver.add(pid: 10, name: "Music", bundleID: "com.apple.Music")

        let apps = AppGrouping.apps(from: [process(1, pid: 10, playing: true)], resolver: resolver, excludedPID: Self.ownPID)

        #expect(apps.map(\.id) == ["com.apple.Music"])
        #expect(apps.first?.isPlaying == true)
    }

    @Test func helperIsAttachedToParentApp() {
        var resolver = MockRunningAppResolver()
        resolver.add(pid: 10, name: "Google Chrome", bundleID: "com.google.Chrome")
        resolver.add(pid: 11, name: "Google Chrome Helper", bundleID: "com.google.Chrome.helper", isRegular: false, parentPID: 10)

        let apps = AppGrouping.apps(
            from: [process(1, pid: 10), process(2, pid: 11, playing: true)],
            resolver: resolver,
            excludedPID: Self.ownPID
        )

        #expect(apps.count == 1)
        #expect(apps.first?.name == "Google Chrome")
        #expect(apps.first?.processObjectIDs == [1, 2])
        #expect(apps.first?.isPlaying == true)
    }

    @Test func helperIsMatchedByBundlePrefixWhenParentIsLaunchd() {
        var resolver = MockRunningAppResolver()
        resolver.add(pid: 10, name: "Slack", bundleID: "com.tinyspeck.slackmacgap")
        resolver.add(pid: 12, name: "Slack Helper", bundleID: "com.tinyspeck.slackmacgap.helper", isRegular: false)

        let apps = AppGrouping.apps(from: [process(3, pid: 12)], resolver: resolver, excludedPID: Self.ownPID)

        #expect(apps.map(\.id) == ["com.tinyspeck.slackmacgap"])
    }

    @Test func webKitContentBelongsToSafari() {
        var resolver = MockRunningAppResolver()
        resolver.add(pid: 10, name: "Safari", bundleID: "com.apple.Safari")
        resolver.add(pid: 13, name: "Safari Web Content", bundleID: "com.apple.WebKit.WebContent", isRegular: false)

        let apps = AppGrouping.apps(from: [process(4, pid: 13, playing: true)], resolver: resolver, excludedPID: Self.ownPID)

        #expect(apps.map(\.name) == ["Safari"])
    }

    @Test func backgroundProcessWithoutAppIsHidden() {
        var resolver = MockRunningAppResolver()
        resolver.add(pid: 14, name: "coreaudiod helper", bundleID: "com.apple.something", isRegular: false)

        let apps = AppGrouping.apps(from: [process(5, pid: 14, playing: true)], resolver: resolver, excludedPID: Self.ownPID)

        #expect(apps.isEmpty)
    }

    @Test func orpheusItselfIsExcluded() {
        var resolver = MockRunningAppResolver()
        resolver.add(pid: Self.ownPID, name: "Orpheus", bundleID: "com.ritooon.Orpheus")

        let apps = AppGrouping.apps(from: [process(6, pid: Self.ownPID, playing: true)], resolver: resolver, excludedPID: Self.ownPID)

        #expect(apps.isEmpty)
    }

    @Test func playingAppsComeFirstThenByName() {
        var resolver = MockRunningAppResolver()
        resolver.add(pid: 10, name: "Zoom", bundleID: "us.zoom.xos")
        resolver.add(pid: 20, name: "Arc", bundleID: "company.thebrowser.Browser")
        resolver.add(pid: 30, name: "Music", bundleID: "com.apple.Music")

        let apps = AppGrouping.apps(
            from: [process(1, pid: 10, playing: true), process(2, pid: 20), process(3, pid: 30)],
            resolver: resolver,
            excludedPID: Self.ownPID
        )

        #expect(apps.map(\.name) == ["Zoom", "Arc", "Music"])
    }
}
