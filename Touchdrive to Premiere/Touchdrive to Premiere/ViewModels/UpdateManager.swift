//
//  UpdateManager.swift
//  Synaxis
//
//  Manages checking for and applying app updates from GitHub Releases.
//

import Foundation
import AppKit
import OSLog

/// Manages checking for and applying app updates from GitHub Releases.
@MainActor
@Observable
final class UpdateManager {
    nonisolated deinit { }

    // MARK: - Observable State

    private(set) var isChecking: Bool = false
    private(set) var availableUpdate: GitHubRelease?
    private(set) var lastCheckDate: Date?
    private(set) var lastError: String?
    private(set) var isDownloading: Bool = false
    private(set) var downloadProgress: Double = 0
    private(set) var isInstalling: Bool = false

    // MARK: - Settings (UserDefaults-backed)

    var autoCheckEnabled: Bool {
        didSet { UserDefaults.standard.set(autoCheckEnabled, forKey: Keys.autoCheckEnabled) }
    }

    var includePreReleases: Bool {
        didSet { UserDefaults.standard.set(includePreReleases, forKey: Keys.includePreReleases) }
    }

    // MARK: - Constants

    private static let repoOwner = "NorthwoodsCommunityChurch"
    private static let repoName = "Synaxis"
    private static let assetPrefix = "Synaxis-"
    private static let assetSuffix = "-aarch64.zip"

    private static let checkCacheInterval: TimeInterval = 900 // 15 minutes
    private static let initialCheckDelay: UInt64 = 5_000_000_000 // 5 seconds

    // MARK: - Private

    private var session: URLSession
    private var checkTask: Task<Void, Never>?
    private var downloadTask: Task<Void, Never>?

    // MARK: - Init

    init() {
        let defaults = UserDefaults.standard
        defaults.register(defaults: [
            Keys.autoCheckEnabled: true,
            Keys.includePreReleases: false
        ])
        autoCheckEnabled = defaults.bool(forKey: Keys.autoCheckEnabled)
        includePreReleases = defaults.bool(forKey: Keys.includePreReleases)

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        session = URLSession(configuration: config)

        if autoCheckEnabled {
            scheduleInitialCheck()
        }
    }

    // MARK: - Public API

    /// Check for updates. If `force` is false, respects the 15-minute cache.
    func checkForUpdates(force: Bool = false) {
        guard !isChecking else { return }

        // Respect cache unless forced
        if !force, let lastCheck = lastCheckDate,
           Date().timeIntervalSince(lastCheck) < Self.checkCacheInterval {
            Log.update.info("Skipping update check (cached)")
            return
        }

        checkTask?.cancel()
        checkTask = Task {
            await performUpdateCheck()
        }
    }

    /// Download and install the available update.
    func downloadAndInstallUpdate() {
        guard let release = availableUpdate,
              let asset = findAsset(in: release) else {
            lastError = "No update available"
            return
        }

        downloadTask?.cancel()
        downloadTask = Task {
            await performDownloadAndInstall(release: release, asset: asset)
        }
    }

    /// Dismiss the available update notification.
    func dismissAvailableUpdate() {
        availableUpdate = nil
    }

    // MARK: - Private Implementation

    private func scheduleInitialCheck() {
        Task {
            try? await Task.sleep(nanoseconds: Self.initialCheckDelay)
            guard !Task.isCancelled else { return }
            checkForUpdates()
        }
    }

    private func performUpdateCheck() async {
        isChecking = true
        lastError = nil
        defer { isChecking = false }

        Log.update.info("Checking for updates...")

        let urlString = "https://api.github.com/repos/\(Self.repoOwner)/\(Self.repoName)/releases"
        guard let url = URL(string: urlString) else {
            lastError = "Invalid API URL"
            return
        }

        do {
            var request = URLRequest(url: url)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

            let (data, response) = try await session.data(for: request)

            guard let http = response as? HTTPURLResponse else {
                lastError = "Invalid response"
                return
            }

            guard http.statusCode == 200 else {
                if http.statusCode == 403 {
                    lastError = "Rate limited (60 req/hour)"
                } else if http.statusCode == 404 {
                    lastError = "Repository not found"
                } else {
                    lastError = "HTTP \(http.statusCode)"
                }
                Log.update.error("Update check failed: \(self.lastError ?? "unknown")")
                return
            }

            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            decoder.dateDecodingStrategy = .iso8601
            let releases = try decoder.decode([GitHubRelease].self, from: data)

            lastCheckDate = Date()

            // Find the latest applicable release
            let candidates = releases.filter { release in
                // Filter pre-releases unless opted in
                if release.prerelease && !includePreReleases {
                    return false
                }
                // Must have a matching asset
                return findAsset(in: release) != nil
            }

            guard let latest = candidates.first,
                  let latestVersion = Version(string: latest.tagName),
                  latestVersion > Version.current else {
                Log.update.info("No update available (current: \(Version.current))")
                availableUpdate = nil
                return
            }

            Log.update.info("Update available: \(latest.tagName)")
            availableUpdate = latest

        } catch {
            if (error as NSError).code == NSURLErrorCancelled { return }
            lastError = error.localizedDescription
            Log.update.error("Update check error: \(error.localizedDescription)")
        }
    }

    private func findAsset(in release: GitHubRelease) -> GitHubAsset? {
        release.assets.first { asset in
            asset.name.hasPrefix(Self.assetPrefix) && asset.name.hasSuffix(Self.assetSuffix)
        }
    }

    private func performDownloadAndInstall(release: GitHubRelease, asset: GitHubAsset) async {
        isDownloading = true
        downloadProgress = 0
        lastError = nil
        defer {
            isDownloading = false
            downloadProgress = 0
        }

        Log.update.info("Downloading update: \(asset.name)")

        do {
            // Download to temp directory
            let tempDir = FileManager.default.temporaryDirectory
            let zipPath = tempDir.appendingPathComponent(asset.name)

            // Remove existing file if present
            try? FileManager.default.removeItem(at: zipPath)

            let (localURL, _) = try await session.download(from: asset.browserDownloadUrl)
            try FileManager.default.moveItem(at: localURL, to: zipPath)

            Log.update.info("Download complete, extracting...")

            // Extract zip
            let extractDir = tempDir.appendingPathComponent("SynaxisUpdate-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)

            let unzipProcess = Process()
            unzipProcess.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            unzipProcess.arguments = ["-q", zipPath.path, "-d", extractDir.path]
            try unzipProcess.run()
            unzipProcess.waitUntilExit()

            guard unzipProcess.terminationStatus == 0 else {
                lastError = "Failed to extract update (exit code \(unzipProcess.terminationStatus))"
                Log.update.error("Unzip failed with exit code \(unzipProcess.terminationStatus)")
                return
            }

            // Find the .app in extracted contents
            let contents = try FileManager.default.contentsOfDirectory(at: extractDir, includingPropertiesForKeys: nil)
            guard let newAppURL = contents.first(where: { $0.pathExtension == "app" }) else {
                lastError = "No app found in update package"
                Log.update.error("No .app bundle found in extracted contents")
                return
            }

            // Get current app path
            let currentAppURL = Bundle.main.bundleURL

            Log.update.info("Installing update from \(newAppURL.path) to \(currentAppURL.path)")

            // Install via trampoline
            isInstalling = true
            await installViaTrampoline(newApp: newAppURL, currentApp: currentAppURL, extractDir: extractDir, zipPath: zipPath)

        } catch {
            lastError = error.localizedDescription
            Log.update.error("Download/install error: \(error.localizedDescription)")
        }
    }

    private func installViaTrampoline(newApp: URL, currentApp: URL, extractDir: URL, zipPath: URL) async {
        let pid = ProcessInfo.processInfo.processIdentifier
        let trampolineScript = """
        #!/bin/bash
        # Synaxis Update Trampoline
        # Wait for app to exit
        while kill -0 \(pid) 2>/dev/null; do
            sleep 0.5
        done

        # Small delay to ensure clean exit
        sleep 1

        # Remove old app
        rm -rf "\(currentApp.path)"

        # Move new app into place
        mv "\(newApp.path)" "\(currentApp.path)"

        # Re-sign ad hoc
        codesign --force --deep --sign - "\(currentApp.path)" 2>/dev/null

        # Relaunch
        open "\(currentApp.path)"

        # Cleanup
        rm -rf "\(extractDir.path)"
        rm -f "\(zipPath.path)"
        rm -- "$0"
        """

        let tempDir = FileManager.default.temporaryDirectory
        let scriptPath = tempDir.appendingPathComponent("synaxis-update-\(UUID().uuidString).sh")

        do {
            try trampolineScript.write(to: scriptPath, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptPath.path)

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = [scriptPath.path]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()

            Log.update.info("Trampoline launched, terminating app")

            // Terminate the app
            NSApplication.shared.terminate(nil)

        } catch {
            lastError = "Failed to launch update installer: \(error.localizedDescription)"
            Log.update.error("Trampoline error: \(error.localizedDescription)")
            isInstalling = false
        }
    }

    // MARK: - UserDefaults Keys

    private enum Keys {
        static let autoCheckEnabled = "updateAutoCheckEnabled"
        static let includePreReleases = "updateIncludePreReleases"
    }
}

// MARK: - GitHub API Models

struct GitHubRelease: Codable, Identifiable {
    let id: Int
    let tagName: String
    let name: String
    let body: String?
    let prerelease: Bool
    let publishedAt: Date
    let assets: [GitHubAsset]
}

struct GitHubAsset: Codable, Identifiable {
    let id: Int
    let name: String
    let browserDownloadUrl: URL
    let size: Int
}
