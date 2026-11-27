import SwiftUI
import AppKit
import AVFoundation
import ApplicationServices
import ServiceManagement
import MurmurCore

// MARK: - Look and feel

extension Color {
    /// A color that switches between a light and a dark hex value with the system appearance.
    static func dynamic(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        })
    }
}

enum Theme {
    static let background = Color.dynamic(0xFFF9F2, 0x1B1726)
    static let sidebar = Color.dynamic(0xF4EDFF, 0x221C31)
    static let card = Color.dynamic(0xFFFFFF, 0x2A2340)
    static let chip = Color.dynamic(0xF1EAFB, 0x342C4D)
    static let line = Color.dynamic(0xEEE6F7, 0x3A3254)
    static let ink = Color.dynamic(0x2D2545, 0xF4EFFF)
    static let muted = Color.dynamic(0x7C7396, 0xA9A1C4)
    static let accent = Color.dynamic(0x9B5CFF, 0xB38CFF)
    static let lilac = Color.dynamic(0xC4B2FF, 0xB39DFF)
    static let peach = Color.dynamic(0xFFC2A1, 0xFFB38A)
    static let mint = Color.dynamic(0x3FBF97, 0x7FE0C2)
    static let mintSoft = Color.dynamic(0xE3F7EF, 0x23413A)
    static let warm = Color.dynamic(0xE9813F, 0xFFB077)
    static let warmSoft = Color.dynamic(0xFFEFE3, 0x463126)
    static let capsule = Color.dynamic(0x2D2545, 0x2D2545)
    static let blobGradient = LinearGradient(colors: [peach, lilac], startPoint: .topLeading, endPoint: .bottomTrailing)

    /// Interface text uses the regular system font; only the wordmark is rounded.
    static func rounded(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font { .system(size: size, weight: weight) }
    static func wordmark(_ size: CGFloat) -> Font { .system(size: size, weight: .bold, design: .rounded) }
}

// MARK: - Mascot

/// A soft circle whose edge wobbles gently over time.
struct BlobShape: Shape {
    var time: Double
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2 * 0.92
        var path = Path()
        let steps = 72
        for step in 0...steps {
            let angle = Double(step) / Double(steps) * 2 * .pi
            let wobble = 1 + 0.035 * sin(3 * angle + time * 1.6) + 0.025 * sin(5 * angle - time * 1.1)
            let point = CGPoint(x: center.x + CGFloat(cos(angle) * wobble) * radius, y: center.y + CGFloat(sin(angle) * wobble) * radius)
            if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }
}

struct SmileShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY), control: CGPoint(x: rect.midX, y: rect.maxY * 1.6))
        return path
    }
}

/// Murmur's little blob. It bobs and blinks; while listening its mouth moves.
struct Mascot: View {
    var size: CGFloat = 44
    var listening = false
    var level: Float = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { timeline in
            face(time: reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private func face(time: Double) -> some View {
        let blinking = time.truncatingRemainder(dividingBy: 4.3) < 0.13
        let bob = CGFloat(sin(time * 2.2)) * size * 0.03
        let mouthOpen = CGFloat(0.05 + 0.08 * Double(min(max(level, 0.15), 1)) * abs(sin(time * 9)))
        return ZStack {
            BlobShape(time: time).fill(Theme.blobGradient)
            BlobShape(time: time).stroke(Color.white.opacity(0.35), lineWidth: max(1, size * 0.02))
            HStack(spacing: size * 0.2) {
                eye(blinking: blinking)
                eye(blinking: blinking)
            }.offset(y: -size * 0.05)
            HStack(spacing: size * 0.4) {
                cheek
                cheek
            }.offset(y: size * 0.1)
            Group {
                if listening {
                    Ellipse().fill(Theme.capsule).frame(width: size * 0.13, height: size * mouthOpen)
                } else {
                    SmileShape().stroke(Theme.capsule, style: StrokeStyle(lineWidth: max(1.2, size * 0.035), lineCap: .round)).frame(width: size * 0.16, height: size * 0.05)
                }
            }.offset(y: size * 0.15)
        }
        .offset(y: bob)
    }

    private func eye(blinking: Bool) -> some View {
        Capsule().fill(Theme.capsule).frame(width: size * 0.085, height: blinking ? size * 0.02 : size * 0.13)
    }
    private var cheek: some View {
        Ellipse().fill(Color(red: 1, green: 0.45, blue: 0.55).opacity(0.3)).frame(width: size * 0.15, height: size * 0.09)
    }
}

// MARK: - Building blocks

struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(.horizontal, 16).padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Theme.line, lineWidth: 1))
    }
}

struct CardDivider: View {
    var body: some View { Rectangle().fill(Theme.line).frame(height: 1) }
}

struct SettingRow<Trailing: View>: View {
    var icon: String? = nil
    let title: String
    var detail: String? = nil
    @ViewBuilder var trailing: Trailing
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.ink)
                if let detail { Text(detail).font(.system(size: 12)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true) }
            }
            Spacer(minLength: 12)
            trailing
        }.padding(.vertical, 9)
    }
}

struct PillButtonStyle: ButtonStyle {
    var prominent = true
    var compact = false
    func makeBody(configuration: Configuration) -> some View {
        PillBody(configuration: configuration, prominent: prominent, compact: compact)
    }
    private struct PillBody: View {
        let configuration: ButtonStyleConfiguration
        let prominent: Bool
        let compact: Bool
        @Environment(\.isEnabled) private var isEnabled
        var body: some View {
            configuration.label
                .font(.system(size: compact ? 12 : 13, weight: .medium))
                .padding(.horizontal, compact ? 10 : 14).padding(.vertical, compact ? 4 : 7)
                .foregroundStyle(prominent ? Color.white : Theme.ink)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(prominent ? AnyShapeStyle(LinearGradient(colors: [Theme.accent, Theme.accent.opacity(0.82)], startPoint: .top, endPoint: .bottom)) : AnyShapeStyle(Theme.chip)))
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(prominent ? Color.clear : Theme.line, lineWidth: 1))
                .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.45)
                .contentShape(RoundedRectangle(cornerRadius: 7))
        }
    }
}

struct StatusBadge: View {
    let ok: Bool
    let text: String
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill").font(.system(size: 11))
            Text(text).font(.system(size: 12, weight: .medium))
        }
        .foregroundStyle(ok ? Theme.mint : Theme.warm)
    }
}

/// A row of selectable capsules, used instead of a segmented control.
struct ChipPicker<Value: Hashable>: View {
    let options: [(value: Value, label: String)]
    @Binding var selection: Value
    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.value) { option in
                let selected = option.value == selection
                Button { withAnimation(.easeOut(duration: 0.12)) { selection = option.value } } label: {
                    Text(option.label)
                        .font(.system(size: 12, weight: selected ? .semibold : .regular))
                        .lineLimit(1).fixedSize()
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .foregroundStyle(selected ? Color.white : Theme.ink.opacity(0.75))
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(selected ? Theme.accent : Color.clear))
                        .shadow(color: selected ? Color.black.opacity(0.08) : .clear, radius: 1, y: 0.5)
                        .contentShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.chip))
    }
}

struct KeyCap: View {
    let key: String
    var body: some View {
        Text(key)
            .font(Theme.rounded(11.5, .bold))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(Theme.line, lineWidth: 1))
            .shadow(color: Theme.ink.opacity(0.08), radius: 0, y: 1.5)
    }
}

struct Note: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.system(size: 11.5)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true).padding(.horizontal, 4)
    }
}

struct SoftTextField: View {
    let placeholder: String
    @Binding var text: String
    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.chip))
    }
}

let cleanupOptions: [(value: CleanupMode, label: String)] = [(.verbatim, "Verbatim"), (.minimal, "Minimal"), (.balanced, "Balanced")]

func cleanupDescription(_ mode: CleanupMode) -> String {
    switch mode {
    case .verbatim: return "Leaves the recognized text exactly as heard."
    case .minimal: return "Adds basic capitalization and ending punctuation."
    case .balanced, .polished: return "Also drops um / uh / erm and fixes adjacent weekday or month corrections, like “Tuesday, actually Thursday”."
    }
}

// MARK: - Restart

/// Quits Murmur and opens it again once this process has fully exited, so the
/// single-instance check in the new copy doesn't mistake the old one for a running copy.
@MainActor enum AppRelauncher {
    static func restart() {
        let helper = Process()
        helper.executableURL = URL(fileURLWithPath: "/bin/sh")
        // Paths are passed as arguments ($1, $2), never interpolated into the script.
        helper.arguments = ["-c", "while /bin/kill -0 \"$1\" 2>/dev/null; do /bin/sleep 0.2; done; /usr/bin/open \"$2\"", "murmur-restart", String(ProcessInfo.processInfo.processIdentifier), Bundle.main.bundleURL.path]
        do {
            try helper.run()
            NSApp.terminate(nil)
        } catch {
            NSSound.beep()
        }
    }
}

// MARK: - Menu-bar dropdown

struct MenuView: View {
    @ObservedObject var controller: DictationController
    @ObservedObject var store: Store
    @ObservedObject var updater: UpdateManager
    var openSettings: () -> Void
    var openNotes: () -> Void
    var closeMenu: () -> Void

    private var recordingDictation: Bool { !controller.isNoteSession && controller.phase == .recording }

    private var statusText: String {
        switch controller.phase {
        case .idle: return "Ready"
        case .preparing: return "Waking up"
        case .recording: return "Listening"
        case .processing: return "Tidying up"
        case .success: return controller.isNoteSession ? "Note saved" : "Done"
        case .error: return "Oops"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Mascot(size: 34, listening: controller.phase == .recording, level: controller.level)
                Text("murmur").font(Theme.wordmark(18)).foregroundStyle(Theme.ink)
                Spacer()
                Text(statusText)
                    .font(Theme.rounded(11.5, .semibold))
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .foregroundStyle(Theme.accent)
                    .background(Capsule().fill(Theme.chip))
            }
            if !controller.keyboardAvailable {
                Text("Your shortcut can’t be heard yet. Turn on Input Monitoring in Settings.").font(.system(size: 11.5)).foregroundStyle(Theme.warm).fixedSize(horizontal: false, vertical: true)
            }
            if let update = updater.state.availableUpdate {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Update available").font(Theme.rounded(12, .semibold)).foregroundStyle(Theme.ink)
                        Text("Version \(update.appVersion.displayString)").font(.system(size: 11)).foregroundStyle(Theme.muted)
                    }
                    Spacer(minLength: 4)
                    Button("Update") {
                        closeMenu()
                        updater.installAvailableUpdate { controller.cancel(); controller.keyboard.stop() }
                    }
                    .buttonStyle(PillButtonStyle(compact: true))
                    .disabled(controller.busy)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.chip))
            }
            Button {
                closeMenu()
                // Closing the menu before capture leaves the external app's focus untouched.
                Task { try? await Task.sleep(nanoseconds: 180_000_000); controller.toggle() }
            } label: {
                Label(recordingDictation ? "Stop dictation" : "Start dictation", systemImage: recordingDictation ? "stop.fill" : "mic.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PillButtonStyle())
            .disabled(controller.busy && !recordingDictation)
            HStack {
                NoteCaptureButton(controller: controller, beforeToggle: closeMenu)
                Spacer()
                Button("Notes…", action: openNotes).buttonStyle(PillButtonStyle(prominent: false, compact: true))
            }
            if controller.busy {
                Button("Cancel") { controller.cancel() }.buttonStyle(PillButtonStyle(prominent: false, compact: true))
            }
            VStack(alignment: .leading, spacing: 7) {
                Text("Cleanup").font(Theme.rounded(11.5, .semibold)).foregroundStyle(Theme.muted)
                ChipPicker(options: cleanupOptions, selection: $store.settings.mode)
            }
            if !controller.message.isEmpty {
                Text(controller.message).font(.system(size: 11.5)).foregroundStyle(Theme.warm).fixedSize(horizontal: false, vertical: true)
            }
            if !controller.result.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(controller.result.prefix(140))).font(.system(size: 12)).foregroundStyle(Theme.ink).lineLimit(3)
                    Button("Copy last result") { controller.copyResult() }.buttonStyle(PillButtonStyle(prominent: false, compact: true))
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.chip.opacity(0.6)))
            }
            HStack(spacing: 5) {
                if store.settings.shortcut == "fn" {
                    Text("Hold").foregroundStyle(Theme.muted); KeyCap(key: "fn"); Text("to talk · double-tap for hands-free").foregroundStyle(Theme.muted)
                } else {
                    Text("Hold your alternative shortcut to talk.").foregroundStyle(Theme.muted)
                }
            }.font(.system(size: 11.5))
            HStack {
                Button("Settings…", action: openSettings).buttonStyle(PillButtonStyle(prominent: false, compact: true))
                Spacer()
                Button("Quit") { controller.cancel(); NSApp.terminate(nil) }.buttonStyle(.plain).font(Theme.rounded(12, .medium)).foregroundStyle(Theme.muted)
            }
        }
        .padding(16).frame(width: 310)
    }
}

// MARK: - Recording capsule

/// The floating pill shown while dictating: just a live waveform, nothing else.
struct RecordingCapsule: View {
    @ObservedObject var controller: DictationController
    var body: some View {
        Group {
            if controller.phase == .error {
                Text(controller.message.isEmpty ? "Dictation stopped" : controller.message)
                    .font(Theme.rounded(11.5, .medium))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
                    .padding(.horizontal, 14).padding(.vertical, 8)
            } else {
                LiveWaveform(level: controller.level, thinking: controller.phase == .preparing)
                    .padding(.horizontal, 9).padding(.vertical, 6)
            }
        }
        .background(Capsule().fill(Theme.capsule.opacity(0.96)))
        .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1))
        .shadow(color: Color.black.opacity(0.2), radius: 5, y: 2)
        .contentShape(Capsule())
        // Clicking the pill while recording finishes the current capture.
        .onTapGesture { if controller.phase == .recording { controller.finish() } }
        .help(controller.phase == .recording ? (controller.isNoteSession ? "Click to stop and save note" : "Click to stop and insert") : "")
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: controller.phase)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(controller.phase == .error ? controller.message : "\(controller.isNoteSession ? "Voice note" : "Dictation") \(controller.phase.rawValue)")
        .accessibilityAddTraits(controller.phase == .recording ? .isButton : [])
    }
}

/// Bars that scroll with the recent microphone level; while transcribing they ripple gently.
struct LiveWaveform: View {
    let level: Float
    let thinking: Bool
    private static let count = 10
    @State private var history = [CGFloat](repeating: 0, count: LiveWaveform.count)
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !thinking || reduceMotion)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<Self.count, id: \.self) { index in
                    Capsule()
                        .fill(LinearGradient(colors: [Theme.peach, Theme.lilac], startPoint: .bottom, endPoint: .top))
                        .frame(width: 2.5, height: barHeight(index, time: time))
                }
            }
            .frame(height: 14)
        }
        .onChange(of: level) { value in
            guard !thinking else { return }
            // Soften the curve so quiet speech is still visible.
            let shaped = CGFloat(pow(Double(min(max(value, 0), 1)), 0.6))
            withAnimation(.linear(duration: 0.08)) { history = Array(history.dropFirst()) + [shaped] }
        }
        .onChange(of: thinking) { now in if now { history = [CGFloat](repeating: 0, count: Self.count) } }
    }

    private func barHeight(_ index: Int, time: Double) -> CGFloat {
        if thinking {
            let wave = (sin(time * 6 - Double(index) * 0.55) + 1) / 2
            return 2.5 + CGFloat(wave) * 4
        }
        return 2.5 + history[index] * 11.5
    }
}

@MainActor final class Overlay {
    private let panel: NSPanel
    init(controller: DictationController) {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 400, height: 76), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating; panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]; panel.hidesOnDeactivate = false; panel.isReleasedWhenClosed = false
        panel.ignoresMouseEvents = true // Clicks pass through except while recording (see update).
        panel.contentView = NSHostingView(rootView: RecordingCapsule(controller: controller))
    }
    func update(phase: DictationPhase) {
        // Visible only while you talk (and briefly for an error); it vanishes the moment you let go.
        guard phase == .preparing || phase == .recording || phase == .error else { panel.orderOut(nil); return }
        // Only clickable while recording, so it can be clicked to stop; otherwise it's see-through to clicks.
        panel.ignoresMouseEvents = phase != .recording
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        if let frame = screen?.visibleFrame { panel.setFrameOrigin(NSPoint(x: frame.midX - panel.frame.width / 2, y: frame.minY + 30)) }
        panel.orderFrontRegardless()
    }
}

// MARK: - Settings window

enum SettingsPage: String, CaseIterable, Identifiable {
    case setup, dictation, style, shortcuts, snippets, dictionary, privacy
    var id: Self { self }
    var title: String {
        switch self {
        case .setup: return "Setup"
        case .dictation: return "Dictation"
        case .style: return "Style"
        case .shortcuts: return "Shortcuts"
        case .snippets: return "Snippets"
        case .dictionary: return "Dictionary"
        case .privacy: return "Privacy"
        }
    }
    var icon: String {
        switch self {
        case .setup: return "checklist"
        case .dictation: return "waveform"
        case .style: return "textformat"
        case .shortcuts: return "keyboard"
        case .snippets: return "text.bubble"
        case .dictionary: return "character.book.closed"
        case .privacy: return "lock"
        }
    }
    var blurb: String {
        switch self {
        case .setup: return "Download the speech model and allow the permissions Murmur needs. Everything runs on this Mac."
        case .dictation: return "Microphone, language and how much Murmur tidies your text."
        case .style: return "How formal your text reads, based on the app you’re typing in."
        case .shortcuts: return "Keys for starting, stopping and pasting dictation."
        case .snippets: return "Short phrases that expand into longer text."
        case .dictionary: return "Names and terms Murmur should spell your way."
        case .privacy: return "What Murmur keeps on this Mac, and for how long."
        }
    }
}

struct SettingsView: View {
    @ObservedObject var controller: DictationController
    @ObservedObject var store: Store
    @ObservedObject var models: SpeechModelManager
    @ObservedObject var updater: UpdateManager
    @State private var page: SettingsPage = .setup
    @State private var status = ""
    @State private var microphones: [Microphone] = []
    @State private var accessibility = AXIsProcessTrusted()
    @State private var monitoring = CGPreflightListenEventAccess()
    @State private var microphone = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    @State private var loginEnabled = SMAppService.mainApp.status == .enabled
    @State private var newCue = ""
    @State private var newSnippet = ""
    @State private var newWord = ""
    @State private var newHint = ""
    private let refresh = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    init(controller: DictationController, store: Store, updater: UpdateManager, page: SettingsPage = .setup) {
        _controller = ObservedObject(wrappedValue: controller)
        _store = ObservedObject(wrappedValue: store)
        _models = ObservedObject(wrappedValue: controller.models)
        _updater = ObservedObject(wrappedValue: updater)
        _page = State(initialValue: page)
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(Theme.line).frame(width: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(page.title).font(.system(size: 20, weight: .semibold)).foregroundStyle(Theme.ink)
                        Text(page.blurb).font(.system(size: 12.5)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                    }.padding(.bottom, 4)
                    content
                }
                .padding(.horizontal, 30).padding(.top, 40).padding(.bottom, 30)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .id(page)
        }
        .frame(width: 780, height: 600)
        .background(Theme.background)
        .tint(Theme.accent)
        .onAppear { microphones = AudioRecorder.microphones() }
        .onReceive(refresh) { _ in
            accessibility = AXIsProcessTrusted(); monitoring = CGPreflightListenEventAccess(); microphone = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
            if monitoring && !controller.keyboardAvailable { controller.keyboard.start() }
            store.pruneHistory()
        }
    }

    @ViewBuilder private var content: some View {
        switch page {
        case .setup: setup
        case .dictation: dictation
        case .style: styleSettings
        case .shortcuts: shortcuts
        case .snippets: snippetSettings
        case .dictionary: dictionary
        case .privacy: privacy
        }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Mascot(size: 40, listening: controller.phase == .recording, level: controller.level)
                VStack(alignment: .leading, spacing: 0) {
                    Text("murmur").font(Theme.wordmark(19)).foregroundStyle(Theme.ink)
                    Text("talk, don’t type").font(Theme.rounded(11, .medium)).foregroundStyle(Theme.muted)
                }
            }
            .padding(.horizontal, 8).padding(.bottom, 18)
            ForEach(SettingsPage.allCases) { item in
                sidebarButton(item)
            }
            Spacer()
            VStack(alignment: .leading, spacing: 6) {
                if controller.stats.words > 0 {
                    Text("\(controller.stats.words.formatted()) words").font(Theme.rounded(15, .bold)).foregroundStyle(Theme.ink)
                    Text(controller.stats.wordsPerMinute > 0 ? "\(controller.stats.wordsPerMinute) wpm · ~\(controller.stats.minutesSaved) min saved" : "Keep talking!").foregroundStyle(Theme.muted)
                } else {
                    HStack(spacing: 5) { Text("Hold").foregroundStyle(Theme.muted); KeyCap(key: store.settings.shortcut == "fn" ? "fn" : "⌃⇧␣"); Text("to talk").foregroundStyle(Theme.muted) }
                    Text("Esc cancels").foregroundStyle(Theme.muted.opacity(0.8))
                }
            }
            .font(.system(size: 11.5))
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.card.opacity(0.7)))
            Text("Version \(updater.currentVersion.displayString)")
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.muted.opacity(0.8))
                .padding(.horizontal, 8).padding(.top, 6)
        }
        .padding(.horizontal, 14).padding(.top, 46).padding(.bottom, 16)
        .frame(width: 210)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.sidebar)
    }

    private func sidebarButton(_ item: SettingsPage) -> some View {
        let selected = page == item
        return Button { withAnimation(.easeOut(duration: 0.15)) { page = item } } label: {
            HStack(spacing: 10) {
                Image(systemName: item.icon).font(.system(size: 13, weight: .semibold)).frame(width: 18)
                Text(item.title).font(Theme.rounded(13.5, selected ? .bold : .medium))
                Spacer()
                if item == .setup && (!allPermissionsReady || updater.state.availableUpdate != nil) {
                    Circle().fill(updater.state.availableUpdate != nil ? Theme.accent : Theme.warm).frame(width: 7, height: 7)
                }
            }
            .foregroundStyle(selected ? Theme.accent : Theme.ink.opacity(0.75))
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(selected ? Theme.card : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: Setup

    private var allPermissionsReady: Bool { microphone && models.isReady && accessibility && monitoring }
    private var readyCount: Int { [models.isReady, microphone, accessibility, monitoring].filter { $0 }.count }

    private var showUpdateProminent: Bool {
        switch updater.state {
        case .available, .downloading, .installing: return true
        default: return false
        }
    }

    private var setup: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                ForEach(0..<4) { index in
                    Capsule().fill(index < readyCount ? AnyShapeStyle(Theme.blobGradient) : AnyShapeStyle(Theme.chip)).frame(height: 5)
                }
                Text(allPermissionsReady ? "All set!" : "\(readyCount) of 4 ready").font(Theme.rounded(12, .semibold)).foregroundStyle(allPermissionsReady ? Theme.mint : Theme.muted).fixedSize().padding(.leading, 6)
            }
            if showUpdateProminent { updatesCard }
            modelCard
            Card {
                permissionRow(icon: "mic.fill", title: "Microphone", detail: "So Murmur can hear you.", ok: microphone) {
                    Task { _ = await AVCaptureDevice.requestAccess(for: .audio); microphone = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized }
                }
                CardDivider()
                permissionRow(icon: "text.cursor", title: "Accessibility", detail: "Lets Murmur type into the app you’re using.", ok: accessibility) {
                    _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
                    openPrivacy("Privacy_Accessibility")
                }
                CardDivider()
                permissionRow(icon: "keyboard", title: "Input Monitoring", detail: "Listens for your talk shortcut anywhere.", ok: monitoring) {
                    _ = CGRequestListenEventAccess(); openPrivacy("Privacy_ListenEvent")
                }
            }
            HStack(spacing: 8) {
                Button("Reconnect shortcuts") { controller.keyboard.start() }.buttonStyle(PillButtonStyle(prominent: false, compact: true))
                Button { controller.cancel(); AppRelauncher.restart() } label: { Label("Restart Murmur", systemImage: "arrow.clockwise") }
                    .buttonStyle(PillButtonStyle(prominent: false, compact: true))
                    .help("Quit and reopen Murmur so new permissions take effect")
                Spacer()
            }
            Note("Just turned a permission on? If macOS asks to quit and reopen, use Restart Murmur here; macOS doesn’t always bring menu-bar apps back by itself.")
            Card {
                SettingRow(icon: "sunrise", title: "Launch at login") {
                    Toggle("", isOn: $loginEnabled).toggleStyle(.switch).labelsHidden()
                }
            }
            .onChange(of: loginEnabled) { enabled in
                do { if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }; status = "" } catch { status = "Login item: \(error.localizedDescription)"; loginEnabled = SMAppService.mainApp.status == .enabled }
            }
            if !showUpdateProminent { updatesCard }
            if !status.isEmpty { Note(status) }
            Note("Speech is recognized by Whisper running on this Mac. Your audio is never uploaded. Network access is limited to downloading the speech model from Hugging Face and checking GitHub Releases for app updates (which can be turned off above). No document text, browser tabs or screenshots are read.")
        }
    }

    private var updatesCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                SettingRow(icon: "arrow.down.circle", title: "Updates", detail: "Installed: \(updater.currentVersion.displayString)") {
                    switch updater.state {
                    case .idle:
                        Button("Check for updates") { updater.checkForUpdates(userInitiated: true) }
                            .buttonStyle(PillButtonStyle(prominent: false, compact: true))
                    case .checking:
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("Checking…").font(.system(size: 12)).foregroundStyle(Theme.muted)
                        }
                    case .upToDate:
                        HStack(spacing: 8) {
                            StatusBadge(ok: true, text: "Up to date")
                            Button("Check again") { updater.checkForUpdates(userInitiated: true) }
                                .buttonStyle(PillButtonStyle(prominent: false, compact: true))
                        }
                    case .available:
                        Button("Update & restart") {
                            updater.installAvailableUpdate { controller.cancel(); controller.keyboard.stop() }
                        }
                        .buttonStyle(PillButtonStyle(compact: true))
                        .disabled(controller.busy)
                    case .downloading, .installing:
                        EmptyView()
                    case .failed:
                        Button("Try again") { updater.checkForUpdates(userInitiated: true) }
                            .buttonStyle(PillButtonStyle(prominent: false, compact: true))
                    }
                }
                switch updater.state {
                case .available(let manifest):
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Murmur \(manifest.appVersion.displayString) is available.")
                            .font(Theme.rounded(12.5, .semibold))
                            .foregroundStyle(Theme.accent)
                        if let notes = manifest.notes, !notes.isEmpty {
                            Text(notes).font(.system(size: 12)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.bottom, 4)
                case .downloading(let fraction):
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Downloading update… \(Int(fraction * 100))%").font(Theme.rounded(12.5, .semibold)).foregroundStyle(Theme.ink)
                        ProgressView(value: fraction).progressViewStyle(.linear).tint(Theme.accent)
                    }
                    .padding(.bottom, 4)
                case .installing:
                    HStack(spacing: 10) {
                        Text("Verifying and installing update… Murmur will restart automatically.").font(Theme.rounded(12.5, .medium)).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        ProgressView().controlSize(.small)
                    }
                    .padding(.bottom, 4)
                case .failed(let message):
                    Text(message).font(.system(size: 12)).foregroundStyle(Theme.warm).fixedSize(horizontal: false, vertical: true).padding(.bottom, 4)
                default:
                    EmptyView()
                }
                CardDivider()
                SettingRow(title: "Check for updates automatically", detail: "Checks GitHub Releases for new versions merged to main.") {
                    Toggle("", isOn: $store.settings.autoCheckUpdates).toggleStyle(.switch).labelsHidden()
                }
            }
        }
    }

    private var modelBusy: Bool {
        switch models.state { case .downloading, .loading: return true; default: return false }
    }

    private var modelCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                SettingRow(icon: "waveform", title: "Speech model", detail: "Whisper, running on your Mac. Download it once and it works offline from then on.") {
                    switch models.state {
                    case .ready: StatusBadge(ok: true, text: "Ready")
                    case .notDownloaded: Button("Download \(models.choice.size)") { models.download() }.buttonStyle(PillButtonStyle(compact: true))
                    case .failed: Button("Try again") { models.redownload() }.buttonStyle(PillButtonStyle(compact: true))
                    case .downloading, .loading: EmptyView()
                    }
                }
                ChipPicker(options: WhisperModelChoice.allCases.map { (value: $0, label: "\($0.label) · \($0.size)") }, selection: $models.choice)
                    .disabled(modelBusy).opacity(modelBusy ? 0.6 : 1)
                Text(models.choice.detail).font(.system(size: 12)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                switch models.state {
                case .downloading(let fraction):
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Downloading… \(Int(fraction * 100))%").font(Theme.rounded(12.5, .semibold)).foregroundStyle(Theme.ink)
                            ProgressView(value: fraction).progressViewStyle(.linear).tint(Theme.accent)
                        }
                    }
                case .loading:
                    HStack(spacing: 12) {
                        Text("Loading the model. The first load after a download can take a minute.").font(Theme.rounded(12.5, .medium)).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        ProgressView().controlSize(.small)
                    }
                case .failed(let message):
                    Text(message).font(.system(size: 12)).foregroundStyle(Theme.warm)
                default:
                    EmptyView()
                }
            }.padding(.bottom, 10)
        }
    }

    private func permissionRow(icon: String, title: String, detail: String, ok: Bool, enable: @escaping () -> Void) -> some View {
        SettingRow(icon: icon, title: title, detail: detail) {
            if ok { StatusBadge(ok: true, text: "All set") }
            else { Button("Turn on", action: enable).buttonStyle(PillButtonStyle(compact: true)) }
        }
    }

    // MARK: Dictation

    private var dictation: some View {
        VStack(alignment: .leading, spacing: 14) {
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Cleanup").font(Theme.rounded(13.5, .semibold)).foregroundStyle(Theme.ink)
                    ChipPicker(options: cleanupOptions, selection: $store.settings.mode)
                    Text(cleanupDescription(store.settings.mode)).font(.system(size: 12)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                }.padding(.vertical, 10)
            }
            Card {
                SettingRow(icon: "mic", title: "Microphone", detail: store.settings.microphoneID == 0 ? AudioRecorder.automaticDescription : nil) {
                    HStack(spacing: 6) {
                        Picker("", selection: $store.settings.microphoneID) { Text("Automatic").tag(UInt32(0)); ForEach(microphones) { Text($0.name).tag($0.id) } }
                            .labelsHidden().frame(maxWidth: 200)
                        Button { microphones = AudioRecorder.microphones() } label: { Image(systemName: "arrow.clockwise") }
                            .buttonStyle(.plain).foregroundStyle(Theme.accent).help("Refresh microphones")
                    }
                }
                CardDivider()
                SettingRow(icon: "globe", title: "Language", detail: "Automatic detection works well; pick a language if short phrases come out in the wrong one.") {
                    Picker("", selection: $store.settings.language) {
                        Text("Detect automatically").tag(""); Text("English").tag("en"); Text("Spanish").tag("es"); Text("Mandarin / Chinese").tag("zh"); Text("French").tag("fr"); Text("German").tag("de"); Text("Japanese").tag("ja"); Text("Portuguese").tag("pt"); Text("Korean").tag("ko"); Text("Hindi").tag("hi")
                    }.labelsHidden().frame(maxWidth: 200)
                }
            }
            Card {
                SettingRow(icon: "app.badge", title: "Adapt punctuation to the app", detail: "Code editors keep your casing and skip the final period. Uses only the app’s ID, locally.") {
                    Toggle("", isOn: $store.settings.contextAware).toggleStyle(.switch).labelsHidden()
                }
                CardDivider()
                SettingRow(icon: "bell", title: "Play start sound") {
                    Toggle("", isOn: $store.settings.audioFeedback).toggleStyle(.switch).labelsHidden()
                }
                CardDivider()
                SettingRow(icon: "speaker.slash", title: "Mute audio while dictating", detail: "Silences music and videos while you talk, then puts the volume back.") {
                    Toggle("", isOn: $store.settings.muteWhileDictating).toggleStyle(.switch).labelsHidden()
                }
                CardDivider()
                SettingRow(icon: "doc.on.clipboard", title: "Clipboard paste fallback", detail: "Only for the original field and cursor. Your clipboard is restored afterwards unless another app changes it.") {
                    Toggle("", isOn: $store.settings.allowClipboard).toggleStyle(.switch).labelsHidden()
                }
            }
            Note("Cleanup is conservative and rule-based, not AI rewriting. It won’t untangle complex restarts or fix grammar.")
        }
    }

    // MARK: Shortcuts

    // MARK: Style

    private var styleSettings: some View {
        VStack(alignment: .leading, spacing: 14) {
            Card {
                styleRow(icon: "heart", title: "Personal messages", detail: "Messages, WhatsApp, Telegram, Discord, Signal", selection: $store.settings.personalStyle)
                CardDivider()
                styleRow(icon: "briefcase", title: "Work messages", detail: "Slack, Teams, Linear", selection: $store.settings.workStyle)
                CardDivider()
                styleRow(icon: "envelope", title: "Email", detail: "Mail, Outlook, Superhuman, Spark", selection: $store.settings.emailStyle)
                CardDivider()
                styleRow(icon: "square.grid.2x2", title: "Everything else", detail: "Notes, docs and other apps", selection: $store.settings.otherStyle)
            }
            Card {
                VStack(alignment: .leading, spacing: 9) {
                    styleExample("Formal", "Sounds good, see you at 3.")
                    styleExample("Casual", "Sounds good, see you at 3")
                    styleExample("Very casual", "sounds good, see you at 3")
                }.padding(.vertical, 10)
            }
            Text("Smart formatting").font(Theme.rounded(15, .bold)).foregroundStyle(Theme.ink).padding(.top, 6)
            Card {
                VStack(alignment: .leading, spacing: 9) {
                    sayRow("“comma”, “period”, “question mark”, “colon”, “em dash”", "Spoken punctuation")
                    sayRow("“new line”, “new paragraph”", "Line breaks")
                    sayRow("“one, milk. two, eggs.”", "A numbered list")
                    sayRow("“at 2, actually 3”", "Fixes it to “at 3”")
                    sayRow("“…scratch that”", "Drops what you just said")
                    sayRow("“…press enter”", "Sends it, handy in chats")
                }.padding(.vertical, 10)
            }
            Note("Browsers, AI chat apps and code editors always get plain formatting. Styles and smart formatting are skipped in Verbatim cleanup.")
        }
    }

    private func styleRow(icon: String, title: String, detail: String, selection: Binding<WritingStyle>) -> some View {
        SettingRow(icon: icon, title: title, detail: detail) {
            ChipPicker(options: WritingStyle.allCases.map { (value: $0, label: $0.label) }, selection: selection)
        }
    }

    private func styleExample(_ name: String, _ sample: String) -> some View {
        HStack(spacing: 10) {
            Text(name).font(Theme.rounded(12, .semibold)).foregroundStyle(Theme.muted).frame(width: 90, alignment: .leading)
            Text(sample).font(.system(size: 13)).foregroundStyle(Theme.ink)
        }
    }

    private func sayRow(_ say: String, _ result: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(say).font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.accent).frame(width: 300, alignment: .leading).fixedSize(horizontal: false, vertical: true)
            Text(result).font(.system(size: 12.5)).foregroundStyle(Theme.ink)
        }
    }

    // MARK: Snippets

    private var snippetSettings: some View {
        VStack(alignment: .leading, spacing: 14) {
            Card {
                VStack(alignment: .leading, spacing: 8) {
                    SoftTextField(placeholder: "When I say… (e.g. “my calendar link”)", text: $newCue)
                    HStack(alignment: .top, spacing: 8) {
                        TextEditor(text: $newSnippet)
                            .font(.system(size: 13)).scrollContentBackground(.hidden)
                            .frame(height: 64).padding(6)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.chip))
                            .overlay(alignment: .topLeading) { if newSnippet.isEmpty { Text("…type this").font(.system(size: 13)).foregroundStyle(Theme.muted).padding(.horizontal, 11).padding(.vertical, 6).allowsHitTesting(false) } }
                        Button("Add") {
                            let cue = newCue.trimmingCharacters(in: .whitespacesAndNewlines); let text = newSnippet.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !cue.isEmpty, !text.isEmpty else { return }
                            store.settings.snippets.append(Snippet(cue: String(cue.prefix(80)), text: String(text.prefix(4000)))); newCue = ""; newSnippet = ""
                        }
                        .buttonStyle(PillButtonStyle(compact: true))
                        .disabled(newCue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || newSnippet.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.settings.snippets.count >= 100)
                    }
                }.padding(.vertical, 10)
            }
            if store.settings.snippets.isEmpty {
                VStack(spacing: 8) {
                    Text("No snippets yet").font(Theme.rounded(14, .semibold)).foregroundStyle(Theme.ink)
                    Text("Try “my email” → your address, or “intro” → a short bio.").font(.system(size: 12)).foregroundStyle(Theme.muted)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 22)
            } else {
                Card {
                    ForEach(Array($store.settings.snippets.enumerated()), id: \.element.id) { index, $snippet in
                        if index > 0 { CardDivider() }
                        HStack(alignment: .top, spacing: 10) {
                            TextField("Cue", text: $snippet.cue).textFieldStyle(.plain).font(Theme.rounded(13, .semibold)).foregroundStyle(Theme.accent).frame(width: 170)
                            TextField("Text", text: $snippet.text, axis: .vertical).textFieldStyle(.plain).font(.system(size: 12.5)).foregroundStyle(Theme.ink).lineLimit(1...4)
                            Button { store.settings.snippets.removeAll { $0.id == snippet.id } } label: { Image(systemName: "trash") }
                                .buttonStyle(.plain).foregroundStyle(Theme.muted).help("Remove snippet")
                        }.padding(.vertical, 10)
                    }
                }
            }
            Note("Say just the cue and Murmur inserts the text exactly as saved. Said inside a sentence, the cue is swapped for the text.")
        }
    }

    private var shortcuts: some View {
        VStack(alignment: .leading, spacing: 14) {
            Card {
                SettingRow(icon: "globe", title: "Primary shortcut") {
                    ChipPicker(options: [("fn", "Fn / Globe"), ("alternative", "Alternative only")], selection: $store.settings.shortcut)
                }
            }
            Note("If Globe opens the emoji picker or system dictation, set System Settings → Keyboard → “Press Globe key to” → “Do Nothing”. Some keyboards don’t expose Fn; use the alternative below.")
            Card {
                SettingRow(icon: "command", title: "Alternative shortcut", detail: "Always available. Default is Control–Shift–Space.") {
                    Picker("", selection: $store.settings.fallbackKeyCode) { Text("Space").tag(UInt16(49)); Text("D").tag(UInt16(2)); Text("F5").tag(UInt16(96)); Text("F6").tag(UInt16(97)); Text("Return").tag(UInt16(36)) }
                        .labelsHidden().frame(maxWidth: 120)
                }
                CardDivider()
                HStack(spacing: 6) {
                    modifier("⌃ Control", mask: 0x40000); modifier("⇧ Shift", mask: 0x20000); modifier("⌥ Option", mask: 0x80000); modifier("⌘ Command", mask: 0x100000)
                }.padding(.vertical, 12)
                if store.settings.fallbackModifiers.nonzeroBitCount < 2 {
                    Text("Pick at least two modifiers to switch the alternative shortcut on.").font(.system(size: 12)).foregroundStyle(Theme.warm).padding(.bottom, 10)
                }
            }
            Card {
                VStack(alignment: .leading, spacing: 9) {
                    tipRow(keys: ["fn"], "Hold to talk; let go to insert. A quick tap does nothing.")
                    tipRow(keys: ["fn", "fn"], "Double-tap for hands-free; press fn again to finish.")
                    tipRow(keys: ["fn", "space"], "While holding fn, switch to hands-free.")
                    tipRow(keys: ["⌃", "⌘", "V"], "Paste your last dictation again.")
                    tipRow(keys: ["esc"], "Cancel. Fn plus another key leaves that system shortcut alone.")
                }.padding(.vertical, 10)
            }
        }
    }

    private func tipRow(keys: [String], _ text: String) -> some View {
        HStack(alignment: .center, spacing: 10) {
            HStack(spacing: 3) { ForEach(Array(keys.enumerated()), id: \.offset) { KeyCap(key: $0.element) } }.frame(width: 96, alignment: .leading)
            Text(text).font(.system(size: 12.5)).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func tip(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Circle().fill(Theme.blobGradient).frame(width: 7, height: 7)
            Text(text).font(.system(size: 12.5)).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func modifier(_ title: String, mask: UInt64) -> some View {
        let on = store.settings.fallbackModifiers & mask != 0
        return Button {
            if on { store.settings.fallbackModifiers &= ~mask } else { store.settings.fallbackModifiers |= mask }
        } label: {
            Text(title)
                .font(Theme.rounded(12.5, .semibold))
                .padding(.horizontal, 11).padding(.vertical, 6)
                .foregroundStyle(on ? Color.white : Theme.ink)
                .background(Capsule().fill(on ? Theme.accent : Theme.chip))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    // MARK: Dictionary

    private var dictionary: some View {
        VStack(alignment: .leading, spacing: 14) {
            Card {
                HStack(spacing: 8) {
                    SoftTextField(placeholder: "Correct spelling", text: $newWord)
                    SoftTextField(placeholder: "Comes out as… (optional, e.g. shiv on)", text: $newHint)
                    Button("Add") {
                        let word = String(newWord.trimmingCharacters(in: .whitespacesAndNewlines).prefix(150)); guard !word.isEmpty else { return }
                        store.settings.dictionary.append(DictionaryEntry(spelling: word, soundsLike: String(newHint.prefix(150)))); newWord = ""; newHint = ""
                    }
                    .buttonStyle(PillButtonStyle(compact: true))
                    .disabled(store.settings.dictionary.count >= 200 || newWord.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }.padding(.vertical, 10)
            }
            if store.settings.dictionary.isEmpty {
                VStack(spacing: 8) {
                    Text("No words yet").font(Theme.rounded(14, .semibold)).foregroundStyle(Theme.ink)
                    Text("Add names, places or jargon you say often.").font(.system(size: 12)).foregroundStyle(Theme.muted)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 26)
            } else {
                Card {
                    ForEach(Array($store.settings.dictionary.enumerated()), id: \.element.id) { index, $entry in
                        if index > 0 { CardDivider() }
                        HStack(spacing: 8) {
                            TextField("Spelling", text: $entry.spelling).textFieldStyle(.plain).font(Theme.rounded(13, .semibold)).foregroundStyle(Theme.ink)
                            TextField("Sounds like", text: $entry.soundsLike).textFieldStyle(.plain).font(.system(size: 12.5)).foregroundStyle(Theme.muted)
                            Button { store.settings.dictionary.removeAll { $0.id == entry.id } } label: { Image(systemName: "trash") }
                                .buttonStyle(.plain).foregroundStyle(Theme.muted).help("Remove word")
                        }.padding(.vertical, 10)
                    }
                }
            }
            Note("Murmur listens for these words and fixes near-misses: “Stef” becomes “Steph”. If a name keeps coming out wrong, put what Murmur writes in “Sounds like” (separate several with commas), and it’ll be swapped for your spelling.")
        }
    }

    // MARK: Privacy

    private var privacy: some View {
        VStack(alignment: .leading, spacing: 14) {
            Card {
                SettingRow(icon: "clock.arrow.circlepath", title: "Save transcription history", detail: "Only text that was successfully inserted, up to 200 entries.") {
                    Toggle("", isOn: $store.settings.keepHistory).toggleStyle(.switch).labelsHidden()
                }
                CardDivider()
                SettingRow(icon: "calendar", title: "Delete history after") {
                    ChipPicker(options: [(1, "1 day"), (7, "7 days"), (30, "30 days")], selection: $store.settings.retentionDays)
                        .disabled(!store.settings.keepHistory).opacity(store.settings.keepHistory ? 1 : 0.5)
                }
            }
            Note("Audio is temporary and removed after processing or cancelling; leftovers from a crash are removed at next launch. Murmur makes no transcription or cleanup network requests, and no transcript is written to logs. The last result stays in memory until your next recording, a cancel, or quitting.")
            if !store.history.isEmpty {
                Card {
                    ForEach(Array(store.history.enumerated()), id: \.element.id) { index, entry in
                        if index > 0 { CardDivider() }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.date.formatted()).font(Theme.rounded(11, .medium)).foregroundStyle(Theme.muted)
                            Text(entry.text).font(.system(size: 12.5)).foregroundStyle(Theme.ink).textSelection(.enabled)
                        }.padding(.vertical, 10)
                    }
                }
            }
            HStack {
                Button("Delete all local history") { store.clearHistory() }.buttonStyle(PillButtonStyle(prominent: false, compact: true)).foregroundStyle(Theme.warm)
                Spacer()
            }
            if !store.persistenceError.isEmpty { Text(store.persistenceError).font(.system(size: 12)).foregroundStyle(Theme.warm) }
        }
    }

    private func openPrivacy(_ anchor: String) { if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") { NSWorkspace.shared.open(url) } }
}
