import Foundation

/// Pure-Swift 16 kHz PCM helpers for in-memory transcription and silence trimming.
public enum AudioSampleUtils {
    public static let sampleRate = 16_000

    /// Converts 16-bit signed linear PCM samples to normalized [-1, 1] floats.
    public static func pcm16ToFloat(_ samples: ArraySlice<Int16>) -> [Float] {
        var output = [Float]()
        output.reserveCapacity(samples.count)
        let scale: Float = 1.0 / 32768.0
        for sample in samples {
            output.append(Float(sample) * scale)
        }
        return output
    }

    public static func pcm16ToFloat(_ samples: [Int16]) -> [Float] {
        pcm16ToFloat(samples[...])
    }

    /// Trims excessive leading and trailing silence while preserving generous padding
    /// around detected speech so onset/offset consonants are never clipped.
    public static func trimSilence(
        _ samples: [Float],
        sampleRate: Int = sampleRate,
        rmsThreshold: Float = 0.008,
        paddingSeconds: Double = 0.25,
        frameDurationSeconds: Double = 0.02
    ) -> [Float] {
        let frameSize = max(1, Int(Double(sampleRate) * frameDurationSeconds))
        guard samples.count > frameSize else { return samples }

        let thresholdSq = rmsThreshold * rmsThreshold
        let frameCount = samples.count / frameSize
        var firstActiveFrame: Int?
        var lastActiveFrame: Int?

        for frame in 0..<frameCount {
            let start = frame * frameSize
            let end = start + frameSize
            var sumSq: Float = 0
            for i in start..<end {
                let v = samples[i]
                sumSq += v * v
            }
            if sumSq / Float(frameSize) >= thresholdSq {
                if firstActiveFrame == nil { firstActiveFrame = frame }
                lastActiveFrame = frame
            }
        }

        // Never drop audio if everything is quiet; let the caller's peak check / Whisper decide.
        guard let first = firstActiveFrame, let last = lastActiveFrame else { return samples }

        let padding = Int(Double(sampleRate) * paddingSeconds)
        let startSample = max(0, first * frameSize - padding)
        let endSample = min(samples.count, (last + 1) * frameSize + padding)
        guard startSample > 0 || endSample < samples.count else { return samples }
        return Array(samples[startSample..<endSample])
    }

    /// Returns the peak frame RMS across the buffer (used to skip pure-silence chunks).
    public static func peakRMS(_ samples: [Float], frameSize: Int = 320) -> Float {
        guard !samples.isEmpty else { return 0 }
        let size = max(1, min(frameSize, samples.count))
        var loudest: Float = 0
        var i = 0
        while i < samples.count {
            let end = min(i + size, samples.count)
            var sumSq: Float = 0
            for j in i..<end {
                let v = samples[j]
                sumSq += v * v
            }
            let rms = sqrt(sumSq / Float(end - i))
            if rms > loudest { loudest = rms }
            i = end
        }
        return loudest
    }
}

/// Decides when buffered recording audio can be split into a self-contained chunk
/// for background pre-transcription while the user is still speaking.
public struct AudioChunkPlanner: Sendable {
    public let sampleRate: Int
    public let minChunkSamples: Int
    public let maxChunkSamples: Int
    public let silenceSamples: Int
    public let silenceRMSThreshold: Float
    public let frameSamples: Int
    public let lookbackSamples: Int

    public init(
        sampleRate: Int = AudioSampleUtils.sampleRate,
        minChunkSeconds: Double = 10.0,
        maxChunkSeconds: Double = 25.0,
        silenceSeconds: Double = 0.45,
        silenceRMSThreshold: Float = 0.015,
        frameSeconds: Double = 0.02,
        lookbackSeconds: Double = 4.0
    ) {
        self.sampleRate = sampleRate
        self.minChunkSamples = max(1, Int(Double(sampleRate) * minChunkSeconds))
        self.maxChunkSamples = max(self.minChunkSamples, Int(Double(sampleRate) * maxChunkSeconds))
        self.silenceSamples = max(1, Int(Double(sampleRate) * silenceSeconds))
        self.silenceRMSThreshold = silenceRMSThreshold
        self.frameSamples = max(1, Int(Double(sampleRate) * frameSeconds))
        self.lookbackSamples = max(self.frameSamples, Int(Double(sampleRate) * lookbackSeconds))
    }

    /// Given the unflushed tail of 16 kHz Int16 samples, returns the number of samples
    /// to emit as a ready chunk, or `nil` if the recorder should keep buffering.
    public func splitLength(for samples: ArraySlice<Int16>) -> Int? {
        let count = samples.count
        guard count >= minChunkSamples else { return nil }

        let base = samples.startIndex
        let thresholdSq = silenceRMSThreshold * silenceRMSThreshold
        let scale: Float = 1.0 / 32768.0

        func frameMeanSquare(at offset: Int) -> Float {
            let start = base + offset
            let end = min(base + count, start + frameSamples)
            guard end > start else { return 0 }
            var sumSq: Float = 0
            for i in start..<end {
                let v = Float(samples[i]) * scale
                sumSq += v * v
            }
            return sumSq / Float(end - start)
        }

        // Prefer splitting on a natural pause at the end of the current buffer.
        let silenceFrames = max(1, silenceSamples / frameSamples)
        let trailingNeeded = silenceFrames * frameSamples
        if count >= trailingNeeded {
            var allQuiet = true
            let startOffset = count - trailingNeeded
            for f in 0..<silenceFrames {
                if frameMeanSquare(at: startOffset + f * frameSamples) >= thresholdSq {
                    allQuiet = false
                    break
                }
            }
            if allQuiet {
                // Split in the middle of the pause so neither chunk starts/ends mid-word.
                return count - trailingNeeded / 2
            }
        }

        // Continuous speech without a pause: split at the quietest frame in the lookback window
        // so we stay well below Whisper's 30-second single-window boundary.
        guard count >= maxChunkSamples else { return nil }
        let searchStart = max(0, count - lookbackSamples)
        let framesToScan = max(1, (count - searchStart) / frameSamples)
        var bestOffset = count - frameSamples
        var lowestEnergy = Float.greatestFiniteMagnitude
        for f in 0..<framesToScan {
            let offset = searchStart + f * frameSamples
            let energy = frameMeanSquare(at: offset)
            if energy < lowestEnergy {
                lowestEnergy = energy
                bestOffset = offset + frameSamples / 2
            }
        }
        return min(count, max(minChunkSamples / 2, bestOffset))
    }
}
