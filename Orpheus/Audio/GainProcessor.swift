import CoreAudio

/// Pure DSP for per-app volume and boost. Every function here is safe on the real-time
/// audio thread: no allocation, no locks, no logging.
enum GainProcessor {
    /// The highest per-app volume: 3 means 300 %.
    static let maxBoost: Float = 3
    /// Above this level, samples go through a soft knee so they never leave [-1, 1].
    static let limiterThreshold: Float = 0.9

    /// Converts a volume setting into a linear amplitude gain.
    ///
    /// Up to 100 %, the curve is quadratic so the slider feels even to the ear.
    /// Above 100 % (boost), the gain grows linearly, up to ``maxBoost``.
    /// - Parameter volume: The volume setting, where 1 means 100 %.
    /// - Returns: The amplitude gain.
    static func gain(forVolume volume: Float) -> Float {
        let clamped = min(max(volume, 0), maxBoost)
        return clamped <= 1 ? clamped * clamped : clamped
    }

    /// A soft limiter: transparent below ``limiterThreshold``, then a smooth curve that
    /// approaches but never reaches ±1.
    /// - Parameter sample: A sample, possibly amplified past ±1.
    /// - Returns: A sample in [-1, 1].
    @inline(__always)
    static func limit(_ sample: Float) -> Float {
        guard sample.isFinite else { return 0 }
        let magnitude = abs(sample)
        guard magnitude > limiterThreshold else { return sample }
        let headroom = 1 - limiterThreshold
        let excess = (magnitude - limiterThreshold) / headroom
        // x / (1 + x) maps [0, ∞) to [0, 1), so the result stays below 1.
        let limited = limiterThreshold + headroom * (excess / (1 + excess))
        return sample < 0 ? -limited : limited
    }

    /// Copies tapped audio to the output buffers, applying a gain ramp and the limiter.
    ///
    /// Output channels are filled from the tap channels in order, wrapping around when the
    /// output has more channels (for example a stereo tap on a 4-channel device).
    /// Output buffers with no matching input are filled with silence.
    /// Buffers must contain interleaved 32-bit float samples.
    /// - Parameters:
    ///   - input: The aggregate device input buffers.
    ///   - firstTapBuffer: Index of the first input buffer that belongs to the tap
    ///     (earlier buffers are the output device's own inputs, such as a headset microphone).
    ///   - output: The output buffers to fill.
    ///   - startGain: The gain at the first frame.
    ///   - endGain: The gain at the last frame; the gain moves linearly in between to avoid clicks.
    /// - Returns: The peak magnitude of the tapped input, before gain.
    @discardableResult
    static func process(
        input: UnsafeMutableAudioBufferListPointer,
        firstTapBuffer: Int,
        output: UnsafeMutableAudioBufferListPointer,
        startGain: Float,
        endGain: Float
    ) -> Float {
        let sampleSize = MemoryLayout<Float>.size
        let tapBufferCount = max(input.count - firstTapBuffer, 0)
        var tapChannels = 0
        var tapFrames = Int.max
        for index in 0 ..< tapBufferCount {
            let buffer = input[firstTapBuffer + index]
            let channels = Int(buffer.mNumberChannels)
            guard channels > 0, buffer.mData != nil else { continue }
            tapChannels += channels
            tapFrames = min(tapFrames, Int(buffer.mDataByteSize) / (channels * sampleSize))
        }

        var peak: Float = 0
        var outputChannelIndex = 0
        for outputIndex in 0 ..< output.count {
            let buffer = output[outputIndex]
            let channels = Int(buffer.mNumberChannels)
            guard channels > 0, let data = buffer.mData else { continue }
            let samples = data.assumingMemoryBound(to: Float.self)
            let frames = Int(buffer.mDataByteSize) / (channels * sampleSize)

            guard tapChannels > 0 else {
                samples.update(repeating: 0, count: frames * channels)
                continue
            }

            let usableFrames = min(frames, tapFrames)
            let step = usableFrames > 1 ? (endGain - startGain) / Float(usableFrames - 1) : 0
            for channel in 0 ..< channels {
                let (source, sourceChannels, sourceChannel) = tapChannel(
                    at: (outputChannelIndex + channel) % tapChannels,
                    in: input,
                    firstTapBuffer: firstTapBuffer
                )
                var gain = startGain
                for frame in 0 ..< usableFrames {
                    let sample = source.map { $0[frame * sourceChannels + sourceChannel] } ?? 0
                    peak = max(peak, abs(sample))
                    samples[frame * channels + channel] = limit(sample * gain)
                    gain += step
                }
                for frame in usableFrames ..< frames {
                    samples[frame * channels + channel] = 0
                }
            }
            outputChannelIndex += channels
        }
        return peak
    }

    /// Finds the buffer and position of a tap channel, counting across all tap buffers.
    @inline(__always)
    private static func tapChannel(
        at index: Int,
        in input: UnsafeMutableAudioBufferListPointer,
        firstTapBuffer: Int
    ) -> (UnsafeMutablePointer<Float>?, Int, Int) {
        var remaining = index
        for bufferIndex in firstTapBuffer ..< input.count {
            let buffer = input[bufferIndex]
            let channels = Int(buffer.mNumberChannels)
            guard channels > 0, let data = buffer.mData else { continue }
            if remaining < channels {
                return (data.assumingMemoryBound(to: Float.self), channels, remaining)
            }
            remaining -= channels
        }
        return (nil, 1, 0)
    }
}
