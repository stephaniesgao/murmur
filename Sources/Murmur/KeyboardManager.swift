import Carbon
import AppKit
import ApplicationServices
import MurmurCore
import os

// Logs only shortcut state (Fn down/up, actions), never which other keys are typed.
private let keyLog = Logger(subsystem: "com.steph.murmur", category: "shortcut")

@MainActor final class KeyboardManager {
    var onAction: ((ShortcutAction) -> Void)?
    var onAvailability: ((Bool) -> Void)?
    var onPasteLast: (() -> Void)?
    var allowsDictationGestures: (() -> Bool)?
    /// Key-ups to swallow because Murmur used the matching key-down (Fn+Space, ⌃⌘V).
    private var swallowKeyUps: Set<UInt16> = []
    var settings: DictationSettings = .init()
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var gesture = ShortcutGesture()
    private var fnDown = false
    private var shortcutDown = false
    private var stopTask: Task<Void, Never>?
    private var watchdog: Timer?
    private static let modifierMask: CGEventFlags = [.maskCommand, .maskAlternate, .maskShift, .maskControl]
    @discardableResult func start() -> Bool {
        stop()
        let mask = (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, info in
            guard let info else { return Unmanaged.passUnretained(event) }
            // This source is installed exclusively on the main run loop.
            let swallow = MainActor.assumeIsolated { Unmanaged<KeyboardManager>.fromOpaque(info).takeUnretainedValue().handle(type, event) }
            return swallow ? nil : Unmanaged.passUnretained(event)
        }
        let info = Unmanaged.passUnretained(self).toOpaque()
        // An active tap lets Murmur swallow only its own shortcuts (Fn+Space, ⌃⌘V) so they don't
        // type into your app. Everything else passes through untouched. Fall back to listening only.
        tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: CGEventMask(mask), callback: callback, userInfo: info)
            ?? CGEvent.tapCreate(tap: .cgSessionEventTap, place: .tailAppendEventTap, options: .listenOnly, eventsOfInterest: CGEventMask(mask), callback: callback, userInfo: info)
        guard let tap else { keyLog.notice("Keyboard monitor unavailable (Input Monitoring not granted)"); onAvailability?(false); return false }
        keyLog.notice("Keyboard monitor started")
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes); CGEvent.tapEnable(tap: tap, enable: true)
        watchdog = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in MainActor.assumeIsolated {
            guard let self else { return }
            if IsSecureEventInputEnabled() { keyLog.notice("Cancel: secure input"); self.reset(cancel: true) }
        } }
        onAvailability?(true); return true
    }
    func stop() {
        watchdog?.invalidate(); watchdog = nil; stopTask?.cancel()
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }; source = nil
        if let tap { CFMachPortInvalidate(tap) }; tap = nil; reset(cancel: false)
    }
    func reset(cancel: Bool = false) {
        if stopTask != nil || gesture.isDown { keyLog.notice("Shortcut reset (cancel: \(cancel, privacy: .public))") }
        gesture.reset(); fnDown = false; shortcutDown = false; stopTask?.cancel(); stopTask = nil; if cancel { onAction?(.cancel) } }
    private func dispatch(_ actions: [ShortcutAction]) {
        if !actions.isEmpty { keyLog.notice("Shortcut actions: \(String(describing: actions), privacy: .public)") }
        for action in actions {
            switch action {
            case .scheduleStop:
                stopTask?.cancel(); stopTask = Task { [weak self] in try? await Task.sleep(nanoseconds: 330_000_000); guard !Task.isCancelled, let self else { return }; self.dispatch(self.gesture.expireTap()) }
            case .cancelScheduledStop: stopTask?.cancel(); onAction?(action)
            default: onAction?(action)
            }
        }
    }
    /// Returns true to swallow the event (only Murmur's own shortcuts).
    private func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput { keyLog.notice("Cancel: event tap was disabled (\(type == .tapDisabledByTimeout ? "timeout" : "user input", privacy: .public))"); reset(cancel: true); if let tap { CGEvent.tapEnable(tap: tap, enable: true) }; return false }
        let key = UInt16(event.getIntegerValueField(.keyboardEventKeycode)); let now = ProcessInfo.processInfo.systemUptime
        if type == .keyUp, swallowKeyUps.remove(key) != nil { return true }
        if type == .keyDown, key == 53 { keyLog.notice("Cancel: Escape"); reset(cancel: true); return false }
        // ⌃⌘V pastes the last transcript again.
        if type == .keyDown, key == 9, event.flags.intersection(Self.modifierMask) == [.maskControl, .maskCommand] {
            if event.getIntegerValueField(.keyboardEventAutorepeat) == 0 { keyLog.notice("Paste last transcript"); onPasteLast?() }
            swallowKeyUps.insert(key); return true
        }
        guard allowsDictationGestures?() != false else { return false }
        if settings.shortcut == "fn", type == .flagsChanged {
            let down = event.flags.contains(.maskSecondaryFn)
            if down != fnDown { fnDown = down
                keyLog.notice("Fn \(down ? "down" : "up", privacy: .public)")
                if down {
                    guard event.flags.intersection(Self.modifierMask).isEmpty else { return false }
                    dispatch(gesture.down(at: now))
                } else { dispatch(gesture.up(at: now)) }
            }
        }
        // Fn+Space switches the current recording to hands-free; the Space never reaches your app.
        if settings.shortcut == "fn", fnDown, type == .keyDown, key == 49 {
            if event.getIntegerValueField(.keyboardEventAutorepeat) == 0 { dispatch(gesture.lockHandsFree(at: now)) }
            swallowKeyUps.insert(key); return true
        }
        // Any other key used with Fn is a system chord, not a dictation gesture.
        if settings.shortcut == "fn", fnDown, type == .keyDown { keyLog.notice("Cancel: another key pressed with Fn"); reset(cancel: true); return false }
        let wanted = CGEventFlags(rawValue: settings.fallbackModifiers)
        if settings.fallbackModifiers.nonzeroBitCount >= 2, type == .keyDown, key == settings.fallbackKeyCode, event.flags.intersection(Self.modifierMask) == wanted {
            guard event.getIntegerValueField(.keyboardEventAutorepeat) == 0, !shortcutDown else { return false }
            shortcutDown = true; dispatch(gesture.down(at: now))
        } else if type == .keyUp, key == settings.fallbackKeyCode, shortcutDown { shortcutDown = false; dispatch(gesture.up(at: now)) }
        else if type == .flagsChanged, shortcutDown, event.flags.intersection(wanted) != wanted { shortcutDown = false; dispatch(gesture.up(at: now)) }
        return false
    }
}
