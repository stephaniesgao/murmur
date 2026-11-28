import AppKit
import SwiftUI
import Combine
import MurmurCore
import os

private let launchLog = Logger(subsystem: "com.steph.murmur", category: "launch")

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var controller: DictationController!
    private var store: Store!
    private var updater: UpdateManager!
    private var updateSettingSubscription: AnyCancellable?
    private var overlay: Overlay!
    private var settingsWindow: NSWindow?
    private var notesWindow: NSWindow?
    private static let reopenNotification = Notification.Name("com.steph.murmur.showSettings")
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if let existing = NSRunningApplication.runningApplications(withBundleIdentifier: "com.steph.murmur").first(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            launchLog.notice("Another copy is already running; asking it to show Settings")
            // This copy was opened by the user, so it holds focus. Hand that focus to the
            // running copy before asking it to show Settings; otherwise macOS refuses its
            // activation and the window opens behind the user's current app.
            if #available(macOS 14.0, *) { NSApp.yieldActivation(to: existing) }
            DistributedNotificationCenter.default().postNotificationName(Self.reopenNotification, object: nil, userInfo: nil, deliverImmediately: true)
            existing.activate(options: [.activateAllWindows])
            NSApp.terminate(nil)
            return
        }
        // Menu-bar apps are usually inactive, and AppKit suspends distributed notifications
        // for inactive apps, so this observer must ask for immediate delivery.
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(handleReopenNotification(_:)), name: Self.reopenNotification, object: nil, suspensionBehavior: .deliverImmediately)
        store = Store(); let models = SpeechModelManager(); controller = DictationController(store: store, models: models); models.prepare(); overlay = Overlay(controller: controller)
        updater = UpdateManager()
        updater.setAutoCheck(store.settings.autoCheckUpdates)
        updateSettingSubscription = store.$settings.map(\.autoCheckUpdates).removeDuplicates().sink { [weak self] enabled in
            self?.updater.setAutoCheck(enabled)
        }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Murmur dictation")
        statusItem.button?.toolTip = "Murmur · voice dictation"
        let menu = NSMenu(); let item = NSMenuItem()
        let menuHost = NSHostingView(rootView: MenuView(
            controller: controller, store: store, updater: updater,
            openSettings: { [weak self] in menu.cancelTracking(); self?.showSettings() },
            openNotes: { [weak self] in menu.cancelTracking(); self?.showNotes() },
            closeMenu: { menu.cancelTracking() }
        ))
        menuHost.frame = NSRect(x: 0, y: 0, width: 310, height: 470)
        item.view = menuHost; menu.addItem(item); statusItem.menu = menu
        updater.onAvailabilityChange = { [weak self] in
            guard let self else { return }
            let hasUpdate = self.updater.state.availableUpdate != nil
            self.statusItem.button?.toolTip = hasUpdate ? "Murmur · update available" : "Murmur · voice dictation"
            menuHost.frame = NSRect(x: 0, y: 0, width: 310, height: hasUpdate ? 530 : 470)
        }
        controller.onStatusChange = { [weak self] in
            guard let self else { return }; self.overlay.update(phase: self.controller.phase)
            self.statusItem.button?.image = NSImage(systemSymbolName: self.controller.phase == .recording ? "mic.fill" : "waveform", accessibilityDescription: "Murmur \(self.controller.phase.rawValue)")
        }
        // A deliberate launch must have a visible result, including after setup.
        showSettings()
    }
    @objc private func handleReopenNotification(_ notification: Notification) {
        launchLog.notice("Received request from another copy to show Settings")
        Task { @MainActor in self.showSettings() }
    }
    func showSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 780, height: 600), styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView], backing: .buffered, defer: false)
            window.title = "Murmur"; window.isReleasedWhenClosed = false
            // Let the custom sidebar run under a transparent title bar.
            window.titlebarAppearsTransparent = true; window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            // Open on the Space the user is looking at, not the one it was last on, including
            // over a full-screen app; otherwise it stays hidden on the desktop Space.
            window.collectionBehavior.formUnion([.moveToActiveSpace, .fullScreenAuxiliary])
            window.contentView = NSHostingView(rootView: SettingsView(controller: controller, store: store, updater: updater)); window.center(); settingsWindow = window
        }
        guard let window = settingsWindow else { return }
        present(window)
        launchLog.notice("Showed Settings (app active: \(NSApp.isActive, privacy: .public))")
    }
    private func showNotes() {
        if notesWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 500), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "Murmur Notes"
            window.isReleasedWhenClosed = false
            window.contentMinSize = NSSize(width: 580, height: 380)
            window.collectionBehavior.formUnion([.moveToActiveSpace, .fullScreenAuxiliary])
            window.contentView = NSHostingView(rootView: NotesView(controller: controller, store: store))
            window.center()
            notesWindow = window
        }
        if let window = notesWindow { present(window) }
    }
    private func present(_ window: NSWindow) {
        if window.isMiniaturized { window.deminiaturize(nil) }
        if #available(macOS 14.0, *) { NSApp.activate() } else { NSApp.activate(ignoringOtherApps: true) }
        window.makeKeyAndOrderFront(nil)
        // Activation can still be refused for a background menu-bar app; make sure the
        // window is at least in front of other apps' windows so it is never hidden behind them.
        window.orderFrontRegardless()
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        launchLog.notice("Reopened from Finder or Dock")
        showSettings()
        return true
    }
    func applicationWillTerminate(_ notification: Notification) { controller?.cancel(); controller?.keyboard.stop() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
@main struct MurmurMain {
    @MainActor static func main() {
        if CommandLine.arguments.contains("--check-speech-support") {
            let choice = WhisperModelChoice.saved; print("Whisper model \(choice.rawValue): \(SpeechModelManager.isDownloaded(choice) ? "downloaded" : "not downloaded") at \(SpeechModelManager.modelFolder(for: choice).path)"); print("Automatic microphone: \(AudioRecorder.automaticDescription)")
            return
        }
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
    }
}
