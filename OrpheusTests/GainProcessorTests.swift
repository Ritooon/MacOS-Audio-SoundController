import CoreAudio
import Foundation
import Testing
@testable import Orpheus

/// Owns an `AudioBufferList` of interleaved float buffers for a test.
private final class TestBuffers {
    let list: UnsafeMutableAudioBufferListPointer
    private var storage: [UnsafeMutablePointer<Float>] = []

    /// - Parameters:
    ///   - channels: Channel count of each buffer.
    ///   - frames: Frames per buffer.
    ///   - fill: Sample value for (buffer, channel, frame).
    init(channels: [Int], frames: Int, fill: (Int, Int, Int) -> Float = { _, _, _ in 0 }) {
        list = AudioBufferList.allocate(maximumBuffers: channels.count)
        for (index, count) in channels.enumerated() {
            let samples = UnsafeMutablePointer<Float>.allocate(capacity: count * frames)
            for frame in 0 ..< frames {
                for channel in 0 ..< count {
                    samples[frame * count + channel] = fill(index, channel, frame)
                }
            }
            storage.append(samples)
            list[index] = AudioBuffer(
                mNumberChannels: UInt32(count),
                mDataByteSize: UInt32(count * frames * MemoryLayout<Float>.size),
                mData: UnsafeMutableRawPointer(samples)
            )
        }
    }

    deinit {
        storage.forEach { $0.deallocate() }
        free(list.unsafeMutablePointer)
    }

    func sample(buffer: Int, channel: Int, frame: Int) -> Float {
        let channels = Int(list[buffer].mNumberChannels)
        return storage[buffer][frame * channels + channel]
    }
}

@Suite("GainProcessor")
struct GainProcessorTests {
    // MARK: Gain curve

    @Test func gainCurveIsQuadraticUpToUnityThenLinear() {
        #expect(GainProcessor.gain(forVolume: 0) == 0)
        #expect(GainProcessor.gain(forVolume: 0.5) == 0.25)
        #expect(GainProcessor.gain(forVolume: 1) == 1)
        #expect(GainProcessor.gain(forVolume: 2) == 2)
    }

    @Test func gainIsClampedToMaxBoost() {
        #expect(GainProcessor.gain(forVolume: 10) == GainProcessor.maxBoost)
        #expect(GainProcessor.gain(forVolume: -1) == 0)
    }

    // MARK: Limiter

    @Test func limiterIsTransparentBelowThreshold() {
        #expect(GainProcessor.limit(0.5) == 0.5)
        #expect(GainProcessor.limit(-0.85) == -0.85)
    }

    @Test(arguments: [Float(0.95), 1, 1.5, 3, 9, 1000])
    func boostIsLimitedToUnitRange(sample: Float) {
        let positive = GainProcessor.limit(sample)
        let negative = GainProcessor.limit(-sample)
        #expect(positive > GainProcessor.limiterThreshold && positive < 1)
        #expect(negative == -positive)
    }

    @Test func limiterIsMonotonic() {
        var previous = GainProcessor.limit(0)
        for step in 1 ... 400 {
            let value = GainProcessor.limit(Float(step) * 0.01)
            #expect(value >= previous)
            previous = value
        }
    }

    @Test func nonFiniteSamplesBecomeSilence() {
        #expect(GainProcessor.limit(.nan) == 0)
        #expect(GainProcessor.limit(.infinity) == 0)
    }

    // MARK: Processing

    @Test func appliesGainFromTapToOutput() {
        let input = TestBuffers(channels: [2], frames: 4) { _, channel, _ in channel == 0 ? 0.4 : -0.2 }
        let output = TestBuffers(channels: [2], frames: 4)

        let peak = GainProcessor.process(input: input.list, firstTapBuffer: 0, output: output.list, startGain: 0.5, endGain: 0.5)

        #expect(peak == 0.4)
        for frame in 0 ..< 4 {
            #expect(output.sample(buffer: 0, channel: 0, frame: frame) == 0.2)
            #expect(output.sample(buffer: 0, channel: 1, frame: frame) == -0.1)
        }
    }

    @Test func boostedOutputNeverLeavesUnitRange() {
        let input = TestBuffers(channels: [2], frames: 64) { _, _, frame in frame.isMultiple(of: 2) ? 0.9 : -0.9 }
        let output = TestBuffers(channels: [2], frames: 64)

        GainProcessor.process(input: input.list, firstTapBuffer: 0, output: output.list, startGain: 3, endGain: 3)

        for frame in 0 ..< 64 {
            for channel in 0 ..< 2 {
                #expect(abs(output.sample(buffer: 0, channel: channel, frame: frame)) < 1)
            }
        }
    }

    @Test func gainRampsAcrossTheBuffer() {
        let input = TestBuffers(channels: [1], frames: 5) { _, _, _ in 0.5 }
        let output = TestBuffers(channels: [1], frames: 5)

        GainProcessor.process(input: input.list, firstTapBuffer: 0, output: output.list, startGain: 0, endGain: 1)

        #expect(output.sample(buffer: 0, channel: 0, frame: 0) == 0)
        #expect(output.sample(buffer: 0, channel: 0, frame: 2) == 0.25)
        #expect(output.sample(buffer: 0, channel: 0, frame: 4) == 0.5)
    }

    @Test func skipsDeviceInputBuffersBeforeTheTap() {
        // Buffer 0 is a headset microphone, buffer 1 is the tap.
        let input = TestBuffers(channels: [1, 2], frames: 2) { buffer, _, _ in buffer == 0 ? 0.8 : 0.3 }
        let output = TestBuffers(channels: [2], frames: 2)

        GainProcessor.process(input: input.list, firstTapBuffer: 1, output: output.list, startGain: 1, endGain: 1)

        #expect(output.sample(buffer: 0, channel: 0, frame: 0) == 0.3)
        #expect(output.sample(buffer: 0, channel: 1, frame: 1) == 0.3)
    }

    @Test func tapChannelsWrapOnWiderOutputs() {
        let input = TestBuffers(channels: [2], frames: 1) { _, channel, _ in channel == 0 ? 0.1 : 0.2 }
        let output = TestBuffers(channels: [4], frames: 1)

        GainProcessor.process(input: input.list, firstTapBuffer: 0, output: output.list, startGain: 1, endGain: 1)

        #expect(output.sample(buffer: 0, channel: 2, frame: 0) == 0.1)
        #expect(output.sample(buffer: 0, channel: 3, frame: 0) == 0.2)
    }

    @Test func missingTapProducesSilence() {
        let input = TestBuffers(channels: [0], frames: 1)
        let output = TestBuffers(channels: [2], frames: 3) { _, _, _ in 0.7 }

        let peak = GainProcessor.process(input: input.list, firstTapBuffer: 0, output: output.list, startGain: 1, endGain: 1)

        #expect(peak == 0)
        #expect(output.sample(buffer: 0, channel: 1, frame: 2) == 0)
    }
}
