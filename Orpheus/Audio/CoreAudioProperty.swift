import CoreAudio
import Foundation

/// Typed helpers around `AudioObjectGetPropertyData` / `AudioObjectSetPropertyData`.
///
/// Every read checks `AudioObjectHasProperty` first and every write also checks
/// `AudioObjectIsPropertySettable`; failures are thrown as ``AudioError``.
/// These helpers allocate, so never call them on the real-time audio thread.
enum CoreAudioProperty {
    static func address(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    static func has(_ id: AudioObjectID, _ address: AudioObjectPropertyAddress) -> Bool {
        var address = address
        return AudioObjectHasProperty(id, &address)
    }

    static func isSettable(_ id: AudioObjectID, _ address: AudioObjectPropertyAddress) -> Bool {
        var address = address
        var settable: DarwinBoolean = false
        return AudioObjectIsPropertySettable(id, &address, &settable) == noErr && settable.boolValue
    }

    static func read<Value>(
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

    static func readArray<Element>(
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

    static func readString(_ id: AudioObjectID, _ address: AudioObjectPropertyAddress) -> String? {
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

    static func write<Value>(
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

/// A set of CoreAudio property listeners delivered on the main queue, removed together.
final class CoreAudioListeners {
    private struct Registration {
        let objectID: AudioObjectID
        let address: AudioObjectPropertyAddress
        let block: AudioObjectPropertyListenerBlock
    }

    private var registrations: [Registration] = []

    deinit {
        removeAll()
    }

    /// Adds a listener if the object has the property.
    /// - Parameters:
    ///   - objectID: The object to observe.
    ///   - address: The property to observe.
    ///   - handler: Called on the main queue when the property changes.
    /// - Returns: `true` if the listener was added.
    @discardableResult
    func add(
        to objectID: AudioObjectID,
        address: AudioObjectPropertyAddress,
        handler: @escaping () -> Void
    ) -> Bool {
        guard CoreAudioProperty.has(objectID, address) else { return false }
        var address = address
        let block: AudioObjectPropertyListenerBlock = { _, _ in handler() }
        guard AudioObjectAddPropertyListenerBlock(objectID, &address, DispatchQueue.main, block) == noErr else {
            return false
        }
        registrations.append(Registration(objectID: objectID, address: address, block: block))
        return true
    }

    /// Removes every listener. Failures are ignored: they happen when the object is already gone.
    func removeAll() {
        for registration in registrations {
            var address = registration.address
            _ = AudioObjectRemovePropertyListenerBlock(
                registration.objectID,
                &address,
                DispatchQueue.main,
                registration.block
            )
        }
        registrations = []
    }
}
