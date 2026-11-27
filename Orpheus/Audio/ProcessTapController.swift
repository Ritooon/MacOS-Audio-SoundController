import CoreAudio
import Foundation
import os

/// A running per-app audio pipeline whose gain can be changed live.
protocol ProcessTapControlling: AnyObject {
    /// The CoreAudio process objects being tapped.
    var processObjectIDs: [AudioObjectID] { get }
    /// The UID of the device the audio is played on.
    var outputDeviceUID: String { get }
    /// Whether any non-silent audio has reached the tap since it started.
    /// It stays `false` when audio-capture permission was refused.
    var hasReceivedAudio: Bool { get }

    /// Changes the amplitude gain; the change is ramped over one buffer to avoid clicks.
    /// - Parameter gain: The new linear gain (see ``GainProcessor/gain(forVolume:)``).
    func setGain(_ gain: Float)

    /// Stops the audio and releases every CoreAudio object. Safe to call more than once.
    func invalidate()
}

/// Creates per-app pipelines, so the app model can be tested with a mock.
protocol ProcessTapMaking {
    /// Starts tapping a set of processes and playing them, with a gain, on a device.
    /// - Parameters:
    ///   - processObjectIDs: The CoreAudio process objects of one app.
    ///   - outputDeviceUID: The device to play on.
    ///   - gain: The initial linear gain.
    /// - Returns: The running pipeline.
    /// - Throws: ``AudioError`` if any CoreAudio step fails.
    func makeTap(processObjectIDs: [AudioObjectID], outputDeviceUID: String, gain: Float) throws -> ProcessTapControlling
}

/// The CoreAudio implementation of ``ProcessTapMaking``.
struct ProcessTapFactory: ProcessTapMaking {
    func makeTap(processObjectIDs: [AudioObjectID], outputDeviceUID: String, gain: Float) throws -> ProcessTapControlling {
        try ProcessTapController(processObjectIDs: processObjectIDs, outputDeviceUID: outputDeviceUID, gain: gain)
    }
}

/// One app's audio pipeline: a Process Tap that mutes the app, a private aggregate device
/// that reads the tap and plays on the chosen output, and an IOProc that applies the gain.
///
/// ```text
/// app processes ──tap (muted when tapped)──▶ aggregate input ──IOProc: GainProcessor──▶ aggregate output = device
/// ```
final class ProcessTapController: ProcessTapControlling {
    /// Prefix of the UIDs of the aggregate devices Orpheus creates; they are hidden from device lists.
    static let aggregateUIDPrefix = "com.ritooon.Orpheus.tap."

    let processObjectIDs: [AudioObjectID]
    let outputDeviceUID: String

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Orpheus", category: "ProcessTap")
    private let targetGain: AtomicFloat
    private let receivedAudio = AtomicFloat(0)
    /// The gain reached at the end of the previous buffer. Only touched by the audio thread.
    private let rampGain: UnsafeMutablePointer<Float>
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?

    var hasReceivedAudio: Bool {
        receivedAudio.load() > 0
    }

    /// Creates and starts the pipeline.
    /// - Parameters:
    ///   - processObjectIDs: The CoreAudio process objects of one app.
    ///   - outputDeviceUID: The device to play on.
    ///   - gain: The initial linear gain.
    /// - Throws: ``AudioError`` if any step fails; everything created so far is released.
    init(processObjectIDs: [AudioObjectID], outputDeviceUID: String, gain: Float) throws {
        self.processObjectIDs = processObjectIDs
        self.outputDeviceUID = outputDeviceUID
        targetGain = AtomicFloat(gain)
        rampGain = .allocate(capacity: 1)
        rampGain.initialize(to: gain)
        do {
            let tapUID = try createTap()
            try createAggregateDevice(tapUID: tapUID)
            try checkFormats()
            try startIO()
        } catch {
            invalidate()
            throw error
        }
    }

    deinit {
        invalidate()
        rampGain.deallocate()
    }

    func setGain(_ gain: Float) {
        targetGain.store(gain)
    }

    func invalidate() {
        if let ioProcID {
            AudioDeviceStop(aggregateID, ioProcID)
            AudioDeviceDestroyIOProcID(aggregateID, ioProcID)
            self.ioProcID = nil
        }
        if aggregateID != kAudioObjectUnknown {
            let status = AudioHardwareDestroyAggregateDevice(aggregateID)
            if status != noErr { logger.warning("Could not destroy aggregate device: \(status)") }
            aggregateID = AudioObjectID(kAudioObjectUnknown)
        }
        if tapID != kAudioObjectUnknown {
            let status = AudioHardwareDestroyProcessTap(tapID)
            if status != noErr { logger.warning("Could not destroy process tap: \(status)") }
            tapID = AudioObjectID(kAudioObjectUnknown)
        }
    }

    // MARK: Setup

    private func createTap() throws -> String {
        let description = CATapDescription(stereoMixdownOfProcesses: processObjectIDs)
        description.uuid = UUID()
        description.name = "Orpheus"
        description.isPrivate = true
        description.muteBehavior = CATapMuteBehavior.mutedWhenTapped

        var tapID = AudioObjectID(kAudioObjectUnknown)
        let status = AudioHardwareCreateProcessTap(description, &tapID)
        guard status == noErr else {
            throw AudioError(operation: "capture the app's audio", reason: .status(status))
        }
        self.tapID = tapID
        return description.uuid.uuidString
    }

    private func createAggregateDevice(tapUID: String) throws {
        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Orpheus",
            kAudioAggregateDeviceUIDKey: Self.aggregateUIDPrefix + UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputDeviceUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [
                [kAudioSubDeviceUIDKey: outputDeviceUID],
            ],
            kAudioAggregateDeviceTapListKey: [
                [
                    kAudioSubTapDriftCompensationKey: true,
                    kAudioSubTapUIDKey: tapUID,
                ],
            ],
        ]
        var aggregateID = AudioObjectID(kAudioObjectUnknown)
        let status = AudioHardwareCreateAggregateDevice(description as CFDictionary, &aggregateID)
        guard status == noErr else {
            throw AudioError(operation: "create the app's audio route", reason: .status(status))
        }
        self.aggregateID = aggregateID
    }

    /// The IOProc reads and writes 32-bit float samples; refuse anything else instead of
    /// producing noise.
    private func checkFormats() throws {
        let tapFormat: AudioStreamBasicDescription = try CoreAudioProperty.read(
            tapID,
            CoreAudioProperty.address(kAudioTapPropertyFormat),
            initial: AudioStreamBasicDescription(),
            operation: "read the tap format"
        )
        guard Self.isFloat32(tapFormat) else {
            throw AudioError(operation: "use the app's audio format", reason: .propertyUnsupported)
        }

        let outputStreams: [AudioStreamID] = try CoreAudioProperty.readArray(
            aggregateID,
            CoreAudioProperty.address(kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeOutput),
            operation: "list the output streams"
        )
        for stream in outputStreams {
            let format: AudioStreamBasicDescription = try CoreAudioProperty.read(
                stream,
                CoreAudioProperty.address(kAudioStreamPropertyVirtualFormat),
                initial: AudioStreamBasicDescription(),
                operation: "read the output format"
            )
            guard Self.isFloat32(format) else {
                throw AudioError(operation: "use the output device's audio format", reason: .propertyUnsupported)
            }
        }
    }

    private func startIO() throws {
        let inputStreams: [AudioStreamID] = (try? CoreAudioProperty.readArray(
            aggregateID,
            CoreAudioProperty.address(kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeInput),
            operation: "list the input streams"
        )) ?? []
        // The aggregate lists the output device's own input streams (for example a headset
        // microphone) first, then the tap's single mixdown stream.
        let firstTapBuffer = max(inputStreams.count - 1, 0)

        // Captured by the real-time block: only pointers and values, no allocation.
        let targetGain = targetGain
        let receivedAudio = receivedAudio
        let rampGain = rampGain

        var procID: AudioDeviceIOProcID?
        var status = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, nil) { _, inputData, _, outputData, _ in
            let input = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inputData))
            let output = UnsafeMutableAudioBufferListPointer(outputData)
            let endGain = targetGain.load()
            let peak = GainProcessor.process(
                input: input,
                firstTapBuffer: firstTapBuffer,
                output: output,
                startGain: rampGain.pointee,
                endGain: endGain
            )
            rampGain.pointee = endGain
            if peak > 0 {
                receivedAudio.store(1)
            }
        }
        guard status == noErr, let procID else {
            throw AudioError(operation: "start the app's audio route", reason: .status(status))
        }
        ioProcID = procID

        status = AudioDeviceStart(aggregateID, procID)
        guard status == noErr else {
            throw AudioError(operation: "start the app's audio route", reason: .status(status))
        }
    }

    private static func isFloat32(_ format: AudioStreamBasicDescription) -> Bool {
        format.mFormatID == kAudioFormatLinearPCM
            && format.mFormatFlags & kAudioFormatFlagIsFloat != 0
            && format.mBitsPerChannel == 32
    }
}
