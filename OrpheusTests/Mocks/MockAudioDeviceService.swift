@testable import Orpheus

/// An in-memory ``AudioDeviceProviding`` for tests. It never touches real audio hardware.
final class MockAudioDeviceService: AudioDeviceProviding {
    struct VolumeKey: Hashable {
        let id: AudioDevice.ID
        let scope: DeviceScope
    }

    var devices: [AudioDevice] = []
    var defaults: [DeviceRole: AudioDevice.ID] = [:]
    var volumes: [VolumeKey: VolumeState] = [:]

    var devicesError: AudioError?
    var setDefaultError: AudioError?
    var setVolumeError: AudioError?
    var setMutedError: AudioError?

    private(set) var setDefaultCalls: [(id: AudioDevice.ID, role: DeviceRole)] = []
    private(set) var setVolumeCalls: [(level: Float, id: AudioDevice.ID, scope: DeviceScope)] = []
    private(set) var setMutedCalls: [(muted: Bool, id: AudioDevice.ID, scope: DeviceScope)] = []
    private(set) var isObserving = false
    private var onChange: (() -> Void)?

    func allDevices() throws -> [AudioDevice] {
        if let devicesError { throw devicesError }
        return devices
    }

    func defaultDeviceID(for role: DeviceRole) throws -> AudioDevice.ID? {
        defaults[role]
    }

    func setDefaultDevice(_ id: AudioDevice.ID, for role: DeviceRole) throws {
        setDefaultCalls.append((id, role))
        if let setDefaultError { throw setDefaultError }
        defaults[role] = id
    }

    func volumeState(of id: AudioDevice.ID, scope: DeviceScope) -> VolumeState? {
        volumes[VolumeKey(id: id, scope: scope)]
    }

    func setVolume(_ level: Float, of id: AudioDevice.ID, scope: DeviceScope) throws {
        setVolumeCalls.append((level, id, scope))
        if let setVolumeError { throw setVolumeError }
        volumes[VolumeKey(id: id, scope: scope)]?.level = level
    }

    func setMuted(_ muted: Bool, of id: AudioDevice.ID, scope: DeviceScope) throws {
        setMutedCalls.append((muted, id, scope))
        if let setMutedError { throw setMutedError }
        volumes[VolumeKey(id: id, scope: scope)]?.isMuted = muted
    }

    func startObserving(_ onChange: @escaping () -> Void) {
        isObserving = true
        self.onChange = onChange
    }

    func stopObserving() {
        isObserving = false
        onChange = nil
    }

    /// Simulates a CoreAudio change notification.
    func simulateChange() {
        onChange?()
    }
}

extension AudioDevice {
    /// Builds a test device.
    static func fixture(
        id: AudioDevice.ID,
        name: String,
        transport: TransportKind = .builtIn,
        outputChannels: Int = 2,
        inputChannels: Int = 0
    ) -> AudioDevice {
        AudioDevice(
            id: id,
            uid: "uid-\(id)",
            name: name,
            transport: transport,
            outputChannels: outputChannels,
            inputChannels: inputChannels,
            sampleRate: 48000
        )
    }
}

extension VolumeState {
    /// A fully controllable volume.
    static func settable(_ level: Float, muted: Bool? = false) -> VolumeState {
        VolumeState(level: level, isSettable: true, isMuted: muted, isMuteSettable: muted != nil)
    }
}
