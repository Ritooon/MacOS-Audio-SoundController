import AudioToolbox
import CoreAudio
import Foundation
import os

/// Abstraction over system audio devices, so that app logic can be tested without real hardware.
protocol AudioDeviceProviding: AnyObject {
    /// All devices currently known to the system.
    /// - Throws: ``AudioError`` if the device list cannot be read.
    func allDevices() throws -> [AudioDevice]

    /// The device currently assigned to a role.
    /// - Parameter role: The system role.
    /// - Returns: The device ID, or `nil` when no device fills the role.
    /// - Throws: ``AudioError`` if the default device cannot be read.
    func defaultDeviceID(for role: DeviceRole) throws -> AudioDevice.ID?

    /// Assigns a device to a role.
    /// - Parameters:
    ///   - id: The device to assign.
    ///   - role: The system role.
    /// - Throws: ``AudioError`` if the system refuses the change.
    func setDefaultDevice(_ id: AudioDevice.ID, for role: DeviceRole) throws

    /// The volume and mute state of a device.
    /// - Parameters:
    ///   - id: The device.
    ///   - scope: Output or input.
    /// - Returns: The state, or `nil` when the device has no volume control in that scope.
    func volumeState(of id: AudioDevice.ID, scope: DeviceScope) -> VolumeState?

    /// Changes the volume of a device.
    /// - Parameters:
    ///   - level: The new volume, from 0 to 1.
    ///   - id: The device.
    ///   - scope: Output or input.
    /// - Throws: ``AudioError`` if the device has no settable volume.
    func setVolume(_ level: Float, of id: AudioDevice.ID, scope: DeviceScope) throws

    /// Mutes or unmutes a device.
    /// - Parameters:
    ///   - muted: The new mute state.
    ///   - id: The device.
    ///   - scope: Output or input.
    /// - Throws: ``AudioError`` if the device has no settable mute control.
    func setMuted(_ muted: Bool, of id: AudioDevice.ID, scope: DeviceScope) throws

    /// Starts calling `onChange` on the main queue whenever devices, defaults,
    /// or the volume of a default device change.
    /// - Parameter onChange: The closure to call.
    func startObserving(_ onChange: @escaping () -> Void)

    /// Stops observing and removes every listener added by ``startObserving(_:)``.
    func stopObserving()
}

/// The CoreAudio implementation of ``AudioDeviceProviding``.
///
/// Use it from the main thread only: its listeners are delivered on the main queue.
final class AudioDeviceService: AudioDeviceProviding {
    private struct Listener {
        let objectID: AudioObjectID
        var address: AudioObjectPropertyAddress
        let block: AudioObjectPropertyListenerBlock
    }

    private static let systemObject = AudioObjectID(kAudioObjectSystemObject)

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Orpheus", category: "AudioDeviceService")
    private var systemListeners: [Listener] = []
    private var deviceListeners: [Listener] = []
    private var onChange: (() -> Void)?

    deinit {
        stopObserving()
    }

    // MARK: Devices

    func allDevices() throws -> [AudioDevice] {
        let ids: [AudioObjectID] = try readArray(
            Self.systemObject,
            address(kAudioHardwarePropertyDevices),
            operation: "list audio devices"
        )
        return ids.compactMap(makeDevice)
    }

    func defaultDeviceID(for role: DeviceRole) throws -> AudioDevice.ID? {
        let id: AudioObjectID = try read(
            Self.systemObject,
            address(Self.selector(for: role)),
            initial: AudioObjectID(kAudioObjectUnknown),
            operation: "read the default device"
        )
        return id == kAudioObjectUnknown ? nil : id
    }

    func setDefaultDevice(_ id: AudioDevice.ID, for role: DeviceRole) throws {
        try write(
            Self.systemObject,
            address(Self.selector(for: role)),
            value: id,
            operation: "change the default device"
        )
    }

    // MARK: Volume and mute

    func volumeState(of id: AudioDevice.ID, scope: DeviceScope) -> VolumeState? {
        guard let volumeAddress = volumeAddress(of: id, scope: scope),
              let level: Float32 = try? read(id, volumeAddress, initial: 0, operation: "read the volume")
        else {
            return nil
        }
        let muteAddress = address(kAudioDevicePropertyMute, scope: Self.coreAudioScope(scope))
        let muteValue: UInt32? = has(id, muteAddress)
            ? try? read(id, muteAddress, initial: 0, operation: "read the mute state")
            : nil
        return VolumeState(
            level: level,
            isSettable: isSettable(id, volumeAddress),
            isMuted: muteValue.map { $0 != 0 },
            isMuteSettable: muteValue != nil && isSettable(id, muteAddress)
        )
    }

    func setVolume(_ level: Float, of id: AudioDevice.ID, scope: DeviceScope) throws {
        guard let volumeAddress = volumeAddress(of: id, scope: scope) else {
            throw AudioError(operation: "change the volume", reason: .propertyUnsupported)
        }
        let clamped = Float32(min(max(level, 0), 1))
        try write(id, volumeAddress, value: clamped, operation: "change the volume")
    }

    func setMuted(_ muted: Bool, of id: AudioDevice.ID, scope: DeviceScope) throws {
        let muteAddress = address(kAudioDevicePropertyMute, scope: Self.coreAudioScope(scope))
        try write(id, muteAddress, value: UInt32(muted ? 1 : 0), operation: "change the mute state")
    }

    // MARK: Observation

    func startObserving(_ onChange: @escaping () -> Void) {
        stopObserving()
        self.onChange = onChange
        let selectors = [
            kAudioHardwarePropertyDevices,
            kAudioHardwarePropertyDefaultOutputDevice,
            kAudioHardwarePropertyDefaultInputDevice,
            kAudioHardwarePropertyDefaultSystemOutputDevice,
        ]
        systemListeners = selectors.compactMap { selector in
            addListener(to: Self.systemObject, address: address(selector)) { [weak self] in
                self?.updateDeviceListeners()
                self?.onChange?()
            }
        }
        updateDeviceListeners()
    }

    func stopObserving() {
        (systemListeners + deviceListeners).forEach(removeListener)
        systemListeners = []
        deviceListeners = []
        onChange = nil
    }

    /// Listens to volume and mute changes on the current default output and input devices.
    private func updateDeviceListeners() {
        deviceListeners.forEach(removeListener)
        deviceListeners = []

        let targets: [(AudioDevice.ID, DeviceScope)] = [DeviceRole.output, .input].compactMap { role in
            guard let id = try? defaultDeviceID(for: role) else { return nil }
            return (id, role.scope)
        }

        for (id, scope) in targets {
            let coreScope = Self.coreAudioScope(scope)
            let selectors = [
                kAudioDevicePropertyVolumeScalar,
                kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
                kAudioDevicePropertyMute,
            ]
            for selector in selectors {
                let listened = address(selector, scope: coreScope)
                guard has(id, listened) else { continue }
                if let listener = addListener(to: id, address: listened, handler: { [weak self] in
                    self?.onChange?()
                }) {
                    deviceListeners.append(listener)
                }
            }
        }
    }

    private func addListener(
        to objectID: AudioObjectID,
        address: AudioObjectPropertyAddress,
        handler: @escaping () -> Void
    ) -> Listener? {
        var address = address
        let block: AudioObjectPropertyListenerBlock = { _, _ in handler() }
        let status = AudioObjectAddPropertyListenerBlock(objectID, &address, DispatchQueue.main, block)
        guard status == noErr else {
            logger.warning("Could not add listener \(address.mSelector) on \(objectID): \(status)")
            return nil
        }
        return Listener(objectID: objectID, address: address, block: block)
    }

    private func removeListener(_ listener: Listener) {
        var address = listener.address
        let status = AudioObjectRemovePropertyListenerBlock(
            listener.objectID,
            &address,
            DispatchQueue.main,
            listener.block
        )
        if status != noErr {
            // Expected when the device has already disappeared.
            logger.debug("Could not remove listener on \(listener.objectID): \(status)")
        }
    }

    // MARK: Device description

    private func makeDevice(_ id: AudioObjectID) -> AudioDevice? {
        guard let uid = readString(id, address(kAudioDevicePropertyDeviceUID)),
              let name = readString(id, address(kAudioObjectPropertyName))
        else {
            return nil
        }
        let transport: UInt32 = (try? read(
            id,
            address(kAudioDevicePropertyTransportType),
            initial: 0,
            operation: "read the transport type"
        )) ?? 0
        let sampleRate: Float64? = try? read(
            id,
            address(kAudioDevicePropertyNominalSampleRate),
            initial: 0,
            operation: "read the sample rate"
        )
        return AudioDevice(
            id: id,
            uid: uid,
            name: name,
            transport: Self.transportKind(transport),
            outputChannels: channelCount(id, scope: kAudioObjectPropertyScopeOutput),
            inputChannels: channelCount(id, scope: kAudioObjectPropertyScopeInput),
            sampleRate: sampleRate.flatMap { $0 > 0 ? $0 : nil }
        )
    }

    private func channelCount(_ id: AudioObjectID, scope: AudioObjectPropertyScope) -> Int {
        var streamAddress = address(kAudioDevicePropertyStreamConfiguration, scope: scope)
        var size: UInt32 = 0
        guard AudioObjectHasProperty(id, &streamAddress),
              AudioObjectGetPropertyDataSize(id, &streamAddress, 0, nil, &size) == noErr,
              size > 0
        else {
            return 0
        }
        let buffer = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { buffer.deallocate() }
        guard AudioObjectGetPropertyData(id, &streamAddress, 0, nil, &size, buffer) == noErr else {
            return 0
        }
        let list = UnsafeMutableAudioBufferListPointer(buffer.assumingMemoryBound(to: AudioBufferList.self))
        return list.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    /// The address of the device volume: the main element if it exists,
    /// otherwise the virtual main volume that CoreAudio derives from the channels.
    private func volumeAddress(of id: AudioObjectID, scope: DeviceScope) -> AudioObjectPropertyAddress? {
        let coreScope = Self.coreAudioScope(scope)
        let candidates = [
            address(kAudioDevicePropertyVolumeScalar, scope: coreScope),
            address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, scope: coreScope),
        ]
        return candidates.first { has(id, $0) }
    }

    // MARK: Mapping

    private static func selector(for role: DeviceRole) -> AudioObjectPropertySelector {
        switch role {
        case .output: kAudioHardwarePropertyDefaultOutputDevice
        case .input: kAudioHardwarePropertyDefaultInputDevice
        case .soundEffects: kAudioHardwarePropertyDefaultSystemOutputDevice
        }
    }

    private static func coreAudioScope(_ scope: DeviceScope) -> AudioObjectPropertyScope {
        switch scope {
        case .output: kAudioObjectPropertyScopeOutput
        case .input: kAudioObjectPropertyScopeInput
        }
    }

    private static func transportKind(_ value: UInt32) -> TransportKind {
        switch value {
        case kAudioDeviceTransportTypeBuiltIn: .builtIn
        case kAudioDeviceTransportTypeUSB: .usb
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: .bluetooth
        case kAudioDeviceTransportTypeHDMI: .hdmi
        case kAudioDeviceTransportTypeDisplayPort: .displayPort
        case kAudioDeviceTransportTypeAirPlay: .airPlay
        case kAudioDeviceTransportTypeThunderbolt: .thunderbolt
        case kAudioDeviceTransportTypeAggregate, kAudioDeviceTransportTypeAutoAggregate: .aggregate
        case kAudioDeviceTransportTypeVirtual: .virtual
        default: .other
        }
    }

    // MARK: Property access

    private func address(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private func has(_ id: AudioObjectID, _ address: AudioObjectPropertyAddress) -> Bool {
        var address = address
        return AudioObjectHasProperty(id, &address)
    }

    private func isSettable(_ id: AudioObjectID, _ address: AudioObjectPropertyAddress) -> Bool {
        var address = address
        var settable: DarwinBoolean = false
        return AudioObjectIsPropertySettable(id, &address, &settable) == noErr && settable.boolValue
    }

    private func read<Value>(
        _ id: AudioObjectID,
        _ address: AudioObjectPropertyAddress,
        initial: Value,
        operation: String
    ) throws -> Value {
        var address = address
        guard AudioObjectHasProperty(id, &address) else {
            throw AudioError(operation: operation, reason: .propertyUnsupported)
        }
        var value = initial
        var size = UInt32(MemoryLayout<Value>.size)
        let status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(id, &address, 0, nil, &size, pointer)
        }
        guard status == noErr else {
            throw AudioError(operation: operation, reason: .status(status))
        }
        return value
    }

    private func readArray<Element>(
        _ id: AudioObjectID,
        _ address: AudioObjectPropertyAddress,
        operation: String
    ) throws -> [Element] where Element: BinaryInteger {
        var address = address
        var size: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size)
        guard status == noErr else {
            throw AudioError(operation: operation, reason: .status(status))
        }
        var values = [Element](repeating: 0, count: Int(size) / MemoryLayout<Element>.stride)
        guard !values.isEmpty else { return [] }
        status = values.withUnsafeMutableBytes { buffer in
            // The buffer always has a base address because `values` is not empty.
            AudioObjectGetPropertyData(id, &address, 0, nil, &size, buffer.baseAddress!)
        }
        guard status == noErr else {
            throw AudioError(operation: operation, reason: .status(status))
        }
        // The device list can shrink between the two calls.
        return Array(values.prefix(Int(size) / MemoryLayout<Element>.stride))
    }

    private func readString(_ id: AudioObjectID, _ address: AudioObjectPropertyAddress) -> String? {
        var address = address
        guard AudioObjectHasProperty(id, &address) else { return nil }
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(id, &address, 0, nil, &size, pointer)
        }
        guard status == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }

    private func write<Value>(
        _ id: AudioObjectID,
        _ address: AudioObjectPropertyAddress,
        value: Value,
        operation: String
    ) throws {
        guard has(id, address) else {
            throw AudioError(operation: operation, reason: .propertyUnsupported)
        }
        guard isSettable(id, address) else {
            throw AudioError(operation: operation, reason: .propertyNotSettable)
        }
        var address = address
        var value = value
        let status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectSetPropertyData(id, &address, 0, nil, UInt32(MemoryLayout<Value>.size), pointer)
        }
        guard status == noErr else {
            throw AudioError(operation: operation, reason: .status(status))
        }
    }
}
