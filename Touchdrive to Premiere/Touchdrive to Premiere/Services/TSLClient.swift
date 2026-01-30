import Foundation
import Network
import Observation
import OSLog

// MARK: - TSL Protocol Listener

/// TSL UMD 5.0 / 3.1 TCP **listener** for Ross Carbonite switchers.
///
/// Listens on a TCP port for incoming connections from the Carbonite.
/// The Carbonite acts as a TCP client — it connects outbound to the
/// IP/port configured in its Device Configuration panel.
///
/// The listener auto-detects TSL 5.0 vs TSL 3.1 framing and parses
/// Carbonite-style label strings (`source-index:bus-label:source-label`).
///
/// Parsed tally data is fed into a ``BusStateModel`` and program-change
/// events are emitted through the ``onEvent`` callback.
@Observable
final class TSLClient {
    nonisolated deinit { }

    // MARK: - Observable State

    /// True when the TCP listener is actively accepting connections.
    private(set) var isListening = false

    /// True when a Carbonite (or other TSL source) has connected.
    private(set) var isConnected = false

    /// Remote endpoint description (e.g. "10.10.11.11:54321") when connected.
    private(set) var connectedPeer: String?

    /// Human-readable description of the last error, or nil.
    private(set) var lastError: String?

    /// Hex dump of the most recently received raw TCP chunk (for diagnostics UI).
    private(set) var lastRawHex: String = ""

    // MARK: - Callbacks

    /// Fires for every production-relevant state change detected from TSL data.
    var onEvent: ((ProductionEvent) -> Void)?

    // MARK: - Shared Model

    /// The authoritative tally/bus state model that the UI observes.
    let busState: BusStateModel

    // MARK: - Private State

    private var listener: NWListener?
    private var connection: NWConnection?
    private var dataBuffer = Data()
    private var listeningPort: UInt16 = 0

    /// When true, program-cut events are suppressed. Set on new connection
    /// to avoid false cuts from the initial TSL state dump.
    private var suppressingCuts = false
    private var suppressionTask: Task<Void, Never>?

    // MARK: - Init

    init(busState: BusStateModel) {
        self.busState = busState
    }

    // MARK: - Lifecycle

    /// Starts listening for incoming TSL connections on the given port.
    /// The Carbonite should be configured to connect to this Mac's IP
    /// on this port.
    func startListening(port: UInt16) {
        stopListening()

        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            lastError = "Invalid port: \(port)"
            Log.tsl.error("Invalid port number: \(port)")
            return
        }

        listeningPort = port

        do {
            let newListener = try NWListener(using: .tcp, on: nwPort)

            newListener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                self.handleListenerState(state)
            }

            newListener.newConnectionHandler = { [weak self] conn in
                guard let self else { return }
                self.handleIncomingConnection(conn)
            }

            newListener.start(queue: .main)
            listener = newListener

            Log.tsl.info("TSL listener starting on port \(port)")
        } catch {
            lastError = "Failed to start listener: \(error.localizedDescription)"
            Log.tsl.error("TSL listener failed to start: \(error.localizedDescription)")
        }
    }

    /// Tears down the listener and any active connection.
    func stopListening() {
        connection?.cancel()
        connection = nil
        connectedPeer = nil

        listener?.cancel()
        listener = nil

        dataBuffer.removeAll()
        suppressionTask?.cancel()
        suppressionTask = nil
        suppressingCuts = false
        isListening = false
        isConnected = false
        lastError = nil

        Log.tsl.info("TSL listener stopped")
    }

    // Keep the old API name so ConnectionManager compiles without changes.
    func connect(host: String, port: Int) {
        startListening(port: UInt16(clamping: port))
    }

    func disconnect() {
        stopListening()
    }

    // MARK: - Listener State

    private func handleListenerState(_ state: NWListener.State) {
        switch state {
        case .ready:
            isListening = true
            lastError = nil
            Log.tsl.info("TSL listener ready on port \(self.listeningPort)")
            emitConnectionEvent(listening: true)

        case .failed(let error):
            Log.tsl.error("TSL listener failed: \(error.localizedDescription)")
            lastError = "Listener failed: \(error.localizedDescription)"
            isListening = false
            emitConnectionEvent(listening: false)

        case .cancelled:
            Log.tsl.info("TSL listener cancelled")
            isListening = false

        case .waiting(let error):
            Log.tsl.warning("TSL listener waiting: \(error.localizedDescription)")
            lastError = "Waiting: \(error.localizedDescription)"

        case .setup:
            break

        @unknown default:
            break
        }
    }

    // MARK: - Incoming Connections

    private func handleIncomingConnection(_ conn: NWConnection) {
        // Replace any existing connection (only one Carbonite at a time)
        if let old = connection {
            Log.tsl.info("TSL replacing existing connection with new one")
            old.cancel()
        }

        connection = conn
        dataBuffer.removeAll()

        // Reset bus state and suppress cut events during the initial data dump.
        // The Carbonite sends tally for all sources on connect; without this
        // guard every source that is on-program would emit a false "cut" event.
        busState.reset()
        suppressingCuts = true
        suppressionTask?.cancel()
        suppressionTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
            self?.suppressingCuts = false
            Log.tsl.info("TSL initial state suppression ended")
        }

        // Describe the remote peer
        if case .hostPort(let host, let port) = conn.endpoint {
            let peerString = "\(host):\(port)"
            connectedPeer = peerString
            Log.tsl.info("TSL incoming connection from \(peerString)")
        } else {
            connectedPeer = conn.endpoint.debugDescription
        }

        conn.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            self.handleConnectionState(state, connection: conn)
        }

        conn.start(queue: .main)
        receiveLoop(on: conn)
    }

    // MARK: - Connection State

    private func handleConnectionState(_ state: NWConnection.State, connection conn: NWConnection) {
        switch state {
        case .ready:
            isConnected = true
            lastError = nil
            Log.tsl.info("TSL connection ready from \(self.connectedPeer ?? "unknown")")
            emitConnectionEvent(connected: true)

        case .failed(let error):
            Log.tsl.error("TSL connection failed: \(error.localizedDescription)")
            cleanUpConnection(conn)
            emitConnectionEvent(connected: false)

        case .cancelled:
            Log.tsl.info("TSL connection cancelled")
            cleanUpConnection(conn)

        case .preparing, .setup:
            break

        case .waiting(let error):
            Log.tsl.warning("TSL connection waiting: \(error.localizedDescription)")

        @unknown default:
            break
        }
    }

    private func cleanUpConnection(_ conn: NWConnection) {
        if connection === conn {
            connection = nil
            connectedPeer = nil
            isConnected = false
            dataBuffer.removeAll()
        }
    }

    // MARK: - Receive Loop

    private func receiveLoop(on conn: NWConnection) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }

            if let error {
                Log.tsl.error("TSL receive error: \(error.localizedDescription)")
                self.lastError = "Receive error: \(error.localizedDescription)"
                return
            }

            if let data, !data.isEmpty {
                // Update diagnostic hex display
                let hexPrefix = data.prefix(48).map { String(format: "%02X", $0) }.joined(separator: " ")
                let suffix = data.count > 48 ? "..." : ""
                self.lastRawHex = hexPrefix + suffix

                Log.tsl.debug("TSL received \(data.count) bytes: \(hexPrefix)\(suffix)")

                self.dataBuffer.append(data)
                self.processBuffer()
            }

            if isComplete {
                Log.tsl.info("TSL connection stream completed")
                self.cleanUpConnection(conn)
                self.emitConnectionEvent(connected: false)
                // Listener stays up — Carbonite can reconnect
            } else {
                self.receiveLoop(on: conn)
            }
        }
    }

    // MARK: - Protocol Detection & Parsing

    /// Drains the TCP stream buffer, extracting and parsing complete TSL messages.
    private func processBuffer() {
        while dataBuffer.count >= 4 {
            let bytes = [UInt8](dataBuffer.prefix(4))
            let pbc = Int(bytes[0]) | (Int(bytes[1]) << 8)  // little-endian 16-bit
            let version = bytes[2]

            // TSL 5.0: PBC in [10, 1000], version == 0x00, enough data buffered
            let totalMessageLength = pbc + 2  // PBC excludes its own 2 bytes
            if pbc >= 10 && pbc <= 1000 && version == 0x00 && totalMessageLength <= dataBuffer.count {
                let messageData = Data(dataBuffer.prefix(totalMessageLength))
                dataBuffer.removeFirst(totalMessageLength)
                parseTSL5(messageData)
                continue
            }

            // TSL 3.1 fallback: fixed 18-byte messages, detected when PBC looks invalid
            if pbc > 1000 && dataBuffer.count >= 18 {
                let messageData = Data(dataBuffer.prefix(18))
                dataBuffer.removeFirst(18)
                parseTSL31(messageData)
                continue
            }

            // Incomplete or unrecognizable data
            if pbc > 1000 || totalMessageLength > dataBuffer.count {
                if pbc > 1000 {
                    Log.tsl.warning("Clearing TSL buffer: unrecognised framing (PBC=\(pbc))")
                    dataBuffer.removeAll()
                }
                // Otherwise we just need more data; wait for the next receive.
                break
            }

            break
        }
    }

    // MARK: - TSL 5.0 Parser

    /// Parses a single TSL UMD 5.0 message (including the 2-byte PBC prefix).
    ///
    /// Wire format:
    /// ```
    /// [0-1]   PBC          (LE u16, payload byte count excluding this field)
    /// [2]     Version      (0x00)
    /// [3]     Flags
    /// [4-5]   Screen       (LE u16)
    /// [6-7]   Index        (LE u16)
    /// [8-9]   Control      (LE u16, tally brightness bits)
    /// [10-11] TextLength   (LE u16)
    /// [12..]  Text         (UTF-8, fallback UTF-16LE)
    /// ```
    private func parseTSL5(_ data: Data) {
        guard data.count >= 12 else {
            Log.tsl.warning("TSL 5.0 message too short (\(data.count) bytes)")
            return
        }

        let index   = Int(data[6])  | (Int(data[7])  << 8)
        let control = Int(data[8])  | (Int(data[9])  << 8)

        // Tally brightness levels (0-3 per tally):
        //   bits 0-1  = Tally 1 (Program / Red)
        //   bits 2-3  = Tally 2 (Preview / Green)
        let programBrightness = control & 0x03
        let previewBrightness = (control >> 2) & 0x03

        let tally = TallyState(
            program: programBrightness > 0,
            preview: previewBrightness > 0,
            brightness: max(programBrightness, previewBrightness)
        )

        // Extract label text
        var displayText: String?
        if data.count > 12 {
            let textLength = Int(data[10]) | (Int(data[11]) << 8)
            let textEnd = 12 + textLength
            if textLength > 0 && data.count >= textEnd {
                let textData = data[12 ..< textEnd]

                // Try UTF-8 first (most common from Ross gear), then UTF-16LE
                if let utf8 = String(data: textData, encoding: .utf8)?
                    .trimmingCharacters(in: .controlCharacters)
                    .trimmingCharacters(in: .whitespaces),
                   !utf8.isEmpty
                {
                    displayText = utf8
                } else if let utf16 = String(data: textData, encoding: .utf16LittleEndian)?
                    .trimmingCharacters(in: .controlCharacters)
                    .trimmingCharacters(in: .whitespaces),
                          !utf16.isEmpty
                {
                    displayText = utf16
                }
            }
        }

        Log.tsl.debug("TSL 5.0: idx=\(index) pgm=\(tally.program) pvw=\(tally.preview) text=\(displayText ?? "(none)")")

        applyTallyUpdate(index: index, tally: tally, displayText: displayText)
    }

    // MARK: - TSL 3.1 Parser

    /// Parses a single 18-byte TSL UMD 3.1 message.
    ///
    /// Wire format:
    /// ```
    /// [0]     Address   (0-126)
    /// [1]     Control   (bits 0-1 = tally1/program, bits 2-3 = tally2/preview)
    /// [2-17]  Display   (16 ASCII characters, space-padded)
    /// ```
    private func parseTSL31(_ data: Data) {
        guard data.count >= 18 else {
            Log.tsl.warning("TSL 3.1 message too short (\(data.count) bytes)")
            return
        }

        let address = Int(data[0])
        let control = data[1]

        let programBrightness = Int(control & 0x03)
        let previewBrightness = Int((control >> 2) & 0x03)

        let tally = TallyState(
            program: programBrightness > 0,
            preview: previewBrightness > 0,
            brightness: max(programBrightness, previewBrightness)
        )

        // 16-char display field
        let textData = data[2 ..< 18]
        let displayText = String(data: textData, encoding: .utf8)?
            .trimmingCharacters(in: .controlCharacters)
            .trimmingCharacters(in: .whitespaces)

        // TSL 3.1 addresses are 0-based; convert to 1-based index
        let index = address + 1

        Log.tsl.debug("TSL 3.1: addr=\(address) idx=\(index) pgm=\(tally.program) pvw=\(tally.preview) text=\(displayText ?? "(none)")")

        applyTallyUpdate(index: index, tally: tally, displayText: displayText)
    }

    // MARK: - Carbonite Label Parsing

    /// Parses a Carbonite-style TSL label into bus and source components.
    ///
    /// The Carbonite encodes labels as `<source-index>:<bus-label>:<source-label>`,
    /// for example `3:ME1PGM:CAM 1`.  If the label doesn't match this format, the
    /// entire string is treated as the source label with an empty bus label.
    private func parseCarboniteLabel(_ label: String) -> (busLabel: String, sourceLabel: String) {
        let parts = label.split(separator: ":", maxSplits: 2).map(String.init)

        // Expected format:  sourceIndex:busLabel:sourceLabel
        // The leading sourceIndex is redundant (we already have the TSL index), so skip it.
        guard parts.count >= 3 else {
            // Not in Carbonite format; use the whole string as the source label
            return ("", label)
        }

        let busLabel = parts[1]
        let sourceLabel = parts[2]
        return (busLabel, sourceLabel)
    }

    // MARK: - State Update & Event Emission

    /// Feeds a parsed tally update into ``busState`` and emits production events when
    /// the program source changes.
    private func applyTallyUpdate(index: Int, tally: TallyState, displayText: String?) {
        let (busLabel, sourceLabel): (String, String)
        if let text = displayText, !text.isEmpty {
            (busLabel, sourceLabel) = parseCarboniteLabel(text)
        } else {
            (busLabel, sourceLabel) = ("", "Source \(index)")
        }

        let changedBus = busState.update(
            index: index,
            tally: tally,
            busLabel: busLabel,
            sourceLabel: sourceLabel
        )

        // Emit a programCut event when the program source on a bus changes.
        // Suppress during the initial connection burst to avoid false cuts.
        if let bus = changedBus, !suppressingCuts {
            let event = ProductionEvent(
                type: .programCut,
                payload: .programCut(
                    sourceIndex: index,
                    sourceName: sourceLabel,
                    busName: bus
                )
            )
            Log.tsl.info("Program cut: \(sourceLabel) on \(bus) (idx \(index))")
            onEvent?(event)
        } else if let bus = changedBus {
            Log.tsl.debug("Suppressed initial cut: \(sourceLabel) on \(bus) (idx \(index))")
        }
    }

    // MARK: - Connection Events

    private func emitConnectionEvent(listening: Bool) {
        let event = ProductionEvent(
            type: .connectionChange,
            payload: .connectionChange(
                service: "TSL",
                connected: listening,
                detail: listening ? "Listening on port \(listeningPort)" : nil
            )
        )
        onEvent?(event)
    }

    private func emitConnectionEvent(connected: Bool) {
        let event = ProductionEvent(
            type: .connectionChange,
            payload: .connectionChange(
                service: "TSL",
                connected: connected,
                detail: connected ? connectedPeer : nil
            )
        )
        onEvent?(event)
    }
}
