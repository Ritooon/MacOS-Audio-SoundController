import CoreAudio
@testable import Orpheus

/// An in-memory ``AudioProcessProviding``.
final class MockAudioProcessService: AudioProcessProviding {
    var processes: [AudioProcess] = []
    var error: AudioError?
    private(set) var isObserving = false
    private var onChange: (() -> Void)?

    func audioProcesses() throws -> [AudioProcess] {
        if let error { throw error }
        return processes
    }

    func startObserving(_ onChange: @escaping () -> Void) {
        isObserving = true
        self.onChange = onChange
    }

    func stopObserving() {
        isObserving = false
        onChange = nil
    }
}

/// A fixed table of running processes.
struct MockRunningAppResolver: RunningAppResolving {
    var infos: [pid_t: RunningAppInfo] = [:]

    func info(for pid: pid_t) -> RunningAppInfo? {
        infos[pid]
    }

    func regularApps() -> [RunningAppInfo] {
        infos.values.filter(\.isRegular).sorted { $0.pid < $1.pid }
    }

    mutating func add(
        pid: pid_t,
        name: String,
        bundleID: String?,
        isRegular: Bool = true,
        parentPID: pid_t? = 1
    ) {
        infos[pid] = RunningAppInfo(pid: pid, parentPID: parentPID, bundleID: bundleID, name: name, isRegular: isRegular)
    }
}

/// A tap that records the gain it receives.
final class MockProcessTap: ProcessTapControlling {
    let processObjectIDs: [AudioObjectID]
    let outputDeviceUID: String
    var hasReceivedAudio = true
    private(set) var gain: Float
    private(set) var isInvalidated = false

    init(processObjectIDs: [AudioObjectID], outputDeviceUID: String, gain: Float) {
        self.processObjectIDs = processObjectIDs
        self.outputDeviceUID = outputDeviceUID
        self.gain = gain
    }

    func setGain(_ gain: Float) {
        self.gain = gain
    }

    func invalidate() {
        isInvalidated = true
    }
}

/// Creates ``MockProcessTap``s and keeps them for inspection.
final class MockTapFactory: ProcessTapMaking {
    var error: AudioError?
    var receivesAudio = true
    private(set) var made: [MockProcessTap] = []

    /// Taps that are still running.
    var liveTaps: [MockProcessTap] {
        made.filter { !$0.isInvalidated }
    }

    func makeTap(processObjectIDs: [AudioObjectID], outputDeviceUID: String, gain: Float) throws -> ProcessTapControlling {
        if let error { throw error }
        let tap = MockProcessTap(processObjectIDs: processObjectIDs, outputDeviceUID: outputDeviceUID, gain: gain)
        tap.hasReceivedAudio = receivesAudio
        made.append(tap)
        return tap
    }
}
