import Foundation
import Network
import Observation
import OSLog

// MARK: - FTP Server

@Observable
final class FTPServer {
    nonisolated deinit { }

    // MARK: - Observable State

    private(set) var isListening = false
    private(set) var activeSessionCount = 0
    private(set) var lastError: String?
    private(set) var recentTransfers: [FTPTransferStatus] = []

    // MARK: - Configuration

    var baseTransferPath: String = ""
    var basePathURL: URL?

    /// Global FTP credentials (single username/password for all connections).
    var username: String = ""
    var password: String = ""

    // MARK: - Callbacks

    var onTransferComplete: ((ProductionEvent) -> Void)?

    // MARK: - Private State

    private var listener: NWListener?
    private var sessions: [UUID: FTPSession] = [:]
    private var listeningPort: UInt16 = 0

    // MARK: - Lifecycle

    func startListening(port: UInt16) {
        stopListening()

        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            lastError = "Invalid port: \(port)"
            Log.ftp.error("Invalid FTP port: \(port)")
            return
        }

        listeningPort = port

        do {
            // Use TCP parameters that support both IPv4 and IPv6
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            let newListener = try NWListener(using: parameters, on: nwPort)

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

            Log.ftp.info("FTP server starting on port \(port)")
        } catch {
            lastError = "Failed to start FTP server: \(error.localizedDescription)"
            Log.ftp.error("FTP server failed to start: \(error.localizedDescription)")
        }
    }

    func stopListening() {
        for session in sessions.values {
            session.close()
        }
        sessions.removeAll()
        activeSessionCount = 0

        listener?.cancel()
        listener = nil
        isListening = false
        lastError = nil

        Log.ftp.info("FTP server stopped")
    }

    // MARK: - Credential Management

    func updateCredentials(username: String, password: String) {
        self.username = username
        self.password = password
        Log.ftp.info("FTP credentials updated")
    }

    // MARK: - Transfer Path Resolution

    func resolveTransferPath() -> URL? {
        let basePath: String
        if let url = basePathURL {
            basePath = url.path
        } else if !baseTransferPath.isEmpty {
            basePath = baseTransferPath
        } else {
            return nil
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateFolder = dateFormatter.string(from: Date())

        return URL(fileURLWithPath: basePath)
            .appendingPathComponent(dateFolder)
    }

    // MARK: - Listener State

    private func handleListenerState(_ state: NWListener.State) {
        switch state {
        case .ready:
            isListening = true
            lastError = nil
            Log.ftp.info("FTP server ready on port \(self.listeningPort)")

        case .failed(let error):
            Log.ftp.error("FTP server failed: \(error.localizedDescription)")
            lastError = "Server failed: \(error.localizedDescription)"
            isListening = false

        case .cancelled:
            Log.ftp.info("FTP server cancelled")
            isListening = false

        case .waiting(let error):
            Log.ftp.warning("FTP server waiting: \(error.localizedDescription)")
            lastError = "Waiting: \(error.localizedDescription)"

        case .setup:
            break

        @unknown default:
            break
        }
    }

    // MARK: - Incoming Connections

    private func handleIncomingConnection(_ conn: NWConnection) {
        let session = FTPSession(connection: conn, server: self)

        session.onClose = { [weak self] sessionId in
            guard let self else { return }
            self.sessions.removeValue(forKey: sessionId)
            self.activeSessionCount = self.sessions.count
            Log.ftp.info("FTP session closed, \(self.sessions.count) active")
        }

        session.onTransferComplete = { [weak self] status in
            guard let self else { return }
            self.recentTransfers.append(status)
            // Keep only the most recent 50 transfers
            if self.recentTransfers.count > 50 {
                self.recentTransfers.removeFirst(self.recentTransfers.count - 50)
            }

            let event = ProductionEvent(
                type: .ftpTransfer,
                payload: .ftpTransfer(
                    fileName: status.fileName,
                    fileSize: status.bytesReceived,
                    destinationPath: self.baseTransferPath
                )
            )
            self.onTransferComplete?(event)
        }

        sessions[session.id] = session
        activeSessionCount = sessions.count
        session.start()

        Log.ftp.info("FTP session accepted, \(self.sessions.count) active")
    }
}
