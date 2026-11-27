import CoreAudio
import Foundation

/// An error raised by the audio layer.
///
/// It keeps the operation that failed and, for CoreAudio failures, the raw `OSStatus`,
/// so that logs and user-facing messages can say exactly what went wrong.
struct AudioError: Error, Equatable {
    /// The reason an audio operation failed.
    enum Reason: Equatable {
        /// A CoreAudio call returned a non-zero status.
        case status(OSStatus)
        /// The object does not expose the requested property.
        case propertyUnsupported
        /// The property exists but cannot be written.
        case propertyNotSettable
        /// The device is no longer present.
        case deviceNotFound
    }

    /// A short description of the failing operation, for example `"set default output device"`.
    let operation: String
    /// Why the operation failed.
    let reason: Reason
}

extension AudioError: LocalizedError {
    var errorDescription: String? {
        switch reason {
        case let .status(status):
            "Could not \(operation) (CoreAudio error \(status))."
        case .propertyUnsupported:
            "Could not \(operation): this device does not support it."
        case .propertyNotSettable:
            "Could not \(operation): this device does not allow it."
        case .deviceNotFound:
            "Could not \(operation): the device is no longer connected."
        }
    }
}
