import AppKit
import SwiftUI
import MurmurCore

struct NoteCaptureButton: View {
    @ObservedObject var controller: DictationController
    var beforeToggle: () -> Void = {}

    private var recordingNote: Bool { controller.isNoteSession && controller.phase == .recording }

    var body: some View {
        Button {
            beforeToggle()
            controller.toggleNote()
        } label: {
            Label(recordingNote ? "Stop note" : "Dictate note", systemImage: recordingNote ? "stop.fill" : "mic")
        }
        .buttonStyle(PillButtonStyle(prominent: false, compact: true))
        .disabled(controller.busy && !recordingNote)
    }
}

struct NotesView: View {
    @ObservedObject var controller: DictationController
    @ObservedObject var store: Store
    @State private var query = ""
    @State private var selectedID: UUID?
    @State private var draft = ""
    @State private var pendingDelete: VoiceNote?
    @State private var confirmsDelete = false

    private var selected: VoiceNote? { store.notes.first { $0.id == selectedID } }
    private var hasChanges: Bool { selected.map { $0.text != draft } ?? false }
    private var displayedNotes: [VoiceNote] { store.notes.filter { $0.matches(query) } }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Notes").font(Theme.wordmark(22)).foregroundStyle(Theme.ink)
                    Text("Saved on this Mac").font(.system(size: 12)).foregroundStyle(Theme.muted)
                }
                Spacer()
                if controller.isNoteSession && controller.busy {
                    switch controller.phase {
                    case .preparing: Text("Preparing…").foregroundStyle(Theme.muted)
                    case .processing: Text("Transcribing…").foregroundStyle(Theme.muted)
                    default: EmptyView()
                    }
                    Button("Cancel", action: controller.cancel).buttonStyle(PillButtonStyle(prominent: false, compact: true))
                }
                NoteCaptureButton(controller: controller)
            }
            .padding(16)
            if !store.notesError.isEmpty {
                Text(store.notesError).foregroundStyle(Theme.warm).padding([.horizontal, .bottom], 16)
            } else if controller.isNoteSession && !controller.message.isEmpty {
                Text(controller.message).foregroundStyle(Theme.warm).padding([.horizontal, .bottom], 16)
            }
            Divider()
            HStack(spacing: 0) {
                sidebar
                    .frame(width: 230)
                    .background(Theme.sidebar)
                Divider()
                if let note = selected { editor(note) }
                else {
                    Text(store.notes.isEmpty ? "Dictate a note to get started." : "Select a note to read or edit it.")
                        .foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .background(Theme.background)
        .onAppear { if selectedID == nil { select(store.notes.first) } }
        .onChange(of: store.notes.first?.id) { _ in
            if !hasChanges && !confirmsDelete && query.isEmpty { select(store.notes.first) }
        }
        .alert("Delete this note?", isPresented: $confirmsDelete, presenting: pendingDelete) { note in
            Button("Delete", role: .destructive) {
                do {
                    try store.deleteNote(note.id)
                    select(displayedNotes.first)
                } catch {}
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("This will permanently remove the note from this Mac.")
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Search notes", text: $query)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Search notes")
            if displayedNotes.isEmpty {
                Text(store.notes.isEmpty ? "No notes yet" : "No matching notes")
                    .font(.system(size: 12)).foregroundStyle(Theme.muted)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(displayedNotes) { note in
                            Button {
                                if note.id != selectedID { select(note) }
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(note.title).font(Theme.rounded(13, .semibold)).foregroundStyle(Theme.ink).lineLimit(1)
                                    Text(note.date.formatted(date: .abbreviated, time: .shortened))
                                        .font(.system(size: 11)).foregroundStyle(Theme.muted)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                                .background(RoundedRectangle(cornerRadius: 8).fill(note.id == selectedID ? Theme.chip : Color.clear))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .disabled(hasChanges && note.id != selectedID)
                            .accessibilityAddTraits(note.id == selectedID ? .isSelected : [])
                        }
                    }
                }
            }
        }
        .padding(12)
        .frame(maxHeight: .infinity, alignment: .topLeading)
    }

    private func editor(_ note: VoiceNote) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(note.date.formatted(date: .long, time: .shortened))
                .font(.system(size: 12)).foregroundStyle(Theme.muted)
            TextEditor(text: $draft)
                .font(.system(size: 14)).foregroundStyle(Theme.ink)
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 10).fill(Theme.card))
                .accessibilityLabel("Note text")
            HStack {
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(draft, forType: .string)
                }
                Button("Delete", role: .destructive) {
                    pendingDelete = note
                    confirmsDelete = true
                }
                Spacer()
                if hasChanges {
                    Button("Discard changes") { draft = note.text }
                    Button("Save changes") {
                        do { try store.updateNote(note.id, text: draft) } catch {}
                    }
                }
            }
            .buttonStyle(PillButtonStyle(prominent: false, compact: true))
        }
        .padding(16)
    }

    private func select(_ note: VoiceNote?) {
        selectedID = note?.id
        draft = note?.text ?? ""
    }
}
