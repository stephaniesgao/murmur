import Foundation

/// Identifies an installed or published build of Murmur.
public struct AppVersion: Equatable, Sendable {
    public let shortVersion: String
    public let build: Int
    public let commit: String?

    public init(shortVersion: String, build: Int, commit: String? = nil) {
        self.shortVersion = shortVersion
        self.build = build
        self.commit = commit?.isEmpty == true ? nil : commit
    }

    public var displayString: String {
        "\(shortVersion) (build \(build))"
    }

    public static func parseSemantic(_ version: String) -> [Int] {
        let trimmed = version.trimmingCharacters(in: .whitespacesAndNewlines)
        let stripped = trimmed.hasPrefix("v") || trimmed.hasPrefix("V") ? String(trimmed.dropFirst()) : trimmed
        let core = stripped.split(separator: "-", maxSplits: 1).first.map(String.init) ?? stripped
        let parts = core.split(separator: ".").map { segment -> Int in
            let digits = segment.prefix { $0.isNumber }
            return Int(digits) ?? 0
        }
        return parts.isEmpty ? [0] : parts
    }

    public func isNewer(than other: AppVersion) -> Bool {
        let lhs = Self.parseSemantic(shortVersion)
        let rhs = Self.parseSemantic(other.shortVersion)
        let count = max(lhs.count, rhs.count)
        for i in 0..<count {
            let l = i < lhs.count ? lhs[i] : 0
            let r = i < rhs.count ? rhs[i] : 0
            if l != r { return l > r }
        }
        return build > other.build
    }
}

/// JSON manifest published alongside Murmur.zip on GitHub Releases.
public struct UpdateManifest: Codable, Equatable, Sendable {
    public let version: String
    public let build: Int
    public let commit: String?
    public let downloadURL: URL
    public let sha256: String
    public let notes: String?
    public let publishedAt: String?

    public init(
        version: String,
        build: Int,
        commit: String? = nil,
        downloadURL: URL,
        sha256: String,
        notes: String? = nil,
        publishedAt: String? = nil
    ) {
        self.version = version
        self.build = build
        self.commit = commit
        self.downloadURL = downloadURL
        self.sha256 = sha256
        self.notes = notes
        self.publishedAt = publishedAt
    }

    public var appVersion: AppVersion {
        AppVersion(shortVersion: version, build: build, commit: commit)
    }

    public var normalizedSHA256: String {
        sha256.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    public func validate(allowLocalHTTP: Bool = false) throws {
        guard !version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DictationError.message("Update manifest is missing a version.")
        }
        guard build > 0 else {
            throw DictationError.message("Update manifest has an invalid build number.")
        }
        guard UpdatePolicy.isAllowedDownloadURL(downloadURL, allowLocalHTTP: allowLocalHTTP) else {
            throw DictationError.message("Update download URL must use HTTPS.")
        }
        let hex = normalizedSHA256
        guard hex.count == 64, hex.allSatisfy({ $0.isHexDigit }) else {
            throw DictationError.message("Update manifest has an invalid SHA-256 checksum.")
        }
    }
}

public enum UpdatePolicy {
    public static let defaultFeedURL = URL(string: "https://github.com/stephaniesgao/murmur/releases/latest/download/update.json")!

    public static func isLocalhost(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host == "localhost" || host == "127.0.0.1" || host == "::1"
    }

    public static func isAllowedFeedURL(_ url: URL) -> Bool {
        switch url.scheme?.lowercased() {
        case "https": return true
        case "http": return isLocalhost(url)
        default: return false
        }
    }

    public static func isAllowedDownloadURL(_ url: URL, allowLocalHTTP: Bool = false) -> Bool {
        switch url.scheme?.lowercased() {
        case "https": return true
        case "http": return allowLocalHTTP && isLocalhost(url)
        default: return false
        }
    }

    public static func isUpdateAvailable(current: AppVersion, manifest: UpdateManifest) -> Bool {
        manifest.appVersion.isNewer(than: current)
    }

    /// Arguments for `/bin/sh` to wait for the current process to exit, atomically swap the
    /// staged app bundle into place, roll back on failure, clean up, and relaunch.
    /// Paths are passed as positional parameters ($1..$4), never interpolated into the script.
    public static func installHelperArguments(
        pid: Int32,
        stagedAppPath: String,
        targetAppPath: String,
        stagingRootPath: String
    ) -> [String] {
        let script = """
        trap '' HUP
        pid="$1"
        staged="$2"
        target="$3"
        staging_root="$4"
        backup="${staging_root}/previous.app"
        while /bin/kill -0 "$pid" 2>/dev/null; do /bin/sleep 0.2; done
        if ! /bin/mv "$target" "$backup"; then
          /bin/rm -rf "$staging_root"
          exit 1
        fi
        if ! /bin/mv "$staged" "$target"; then
          if /bin/mv "$backup" "$target" 2>/dev/null; then
            /bin/rm -rf "$staging_root"
          fi
          exit 1
        fi
        /bin/rm -rf "$staging_root"
        /usr/bin/open "$target"
        """
        return ["-c", script, "murmur-update", String(pid), stagedAppPath, targetAppPath, stagingRootPath]
    }
}
