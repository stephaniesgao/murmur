import Foundation
import os
import WhisperKit
import AVFoundation
import MurmurCore

private let speechLog = Logger(subsystem: "com.steph.murmur", category: "speech")

/// The Whisper model sizes Murmur offers. Raw values are WhisperKit model folder names.
enum WhisperModelChoice: String, CaseIterable, Identifiable, Sendable {
    case quick = "openai_whisper-base"
    case balanced = "openai_whisper-small_216MB"
    case best = "openai_whisper-large-v3-v20240930_turbo_632MB"

    var id: String { rawValue }
    var label: String {
        switch self { case .quick: return "Quick"; case .balanced: return "Balanced"; case .best: return "Best" }
    }
    var size: String {
        switch self { case .quick: return "~150 MB"; case .balanced: return "~220 MB"; case .best: return "~630 MB" }
    }
    var detail: String {
        switch self {
        case .quick: return "Smallest and fastest. Fine for short, clear English."
        case .balanced: return "A good mix of speed and accuracy for everyday dictation."
        case .best: return "Most accurate, especially for accents, names and mixed languages. Slower on long clips."
        }
    }

    static let defaultsKey = "whisperModel"
    static var saved: WhisperModelChoice {
        UserDefaults.standard.string(forKey: defaultsKey).flatMap(WhisperModelChoice.init(rawValue:)) ?? .balanced
    }
}

/// Downloads, loads and runs the local Whisper model. Audio never leaves the Mac; the only
/// network use is the one-time model and tokenizer download from Hugging Face.
@MainActor final class SpeechModelManager: ObservableObject {
    enum State: Equatable {
        case notDownloaded
        case downloading(Double)
        case loading
        case ready
        case failed(String)
    }

    @Published private(set) var state: State = .notDownloaded
    @Published var choice: WhisperModelChoice {
        didSet {
            guard choice != oldValue else { return }
            UserDefaults.standard.set(choice.rawValue, forKey: WhisperModelChoice.defaultsKey)
            kit = nil
            work?.cancel()
            state = .notDownloaded
            // Picking a model you don't have yet starts its one-time download right away.
            if Self.isDownloaded(choice) { prepare() } else { download() }
        }
    }

    private var kit: WhisperKit?
    private var work: Task<Void, Never>?

    /// Models and tokenizers live in ~/Library/Application Support/Murmur/Models.
    static let directory: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Murmur", isDirectory: true)
        .appendingPathComponent("Models", isDirectory: true)

    init() { choice = WhisperModelChoice.saved }

    var isReady: Bool { state == .ready }

    static func modelFolder(for choice: WhisperModelChoice) -> URL {
        directory.appendingPathComponent("models/argmaxinc/whisperkit-coreml/\(choice.rawValue)", isDirectory: true)
    }

    static func isDownloaded(_ choice: WhisperModelChoice) -> Bool {
        let folder = modelFolder(for: choice)
        return ["AudioEncoder.mlmodelc", "TextDecoder.mlmodelc", "MelSpectrogram.mlmodelc"].allSatisfy {
            FileManager.default.fileExists(atPath: folder.appendingPathComponent($0).path)
        }
    }

    /// Loads the chosen model if it's already on disk; otherwise waits for the user to download it.
    func prepare() {
        if Self.isDownloaded(choice) { load(from: Self.modelFolder(for: choice)) } else { state = .notDownloaded }
    }

    func download() {
        guard !isBusy else { return }
        let choice = choice
        state = .downloading(0)
        work = Task { [weak self] in
            do {
                try FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
                let folder = try await WhisperKit.download(variant: choice.rawValue, downloadBase: Self.directory) { progress in
                    let fraction = progress.fractionCompleted
                    Task { @MainActor [weak self] in
                        guard let self, case .downloading = self.state else { return }
                        self.state = .downloading(fraction)
                    }
                }
                guard !Task.isCancelled, let self, self.choice == choice else { return }
                speechLog.notice("Downloaded \(choice.rawValue, privacy: .public)")
                self.load(from: folder)
            } catch {
                guard !Task.isCancelled, let self, self.choice == choice else { return }
                speechLog.error("Model download failed: \(error.localizedDescription, privacy: .public)")
                self.state = .failed("Couldn’t download the speech model. Check your internet connection and try again.")
            }
        }
    }

    private var isBusy: Bool {
        switch state { case .downloading, .loading: return true; default: return false }
    }

    private func load(from folder: URL) {
        let choice = choice
        state = .loading
        work = Task { [weak self] in
            do {
                // The tokenizer is fetched once alongside the model and cached in the same folder.
                let config = WhisperKitConfig(model: choice.rawValue, downloadBase: Self.directory, modelFolder: folder.path, tokenizerFolder: Self.directory, verbose: false, prewarm: true, load: true, download: false)
                let loaded = try await WhisperKit(config)
                guard !Task.isCancelled, let self, self.choice == choice else { return }
                self.kit = loaded
                self.state = .ready
                speechLog.notice("Loaded \(choice.rawValue, privacy: .public)")
            } catch {
                guard !Task.isCancelled, let self, self.choice == choice else { return }
                speechLog.error("Model load failed: \(error.localizedDescription, privacy: .public)")
                self.state = .failed("The speech model didn’t load. Try downloading it again.")
            }
        }
    }

    /// Removes the chosen model's files so it can be downloaded fresh.
    func redownload() {
        work?.cancel(); kit = nil
        try? FileManager.default.removeItem(at: Self.modelFolder(for: choice))
        download()
    }

    /// Waits briefly for a model that is still loading, so dictating right after launch works.
    private func readyKit() async throws -> WhisperKit {
        for _ in 0..<150 {
            if let kit, state == .ready { return kit }
            guard case .loading = state else { break }
            try await Task.sleep(nanoseconds: 200_000_000)
        }
        if let kit, state == .ready { return kit }
        throw DictationError.message("Murmur’s speech model isn’t ready yet. Open Settings → Setup to download it.")
    }

    func transcribe(file: URL, settings: DictationSettings) async throws -> String {
        let kit = try await readyKit()
        try Task.checkCancellation()
        let language = settings.language.isEmpty ? nil : settings.language
        var options = DecodingOptions(
            language: language,
            temperature: 0,
            usePrefillPrompt: true,
            detectLanguage: language == nil,
            skipSpecialTokens: true,
            withoutTimestamps: true,
            noSpeechThreshold: nil, // short phrases like “sounds good” were being dropped as silence
            chunkingStrategy: .vad
        )
        // Dictionary spellings become a prompt, which nudges Whisper toward those spellings.
        let words = settings.dictionary.prefix(100).map(\.spelling).filter { !$0.isEmpty }
        if !words.isEmpty, let tokenizer = kit.tokenizer {
            let tokens = tokenizer.encode(text: " " + words.joined(separator: ", ")).filter { $0 < tokenizer.specialTokens.specialTokenBegin }
            options.promptTokens = Array(tokens.suffix(200))
        }
        if let audio = try? AVAudioFile(forReading: file) {
            let format = audio.fileFormat
            speechLog.notice("Audio: \(Int(format.sampleRate), privacy: .public) Hz, \(format.channelCount, privacy: .public) ch, \(String(format: "%.1f", Double(audio.length) / format.sampleRate), privacy: .public)s")
        }
        // Never spin forever: give up after 45 seconds with a clear message.
        let results = try await withThrowingTaskGroup(of: [TranscriptionResult]?.self) { group in
            group.addTask { try await kit.transcribe(audioPath: file.path, decodeOptions: options) }
            group.addTask { try await Task.sleep(nanoseconds: 45_000_000_000); return nil }
            guard let first = try await group.next(), let results = first else {
                group.cancelAll()
                speechLog.error("Transcription timed out")
                throw DictationError.message("Transcription took too long and was stopped. Try again, or pick the Quick model in Setup.")
            }
            group.cancelAll()
            return results
        }
        try Task.checkCancellation()
        var text = Self.clean(results.map(\.text).joined(separator: " "))
        // Whisper sometimes "hears" a stray word in silence; treat those as no speech.
        if ["you", "you.", "."].contains(text.lowercased()) { text = "" }
        guard !text.isEmpty else { throw DictationError.message("No speech was recognized.") }
        return text
    }

    /// Removes Whisper's non-speech markers such as [BLANK_AUDIO] or (music).
    nonisolated static func clean(_ raw: String) -> String {
        var text = raw.replacingOccurrences(of: #"\[[^\]]*\]|\((?:music|applause|laughter|silence|inaudible)[^)]*\)|<\|[^|]*\|>"#, with: " ", options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
