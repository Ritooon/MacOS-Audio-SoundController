import OrpheusAtomics

/// A `Float` that can be written on the main thread and read on the real-time audio thread
/// without locks or allocation.
///
/// The storage is allocated once in `init` and freed in `deinit`; ``load()`` and ``store(_:)``
/// only perform a single atomic 32-bit access.
final class AtomicFloat: @unchecked Sendable {
    private let storage: UnsafeMutablePointer<UInt32>

    /// Creates the value.
    /// - Parameter value: The initial value.
    init(_ value: Float) {
        storage = .allocate(capacity: 1)
        storage.initialize(to: value.bitPattern)
    }

    deinit {
        storage.deallocate()
    }

    /// Reads the value. Safe on the real-time thread.
    /// - Returns: The last stored value.
    func load() -> Float {
        Float(bitPattern: orpheus_atomic_load_u32(storage))
    }

    /// Writes the value.
    /// - Parameter value: The new value.
    func store(_ value: Float) {
        orpheus_atomic_store_u32(storage, value.bitPattern)
    }
}
