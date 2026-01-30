//
//  HyperDeckClient.swift
//  Synaxis
//
//  Blackmagic HyperDeck Extreme 8K Ethernet Protocol client.
//  Connects via TCP to port 9993 using the text-based HyperDeck protocol.
//  All commands and responses are terminated with \r\n.
//

import Foundation
import Network
import Observation
import OSLog

@MainActor
@Observable
final class HyperDeckClient {
    nonisolated deinit { }

    // MARK: - Observable Properties

    private(set) var isConnected: Bool = false
    private(set) var transportStatus: String = "stopped"
    private(set) var currentTimecode: String = "00:00:00:00"
    private(set) var currentClipName: String = ""
    private(set) var lastError: String?

    var isRecording: Bool { transportStatus == "record" }

    // Slot and clip data retained for camera-file-path matching
    private(set) var slots: [SlotInfo] = []
    private(set) var clips: [ClipInfo] = []
    private(set) var currentClipId: Int?

    // MARK: - Event Callback

    var onEvent: ((ProductionEvent) -> Void)?

    // MARK: - Nested Types

    struct SlotInfo: Identifiable {
        let id: Int
        var status: String
        var volumeName: String
        var recordingTime: Int
        var videoFormat: String
    }

    struct ClipInfo: Identifiable {
        let id: Int
        var name: String
        var startTimecode: String
        var duration: String
    }

    // MARK: - Configuration

    let name: String

    // MARK: - Private State

    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "com.touchdrive.hyperdeck", qos: .userInteractive)
    private var messageBuffer: String = ""
    private var previousTransportStatus: String = "stopped"

    // Transport polling — periodically queries transport info as a reliable
    // fallback when async notifications don't arrive.
    private var pollTask: Task<Void, Never>?

    // Reconnection
    private var reconnectTask: Task<Void, Never>?
    private var reconnectDelay: TimeInterval = 1
    private var shouldReconnect: Bool = false
    private var currentHost: String = ""
    private var currentPort: Int = 9993

    private static let maxReconnectDelay: TimeInterval = 30
    private static let terminator = "\r\n"

    // MARK: - Initialisation

    init(name: String = "HyperDeck") {
        self.name = name
    }

    // MARK: - Public Methods

    /// Establish a TCP connection to the HyperDeck.
    func connect(host: String, port: Int) {
        disconnect()

        currentHost = host
        currentPort = port
        shouldReconnect = true
        reconnectDelay = 1

        lastError = nil
        Log.hyperDeck.info("[\(self.name)] Connecting to \(host):\(port)")

        performConnect(host: host, port: port)
    }

    /// Tear down the connection and stop reconnection attempts.
    func disconnect() {
        shouldReconnect = false
        reconnectTask?.cancel()
        reconnectTask = nil
        stopPolling()
        connection?.stateUpdateHandler = nil
        connection?.cancel()
        connection = nil
        messageBuffer = ""

        if isConnected {
            isConnected = false
            emitConnectionChange(connected: false)
        }
    }

    /// Send `record\r\n` and immediately query transport to confirm.
    func record() {
        sendCommand("record")
        queryTransportAfterDelay()
    }

    /// Send `record: name: {name}\r\n` and immediately query transport to confirm.
    func recordWithName(_ name: String) {
        sendCommand("record: name: \(name)")
        queryTransportAfterDelay()
    }

    /// Send `stop\r\n` and immediately query transport to confirm.
    func stop() {
        sendCommand("stop")
        queryTransportAfterDelay()
    }

    /// Send `play\r\n` and immediately query transport to confirm.
    func play() {
        sendCommand("play")
        queryTransportAfterDelay()
    }

    /// Query transport info after a short delay to let the command take effect.
    private func queryTransportAfterDelay() {
        Task {
            try? await Task.sleep(nanoseconds: 200_000_000)
            queryTransportInfo()
        }
    }

    /// Send `transport info\r\n`.
    func queryTransportInfo() {
        sendCommand("transport info")
    }

    /// Send `clips get\r\n`.
    func queryClipList() {
        sendCommand("clips get")
    }

    /// Send `slot info\r\n`.
    func querySlotInfo() {
        sendCommand("slot info")
    }

    /// Enable async notifications so the HyperDeck pushes transport/slot/config changes.
    func enableNotifications() {
        sendCommand("notify: transport: true slot: true configuration: true")
    }

    // MARK: - Connection Lifecycle

    private func performConnect(host: String, port: Int) {
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(clamping: port)) else {
            let msg = "Invalid port value: \(port)"
            Log.hyperDeck.error("[\(self.name)] \(msg)")
            lastError = msg
            return
        }

        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(host), port: nwPort)

        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true

        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.connectionTimeout = 10
        tcpOptions.enableKeepalive = true
        tcpOptions.keepaliveIdle = 5
        parameters.defaultProtocolStack.transportProtocol = tcpOptions

        let conn = NWConnection(to: endpoint, using: parameters)

        conn.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            Task { @MainActor in
                self.handleStateChange(state)
            }
        }

        connection = conn
        conn.start(queue: queue)
    }

    private func handleStateChange(_ state: NWConnection.State) {
        switch state {
        case .ready:
            Log.hyperDeck.info("[\(self.name)] Connected to \(self.currentHost):\(self.currentPort)")
            isConnected = true
            lastError = nil
            reconnectDelay = 1
            emitConnectionChange(connected: true)
            startReceiving()
            startPolling()
            // The HyperDeck sends a 500 connection info block on connect.
            // After receiving it we enable notifications and query initial state.

        case .failed(let error):
            Log.hyperDeck.error("[\(self.name)] Connection failed: \(error.localizedDescription)")
            let wasConnected = isConnected
            isConnected = false
            lastError = "Connection failed: \(error.localizedDescription)"
            stopPolling()
            connection?.cancel()
            connection = nil
            if wasConnected {
                emitConnectionChange(connected: false)
            }
            scheduleReconnect()

        case .cancelled:
            let wasConnected = isConnected
            isConnected = false
            stopPolling()
            if wasConnected {
                emitConnectionChange(connected: false)
            }

        case .waiting(let error):
            Log.hyperDeck.warning("[\(self.name)] Waiting: \(error.localizedDescription)")
            lastError = "Waiting: \(error.localizedDescription)"

        default:
            break
        }
    }

    // MARK: - Reconnection with Exponential Backoff

    private func scheduleReconnect() {
        guard shouldReconnect else { return }

        let delay = reconnectDelay
        reconnectDelay = min(reconnectDelay * 2, Self.maxReconnectDelay)

        Log.hyperDeck.info("[\(self.name)] Reconnecting in \(delay, format: .fixed(precision: 0))s")

        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            } catch {
                return // Task cancelled
            }
            guard self.shouldReconnect, !self.isConnected else { return }
            Log.hyperDeck.info("[\(self.name)] Attempting reconnect to \(self.currentHost):\(self.currentPort)")
            self.performConnect(host: self.currentHost, port: self.currentPort)
        }
    }

    // MARK: - Transport Polling

    /// Start polling transport info every second. This ensures timecode
    /// and transport status stay updated even if async notifications are
    /// unreliable or unsupported by the HyperDeck firmware.
    private func startPolling() {
        stopPolling()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                } catch {
                    return
                }
                guard let self, self.isConnected else { return }
                self.queryTransportInfo()
            }
        }
    }

    private func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    // MARK: - Send

    private func sendCommand(_ command: String) {
        guard let connection, isConnected else {
            Log.hyperDeck.warning("[\(self.name)] Cannot send, not connected: \(command)")
            lastError = "Not connected"
            return
        }

        let message = command + Self.terminator
        guard let data = message.data(using: .utf8) else {
            Log.hyperDeck.error("[\(self.name)] Failed to encode command: \(command)")
            return
        }

        Log.hyperDeck.debug("[\(self.name)] TX: \(command)")

        connection.send(content: data, completion: .contentProcessed { [weak self] error in
            guard let self, let error else { return }
            Task { @MainActor in
                Log.hyperDeck.error("[\(self.name)] Send failed: \(error.localizedDescription)")
                self.lastError = "Send failed: \(error.localizedDescription)"
            }
        })
    }

    // MARK: - Receive

    private func startReceiving() {
        guard let connection else { return }

        connection.receive(minimumIncompleteLength: 1, maximumLength: 16384) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            Task { @MainActor in
                if let data, let text = String(data: data, encoding: .utf8) {
                    self.processIncomingData(text)
                }

                if let error {
                    Log.hyperDeck.error("[\(self.name)] Receive error: \(error.localizedDescription)")
                    self.lastError = "Receive error: \(error.localizedDescription)"
                }

                if isComplete {
                    // Connection closed by remote
                    Log.hyperDeck.info("[\(self.name)] Remote closed connection")
                    let wasConnected = self.isConnected
                    self.isConnected = false
                    self.connection?.cancel()
                    self.connection = nil
                    if wasConnected {
                        self.emitConnectionChange(connected: false)
                    }
                    self.scheduleReconnect()
                } else if self.connection != nil {
                    self.startReceiving()
                }
            }
        }
    }

    // MARK: - Response Parsing

    /// Buffer incoming data and extract complete response blocks delimited by `\r\n\r\n`.
    private func processIncomingData(_ data: String) {
        messageBuffer += data

        // Complete response blocks are terminated by a blank line (\r\n\r\n).
        while let range = messageBuffer.range(of: "\r\n\r\n") {
            let block = String(messageBuffer[..<range.lowerBound])
            messageBuffer = String(messageBuffer[range.upperBound...])

            if !block.isEmpty {
                parseResponseBlock(block)
            }
        }
    }

    /// Parse a complete response block. The first line contains the status code and label.
    private func parseResponseBlock(_ block: String) {
        let lines = block.components(separatedBy: "\r\n")
        guard let header = lines.first, !header.isEmpty else { return }

        Log.hyperDeck.debug("[\(self.name)] RX: \(header)")

        // Extract 3-digit response code from the header line.
        guard header.count >= 3,
              let code = Int(String(header.prefix(3))) else {
            Log.hyperDeck.warning("[\(self.name)] Malformed response header: \(header)")
            return
        }

        let fields = parseFields(from: Array(lines.dropFirst()))

        switch code {
        case 200:
            // OK -- generic success acknowledgment
            break

        case 202:
            // Slot info response
            parseSlotInfo(fields)

        case 204:
            // Device info
            Log.hyperDeck.info("[\(self.name)] Device info received")

        case 205:
            // Clips info
            parseClipsInfo(Array(lines.dropFirst()))

        case 208:
            // Transport info (synchronous query response)
            parseTransportInfo(fields)

        case 500:
            // Connection info -- sent on initial connect
            Log.hyperDeck.info("[\(self.name)] HyperDeck connection info: \(fields["model"] ?? "unknown model")")
            // Now that we are connected, enable notifications and query initial state.
            enableNotifications()
            Task {
                // Small delay to let the notification subscription register before querying.
                try? await Task.sleep(nanoseconds: 200_000_000)
                queryTransportInfo()
                querySlotInfo()
                queryClipList()
            }

        case 502:
            // Async slot notification
            parseSlotInfo(fields)

        case 508:
            // Async transport notification
            parseTransportInfo(fields)

        default:
            Log.hyperDeck.debug("[\(self.name)] Unhandled response code \(code): \(header)")
        }
    }

    /// Parse `key: value` lines into a dictionary.
    /// HyperDeck uses the format `key: value` where the key itself may contain spaces
    /// (e.g. "display timecode", "clip id", "slot id", "video format").
    /// The value starts after the first `: ` separator.
    private func parseFields(from lines: [String]) -> [String: String] {
        var fields: [String: String] = [:]
        for line in lines {
            guard let separatorRange = line.range(of: ": ") else { continue }
            let key = String(line[..<separatorRange.lowerBound]).trimmingCharacters(in: .whitespaces).lowercased()
            let value = String(line[separatorRange.upperBound...]).trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { continue }
            fields[key] = value
        }
        return fields
    }

    // MARK: - Transport Info

    private func parseTransportInfo(_ fields: [String: String]) {
        let newStatus = fields["status"] ?? transportStatus
        let displayTC = fields["display timecode"]
        let rawTC = fields["timecode"]
        let timecode = displayTC ?? rawTC ?? currentTimecode
        let clipId = fields["clip id"].flatMap(Int.init)

        previousTransportStatus = transportStatus
        transportStatus = newStatus
        currentTimecode = timecode

        if let clipId {
            currentClipId = clipId
            if let clip = clips.first(where: { $0.id == clipId }) {
                currentClipName = clip.name
            }
        }

        Log.hyperDeck.info("[\(self.name)] Transport: \(newStatus) tc=\(timecode) clip=\(self.currentClipName)")

        // Detect record start / stop transitions
        if previousTransportStatus != "record" && newStatus == "record" {
            Log.hyperDeck.info("[\(self.name)] Record STARTED — clip: \(self.currentClipName)")
            let event = ProductionEvent(
                type: .recordStart,
                payload: .recordStart(clipName: currentClipName.isEmpty ? nil : currentClipName),
                timecode: timecode
            )
            onEvent?(event)
        } else if previousTransportStatus == "record" && newStatus != "record" {
            Log.hyperDeck.info("[\(self.name)] Record STOPPED — clip: \(self.currentClipName)")
            let event = ProductionEvent(
                type: .recordStop,
                payload: .recordStop(clipName: currentClipName.isEmpty ? nil : currentClipName),
                timecode: timecode
            )
            onEvent?(event)
        }
    }

    // MARK: - Slot Info

    private func parseSlotInfo(_ fields: [String: String]) {
        let slotId = fields["slot id"].flatMap(Int.init) ?? 1
        let status = fields["status"] ?? ""
        let volumeName = fields["volume name"] ?? ""
        let recordingTime = fields["recording time"].flatMap(Int.init) ?? 0
        let videoFormat = fields["video format"] ?? ""

        let info = SlotInfo(
            id: slotId,
            status: status,
            volumeName: volumeName,
            recordingTime: recordingTime,
            videoFormat: videoFormat
        )

        if let index = slots.firstIndex(where: { $0.id == slotId }) {
            slots[index] = info
        } else {
            slots.append(info)
        }

        Log.hyperDeck.info("[\(self.name)] Slot \(slotId): \(status) volume=\(volumeName)")
    }

    // MARK: - Clips Info

    /// Clip list format:
    /// ```
    /// clip count: 3
    /// 1: My Clip Name 00:00:00:00 00:10:00:00
    /// 2: Another Clip 01:00:00:00 00:05:30:00
    /// ```
    /// Clip names can contain spaces, so we parse from the right: the last two
    /// space-separated tokens are start-timecode and duration (both match the
    /// pattern `\d{2}:\d{2}:\d{2}:\d{2}`). Everything between the id prefix and
    /// the start timecode is the clip name.
    private func parseClipsInfo(_ lines: [String]) {
        var newClips: [ClipInfo] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Skip the "clip count:" line
            if trimmed.lowercased().hasPrefix("clip count") { continue }

            // Expect format: "{id}: {name} {startTC} {duration}"
            guard let colonRange = trimmed.range(of: ": ") else { continue }
            let idString = String(trimmed[..<colonRange.lowerBound]).trimmingCharacters(in: .whitespaces)
            guard let clipId = Int(idString) else { continue }

            let remainder = String(trimmed[colonRange.upperBound...]).trimmingCharacters(in: .whitespaces)

            // Parse from the right to correctly handle clip names with spaces.
            // The last token is the duration timecode, the second-to-last is the start timecode.
            let tokens = remainder.split(separator: " ")
            guard tokens.count >= 3 else { continue }

            let durationToken = String(tokens[tokens.count - 1])
            let startTCToken = String(tokens[tokens.count - 2])

            // Verify both look like timecodes (##:##:##:##)
            guard looksLikeTimecode(durationToken), looksLikeTimecode(startTCToken) else {
                // Fallback: treat first token as name if pattern does not match
                Log.hyperDeck.warning("[\(self.name)] Unexpected clip line format: \(trimmed)")
                continue
            }

            // Everything before the start timecode is the clip name
            let nameTokens = tokens.dropLast(2)
            let clipName = nameTokens.joined(separator: " ")

            guard !clipName.isEmpty else { continue }

            newClips.append(ClipInfo(
                id: clipId,
                name: clipName,
                startTimecode: startTCToken,
                duration: durationToken
            ))
        }

        if !newClips.isEmpty {
            clips = newClips
            Log.hyperDeck.info("[\(self.name)] Parsed \(newClips.count) clip(s)")

            // Update current clip name if we have a clip id
            if let clipId = currentClipId, let clip = clips.first(where: { $0.id == clipId }) {
                currentClipName = clip.name
            }
        }
    }

    /// Returns `true` if the string matches the `##:##:##:##` timecode pattern.
    private func looksLikeTimecode(_ s: String) -> Bool {
        let parts = s.split(separator: ":")
        return parts.count == 4 && parts.allSatisfy({ $0.count >= 1 && $0.count <= 3 && $0.allSatisfy(\.isNumber) })
    }

    // MARK: - Event Emission

    private func emitConnectionChange(connected: Bool) {
        let detail = connected ? "\(currentHost):\(currentPort)" : nil
        let event = ProductionEvent(
            type: .connectionChange,
            payload: .connectionChange(service: name, connected: connected, detail: detail),
            timecode: currentTimecode
        )
        onEvent?(event)
    }
}
