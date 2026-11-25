import Foundation
public enum CleanupMode: String, CaseIterable, Codable, Sendable { case minimal, balanced, polished, verbatim }
public enum AppContext: String, Sendable { case general, message, email, document, code, prompt
    public static func detect(bundle: String) -> Self {
        let b = bundle.lowercased()
        if ["slack", "whatsapp", "messages", "telegram", "discord"].contains(where: b.contains) { return .message }
        if ["mail", "outlook", "mimestream"].contains(where: b.contains) { return .email }
        if ["vscode", "vscodium", "cursor", "xcode", "terminal", "iterm"].contains(where: b.contains) { return .code }
        if ["chatgpt", "claude"].contains(where: b.contains) { return .prompt }
        if ["notion", "word", "pages", "obsidian"].contains(where: b.contains) { return .document }
        return .general
    }
}
public struct DictionaryEntry: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID; public var spelling: String; public var soundsLike: String
    public init(id: UUID = UUID(), spelling: String, soundsLike: String = "") { self.id = id; self.spelling = spelling; self.soundsLike = soundsLike }
}
public struct HistoryEntry: Codable, Identifiable, Sendable {
    public var id: UUID; public var date: Date; public var text: String
    public init(text: String) { id = UUID(); date = Date(); self.text = text }
}
/// How casual dictated text should read, per kind of app.
public enum WritingStyle: String, CaseIterable, Codable, Sendable {
    case formal, casual, veryCasual
    public var label: String { switch self { case .formal: return "Formal"; case .casual: return "Casual"; case .veryCasual: return "Very casual" } }
}
/// The kinds of apps a writing style can be set for. Browsers, AI chat apps and code tools get no style.
public enum StyleCategory: String, CaseIterable, Codable, Sendable {
    case personal, work, email, other
    public static func detect(bundle: String) -> StyleCategory? {
        let b = bundle.lowercased()
        if ["mobilesms", "whatsapp", "telegram", "discord", "signal", "messenger", "imessage"].contains(where: b.contains) { return .personal }
        if ["slack", "teams", "zoom.us.chat", "linear"].contains(where: b.contains) { return .work }
        if ["com.apple.mail", "outlook", "mimestream", "superhuman", "spark", "airmail"].contains(where: b.contains) { return .email }
        if ["chrome", "safari", "firefox", "arc", "browser", "chatgpt", "claude", "vscode", "vscodium", "cursor", "xcode", "terminal", "iterm", "warp", "ghostty"].contains(where: b.contains) { return nil }
        return .other
    }
}
/// A voice shortcut: say the cue, get the full text.
public struct Snippet: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID; public var cue: String; public var text: String
    public init(id: UUID = UUID(), cue: String, text: String) { self.id = id; self.cue = cue; self.text = text }
}
public struct DictationSettings: Codable, Equatable, Sendable {
    public var mode: CleanupMode = .balanced
    public var language = ""
    public var contextAware = true
    public var audioFeedback = false
    public var allowClipboard = true
    public var keepHistory = false
    public var retentionDays = 7
    public var microphoneID: UInt32 = 0
    public var shortcut = "fn"
    public var fallbackKeyCode: UInt16 = 49
    public var fallbackModifiers: UInt64 = 0x60000 // Control + Shift
    public var dictionary: [DictionaryEntry] = []
    public var personalStyle: WritingStyle = .casual
    public var workStyle: WritingStyle = .formal
    public var emailStyle: WritingStyle = .formal
    public var otherStyle: WritingStyle = .formal
    public var snippets: [Snippet] = []
    public var muteWhileDictating = false
    public init() {}

    public func style(for category: StyleCategory?) -> WritingStyle {
        switch category { case .personal: return personalStyle; case .work: return workStyle; case .email: return emailStyle; case .other: return otherStyle; case nil: return .formal }
    }

    private enum CodingKeys: String, CodingKey {
        case mode, language, contextAware, audioFeedback, allowClipboard, keepHistory, retentionDays, microphoneID, shortcut, fallbackKeyCode, fallbackModifiers, dictionary
        case personalStyle, workStyle, emailStyle, otherStyle, snippets, muteWhileDictating
    }
    /// Every field is optional when reading, so settings saved by older versions keep working.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = DictationSettings()
        mode = (try? c.decodeIfPresent(CleanupMode.self, forKey: .mode)) ?? d.mode
        language = (try? c.decodeIfPresent(String.self, forKey: .language)) ?? d.language
        contextAware = (try? c.decodeIfPresent(Bool.self, forKey: .contextAware)) ?? d.contextAware
        audioFeedback = (try? c.decodeIfPresent(Bool.self, forKey: .audioFeedback)) ?? d.audioFeedback
        allowClipboard = (try? c.decodeIfPresent(Bool.self, forKey: .allowClipboard)) ?? d.allowClipboard
        keepHistory = (try? c.decodeIfPresent(Bool.self, forKey: .keepHistory)) ?? d.keepHistory
        retentionDays = (try? c.decodeIfPresent(Int.self, forKey: .retentionDays)) ?? d.retentionDays
        microphoneID = (try? c.decodeIfPresent(UInt32.self, forKey: .microphoneID)) ?? d.microphoneID
        shortcut = (try? c.decodeIfPresent(String.self, forKey: .shortcut)) ?? d.shortcut
        fallbackKeyCode = (try? c.decodeIfPresent(UInt16.self, forKey: .fallbackKeyCode)) ?? d.fallbackKeyCode
        fallbackModifiers = (try? c.decodeIfPresent(UInt64.self, forKey: .fallbackModifiers)) ?? d.fallbackModifiers
        dictionary = (try? c.decodeIfPresent([DictionaryEntry].self, forKey: .dictionary)) ?? d.dictionary
        personalStyle = (try? c.decodeIfPresent(WritingStyle.self, forKey: .personalStyle)) ?? d.personalStyle
        workStyle = (try? c.decodeIfPresent(WritingStyle.self, forKey: .workStyle)) ?? d.workStyle
        emailStyle = (try? c.decodeIfPresent(WritingStyle.self, forKey: .emailStyle)) ?? d.emailStyle
        otherStyle = (try? c.decodeIfPresent(WritingStyle.self, forKey: .otherStyle)) ?? d.otherStyle
        snippets = (try? c.decodeIfPresent([Snippet].self, forKey: .snippets)) ?? d.snippets
        muteWhileDictating = (try? c.decodeIfPresent(Bool.self, forKey: .muteWhileDictating)) ?? d.muteWhileDictating
    }
}
public struct CleanupRequest: Sendable {
    public let transcript: String; public let mode: CleanupMode; public let context: AppContext; public let dictionary: [DictionaryEntry]
    public let style: WritingStyle; public let snippets: [Snippet]
    public init(transcript: String, mode: CleanupMode, context: AppContext, dictionary: [DictionaryEntry], style: WritingStyle = .formal, snippets: [Snippet] = []) { self.transcript = transcript; self.mode = mode; self.context = context; self.dictionary = dictionary; self.style = style; self.snippets = snippets }
}

public protocol FileTranscriptionProvider: Sendable { func transcribe(file: URL, settings: DictationSettings) async throws -> String }
public protocol TranscriptionProvider: Sendable { func transcribe(audio: Data, settings: DictationSettings) async throws -> String }
public protocol CleanupProvider: Sendable { func clean(_ request: CleanupRequest, model: String) async throws -> String }

public enum ShortcutAction: Equatable { case start, stop, cancel, scheduleStop, cancelScheduledStop }
public struct ShortcutGesture {
    public private(set) var isDown = false
    public private(set) var handsFree = false
    private var downTime: Double = 0
    private var pendingTap: Double?
    private var suppressedUntilRelease = false
    private var handsFreeStart: Double = 0
    public init() {}
    public mutating func down(at time: Double) -> [ShortcutAction] {
        guard !isDown else { return [] }; isDown = true; downTime = time
        // A press within half a second of starting hands-free is an accidental triple tap: cancel.
        if handsFree { handsFree = false; suppressedUntilRelease = true; return [time - handsFreeStart < 0.5 ? .cancel : .stop] }
        if let tap = pendingTap, time - tap <= 0.32 { pendingTap = nil; handsFree = true; handsFreeStart = time; return [.cancelScheduledStop] }
        pendingTap = nil; return [.start]
    }
    public mutating func up(at time: Double) -> [ShortcutAction] {
        guard isDown else { return [] }; isDown = false
        if suppressedUntilRelease { suppressedUntilRelease = false; return [] }
        if handsFree { return [] }
        if time - downTime < 0.22 { pendingTap = time; return [.scheduleStop] }
        return [.stop]
    }
    /// A quick tap that wasn't followed by a second one is discarded: hold to talk.
    public mutating func expireTap() -> [ShortcutAction] { guard pendingTap != nil, !handsFree else { return [] }; pendingTap = nil; return [.cancel] }
    /// Fn+Space while holding Fn: keep recording after release (hands-free).
    public var canLockHandsFree: Bool { isDown && !handsFree && !suppressedUntilRelease }
    public mutating func lockHandsFree(at time: Double) -> [ShortcutAction] {
        guard canLockHandsFree else { return [] }
        handsFree = true; handsFreeStart = time; pendingTap = nil; return [.cancelScheduledStop]
    }
    public mutating func reset() { self = Self() }
}
public enum DictationPhase: String, Equatable { case idle, preparing, recording, processing, success, error }
public struct SessionGate {
    public private(set) var id: UUID?
    public private(set) var phase: DictationPhase = .idle
    public init() {}
    public mutating func begin() -> UUID? {
        guard [.idle, .success, .error].contains(phase) else { return nil }
        let token = UUID(); id = token; phase = .preparing; return token
    }
    @discardableResult public mutating func transition(_ next: DictationPhase, token: UUID) -> Bool {
        guard id == token else { return false }
        let allowed: [DictationPhase: [DictationPhase]] = [.preparing: [.recording, .error], .recording: [.processing, .error], .processing: [.success, .error]]
        guard allowed[phase]?.contains(next) == true else { return false }; phase = next; return true
    }
    public mutating func cancel() { id = nil; phase = .idle }
}
public enum InsertionPolicy {
    public static func mayInsert(originalPID: Int32, currentPID: Int32, sameField: Bool, originalSelection: NSRange?, currentSelection: NSRange?) -> Bool {
        guard originalPID == currentPID, sameField else { return false }
        if let originalSelection { return currentSelection == originalSelection }
        return true
    }
    public static func mayRestoreClipboard(ownedChange: Int, currentChange: Int) -> Bool { ownedChange == currentChange }
}
