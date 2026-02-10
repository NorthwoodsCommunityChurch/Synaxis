import Foundation
import Observation
import OSLog

/// Manages the recording session lifecycle: start/stop, event intake,
/// JSON export/import, and auto-export on stop.
///
/// The ``ConnectionManager`` routes events here via ``handleEvent(_:)``.
/// Views observe ``isRecording``, ``events``, and ``currentSession``.
@MainActor
@Observable
final class SessionManager {
    nonisolated deinit { }

    // MARK: - Observable State

    private(set) var isRecording: Bool = false
    var sessionName: String = ""

    let eventLogger: EventLogger

    var currentSession: ProductionSession? {
        eventLogger.currentSession
    }

    var events: [ProductionEvent] {
        eventLogger.events
    }

    var eventCount: Int {
        eventLogger.events.count
    }

    // MARK: - Init

    init() {
        self.eventLogger = EventLogger()
    }

    // MARK: - Session Lifecycle

    /// Start a new recording session. Populates session metadata from the
    /// current settings and assignment stores.
    func startSession(settings: SettingsManager, assignments: AssignmentStore) {
        let name = sessionName.isEmpty
            ? "Production \(Date().formatted(date: .abbreviated, time: .shortened))"
            : sessionName

        let sessionSettings = SessionSettings(
            frameRate: settings.frameRate,
            resolution: settings.resolution,
            startTimecode: settings.startTimecode,
            timecodeSource: settings.timecodeSource,
            dropFrame: settings.dropFrame,
            cameraAssignments: assignments.cameraAssignments,
            systemOutputs: assignments.systemOutputs,
            keyerAssignments: assignments.keyerAssignments,
            proPresenterConfigs: assignments.proPresenterConfigs
        )

        eventLogger.startSession(name: name, settings: sessionSettings)
        isRecording = true

        Log.session.info("Session started: \(name)")
    }

    /// Stop the active session. Triggers auto-export when configured.
    func stopSession(settings: SettingsManager) {
        eventLogger.stopSession()
        isRecording = false

        Log.session.info("Session stopped: \(self.eventLogger.events.count) events")

        if settings.autoExportOnStop {
            autoExport(settings: settings)
        }
    }

    // MARK: - Event Intake

    /// Called by ``ConnectionManager`` for every production event.
    /// Events are always logged so the Event Log view stays live.
    func handleEvent(_ event: ProductionEvent) {
        eventLogger.logEvent(event)
    }

    // MARK: - Export

    func exportSessionJSON() -> Data? {
        eventLogger.exportSessionJSON()
    }

    func exportSessionJSON(to url: URL) throws {
        guard let data = eventLogger.exportSessionJSON() else {
            throw AppError.sessionNotActive
        }
        try data.write(to: url)
        Log.export.info("Session JSON exported to \(url.lastPathComponent)")
    }

    // MARK: - Import

    func importSession(from data: Data) throws {
        let session = try eventLogger.importSession(from: data)
        sessionName = session.name
        isRecording = false
        Log.session.info("Session imported: \(session.name)")
    }

    func importSession(from url: URL) throws {
        let data = try Data(contentsOf: url)
        try importSession(from: data)
    }

    // MARK: - Auto Export

    private func autoExport(settings: SettingsManager) {
        guard !settings.defaultExportPath.isEmpty else {
            Log.export.warning("Auto-export enabled but no export path configured")
            return
        }

        guard let productionSession = currentSession else {
            Log.export.warning("Auto-export: no session available")
            return
        }

        let fileName = expandFileNamePattern(settings.exportFileNamePattern)
        let dirURL = URL(fileURLWithPath: settings.defaultExportPath)

        // Premiere XML file
        let xmlURL = dirURL.appendingPathComponent(fileName + ".xml")
        do {
            var generator = PremiereXMLGenerator(session: productionSession, mediaRoot: settings.hyperDeckMediaRoot)
            try generator.saveToFile(at: xmlURL)
            Log.export.info("Auto-export XML: \(xmlURL.lastPathComponent)")
        } catch {
            Log.export.error("Auto-export XML failed: \(error.localizedDescription)")
        }

        // JSON session file
        let jsonURL = dirURL.appendingPathComponent(fileName + ".json")
        do {
            try exportSessionJSON(to: jsonURL)
            Log.export.info("Auto-export JSON: \(jsonURL.lastPathComponent)")
        } catch {
            Log.export.error("Auto-export JSON failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Filename Token Expansion

    /// Expands tokens in a file-name pattern:
    /// - `{session}` — session name
    /// - `{date}` — `yyyy-MM-dd`
    /// - `{time}` — `HHmmss`
    /// - `{count}` — number of events
    func expandFileNamePattern(_ pattern: String) -> String {
        let session = eventLogger.currentSession
        let now = Date()

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: now)

        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HHmmss"
        let timeString = timeFormatter.string(from: now)

        var result = pattern
        result = result.replacingOccurrences(of: "{session}", with: session?.name ?? "Untitled")
        result = result.replacingOccurrences(of: "{date}", with: dateString)
        result = result.replacingOccurrences(of: "{time}", with: timeString)
        result = result.replacingOccurrences(of: "{count}", with: "\(eventLogger.events.count)")

        // Sanitize for the file system
        let forbidden = CharacterSet(charactersIn: "/\\:*?\"<>|")
        result = result.components(separatedBy: forbidden).joined(separator: "_")

        return result
    }

    // MARK: - Reset

    func reset() {
        eventLogger.reset()
        isRecording = false
        sessionName = ""
    }
}
