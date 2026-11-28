import AVFoundation
import CoreAudio
import AudioToolbox
import MurmurCore

struct Microphone: Identifiable { let id: UInt32; let name: String }
struct RecordedAudio: Sendable {
    /// Any chunks split right before stop that the controller hasn't drained yet.
    let undrainedChunks: [[Float]]
    /// Remaining 16 kHz mono float samples not already emitted as background chunks.
    let samples: [Float]
    /// Overall peak RMS across the entire recording.
    let peak: Float
    /// Total samples captured across the entire recording (including emitted chunks).
    let totalSamples: Int
    /// True if at least one earlier chunk was emitted for background transcription.
    let hadStreamedChunks: Bool
}
/// Records the microphone with an input-only Audio Queue at 16 kHz mono (what Whisper wants).
/// It never touches audio output, so selecting a microphone can't disturb your headphones,
/// and it avoids the audio-engine device switching that failed silently on some setups.
final class AudioRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var queue: AudioQueueRef?
    private var samples: [Int16] = []
    private var pendingChunks: [[Float]] = []
    private var totalSampleCount = 0
    private var samplesSinceChunkCheck = 0
    private var hadStreamedChunks = false
    private var peak: Float = 0
    private var running = false
    private let chunkPlanner = AudioChunkPlanner()
    private let callbackQueue = DispatchQueue(label: "com.steph.murmur.recorder")
    private let disposalQueue = DispatchQueue(label: "com.steph.murmur.recorder.dispose")
    private static let sampleRate: Double = Double(AudioSampleUtils.sampleRate)
    private static let chunkCheckIntervalSamples = 4_000 // ~250 ms
    var onLevel: (@Sendable (Float) -> Void)?
    var onChunkAvailable: (@Sendable () -> Void)?
    var onFailure: (@Sendable (String) -> Void)?
    private static var folder: URL { FileManager.default.temporaryDirectory.appendingPathComponent("com.steph.murmur.audio", isDirectory: true) }
    static func removeStaleAudio() { try? FileManager.default.removeItem(at: folder) }
    static func microphones() -> [Microphone] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else { return [] }
        var devices = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &devices) == noErr else { return [] }
        return devices.compactMap { id in
            var streams = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams, mScope: kAudioDevicePropertyScopeInput, mElement: kAudioObjectPropertyElementMain); var bytes: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(id, &streams, 0, nil, &bytes) == noErr, bytes > 0 else { return nil }
            var nameAddress = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            var name: Unmanaged<CFString>?; var nameSize = UInt32(MemoryLayout<CFString?>.size)
            guard AudioObjectGetPropertyData(id, &nameAddress, 0, nil, &nameSize, &name) == noErr else { return nil }
            return Microphone(id: id, name: name?.takeUnretainedValue() as String? ?? "Microphone")
        }
    }
    private static func transport(of device: AudioDeviceID) -> UInt32 {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyTransportType, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value: UInt32 = 0; var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr ? value : 0
    }
    private static func defaultInput() -> AudioDeviceID? {
        var property = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var device: AudioDeviceID = 0; var bytes = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &property, 0, nil, &bytes, &device) == noErr, device != 0 else { return nil }
        return device
    }
    /// "Automatic" uses the system microphone, except a Bluetooth headset mic: opening one switches
    /// the headphones into call mode (lower audio quality, hearing your own voice, a slow start).
    /// In that case the Mac's built-in microphone is used instead.
    static func automaticInput() -> AudioDeviceID? {
        guard let system = defaultInput() else { return nil }
        let bluetooth = [kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE].contains(transport(of: system))
        guard bluetooth else { return system }
        return microphones().map(\.id).first { transport(of: $0) == kAudioDeviceTransportTypeBuiltIn } ?? system
    }
    static var automaticDescription: String {
        guard let device = automaticInput(), let mic = microphones().first(where: { $0.id == device }) else { return "Uses your Mac’s microphone." }
        return "Using \(mic.name). Bluetooth headset mics are skipped so your headphones stay in high quality."
    }
    private static func uid(of device: AudioDeviceID) -> CFString? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceUID, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var uid: Unmanaged<CFString>?; var size = UInt32(MemoryLayout<CFString?>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &uid) == noErr else { return nil }
        return uid?.takeRetainedValue()
    }

    func start(device: UInt32) throws {
        cancel()
        let selected: AudioDeviceID
        if device == 0 {
            guard let automatic = Self.automaticInput() else { throw DictationError.message("No microphone is available.") }
            selected = automatic
        } else { selected = device }
        guard let uid = Self.uid(of: selected) else { throw DictationError.message("The selected microphone is unavailable. Choose Automatic in Settings.") }

        var format = AudioStreamBasicDescription(mSampleRate: Self.sampleRate, mFormatID: kAudioFormatLinearPCM, mFormatFlags: kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked, mBytesPerPacket: 2, mFramesPerPacket: 1, mBytesPerFrame: 2, mChannelsPerFrame: 1, mBitsPerChannel: 16, mReserved: 0)
        var newQueue: AudioQueueRef?
        let created = AudioQueueNewInputWithDispatchQueue(&newQueue, &format, 0, callbackQueue) { [weak self] queue, buffer, _, _, _ in
            guard let self else { return }
            let count = Int(buffer.pointee.mAudioDataByteSize) / 2
            var readyChunk: [Int16]?
            if count > 0 {
                let pointer = buffer.pointee.mAudioData.assumingMemoryBound(to: Int16.self)
                let chunk = UnsafeBufferPointer(start: pointer, count: count)
                var sum: Float = 0
                for sample in chunk { let value = Float(sample) / 32768; sum += value * value }
                let level = sqrt(sum / Float(count))
                self.lock.lock()
                let isRunning = self.running
                if isRunning {
                    self.samples.append(contentsOf: chunk)
                    self.totalSampleCount += count
                    self.samplesSinceChunkCheck += count
                    self.peak = max(self.peak, level)
                    if self.onChunkAvailable != nil,
                       self.samplesSinceChunkCheck >= Self.chunkCheckIntervalSamples,
                       self.samples.count >= self.chunkPlanner.minChunkSamples {
                        self.samplesSinceChunkCheck = 0
                        if let split = self.chunkPlanner.splitLength(for: self.samples[...]) {
                            readyChunk = Array(self.samples.prefix(split))
                            self.samples.removeFirst(split)
                            self.hadStreamedChunks = true
                        }
                    }
                }
                self.lock.unlock()
                if isRunning { self.onLevel?(min(1, level * 8)) }
                if let readyChunk {
                    let floats = AudioSampleUtils.pcm16ToFloat(readyChunk)
                    if AudioSampleUtils.peakRMS(floats) > 0.001 {
                        self.lock.lock()
                        self.pendingChunks.append(floats)
                        let stillRunning = self.running
                        self.lock.unlock()
                        if stillRunning { self.onChunkAvailable?() }
                    }
                }
            }
            self.lock.lock(); let isRunning = self.running; self.lock.unlock()
            if isRunning { AudioQueueEnqueueBuffer(queue, buffer, 0, nil) }
        }
        guard created == noErr, let newQueue else { throw DictationError.message("Couldn’t open the microphone (error \(created)).") }
        var deviceUID: CFString? = uid
        let setDevice = withUnsafeMutablePointer(to: &deviceUID) { pointer in
            AudioQueueSetProperty(newQueue, kAudioQueueProperty_CurrentDevice, pointer, UInt32(MemoryLayout<CFString?>.size))
        }
        guard setDevice == noErr else { AudioQueueDispose(newQueue, true); throw DictationError.message("The selected microphone is unavailable. Choose Automatic in Settings.") }
        // Four 40 ms buffers keep audio flowing smoothly with low stop latency.
        for _ in 0..<4 {
            var buffer: AudioQueueBufferRef?
            if AudioQueueAllocateBuffer(newQueue, 1_280, &buffer) == noErr, let buffer { AudioQueueEnqueueBuffer(newQueue, buffer, 0, nil) }
        }
        lock.lock()
        samples = []; samples.reserveCapacity(16_000 * 30)
        pendingChunks = []
        totalSampleCount = 0; samplesSinceChunkCheck = 0; hadStreamedChunks = false
        peak = 0; running = true; queue = newQueue
        lock.unlock()
        let started = AudioQueueStart(newQueue, nil)
        guard started == noErr else { cancel(); throw DictationError.message("Couldn’t start the microphone (error \(started)).") }
    }

    /// Atomically drains any completed chunks ready for background transcription.
    func takePendingChunks() -> [[Float]] {
        lock.lock(); defer { lock.unlock() }
        guard !pendingChunks.isEmpty else { return [] }
        let drained = pendingChunks
        pendingChunks = []
        return drained
    }

    func finish() throws -> RecordedAudio {
        let (undrained, recorded, loudest, total, streamed) = stop()
        guard total > 0 else { throw DictationError.message("No audio was recorded.") }
        guard loudest > 0.001 else { throw DictationError.message("No audible speech was captured. Check your selected microphone.") }
        let floats = AudioSampleUtils.trimSilence(AudioSampleUtils.pcm16ToFloat(recorded))
        return RecordedAudio(undrainedChunks: undrained, samples: floats, peak: loudest, totalSamples: total, hadStreamedChunks: streamed)
    }

    func cancel() { _ = stop() }

    /// Stops recording and hands back any undrained chunks plus remaining unflushed samples.
    private func stop() -> ([[Float]], [Int16], Float, Int, Bool) {
        lock.lock(); let current = queue; queue = nil; running = false; lock.unlock()
        if let current {
            AudioQueueStop(current, true)
            callbackQueue.sync {}
            disposalQueue.async { AudioQueueDispose(current, true) }
        }
        lock.lock(); defer { lock.unlock() }
        let result = (pendingChunks, samples, peak, totalSampleCount, hadStreamedChunks)
        pendingChunks = []; samples = []; peak = 0; totalSampleCount = 0; samplesSinceChunkCheck = 0; hadStreamedChunks = false
        return result
    }
}
