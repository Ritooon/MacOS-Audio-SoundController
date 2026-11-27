import Testing
@testable import Orpheus

@MainActor
@Suite("SystemAudioModel")
struct SystemAudioModelTests {
    private let speakers = AudioDevice.fixture(id: 10, name: "MacBook Speakers")
    private let headphones = AudioDevice.fixture(id: 20, name: "AirPods", transport: .bluetooth, inputChannels: 1)
    private let microphone = AudioDevice.fixture(id: 30, name: "Built-in Microphone", outputChannels: 0, inputChannels: 1)

    private func makeModel() -> (SystemAudioModel, MockAudioDeviceService) {
        let mock = MockAudioDeviceService()
        mock.devices = [speakers, headphones, microphone]
        mock.defaults = [.output: speakers.id, .input: microphone.id, .soundEffects: speakers.id]
        mock.volumes = [
            .init(id: speakers.id, scope: .output): .settable(0.5),
            .init(id: headphones.id, scope: .output): .settable(0.8),
            .init(id: microphone.id, scope: .input): .settable(0.7, muted: nil),
        ]
        return (SystemAudioModel(provider: mock), mock)
    }

    // MARK: Refresh

    @Test func refreshSplitsDevicesByScopeAndSortsByName() {
        let (model, _) = makeModel()
        model.refresh()

        #expect(model.output.devices.map(\.name) == ["AirPods", "MacBook Speakers"])
        #expect(model.input.devices.map(\.name) == ["AirPods", "Built-in Microphone"])
        #expect(model.soundEffects.devices == model.output.devices)
    }

    @Test func refreshReadsDefaultsAndVolumes() {
        let (model, _) = makeModel()
        model.refresh()

        #expect(model.output.selectedDevice == speakers)
        #expect(model.output.volume?.level == 0.5)
        #expect(model.input.selectedDevice == microphone)
        #expect(model.input.volume?.isMuted == nil)
    }

    @Test func soundEffectsHasNoVolumeControl() {
        let (model, _) = makeModel()
        model.refresh()

        #expect(model.soundEffects.selectedDevice == speakers)
        #expect(model.soundEffects.volume == nil)
    }

    @Test func emptyDeviceListIsHandled() {
        let (model, mock) = makeModel()
        mock.devices = []
        mock.defaults = [:]
        model.refresh()

        #expect(model.output.devices.isEmpty)
        #expect(model.output.selectedDevice == nil)
        #expect(model.output.volume == nil)
        #expect(model.errorMessage == nil)
    }

    @Test func deviceListErrorIsReported() {
        let (model, mock) = makeModel()
        mock.devicesError = AudioError(operation: "list audio devices", reason: .status(-50))
        model.refresh()

        #expect(model.output.devices.isEmpty)
        #expect(model.errorMessage?.contains("list audio devices") == true)
    }

    @Test func defaultDeviceMissingFromListHasNoSelectedDevice() {
        let (model, mock) = makeModel()
        mock.defaults[.output] = 999
        model.refresh()

        #expect(model.output.selectedID == 999)
        #expect(model.output.selectedDevice == nil)
    }

    @Test func deviceWithoutVolumeControlHasNoVolume() {
        let (model, mock) = makeModel()
        mock.volumes[.init(id: speakers.id, scope: .output)] = nil
        model.refresh()

        #expect(model.output.volume == nil)
    }

    // MARK: Selection

    @Test func selectingDeviceChangesDefault() {
        let (model, mock) = makeModel()
        model.refresh()
        model.selectDevice(headphones.id, for: .output)

        #expect(mock.setDefaultCalls.count == 1)
        #expect(model.output.selectedDevice == headphones)
        #expect(model.output.volume?.level == 0.8)
    }

    @Test func selectingCurrentDeviceDoesNothing() {
        let (model, mock) = makeModel()
        model.refresh()
        model.selectDevice(speakers.id, for: .output)

        #expect(mock.setDefaultCalls.isEmpty)
    }

    @Test func selectionFailureKeepsPreviousDeviceAndReportsError() {
        let (model, mock) = makeModel()
        mock.setDefaultError = AudioError(operation: "change the default device", reason: .propertyNotSettable)
        model.refresh()
        model.selectDevice(headphones.id, for: .output)

        #expect(model.output.selectedDevice == speakers)
        #expect(model.errorMessage != nil)
    }

    // MARK: Volume

    @Test(arguments: [(Float(-0.5), Float(0)), (0.3, 0.3), (1.7, 1)])
    func volumeIsClampedToUnitRange(input: Float, expected: Float) {
        let (model, mock) = makeModel()
        model.refresh()
        model.setVolume(input, for: .output)

        #expect(mock.setVolumeCalls.last?.level == expected)
        #expect(model.output.volume?.level == expected)
    }

    @Test func volumeIsNotChangedWhenNotSettable() {
        let (model, mock) = makeModel()
        mock.volumes[.init(id: speakers.id, scope: .output)]?.isSettable = false
        model.refresh()
        model.setVolume(0.9, for: .output)

        #expect(mock.setVolumeCalls.isEmpty)
        #expect(model.output.volume?.level == 0.5)
    }

    @Test func volumeFailureKeepsLevelAndReportsError() {
        let (model, mock) = makeModel()
        mock.setVolumeError = AudioError(operation: "change the volume", reason: .deviceNotFound)
        model.refresh()
        model.setVolume(0.9, for: .output)

        #expect(model.output.volume?.level == 0.5)
        #expect(model.errorMessage?.contains("no longer connected") == true)
    }

    @Test func inputVolumeUsesInputScope() {
        let (model, mock) = makeModel()
        model.refresh()
        model.setVolume(0.2, for: .input)

        #expect(mock.setVolumeCalls.last?.scope == .input)
        #expect(mock.setVolumeCalls.last?.id == microphone.id)
    }

    // MARK: Mute

    @Test func toggleMuteFlipsState() {
        let (model, mock) = makeModel()
        model.refresh()
        model.toggleMute(for: .output)

        #expect(mock.setMutedCalls.last?.muted == true)
        #expect(model.output.volume?.isMuted == true)

        model.toggleMute(for: .output)
        #expect(model.output.volume?.isMuted == false)
    }

    @Test func toggleMuteIsIgnoredWithoutMuteControl() {
        let (model, mock) = makeModel()
        model.refresh()
        model.toggleMute(for: .input)

        #expect(mock.setMutedCalls.isEmpty)
    }

    // MARK: Observation and toasts

    @Test func startObservesAndStopReleases() {
        let (model, mock) = makeModel()
        model.start()
        #expect(mock.isObserving)

        model.stop()
        #expect(!mock.isObserving)
    }

    @Test func devicesPresentAtLaunchDoNotShowToast() {
        let (model, _) = makeModel()
        model.refresh()

        #expect(model.toast == nil)
    }

    @Test func connectingDeviceShowsToast() {
        let (model, mock) = makeModel()
        model.refresh()
        mock.devices.append(.fixture(id: 40, name: "USB DAC", transport: .usb))
        model.refresh()

        #expect(model.toast?.text == "USB DAC connected")
        #expect(model.toast?.symbolName == "cable.connector")

        model.dismissToast()
        #expect(model.toast == nil)
    }

    @Test func disconnectingDeviceShowsToast() {
        let (model, mock) = makeModel()
        model.refresh()
        mock.devices.removeAll { $0.id == headphones.id }
        model.refresh()

        #expect(model.toast?.text == "AirPods disconnected")
        #expect(!model.output.devices.contains(headphones))
    }
}
