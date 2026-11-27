import AppKit
import CryptoKit
import Foundation
import MurmurCore
import os

private let updateLog = Logger(subsystem: "com.steph.murmur", category: "updates")

enum UpdateState: Equatable {
    case idle
    case checking
    case upToDate
    case available(UpdateManifest)
    case downloading(Double)
    case installing
    case failed(String)

    var availableUpdate: UpdateManifest? {
        if case .available(let manifest) = self { return manifest }
        return nil
    }

    var isBusy: Bool {
        switch self {
        case .checking, .downloading, .installing: return true
        default: return false
        }
    }
}

@MainActor final class UpdateManager: ObservableObject {
    @Published private(set) var state: UpdateState = .idle
    @Published private(set) var lastChecked: Date?
    let currentVersion: AppVersion
    var onAvailabilityChange: (() -> Void)?

    private var activeTask: Task<Void, Never>?
    private var periodicTask: Task<Void, Never>?
    private var autoCheckEnabled = false

    private static let checkIntervalSeconds: UInt64 = 4 * 60 * 60
    private static let startupDelaySeconds: UInt64 = 4

    init(bundle: Bundle = .main) {
        let short = (bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0.0.0"
        let buildString = (bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? "0"
        let commit = bundle.object(forInfoDictionaryKey: "MurmurCommitSHA") as? String
        self.currentVersion = AppVersion(shortVersion: short, build: Int(buildString) ?? 0, commit: commit)
    }

    var feedURL: URL {
        let candidates = [
            ProcessInfo.processInfo.environment["MURMUR_UPDATE_URL"],
            UserDefaults.standard.string(forKey: "MurmurUpdateURL"),
            Bundle.main.object(forInfoDictionaryKey: "MurmurUpdateURL") as? String,
        ]
        for raw in candidates {
            if let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
               !trimmed.isEmpty,
               let url = URL(string: trimmed),
               UpdatePolicy.isAllowedFeedURL(url) {
                return url
            }
        }
        return UpdatePolicy.defaultFeedURL
    }

    func setAutoCheck(_ enabled: Bool) {
        guard enabled != autoCheckEnabled else { return }
        autoCheckEnabled = enabled
        periodicTask?.cancel()
        periodicTask = nil
        guard enabled else { return }

        let initialDelay: UInt64
        if let raw = ProcessInfo.processInfo.environment["MURMUR_UPDATE_CHECK_DELAY"], let parsed = UInt64(raw) {
            initialDelay = parsed
        } else {
            initialDelay = Self.startupDelaySeconds
        }

        periodicTask = Task { [weak self] in
            if initialDelay > 0 {
                try? await Task.sleep(nanoseconds: initialDelay * 1_000_000_000)
            }
            while !Task.isCancelled {
                guard let self else { return }
                await self.performCheck(userInitiated: false)
                try? await Task.sleep(nanoseconds: Self.checkIntervalSeconds * 1_000_000_000)
            }
        }
    }

    func checkForUpdates(userInitiated: Bool = true) {
        guard !state.isBusy else { return }
        activeTask?.cancel()
        activeTask = Task { [weak self] in
            await self?.performCheck(userInitiated: userInitiated)
        }
    }

    private func performCheck(userInitiated: Bool) async {
        guard !state.isBusy else { return }
        let url = feedURL
        if userInitiated { state = .checking }
        updateLog.notice("Checking for updates from \(url.absoluteString, privacy: .public) (current: \(self.currentVersion.displayString, privacy: .public))")

        do {
            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("Murmur/\(currentVersion.shortVersion)", forHTTPHeaderField: "User-Agent")

            let (data, response) = try await URLSession.shared.data(for: request)
            guard !Task.isCancelled else { return }
            guard let http = response as? HTTPURLResponse else {
                throw DictationError.message("Unexpected response while checking for updates.")
            }
            if http.statusCode == 404 {
                lastChecked = Date()
                if userInitiated { state = .upToDate }
                updateLog.notice("No published release manifest found yet (404)")
                return
            }
            guard (200..<300).contains(http.statusCode) else {
                throw DictationError.message("Update server returned status \(http.statusCode).")
            }

            let manifest = try JSONDecoder().decode(UpdateManifest.self, from: data)
            try manifest.validate(allowLocalHTTP: UpdatePolicy.isLocalhost(url))
            lastChecked = Date()

            if UpdatePolicy.isUpdateAvailable(current: currentVersion, manifest: manifest) {
                updateLog.notice("Update available: \(manifest.appVersion.displayString, privacy: .public)")
                state = .available(manifest)
                onAvailabilityChange?()
            } else {
                updateLog.notice("Murmur is up to date (\(self.currentVersion.displayString, privacy: .public))")
                if userInitiated || state.availableUpdate != nil {
                    state = .upToDate
                    onAvailabilityChange?()
                }
            }
        } catch {
            guard !Task.isCancelled else { return }
            updateLog.notice("Update check failed: \(error.localizedDescription, privacy: .public)")
            if userInitiated {
                state = .failed(error.localizedDescription)
            }
        }
    }

    func installAvailableUpdate(isBusy: @escaping () -> Bool, beforeTerminate: @escaping () -> Void) {
        guard case .available(let manifest) = state else { return }
        activeTask?.cancel()
        activeTask = Task { [weak self] in
            await self?.performInstall(manifest: manifest, isBusy: isBusy, beforeTerminate: beforeTerminate)
        }
    }

    private func performInstall(manifest: UpdateManifest, isBusy: @escaping () -> Bool, beforeTerminate: @escaping () -> Void) async {
        let targetApp = Bundle.main.bundleURL
        guard targetApp.pathExtension == "app" else {
            state = .failed("Updates can only be installed when running from Murmur.app.")
            return
        }
        let parentDirectory = targetApp.deletingLastPathComponent()
        guard FileManager.default.isWritableFile(atPath: parentDirectory.path) else {
            state = .failed("Move Murmur.app to Applications (or a writable folder) to install updates automatically.")
            return
        }

        let stagingRoot = parentDirectory.appendingPathComponent(".murmur-update-\(UUID().uuidString)", isDirectory: true)
        var handoffStarted = false
        defer {
            if !handoffStarted {
                try? FileManager.default.removeItem(at: stagingRoot)
            }
        }

        do {
            try FileManager.default.createDirectory(at: stagingRoot, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let zipURL = stagingRoot.appendingPathComponent("Murmur.zip")
            state = .downloading(0)

            let computedSHA = try await download(url: manifest.downloadURL, to: zipURL)
            guard computedSHA == manifest.normalizedSHA256 else {
                throw DictationError.message("Downloaded update failed checksum verification.")
            }

            state = .installing
            let extractDir = stagingRoot.appendingPathComponent("extracted", isDirectory: true)
            try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)

            try await runProcess("/usr/bin/ditto", arguments: ["-x", "-k", zipURL.path, extractDir.path], failureMessage: "Could not unpack the downloaded update.")
            try? FileManager.default.removeItem(at: zipURL)

            let stagedApp = try locateAppBundle(in: extractDir)
            try verifyStagedBundle(stagedApp, expected: manifest)

            // Strip any quarantine attribute defensively before verifying and relaunching.
            _ = try? await runProcess("/usr/bin/xattr", arguments: ["-dr", "com.apple.quarantine", stagedApp.path], failureMessage: "")
            try await runProcess("/usr/bin/codesign", arguments: ["--verify", "--deep", "--strict", stagedApp.path], failureMessage: "The downloaded app failed code signature verification.")

            // Wait for any dictation or note capture started during the download to finish before restarting.
            while isBusy() {
                try Task.checkCancellation()
                try await Task.sleep(nanoseconds: 250_000_000)
            }

            let helper = Process()
            helper.executableURL = URL(fileURLWithPath: "/bin/sh")
            helper.arguments = UpdatePolicy.installHelperArguments(
                pid: ProcessInfo.processInfo.processIdentifier,
                stagedAppPath: stagedApp.path,
                targetAppPath: targetApp.path,
                stagingRootPath: stagingRoot.path
            )
            try helper.run()
            handoffStarted = true
            updateLog.notice("Handed off update install for \(manifest.appVersion.displayString, privacy: .public); restarting")
            beforeTerminate()
            NSApp.terminate(nil)
        } catch {
            updateLog.notice("Update install failed: \(error.localizedDescription, privacy: .public)")
            state = .failed(error.localizedDescription)
        }
    }

    private func download(url: URL, to destination: URL) async throws -> String {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 120)
        request.setValue("Murmur/\(currentVersion.shortVersion)", forHTTPHeaderField: "User-Agent")

        let downloader = UpdateDownloader { [weak self] fraction in
            Task { @MainActor in self?.state = .downloading(fraction) }
        }
        try await downloader.download(request: request, to: destination)
        state = .downloading(1)
        return try Self.sha256(of: destination)
    }

    private static func sha256(of fileURL: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk = try handle.read(upToCount: 262_144) ?? Data()
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func locateAppBundle(in directory: URL) throws -> URL {
        let direct = directory.appendingPathComponent("Murmur.app")
        if FileManager.default.fileExists(atPath: direct.path) { return direct }
        let items = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        if let app = items.first(where: { $0.pathExtension == "app" }) { return app }
        throw DictationError.message("The downloaded archive did not contain Murmur.app.")
    }

    private func verifyStagedBundle(_ appURL: URL, expected: UpdateManifest) throws {
        let plistURL = appURL.appendingPathComponent("Contents/Info.plist")
        let data = try Data(contentsOf: plistURL)
        guard let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw DictationError.message("The downloaded app is missing a valid Info.plist.")
        }
        guard (plist["CFBundleIdentifier"] as? String) == "com.steph.murmur" else {
            throw DictationError.message("The downloaded app has an unexpected bundle identifier.")
        }
        let short = (plist["CFBundleShortVersionString"] as? String) ?? ""
        let build = Int((plist["CFBundleVersion"] as? String) ?? "") ?? 0
        let stagedVersion = AppVersion(shortVersion: short, build: build)
        guard stagedVersion.isNewer(than: currentVersion) else {
            throw DictationError.message("The downloaded app (\(stagedVersion.displayString)) is not newer than the installed copy.")
        }
        if stagedVersion.shortVersion != expected.version || stagedVersion.build != expected.build {
            updateLog.notice("Staged app version \(stagedVersion.displayString, privacy: .public) differs from manifest \(expected.appVersion.displayString, privacy: .public)")
        }
    }

    private func runProcess(_ path: String, arguments: [String], failureMessage: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = arguments
            process.standardOutput = Pipe()
            process.standardError = Pipe()
            process.terminationHandler = { proc in
                if proc.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: DictationError.message(failureMessage.isEmpty ? "Command failed (\(proc.terminationStatus))." : failureMessage))
                }
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

private final class UpdateDownloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let onProgress: @Sendable (Double) -> Void
    private var destination: URL?
    private var continuation: CheckedContinuation<Void, Error>?
    private var lastReported: Double = -1
    private var session: URLSession?

    init(onProgress: @escaping @Sendable (Double) -> Void) {
        self.onProgress = onProgress
    }

    func download(request: URLRequest, to destination: URL) async throws {
        self.destination = destination
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.continuation = continuation
            let config = URLSessionConfiguration.ephemeral
            let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
            self.session = session
            session.downloadTask(with: request).resume()
        }
    }

    private func finish(_ result: Result<Void, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        session?.finishTasksAndInvalidate()
        session = nil
        switch result {
        case .success: continuation.resume()
        case .failure(let error): continuation.resume(throwing: error)
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let fraction = min(1, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
        if fraction - lastReported >= 0.02 {
            lastReported = fraction
            onProgress(fraction)
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        if let http = downloadTask.response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            finish(.failure(DictationError.message("Could not download the update archive (status \(http.statusCode)).")))
            return
        }
        guard let destination else {
            finish(.failure(DictationError.message("Missing download destination.")))
            return
        }
        do {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: location, to: destination)
            finish(.success(()))
        } catch {
            finish(.failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { finish(.failure(error)) }
    }
}

