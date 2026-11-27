import Foundation

public struct VoiceNote: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let date: Date
    public internal(set) var text: String

    init(text: String) {
        id = UUID()
        date = Date()
        self.text = text
    }

    public var title: String {
        text.split(whereSeparator: \.isNewline)
            .lazy.map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? "Untitled note"
    }

    public func matches(_ query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty || text.localizedStandardContains(query)
    }
}

public struct NoteArchive {
    private let directory: URL
    private var file: URL { directory.appendingPathComponent("notes.json") }

    public init(directory: URL) { self.directory = directory }

    public func load() throws -> [VoiceNote] {
        do { return try JSONDecoder().decode([VoiceNote].self, from: Data(contentsOf: file)) }
        catch CocoaError.fileReadNoSuchFile { return [] }
    }

    public func add(_ text: String) throws -> [VoiceNote] {
        try change { $0.insert(VoiceNote(text: text), at: 0) }
    }

    public func update(_ id: UUID, text: String) throws -> [VoiceNote] {
        try change { notes in
            guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
            notes[index].text = text
        }
    }

    public func delete(_ id: UUID) throws -> [VoiceNote] {
        try change { $0.removeAll { $0.id == id } }
    }

    private func change(_ edit: (inout [VoiceNote]) -> Void) throws -> [VoiceNote] {
        var notes = try load()
        edit(&notes)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(notes).write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        return notes
    }
}
