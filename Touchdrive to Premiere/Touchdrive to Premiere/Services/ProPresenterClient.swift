//
//  ProPresenterClient.swift
//  Synaxis
//
//  ProPresenter 7 REST API client with polling-based slide change detection.
//  Pro7 21.1 returns one-shot responses (not chunked streaming), so we poll
//  two endpoints at a fixed interval and compare fingerprints:
//    - /v1/status/slide         → current slide UUID and text
//    - /v1/presentation/slide_index → slide index and presentation name/UUID
//  Slide thumbnails are fetched on change via:
//    - /v1/presentation/{uuid}/thumbnail/{index}
//

import Foundation
import Observation
import OSLog
import AppKit

// MARK: - ProPresenterClient

/// Connects to a ProPresenter 7 instance via its REST API.
/// The port is configured in Pro7 under Settings > Network (the Port field
/// at the top — NOT the TCP/IP port).
/// Polls slide status at a fixed interval to detect slide changes.
@MainActor @Observable
final class ProPresenterClient {
    nonisolated deinit { }

    // MARK: Observable Properties

    private(set) var isConnected: Bool = false
    private(set) var currentPresentationName: String = ""
    private(set) var currentPresentationUUID: String = ""
    private(set) var currentSlideIndex: Int = 0
    private(set) var currentSlideText: String = ""
    private(set) var currentSlideUUID: String = ""
    private(set) var currentSlideThumbnail: NSImage?
    private(set) var lastError: String?

    /// Human-readable name for this ProPresenter machine.
    var machineName: String = "ProPresenter"

    // MARK: Callback

    /// Called on the main actor whenever a production-relevant event occurs.
    var onEvent: ((ProductionEvent) -> Void)?

    // MARK: Private State

    /// Session used for all HTTP requests (version check + polling).
    private var session: URLSession?

    /// The active polling task.
    private var pollingTask: Task<Void, Never>?

    /// Tracks the last emitted slide fingerprint so we can detect true changes.
    private var lastSlideFingerprint: String = ""

    /// Current reconnect delay in seconds (exponential backoff).
    private var reconnectDelay: TimeInterval = 1.0

    /// Whether the client has been intentionally disconnected by the caller.
    private var intentionallyDisconnected: Bool = true

    /// Host of the ProPresenter machine.
    private var host: String = ""

    /// API port (configured in Pro7 Settings > Network, Port field at the top).
    private var port: Int = 0

    /// Number of consecutive poll failures before marking disconnected.
    private var consecutiveFailures: Int = 0

    // MARK: Constants

    private static let initialReconnectDelay: TimeInterval = 1.0
    private static let maxReconnectDelay: TimeInterval = 30.0

    /// Polling interval in nanoseconds (~500ms).
    private static let pollInterval: UInt64 = 500_000_000

    /// After this many consecutive poll failures, mark as disconnected.
    private static let maxConsecutiveFailures: Int = 3

    // MARK: - Public API

    /// Test whether a ProPresenter instance is reachable at the given host/port.
    /// Returns `true` when GET `/version` succeeds with HTTP 200.
    func testConnection(host: String, port: Int) async -> Bool {
        guard let url = buildURL(host: host, port: port, path: "/version") else {
            Log.proPresenter.error("testConnection: invalid URL for \(host):\(port)")
            return false
        }

        let ephemeral = URLSession(configuration: .ephemeral)
        defer { ephemeral.invalidateAndCancel() }

        do {
            let (_, response) = try await ephemeral.data(from: url)
            guard let http = response as? HTTPURLResponse else { return false }
            return http.statusCode == 200
        } catch {
            Log.proPresenter.error("testConnection failed: \(error.localizedDescription)")
            return false
        }
    }

    /// Connect to a ProPresenter instance via the REST API port.
    /// Tests the connection via `/version`, then starts polling for slide changes.
    func connect(host: String, port: Int, name: String = "ProPresenter") {
        disconnect()

        self.host = host
        self.port = port
        self.machineName = name
        self.intentionallyDisconnected = false
        self.reconnectDelay = Self.initialReconnectDelay
        self.consecutiveFailures = 0

        Log.proPresenter.info("Connecting to \(host):\(port)")

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 15
        session = URLSession(configuration: config)

        Task {
            await performInitialConnection()
        }
    }

    /// Cleanly tear down the session and stop polling.
    func disconnect() {
        intentionallyDisconnected = true

        pollingTask?.cancel()
        pollingTask = nil

        session?.invalidateAndCancel()
        session = nil

        if isConnected {
            isConnected = false
            emitConnectionEvent(connected: false, detail: "Disconnected by user")
        }

        Log.proPresenter.info("Disconnected")
    }

    // MARK: - Initial Connection

    private func performInitialConnection() async {
        guard let session = session else { return }
        guard let url = buildURL(host: host, port: port, path: "/version") else {
            handleConnectionFailure("Invalid URL for \(host):\(port)")
            return
        }

        do {
            let (data, response) = try await session.data(from: url)

            guard let http = response as? HTTPURLResponse else {
                handleConnectionFailure("Non-HTTP response from \(host):\(port)")
                return
            }

            guard http.statusCode == 200 else {
                handleConnectionFailure("HTTP \(http.statusCode) from /version")
                return
            }

            // Log version info for diagnostics.
            if let versionJSON = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let name = versionJSON["name"] as? String ?? "Unknown"
                let platform = versionJSON["platform"] as? String ?? "Unknown"
                let apiVersion = versionJSON["api_version"] as? String ?? "Unknown"
                Log.proPresenter.info("Connected: \(name) on \(platform), API \(apiVersion)")
            }

            isConnected = true
            lastError = nil
            consecutiveFailures = 0
            reconnectDelay = Self.initialReconnectDelay
            emitConnectionEvent(connected: true, detail: "\(host):\(port)")

            startPolling()

        } catch {
            handleConnectionFailure("Connection failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Slide Polling

    /// Starts a polling loop that queries Pro7 at a fixed interval.
    /// Uses two endpoints:
    ///   - `/v1/status/slide` → current slide UUID and text
    ///   - `/v1/presentation/slide_index` → slide index and presentation info
    private func startPolling() {
        pollingTask?.cancel()

        pollingTask = Task { [weak self] in
            guard let self else { return }

            Log.proPresenter.info("Starting slide polling")

            while !Task.isCancelled && !self.intentionallyDisconnected {
                await self.pollSlideStatus()
                try? await Task.sleep(nanoseconds: Self.pollInterval)
            }

            Log.proPresenter.info("Slide polling stopped")
        }
    }

    /// Perform a single poll cycle, fetching both slide and index endpoints.
    private func pollSlideStatus() async {
        guard let session = session else { return }

        // Fetch both endpoints concurrently.
        async let slideResult = fetchJSON(session: session, path: "/v1/status/slide")
        async let indexResult = fetchJSON(session: session, path: "/v1/presentation/slide_index")

        let slideFetch = await slideResult
        let indexFetch = await indexResult

        // Handle slide endpoint result.
        switch slideFetch {
        case .failure:
            handlePollFailure("No response from /v1/status/slide")
            return

        case .noContent:
            // HTTP 204 = no slide active. This is valid, not a failure.
            // Reset failure count and clear current slide state.
            resetFailureCount()
            if !lastSlideFingerprint.isEmpty {
                lastSlideFingerprint = ""
                currentPresentationName = ""
                currentPresentationUUID = ""
                currentSlideIndex = 0
                currentSlideText = ""
                currentSlideUUID = ""
                currentSlideThumbnail = nil
            }
            return

        case .success(let slideJSON):
            resetFailureCount()

            // Extract index JSON if available.
            let indexJSON: [String: Any]?
            if case .success(let json) = indexFetch {
                indexJSON = json
            } else {
                indexJSON = nil
            }

            processSlideResponse(slideJSON: slideJSON, indexJSON: indexJSON)
        }
    }

    /// Reset failure count and restore connected state if needed.
    private func resetFailureCount() {
        if consecutiveFailures > 0 {
            consecutiveFailures = 0
            if !isConnected {
                isConnected = true
                lastError = nil
                emitConnectionEvent(connected: true, detail: "\(host):\(port)")
            }
        }
    }

    /// Result from fetching a JSON endpoint.
    private enum FetchResult {
        case success([String: Any])
        case noContent  // HTTP 204 - valid response, no data
        case failure
    }

    /// Fetch a JSON endpoint, returning success with data, noContent for 204, or failure.
    private func fetchJSON(session: URLSession, path: String) async -> FetchResult {
        guard let url = buildURL(host: host, port: port, path: path) else { return .failure }

        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse else { return .failure }

            if http.statusCode == 204 {
                return .noContent
            }
            guard http.statusCode == 200 else {
                return .failure
            }
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                return .success(json)
            }
            return .failure
        } catch {
            if (error as NSError).code == NSURLErrorCancelled { return .failure }
            Log.proPresenter.warning("Failed to fetch \(path): \(error.localizedDescription)")
            return .failure
        }
    }

    /// Handle a polling failure. After several consecutive failures, mark disconnected
    /// and switch to exponential-backoff reconnection.
    private func handlePollFailure(_ message: String) {
        consecutiveFailures += 1

        if consecutiveFailures >= Self.maxConsecutiveFailures {
            Log.proPresenter.error("Slide polling lost connection: \(message)")
            lastError = message
            pollingTask?.cancel()
            pollingTask = nil
            isConnected = false
            emitConnectionEvent(connected: false, detail: message)
            scheduleReconnect()
        } else {
            Log.proPresenter.warning("Poll failure \(self.consecutiveFailures)/\(Self.maxConsecutiveFailures): \(message)")
        }
    }

    // MARK: - Slide Response Parsing

    /// Parse the combined response from both Pro7 endpoints.
    ///
    /// `/v1/status/slide` returns:
    /// ```json
    /// { "current": { "text": "...", "notes": "", "uuid": "..." },
    ///   "next":    { "text": "...", "notes": "", "uuid": "..." } }
    /// ```
    ///
    /// `/v1/presentation/slide_index` returns:
    /// ```json
    /// { "presentation_index": {
    ///     "index": 2,
    ///     "presentation_id": { "uuid": "...", "name": "Center", "index": ... }
    /// } }
    /// ```
    private func processSlideResponse(slideJSON: [String: Any], indexJSON: [String: Any]?) {
        // -- Extract from /v1/status/slide --
        var slideUUID = ""
        var slideText = ""

        if let current = slideJSON["current"] as? [String: Any] {
            slideUUID = current["uuid"] as? String ?? ""
            slideText = current["text"] as? String ?? ""
        }

        // -- Extract from /v1/presentation/slide_index --
        var slideIndex = 0
        var presentationName = ""
        var presentationUUID = ""

        if let indexJSON,
           let presIndex = indexJSON["presentation_index"] as? [String: Any] {
            slideIndex = presIndex["index"] as? Int ?? 0
            if let presId = presIndex["presentation_id"] as? [String: Any] {
                presentationUUID = presId["uuid"] as? String ?? ""
                presentationName = presId["name"] as? String ?? ""
            }
        }

        // -- Build fingerprint: slide UUID (unique per slide) --
        let fingerprint = slideUUID.isEmpty ? slideText : slideUUID

        guard !fingerprint.isEmpty, fingerprint != lastSlideFingerprint else {
            return // No change or empty
        }
        lastSlideFingerprint = fingerprint

        // -- Update observable state --
        currentPresentationName = presentationName
        currentPresentationUUID = presentationUUID
        currentSlideIndex = slideIndex
        currentSlideText = slideText
        currentSlideUUID = slideUUID

        Log.proPresenter.info("Slide change: \"\(presentationName)\" index \(slideIndex) — \(slideText.prefix(40))")

        // -- Fetch thumbnail in background --
        if !presentationUUID.isEmpty {
            Task {
                await fetchThumbnail(presentationUUID: presentationUUID, slideIndex: slideIndex)
            }
        }

        // -- Emit event --
        let event = ProductionEvent(
            type: .slideChange,
            payload: .slideChange(
                presentationName: presentationName,
                slideIndex: slideIndex,
                slideText: slideText,
                machineName: machineName
            )
        )
        onEvent?(event)
    }

    // MARK: - Thumbnail Fetching

    /// Fetch the slide thumbnail image from Pro7.
    /// Endpoint: `/v1/presentation/{presentationUUID}/thumbnail/{slideIndex}`
    private func fetchThumbnail(presentationUUID: String, slideIndex: Int) async {
        guard let session = session else { return }
        let path = "/v1/presentation/\(presentationUUID)/thumbnail/\(slideIndex)"
        guard let url = buildURL(host: host, port: port, path: path) else { return }

        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                Log.proPresenter.warning("Thumbnail fetch failed: HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
                return
            }
            if let image = NSImage(data: data) {
                currentSlideThumbnail = image
                Log.proPresenter.info("Thumbnail fetched (\(data.count) bytes)")
            }
        } catch {
            Log.proPresenter.warning("Thumbnail fetch error: \(error.localizedDescription)")
        }
    }

    // MARK: - Reconnection

    /// Schedule a reconnection attempt with exponential backoff.
    private func scheduleReconnect() {
        guard !intentionallyDisconnected else { return }

        let delay = reconnectDelay
        reconnectDelay = min(reconnectDelay * 2, Self.maxReconnectDelay)

        Log.proPresenter.info("Reconnecting in \(delay, format: .fixed(precision: 1))s")

        Task {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

            guard !self.intentionallyDisconnected else { return }

            // Tear down stale session before retrying.
            self.pollingTask?.cancel()
            self.pollingTask = nil
            self.session?.invalidateAndCancel()
            self.session = nil

            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 10
            config.timeoutIntervalForResource = 15
            self.session = URLSession(configuration: config)

            await self.performInitialConnection()
        }
    }

    // MARK: - Helpers

    private func buildURL(host: String, port: Int, path: String) -> URL? {
        var components = URLComponents()
        components.scheme = "http"
        components.host = host
        components.port = port
        components.path = path
        return components.url
    }

    private func handleConnectionFailure(_ message: String) {
        Log.proPresenter.error("\(message)")
        lastError = message
        isConnected = false
        emitConnectionEvent(connected: false, detail: message)
        scheduleReconnect()
    }

    private func emitConnectionEvent(connected: Bool, detail: String?) {
        let event = ProductionEvent(
            type: .connectionChange,
            payload: .connectionChange(
                service: machineName,
                connected: connected,
                detail: detail
            )
        )
        onEvent?(event)
    }
}
