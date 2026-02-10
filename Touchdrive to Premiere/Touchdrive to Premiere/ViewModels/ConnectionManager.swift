import Foundation
import Observation
import OSLog

/// Owns all device clients (TSL, ProPresenter×N, HyperDeck) and the
/// shared ``BusStateModel``. Provides connect/disconnect controls and
/// routes production events from every client through a single ``onEvent`` callback.
@MainActor
@Observable
final class ConnectionManager {
    nonisolated deinit { }

    // MARK: - Owned Clients

    let tslClient: TSLClient
    let hyperDeckClient: HyperDeckClient
    let ftpServer: FTPServer
    let busState: BusStateModel

    /// Dictionary of ProPresenter clients keyed by their config UUID.
    private(set) var proPresenterClients: [UUID: ProPresenterClient] = [:]

    // MARK: - Aggregate Status

    var isTSLConnected: Bool { tslClient.isListening }
    var isHyperDeckConnected: Bool { hyperDeckClient.isConnected }
    var isFTPListening: Bool { ftpServer.isListening }

    /// True when at least one ProPresenter machine is connected.
    var isAnyProPresenterConnected: Bool {
        proPresenterClients.values.contains { $0.isConnected }
    }

    /// Whether a specific ProPresenter machine is connected.
    func isProPresenterConnected(id: UUID) -> Bool {
        proPresenterClients[id]?.isConnected ?? false
    }

    /// Look up the client for a specific ProPresenter config.
    func proPresenterClient(for id: UUID) -> ProPresenterClient? {
        proPresenterClients[id]
    }

    var anyConnected: Bool {
        tslClient.isListening || isAnyProPresenterConnected || hyperDeckClient.isConnected
    }

    // MARK: - Event Callback

    /// All production events from every client are funnelled through this single callback.
    /// The App wires this to ``SessionManager/handleEvent(_:)``.
    var onEvent: ((ProductionEvent) -> Void)?

    // MARK: - Init

    init() {
        let bus = BusStateModel()
        self.busState = bus
        self.tslClient = TSLClient(busState: bus)
        self.hyperDeckClient = HyperDeckClient()
        self.ftpServer = FTPServer()

        wireEventCallbacks()
    }

    // MARK: - Bulk Connect / Disconnect

    /// Start all enabled connections using the current settings.
    func connectAll(settings: SettingsManager, assignments: AssignmentStore) {
        // TSL (listener — no host needed, just port)
        if settings.tslEnabled {
            tslClient.startListening(port: settings.tslPort)
        }

        // ProPresenter — connect each enabled & configured machine
        for config in assignments.proPresenterConfigs where config.enabled && config.isConfigured {
            connectProPresenter(config: config)
        }

        // HyperDeck
        if settings.hyperDeckEnabled, !settings.hyperDeckHost.isEmpty {
            hyperDeckClient.connect(
                host: settings.hyperDeckHost,
                port: settings.hyperDeckPort
            )
        }

        // FTP Server
        if settings.ftpEnabled {
            startFTPServer(port: settings.ftpPort, settings: settings)
        }

        Log.session.info("Connect all initiated")
    }

    /// Tear down every connection and reset bus state.
    func disconnectAll() {
        tslClient.stopListening()
        disconnectAllProPresenter()
        hyperDeckClient.disconnect()
        ftpServer.stopListening()
        busState.reset()

        Log.session.info("Disconnect all completed")
    }

    // MARK: - Individual Connection Controls

    func startTSLListener(port: UInt16) {
        tslClient.startListening(port: port)
    }

    func stopTSLListener() {
        tslClient.stopListening()
    }

    /// Connect a single ProPresenter machine. Creates a client if needed.
    func connectProPresenter(config: ProPresenterConfig) {
        let client: ProPresenterClient
        if let existing = proPresenterClients[config.id] {
            client = existing
        } else {
            client = ProPresenterClient()
            client.onEvent = { [weak self] event in
                self?.routeEvent(event)
            }
            proPresenterClients[config.id] = client
        }
        client.connect(host: config.host, port: config.apiPort, name: config.name)
    }

    /// Disconnect a single ProPresenter machine by config ID.
    func disconnectProPresenter(id: UUID) {
        proPresenterClients[id]?.disconnect()
    }

    /// Disconnect and remove all ProPresenter clients.
    func disconnectAllProPresenter() {
        for client in proPresenterClients.values {
            client.disconnect()
        }
        proPresenterClients.removeAll()
    }

    func connectHyperDeck(host: String, port: Int) {
        hyperDeckClient.connect(host: host, port: port)
    }

    func disconnectHyperDeck() {
        hyperDeckClient.disconnect()
    }

    // MARK: - HyperDeck Recording Commands

    func startHyperDeckRecording() {
        hyperDeckClient.record()
    }

    func startHyperDeckRecording(name: String) {
        hyperDeckClient.recordWithName(name)
    }

    func stopHyperDeckRecording() {
        hyperDeckClient.stop()
    }

    // MARK: - FTP Server Controls

    func startFTPServer(port: UInt16, settings: SettingsManager) {
        ftpServer.updateCredentials(username: settings.ftpUsername, password: settings.ftpPassword)
        ftpServer.baseTransferPath = settings.ftpBasePath

        // Resolve security-scoped bookmark if available
        if let bookmark = settings.ftpBasePathBookmark {
            var isStale = false
            if let url = try? URL(resolvingBookmarkData: bookmark, options: .withSecurityScope, bookmarkDataIsStale: &isStale) {
                ftpServer.basePathURL = url
                if isStale {
                    // Re-save updated bookmark
                    settings.ftpBasePathBookmark = try? url.bookmarkData(options: .withSecurityScope)
                    settings.save()
                }
            }
        }

        ftpServer.startListening(port: port)
    }

    func stopFTPServer() {
        ftpServer.stopListening()
    }

    // MARK: - Timecode

    /// Current timecode from the HyperDeck (the primary timecode source).
    var currentTimecode: String {
        hyperDeckClient.currentTimecode
    }

    // MARK: - Private

    private func wireEventCallbacks() {
        tslClient.onEvent = { [weak self] event in
            self?.routeEvent(event)
        }

        hyperDeckClient.onEvent = { [weak self] event in
            self?.routeEvent(event)
        }

        ftpServer.onTransferComplete = { [weak self] event in
            self?.routeEvent(event)
        }
    }

    /// Routes an event through the `onEvent` callback, stamping the current
    /// HyperDeck timecode on events that arrive without one (TSL, ProPresenter).
    private func routeEvent(_ event: ProductionEvent) {
        let stamped: ProductionEvent
        if event.timecode == "00:00:00:00" && currentTimecode != "00:00:00:00" {
            stamped = ProductionEvent(
                type: event.type,
                payload: event.payload,
                timecode: currentTimecode,
                timestamp: event.timestamp
            )
        } else {
            stamped = event
        }
        onEvent?(stamped)
    }
}
