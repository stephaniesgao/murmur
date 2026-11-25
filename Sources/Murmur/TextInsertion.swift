import AppKit
import ApplicationServices
import MurmurCore
import os

// Logs how text was inserted and into which app, never the text itself.
private let insertLog = Logger(subsystem: "com.steph.murmur", category: "insert")

struct InsertionTarget {
    let pid: pid_t
    let bundle: String
    let element: AXUIElement?
    let selection: NSRange?
}
@MainActor final class TextInsertion {
    static func range(_ element: AXUIElement) -> NSRange? {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &raw) == .success, let raw, CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
        var range = CFRange(); guard AXValueGetValue(unsafeBitCast(raw, to: AXValue.self), .cfRange, &range) else { return nil }; return NSRange(location: range.location, length: range.length)
    }
    static func focused(pid: pid_t) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid); AXUIElementSetMessagingTimeout(app, 0.4)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &value) == .success, let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        let element = unsafeBitCast(value, to: AXUIElement.self); AXUIElementSetMessagingTimeout(element, 0.4); return element
    }
    static func characterCount(_ element: AXUIElement) -> Int? {
        var raw: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXNumberOfCharactersAttribute as CFString, &raw) == .success, let count = raw as? Int { return count }
        if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &raw) == .success, let value = raw as? String { return value.utf16.count }
        return nil
    }
    /// The character just before the cursor, when the app reports its text; nil at the start
    /// of a field or when the app doesn't say.
    static func precedingCharacter(_ target: InsertionTarget) -> Character? {
        guard let element = target.element, let selection = target.selection, selection.location > 0 else { return nil }
        var range = CFRange(location: selection.location - 1, length: 1)
        if let rangeValue = AXValueCreate(.cfRange, &range) {
            var raw: CFTypeRef?
            if AXUIElementCopyParameterizedAttributeValue(element, kAXStringForRangeParameterizedAttribute as CFString, rangeValue, &raw) == .success, let string = raw as? String, let last = string.last { return last }
        }
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &raw) == .success, let value = raw as? String else { return nil }
        let ns = value as NSString
        guard selection.location <= ns.length else { return nil }
        return ns.substring(to: selection.location).last
    }
    static func capture() throws -> InsertionTarget {
        guard AXIsProcessTrusted() else { throw DictationError.message("Enable Accessibility access in Settings before dictating.") }
        guard let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { throw DictationError.message("Focus a text field in another app, then use the shortcut.") }
        var element = focused(pid: app.processIdentifier)
        if element == nil {
            // Chromium/Electron apps (Slack, Claude, Cursor, Chrome…) only publish their
            // accessibility tree once asked. Ask, then look again.
            AXUIElementSetAttributeValue(AXUIElementCreateApplication(app.processIdentifier), "AXManualAccessibility" as CFString, kCFBooleanTrue)
            element = focused(pid: app.processIdentifier)
        }
        if let element {
            var role: CFTypeRef?; AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &role)
            if role as? String == kAXSecureTextFieldSubrole { throw DictationError.message("Dictation is disabled in password fields.") }
        }
        return InsertionTarget(pid: app.processIdentifier, bundle: app.bundleIdentifier ?? "", element: element, selection: element.flatMap(range))
    }
    static func validate(_ target: InsertionTarget) -> Bool {
        guard let current = NSWorkspace.shared.frontmostApplication else { return false }
        let focused = focused(pid: target.pid)
        let same: Bool
        if let expected = target.element, let focused { same = CFEqual(expected, focused) }
        else if target.element == nil { same = true } // The app doesn't report fields; only the same-app check applies.
        else { same = false }
        return InsertionPolicy.mayInsert(originalPID: target.pid, currentPID: current.processIdentifier, sameField: same, originalSelection: target.selection, currentSelection: focused.flatMap(range))
    }
    func insert(_ text: String, target: InsertionTarget, allowClipboard: Bool, stillCurrent: () -> Bool) async throws {
        guard !Task.isCancelled, stillCurrent(), Self.validate(target) else { throw DictationError.message("The target or cursor changed. Text was not inserted; copy it from the menu instead.") }
        // Never replace a user's selection or an entire field value.
        if let selection = target.selection, selection.length != 0 { throw DictationError.message("Text was selected when recording started. To avoid replacing it, copy the result manually.") }
        if let element = target.element {
            var settable: DarwinBoolean = false
            if AXUIElementIsAttributeSettable(element, kAXSelectedTextAttribute as CFString, &settable) == .success, settable.boolValue, target.selection != nil {
                let countBefore = Self.characterCount(element)
                let result = AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFString)
                guard result == .success else { throw DictationError.message("The app did not confirm insertion. No paste retry was attempted, to prevent duplicates. Check the field before copying manually.") }
                // Some apps (Chrome, Electron apps like Claude or Slack) report success without showing
                // the text. Check that the cursor moved or the field grew; if nothing changed at all,
                // paste instead. If something changed but not as expected, don't risk a duplicate.
                let added = text.utf16.count
                // Apps can update a beat late, so look a few times before deciding to paste.
                for _ in 0..<4 {
                    try? await Task.sleep(nanoseconds: 90_000_000)
                    let rangeAfter = Self.range(element), countAfter = Self.characterCount(element)
                    let cursorMoved = target.selection.map { rangeAfter?.location == $0.location + added } ?? false
                    let grew = countBefore.map { countAfter == $0 + added } ?? false
                    if cursorMoved || grew { insertLog.notice("Inserted via accessibility into \(target.bundle, privacy: .public)"); return }
                    let unchanged = countBefore != nil && countAfter == countBefore && rangeAfter?.location == target.selection?.location
                    guard unchanged || (countBefore == nil && rangeAfter == nil) else {
                        insertLog.notice("Accessibility insert into \(target.bundle, privacy: .public) changed the field unexpectedly; not pasting")
                        return
                    }
                }
                insertLog.notice("Accessibility insert into \(target.bundle, privacy: .public) didn't show up; pasting instead")
            }
        }
        // Paste into the same app and field. (Apps that report no field get the same-app check.)
        guard allowClipboard else { throw DictationError.message("This field does not support safe direct insertion. Enable clipboard fallback or copy the result manually.") }
        let board = NSPasteboard.general
        // Materialize all pasteboard representations before replacing anything.
        var snapshot: [[NSPasteboard.PasteboardType: Data]] = []
        for item in board.pasteboardItems ?? [] {
            var values: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types { guard let data = item.data(forType: type) else { throw DictationError.message("Clipboard data could not be preserved. Nothing was changed.") }; values[type] = data }
            snapshot.append(values)
        }
        let before = board.changeCount
        guard Self.validate(target), stillCurrent(), board.changeCount == before else { throw DictationError.message("The target or clipboard changed. Copy the result manually.") }
        let source = CGEventSource(stateID: .combinedSessionState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true), let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else { throw DictationError.message("Could not prepare paste events.") }
        board.clearContents(); guard board.setString(text, forType: .string) else { restore(snapshot, board: board); throw DictationError.message("Could not prepare the clipboard.") }
        let owned = board.changeCount
        down.flags = .maskCommand; up.flags = .maskCommand
        down.post(tap: .cghidEventTap); up.post(tap: .cghidEventTap)
        insertLog.notice("Pasted into \(target.bundle, privacy: .public)")
        // Once dispatched, never retry paste: the target provides no reliable acknowledgement.
        try? await Task.sleep(nanoseconds: 800_000_000)
        if InsertionPolicy.mayRestoreClipboard(ownedChange: owned, currentChange: board.changeCount) { restore(snapshot, board: board) }
    }
    /// Pastes text at the current cursor in whatever app is in front, then restores the clipboard.
    /// Used by “paste last transcript”, where there is no original field to check against.
    static func paste(_ text: String) async throws {
        guard AXIsProcessTrusted() else { throw DictationError.message("Enable Accessibility access in Settings to paste.") }
        let board = NSPasteboard.general
        var snapshot: [[NSPasteboard.PasteboardType: Data]] = []
        for item in board.pasteboardItems ?? [] {
            var values: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types { if let data = item.data(forType: type) { values[type] = data } }
            snapshot.append(values)
        }
        board.clearContents(); guard board.setString(text, forType: .string) else { throw DictationError.message("Could not prepare the clipboard.") }
        let owned = board.changeCount
        postKey(9, flags: .maskCommand)
        try? await Task.sleep(nanoseconds: 800_000_000)
        if InsertionPolicy.mayRestoreClipboard(ownedChange: owned, currentChange: board.changeCount) { TextInsertion().restore(snapshot, board: board) }
    }
    /// Presses Return in the frontmost app (for a spoken “press enter”).
    static func pressReturn() { postKey(36, flags: []) }
    private static func postKey(_ key: CGKeyCode, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .combinedSessionState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true), let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false) else { return }
        down.flags = flags; up.flags = flags
        down.post(tap: .cghidEventTap); up.post(tap: .cghidEventTap)
    }
    private func restore(_ snapshot: [[NSPasteboard.PasteboardType: Data]], board: NSPasteboard) {
        board.clearContents()
        let items = snapshot.map { values -> NSPasteboardItem in let item = NSPasteboardItem(); for (type, data) in values { item.setData(data, forType: type) }; return item }
        if !items.isEmpty { board.writeObjects(items) }
    }
}
