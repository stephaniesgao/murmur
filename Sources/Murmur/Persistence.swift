import AppKit
import Combine
import MurmurCore

@MainActor final class Store: ObservableObject {
    @Published var settings: DictationSettings { didSet { saveSettings(); if !settings.keepHistory { clearHistory() } else { pruneHistory() } } }
    @Published private(set) var history: [HistoryEntry] = []
    @Published var persistenceError = ""
    private let directory: URL
    init() {
        directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Murmur", isDirectory: true)
        let config = directory.appendingPathComponent("settings.json")
        var loaded = (try? JSONDecoder().decode(DictationSettings.self, from: Data(contentsOf: config))) ?? DictationSettings()
        if loaded.mode == .polished { loaded.mode = .balanced }
        settings = loaded
        if settings.keepHistory { history = (try? JSONDecoder().decode([HistoryEntry].self, from: Data(contentsOf: directory.appendingPathComponent("history.json")))) ?? [] }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        // Remove leftovers from interrupted prior recordings before any new capture starts.
        AudioRecorder.removeStaleAudio()
        if settings.keepHistory { pruneHistory() } else { clearHistory() }
    }
    private func write<T: Encodable>(_ value: T, name: String) {
        do { let url = directory.appendingPathComponent(name); try JSONEncoder().encode(value).write(to: url, options: .atomic); try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path) }
        catch { persistenceError = "Could not save local settings or history: \(error.localizedDescription)" }
    }
    private func saveSettings() { write(settings, name: "settings.json") }
    func addHistory(_ text: String) { guard settings.keepHistory else { return }; history.insert(HistoryEntry(text: text), at: 0); pruneHistory(); write(history, name: "history.json") }
    func pruneHistory() {
        let cutoff = Date().addingTimeInterval(-Double(max(1, settings.retentionDays)) * 86400)
        let pruned = Array(history.filter { $0.date >= cutoff }.prefix(200))
        let changed = pruned.count != history.count
        history = pruned
        if settings.keepHistory && changed { write(history, name: "history.json") }
    }
    func clearHistory() { history = []; try? FileManager.default.removeItem(at: directory.appendingPathComponent("history.json")) }
}
