import Foundation
import Observation
import os

/// A short message shown at the top of the panel, for example when a device connects.
struct ToastMessage: Equatable, Identifiable {
    let id = UUID()
    let text: String
    let symbolName: String
}

/// The observable state of the system output, input and sound-effects devices.
///
/// Views read this model and call its methods; it talks to CoreAudio only through
/// an ``AudioDeviceProviding`` so that it can be tested with a mock.
@MainActor
@Observable
final class SystemAudioModel {
    /// What the panel shows for one role.
    struct RoleState: Equatable {
        /// Devices that can fill the role, sorted by name.
        var devices: [AudioDevice] = []
        /// The device currently assigned to the role.
        var selectedID: AudioDevice.ID?
        /// The volume of the selected device, or `nil` when it has no volume control.
        var volume: VolumeState?

        /// The selected device, when it is in ``devices``.
        var selectedDevice: AudioDevice? {
            devices.first { $0.id == selectedID }
        }
    }

    private(set) var output = RoleState()
    private(set) var input = RoleState()
    private(set) var soundEffects = RoleState()
    /// The last error, shown inline in the panel.
    private(set) var errorMessage: String?
    /// The current toast, if any.
    private(set) var toast: ToastMessage?

    @ObservationIgnored private let provider: AudioDeviceProviding
    @ObservationIgnored private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Orpheus",
        category: "SystemAudioModel"
    )
    /// UIDs seen at the previous refresh; `nil` before the first one, so that
    /// devices present at launch do not trigger a toast.
    @ObservationIgnored private var knownDevices: [String: AudioDevice]?
    @ObservationIgnored private var refreshScheduled = false

    /// Creates a model.
    /// - Parameter provider: The source of device information.
    init(provider: AudioDeviceProviding) {
        self.provider = provider
    }

    /// The state for a role.
    /// - Parameter role: The system role.
    /// - Returns: Its devices, selection and volume.
    func state(for role: DeviceRole) -> RoleState {
        switch role {
        case .output: output
        case .input: input
        case .soundEffects: soundEffects
        }
    }

    /// Reads the current state and starts following system changes.
    func start() {
        provider.startObserving { [weak self] in
            Task { @MainActor in self?.scheduleRefresh() }
        }
        refresh()
    }

    /// Stops following system changes.
    func stop() {
        provider.stopObserving()
    }

    /// Reads devices, defaults and volumes from the provider.
    func refresh() {
        let devices: [AudioDevice]
        do {
            devices = try provider.allDevices().sorted {
                $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
        } catch {
            report(error)
            devices = []
        }

        announceChanges(in: devices)

        output = makeState(for: .output, from: devices)
        input = makeState(for: .input, from: devices)
        soundEffects = makeState(for: .soundEffects, from: devices)
    }

    /// Assigns a device to a role.
    /// - Parameters:
    ///   - id: The device to assign.
    ///   - role: The system role.
    func selectDevice(_ id: AudioDevice.ID, for role: DeviceRole) {
        guard state(for: role).selectedID != id else { return }
        do {
            try provider.setDefaultDevice(id, for: role)
            errorMessage = nil
        } catch {
            report(error)
        }
        refresh()
    }

    /// Changes the volume of the device assigned to a role.
    /// - Parameters:
    ///   - level: The new volume; values outside 0...1 are clamped.
    ///   - role: The system role.
    func setVolume(_ level: Float, for role: DeviceRole) {
        var state = state(for: role)
        guard let id = state.selectedID, var volume = state.volume, volume.isSettable else { return }
        let clamped = min(max(level, 0), 1)
        do {
            try provider.setVolume(clamped, of: id, scope: role.scope)
            volume.level = clamped
            state.volume = volume
            update(state, for: role)
            errorMessage = nil
        } catch {
            report(error)
        }
    }

    /// Toggles the mute state of the device assigned to a role.
    /// - Parameter role: The system role.
    func toggleMute(for role: DeviceRole) {
        var state = state(for: role)
        guard let id = state.selectedID,
              var volume = state.volume,
              volume.isMuteSettable,
              let isMuted = volume.isMuted
        else {
            return
        }
        do {
            try provider.setMuted(!isMuted, of: id, scope: role.scope)
            volume.isMuted = !isMuted
            state.volume = volume
            update(state, for: role)
            errorMessage = nil
        } catch {
            report(error)
        }
    }

    /// Hides the current toast.
    func dismissToast() {
        toast = nil
    }

    /// Hides the current error message.
    func dismissError() {
        errorMessage = nil
    }

    // MARK: Private

    /// Coalesces bursts of CoreAudio notifications into one refresh.
    private func scheduleRefresh() {
        guard !refreshScheduled else { return }
        refreshScheduled = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            refreshScheduled = false
            refresh()
        }
    }

    private func makeState(for role: DeviceRole, from devices: [AudioDevice]) -> RoleState {
        let candidates = devices.filter { $0.supports(role.scope) }
        let selectedID: AudioDevice.ID?
        do {
            selectedID = try provider.defaultDeviceID(for: role)
        } catch {
            report(error)
            selectedID = nil
        }
        let volume: VolumeState? = switch role {
        case .output, .input:
            selectedID.flatMap { provider.volumeState(of: $0, scope: role.scope) }
        case .soundEffects:
            // macOS has no public API for the alert volume; only the device is chosen here.
            nil
        }
        return RoleState(devices: candidates, selectedID: selectedID, volume: volume)
    }

    private func update(_ state: RoleState, for role: DeviceRole) {
        switch role {
        case .output: output = state
        case .input: input = state
        case .soundEffects: soundEffects = state
        }
    }

    private func announceChanges(in devices: [AudioDevice]) {
        let current = Dictionary(devices.map { ($0.uid, $0) }, uniquingKeysWith: { first, _ in first })
        defer { knownDevices = current }
        guard let previous = knownDevices else { return }

        if let added = devices.first(where: { previous[$0.uid] == nil }) {
            let scope: DeviceScope = added.supports(.output) ? .output : .input
            toast = ToastMessage(
                text: "\(added.name) connected",
                symbolName: added.transport.symbolName(for: scope)
            )
        } else if let removed = previous.values.first(where: { current[$0.uid] == nil }) {
            toast = ToastMessage(text: "\(removed.name) disconnected", symbolName: "bolt.horizontal.circle")
        }
    }

    private func report(_ error: Error) {
        logger.error("\(error.localizedDescription, privacy: .public)")
        errorMessage = error.localizedDescription
    }
}
