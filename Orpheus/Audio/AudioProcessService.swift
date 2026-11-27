import CoreAudio
import Foundation

/// Abstraction over the CoreAudio process list, so app logic can be tested without real processes.
protocol AudioProcessProviding: AnyObject {
    /// The processes that are currently clients of the audio system.
    /// - Throws: ``AudioError`` if the list cannot be read.
    func audioProcesses() throws -> [AudioProcess]

    /// Starts calling `onChange` on the main queue when the process list changes or a
    /// process starts or stops playing.
    /// - Parameter onChange: The closure to call.
    func startObserving(_ onChange: @escaping () -> Void)

    /// Stops observing and removes every listener.
    func stopObserving()
}

/// The CoreAudio implementation of ``AudioProcessProviding``. Use it from the main thread only.
final class AudioProcessService: AudioProcessProviding {
    private static let systemObject = AudioObjectID(kAudioObjectSystemObject)

    private let systemListeners = CoreAudioListeners()
    private let processListeners = CoreAudioListeners()
    private var onChange: (() -> Void)?

    deinit {
        stopObserving()
    }

    func audioProcesses() throws -> [AudioProcess] {
        let ids: [AudioObjectID] = try CoreAudioProperty.readArray(
            Self.systemObject,
            CoreAudioProperty.address(kAudioHardwarePropertyProcessObjectList),
            operation: "list audio processes"
        )
        return ids.compactMap(makeProcess)
    }

    func startObserving(_ onChange: @escaping () -> Void) {
        stopObserving()
        self.onChange = onChange
        systemListeners.add(
            to: Self.systemObject,
            address: CoreAudioProperty.address(kAudioHardwarePropertyProcessObjectList)
        ) { [weak self] in
            self?.updateProcessListeners()
            self?.onChange?()
        }
        updateProcessListeners()
    }

    func stopObserving() {
        systemListeners.removeAll()
        processListeners.removeAll()
        onChange = nil
    }

    private func updateProcessListeners() {
        processListeners.removeAll()
        let ids: [AudioObjectID] = (try? CoreAudioProperty.readArray(
            Self.systemObject,
            CoreAudioProperty.address(kAudioHardwarePropertyProcessObjectList),
            operation: "list audio processes"
        )) ?? []
        for id in ids {
            processListeners.add(
                to: id,
                address: CoreAudioProperty.address(kAudioProcessPropertyIsRunningOutput)
            ) { [weak self] in
                self?.onChange?()
            }
        }
    }

    private func makeProcess(_ id: AudioObjectID) -> AudioProcess? {
        guard let pid: pid_t = try? CoreAudioProperty.read(
            id,
            CoreAudioProperty.address(kAudioProcessPropertyPID),
            initial: -1,
            operation: "read the process ID"
        ), pid > 0 else {
            return nil
        }
        let isRunningOutput: UInt32 = (try? CoreAudioProperty.read(
            id,
            CoreAudioProperty.address(kAudioProcessPropertyIsRunningOutput),
            initial: 0,
            operation: "read the playing state"
        )) ?? 0
        return AudioProcess(
            id: id,
            pid: pid,
            bundleID: CoreAudioProperty.readString(id, CoreAudioProperty.address(kAudioProcessPropertyBundleID)),
            isRunningOutput: isRunningOutput != 0
        )
    }
}
