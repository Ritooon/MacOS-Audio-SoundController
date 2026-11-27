import Testing
@testable import Orpheus

@Suite("AudioDevice")
struct AudioDeviceTests {
    @Test func supportsScopeFollowsChannelCounts() {
        let speaker = AudioDevice.fixture(id: 1, name: "Speaker", outputChannels: 2, inputChannels: 0)
        #expect(speaker.supports(.output))
        #expect(!speaker.supports(.input))
    }

    @Test func rolesMapToScopes() {
        #expect(DeviceRole.output.scope == .output)
        #expect(DeviceRole.soundEffects.scope == .output)
        #expect(DeviceRole.input.scope == .input)
    }

    @Test func builtInSymbolDependsOnScope() {
        #expect(TransportKind.builtIn.symbolName(for: .output) == "hifispeaker.fill")
        #expect(TransportKind.builtIn.symbolName(for: .input) == "mic.fill")
        #expect(TransportKind.bluetooth.symbolName(for: .input) == "headphones")
    }

    @Test func errorDescriptionKeepsOperationAndStatus() {
        let error = AudioError(operation: "change the volume", reason: .status(-50))
        #expect(error.localizedDescription.contains("change the volume"))
        #expect(error.localizedDescription.contains("-50"))
    }
}
