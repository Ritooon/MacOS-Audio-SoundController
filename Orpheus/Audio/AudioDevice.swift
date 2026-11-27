import CoreAudio

/// The direction of audio on a device.
enum DeviceScope: Equatable, Sendable {
    case output
    case input
}

/// A system-wide role a device can be assigned to.
enum DeviceRole: CaseIterable, Identifiable, Sendable {
    /// The default output device (`kAudioHardwarePropertyDefaultOutputDevice`).
    case output
    /// The default input device (`kAudioHardwarePropertyDefaultInputDevice`).
    case input
    /// The device used for alerts and sound effects (`kAudioHardwarePropertyDefaultSystemOutputDevice`).
    case soundEffects

    var id: Self { self }

    /// The scope a device needs in order to fill this role.
    var scope: DeviceScope {
        switch self {
        case .output, .soundEffects: .output
        case .input: .input
        }
    }
}

/// How a device is connected to the Mac.
enum TransportKind: Equatable, Sendable {
    case builtIn
    case usb
    case bluetooth
    case hdmi
    case displayPort
    case airPlay
    case thunderbolt
    case aggregate
    case virtual
    case other

    /// A human-readable name for the transport, shown in device info.
    var displayName: String {
        switch self {
        case .builtIn: "Built-in"
        case .usb: "USB"
        case .bluetooth: "Bluetooth"
        case .hdmi: "HDMI"
        case .displayPort: "DisplayPort"
        case .airPlay: "AirPlay"
        case .thunderbolt: "Thunderbolt"
        case .aggregate: "Aggregate"
        case .virtual: "Virtual"
        case .other: "Other"
        }
    }

    /// An SF Symbol representing a device with this transport.
    /// - Parameter scope: Whether the device is shown as an output or an input.
    /// - Returns: The name of an SF Symbol.
    func symbolName(for scope: DeviceScope) -> String {
        switch self {
        case .bluetooth: "headphones"
        case .usb, .thunderbolt: "cable.connector"
        case .hdmi, .displayPort: "tv"
        case .airPlay: "airplayaudio"
        case .aggregate: "square.stack.3d.up.fill"
        case .virtual: "waveform"
        case .builtIn, .other: scope == .input ? "mic.fill" : "hifispeaker.fill"
        }
    }
}

/// An audio device known to CoreAudio.
struct AudioDevice: Identifiable, Hashable, Sendable {
    /// The CoreAudio object ID. It changes across reboots and reconnections:
    /// use ``uid`` to identify a device persistently.
    typealias ID = AudioObjectID

    let id: ID
    /// The persistent identifier (`kAudioDevicePropertyDeviceUID`).
    let uid: String
    /// The native device name.
    let name: String
    let transport: TransportKind
    /// Number of output channels; 0 when the device cannot play audio.
    let outputChannels: Int
    /// Number of input channels; 0 when the device cannot record audio.
    let inputChannels: Int
    /// The nominal sample rate in Hz, when the device reports one.
    let sampleRate: Double?

    /// Whether the device has channels in the given scope.
    /// - Parameter scope: The direction to check.
    /// - Returns: `true` if the device can be used in that direction.
    func supports(_ scope: DeviceScope) -> Bool {
        switch scope {
        case .output: outputChannels > 0
        case .input: inputChannels > 0
        }
    }
}

/// The volume and mute state of a device in one scope.
struct VolumeState: Equatable, Sendable {
    /// The volume, from 0 to 1.
    var level: Float
    /// Whether the volume can be changed.
    var isSettable: Bool
    /// The mute state, or `nil` when the device has no mute control.
    var isMuted: Bool?
    /// Whether the mute state can be changed.
    var isMuteSettable: Bool
}
