import AppKit
import AVFoundation
import ApplicationServices
import Combine
import MurmurCore
import os

private let dictationLog = Logger(subsystem: "com.steph.murmur", category: "dictation")

/// Word and time totals for the Usage card. Counts only; no text is stored.
struct UsageStats: Equatable {
    var words = 0
    var seconds: Double = 0
    var sessions = 0
    var wordsPerMinute: Int { seconds >= 5 ? Int((Double(words) / (seconds / 60)).rounded()) : 0 }
    /// Minutes saved compared with typing at 40 words per minute.
    var minutesSaved: Int { max(0, Int((Double(words) / 40 - seconds / 60).rounded())) }

    private static let defaults = UserDefaults.standard
    static func load() -> UsageStats {
        UsageStats(words: defaults.integer(forKey: "stats.words"), seconds: defaults.double(forKey: "stats.seconds"), sessions: defaults.integer(forKey: "stats.sessions"))
    }
    func save() {
        Self.defaults.set(words, forKey: "stats.words"); Self.defaults.set(seconds, forKey: "stats.seconds"); Self.defaults.set(sessions, forKey: "stats.sessions")
    }
}

@MainActor final class DictationController: ObservableObject {
    let store: Store
    let keyboard = KeyboardManager()
    private let audio = AudioRecorder()
    private let inserter = TextInsertion()
    private let muter = AudioMuter()
    let models: SpeechModelManager
    private var gate = SessionGate()
    private var work: Task<Void, Never>?
    private var limit: Task<Void, Never>?
    private var dismiss: Task<Void, Never>?
    private var stopWhenReady = false
    private var settingsSubscription: AnyCancellable?
    private var workspaceTokens: [NSObjectProtocol] = []
    private var recordingStarted: Date?
    /// The last inserted text, kept in memory only, for “paste last transcript”.
    private var lastTranscript = ""
    @Published var phase: DictationPhase = .idle
    @Published var level: Float = 0
    @Published var message = ""
    @Published var result = ""
    @Published var keyboardAvailable = false
    @Published var handsFree = false
    @Published private(set) var stats = UsageStats.load()
    var onStatusChange: (() -> Void)?
    private var target: InsertionTarget?
    private var sessionSettings = DictationSettings()
    /// Recordings stop on their own after 10 minutes.
    private static let maximumRecording: UInt64 = 600

    init(store: Store, models: SpeechModelManager) {
        self.store = store
        self.models = models
        keyboard.onAction = { [weak self] action in
            guard let self else { return }
            switch action { case .start: self.start(); case .stop: self.finish(); case .cancel: self.cancel(); case .cancelScheduledStop: self.handsFree = true; default: break }
        }
        keyboard.onPasteLast = { [weak self] in self?.pasteLast() }
        keyboard.onAvailability = { [weak self] in self?.keyboardAvailable = $0 }
        audio.onLevel = { [weak self] value in Task { @MainActor in self?.level = value } }
        audio.onFailure = { [weak self] text in Task { @MainActor in self?.fail(text) } }
        settingsSubscription = store.$settings.removeDuplicates().sink { [weak self] settings in
            guard let self else { return }; self.keyboard.settings = settings
            if self.phase == .recording || self.phase == .preparing { dictationLog.notice("Cancel: settings changed"); self.cancel() }
        }
        keyboard.settings = store.settings; keyboard.start()
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            workspaceTokens.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.cancel() } })
        }
        workspaceTokens.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.keyboard.start() } })
    }
    var busy: Bool { [.preparing, .recording, .processing].contains(phase) }
    var canPasteLast: Bool { !lastTranscript.isEmpty }
    func toggle() { if phase == .recording { finish() } else if !busy { handsFree = true; start() } }
    private func publish() { phase = gate.phase; onStatusChange?() }

    func start() {
        guard let token = gate.begin() else { dictationLog.notice("Start ignored: still \(self.phase.rawValue, privacy: .public)"); return }
        dismiss?.cancel(); stopWhenReady = false; result = ""; message = ""; level = 0
        do { target = try TextInsertion.capture() } catch { fail(error.localizedDescription); return }
        sessionSettings = store.settings
        publish()
        work = Task { [weak self] in
            guard let self else { return }
            do {
                switch self.models.state {
                case .ready, .loading: break
                case .downloading: throw DictationError.message("Murmur’s speech model is still downloading. Try again when Setup shows it’s ready.")
                case .notDownloaded, .failed: throw DictationError.message("Murmur needs its speech model first. Open Settings → Setup and download it.")
                }
                let granted: Bool
                let status = AVCaptureDevice.authorizationStatus(for: .audio)
                dictationLog.notice("Microphone permission: \(status.rawValue, privacy: .public) (3 = allowed, 0 = not asked yet)")
                switch status {
                case .authorized: granted = true
                case .notDetermined:
                    // A menu-bar app's permission prompt can fail to appear; don't wait forever.
                    granted = try await withThrowingTaskGroup(of: Bool?.self) { group in
                        group.addTask { await AVCaptureDevice.requestAccess(for: .audio) }
                        group.addTask { try await Task.sleep(nanoseconds: 20_000_000_000); return nil }
                        let first = try await group.next() ?? nil; group.cancelAll()
                        guard let answer = first else { throw DictationError.message("macOS didn’t show the microphone prompt. Open Settings → Setup and click Turn on next to Microphone.") }
                        return answer
                    }
                default: granted = false
                }
                guard !Task.isCancelled, self.gate.id == token else { dictationLog.notice("Start abandoned after permission check (cancelled: \(Task.isCancelled, privacy: .public))"); return }
                guard granted else { throw DictationError.message("Microphone access is off. Enable it in System Settings → Privacy & Security → Microphone.") }
                dictationLog.notice("Checking focus")
                guard let target = self.target, TextInsertion.validate(target) else { throw DictationError.message("Focus changed during microphone setup. Try the shortcut again in your text field.") }
                dictationLog.notice("Starting microphone")
                try self.audio.start(device: self.sessionSettings.microphoneID)
                dictationLog.notice("Microphone started")
                guard self.gate.transition(.recording, token: token) else { self.audio.cancel(); return }
                dictationLog.notice("Recording")
                if self.sessionSettings.audioFeedback { NSSound(named: "Tink")?.play() }
                if self.sessionSettings.muteWhileDictating { self.muter.mute() }
                self.recordingStarted = Date()
                self.publish()
                self.limit = Task { [weak self] in try? await Task.sleep(nanoseconds: Self.maximumRecording * 1_000_000_000); guard !Task.isCancelled else { return }; self?.finish() }
                if self.stopWhenReady { self.finish() }
            } catch {
                guard self.gate.id == token, !Task.isCancelled else { dictationLog.notice("Start error after cancel: \(error.localizedDescription, privacy: .public)"); return }
                self.fail(error.localizedDescription)
            }
        }
    }

    func finish() {
        if phase == .preparing { dictationLog.notice("Stop while preparing; will stop once recording starts"); stopWhenReady = true; return }
        guard phase == .recording, let token = gate.id, let target else { dictationLog.notice("Stop ignored in phase \(self.phase.rawValue, privacy: .public)"); return }
        handsFree = false; limit?.cancel(); muter.restore()
        let seconds = recordingStarted.map { Date().timeIntervalSince($0) } ?? 0
        do {
            let url = try audio.finish()
            let bytes = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
            dictationLog.notice("Recording stopped after \(String(format: "%.1f", seconds), privacy: .public)s (\(bytes / 1024, privacy: .public) KB)")
            guard gate.transition(.processing, token: token) else { dictationLog.notice("Stop ignored: session changed"); return }; publish()
            let options = sessionSettings
            work = Task { [weak self] in
                guard let self else { return }
                defer { try? FileManager.default.removeItem(at: url) }
                do {
                    let began = Date()
                    let transcript = try await self.models.transcribe(file: url, settings: options)
                    dictationLog.notice("Transcribed in \(String(format: "%.2f", Date().timeIntervalSince(began)), privacy: .public)s (\(transcript.count, privacy: .public) characters)")
                    guard self.gate.id == token, !Task.isCancelled else { dictationLog.notice("Result dropped: session changed"); return }
                    self.result = transcript // Recovery text stays in memory even when history is off.
                    // “…, press enter” sends Return after inserting, handy in chats.
                    let (raw, pressEnter) = options.mode == .verbatim ? (transcript, false) : LocalCleanup.extractPressEnter(transcript)
                    let context = options.contextAware ? AppContext.detect(bundle: target.bundle) : .general
                    let style = options.style(for: StyleCategory.detect(bundle: target.bundle))
                    let request = CleanupRequest(transcript: raw, mode: options.mode, context: context, dictionary: options.dictionary, style: style, snippets: options.snippets)
                    let cleaned = try await LocalCleanup().clean(request, model: "local-rules")
                    // Dictating right after existing text gets a separating space.
                    let edited = cleaned.isEmpty ? cleaned : LocalCleanup.joining(after: TextInsertion.precedingCharacter(target), cleaned)
                    guard self.gate.id == token, !Task.isCancelled else { return }
                    self.result = edited
                    if !edited.isEmpty {
                        try await self.inserter.insert(edited, target: target, allowClipboard: options.allowClipboard, stillCurrent: { self.gate.id == token })
                    }
                    guard self.gate.id == token else { return }
                    if pressEnter { TextInsertion.pressReturn() }
                    self.lastTranscript = edited
                    self.record(words: edited, seconds: seconds)
                    self.store.addHistory(edited); _ = self.gate.transition(.success, token: token); self.publish()
                    self.dismiss = Task { [weak self] in try? await Task.sleep(nanoseconds: 250_000_000); guard !Task.isCancelled, self?.gate.id == token else { return }; self?.gate.cancel(); self?.publish() }
                } catch { guard self.gate.id == token, !Task.isCancelled else { return }; self.fail(error.localizedDescription) }
            }
        } catch { fail(error.localizedDescription) }
    }

    func cancel() {
        work?.cancel(); limit?.cancel(); dismiss?.cancel(); audio.cancel(); muter.restore(); gate.cancel(); handsFree = false; stopWhenReady = false; level = 0; message = ""; result = ""; keyboard.reset(); publish()
    }

    func fail(_ text: String) {
        // Only Murmur's own status messages are logged, never transcribed text.
        dictationLog.notice("Dictation stopped: \(text, privacy: .public)")
        work?.cancel(); limit?.cancel(); audio.cancel(); muter.restore(); handsFree = false; keyboard.reset()
        if let token = gate.id { _ = gate.transition(.error, token: token) }
        message = text; publish()
        // The pill shows the reason briefly, then gets out of the way; the menu keeps the message.
        dismiss?.cancel()
        dismiss = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            guard !Task.isCancelled, let self, self.phase == .error else { return }
            self.gate.cancel(); self.publish()
        }
    }

    /// ⌃⌘V: pastes the last dictation again wherever the cursor is now.
    func pasteLast() {
        if busy { cancel() }
        let text = lastTranscript.isEmpty ? result : lastTranscript
        guard !text.isEmpty else { NSSound.beep(); return }
        Task { do { try await TextInsertion.paste(text) } catch { self.fail(error.localizedDescription) } }
    }

    private func record(words text: String, seconds: Double) {
        let count = text.split { $0.isWhitespace || $0.isNewline }.count
        guard count > 0 else { return }
        stats.words += count; stats.seconds += seconds; stats.sessions += 1; stats.save()
    }

    func copyResult() { guard !result.isEmpty else { return }; NSPasteboard.general.clearContents(); NSPasteboard.general.setString(result, forType: .string) }
}
