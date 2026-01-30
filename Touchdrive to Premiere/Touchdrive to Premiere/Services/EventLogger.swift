import Foundation
import Observation
import OSLog

@Observable
final class EventLogger {
    nonisolated deinit { }

    var events: [ProductionEvent] = []
    var currentSession: ProductionSession?

    var isRecording: Bool {
        currentSession != nil && currentSession?.endTime == nil
    }

    // MARK: - Session Lifecycle

    func startSession(name: String, settings: SessionSettings) {
        var session = ProductionSession(name: name)
        session.frameRate = settings.frameRate
        session.resolution = settings.resolution
        session.startTimecode = settings.startTimecode
        session.timecodeSource = settings.timecodeSource
        session.dropFrame = settings.dropFrame
        session.cameraAssignments = settings.cameraAssignments
        session.keyerAssignments = settings.keyerAssignments
        session.proPresenterConfigs = settings.proPresenterConfigs
        currentSession = session
        events.removeAll()
        Log.session.info("Session started: \(name)")
    }

    func stopSession() {
        currentSession?.endTime = Date()
        currentSession?.events = events
        Log.session.info("Session stopped: \(self.currentSession?.name ?? "unknown"), \(self.events.count) events")
    }

    // MARK: - Event Logging

    func logEvent(_ event: ProductionEvent) {
        events.append(event)
        Log.session.debug("Event: \(event.type.rawValue) — \(event.description)")
    }

    // MARK: - Filtering

    func events(ofType type: EventType) -> [ProductionEvent] {
        events.filter { $0.type == type }
    }

    func events(from start: Date, to end: Date) -> [ProductionEvent] {
        events.filter { $0.timestamp >= start && $0.timestamp <= end }
    }

    var programCuts: [ProductionEvent] {
        events.filter { $0.type == .programCut }.sorted { $0.timestamp < $1.timestamp }
    }

    var slideChanges: [ProductionEvent] {
        events.filter { $0.type == .slideChange }.sorted { $0.timestamp < $1.timestamp }
    }

    var keyerEvents: [ProductionEvent] {
        events.filter { $0.type == .keyerOn || $0.type == .keyerOff }.sorted { $0.timestamp < $1.timestamp }
    }

    // MARK: - Export / Import

    func exportSessionJSON() -> Data? {
        guard let session = currentSession else {
            Log.session.error("No session to export")
            return nil
        }
        var exportSession = session
        exportSession.events = events
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(exportSession)
            Log.export.info("Session exported: \(data.count) bytes")
            return data
        } catch {
            Log.export.error("Session export failed: \(error.localizedDescription)")
            return nil
        }
    }

    func importSession(from data: Data) throws -> ProductionSession {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let session = try decoder.decode(ProductionSession.self, from: data)
        currentSession = session
        events = session.events
        Log.session.info("Session imported: \(session.name), \(session.events.count) events")
        return session
    }

    // MARK: - Clear

    func clearEvents() {
        events.removeAll()
    }

    func reset() {
        events.removeAll()
        currentSession = nil
    }
}

// MARK: - Session Settings

struct SessionSettings {
    var frameRate: Double = 29.97
    var resolution: Resolution = .hd1080
    var startTimecode: String = "01:00:00:00"
    var timecodeSource: TimecodeSource = .hyperDeck
    var dropFrame: Bool = true
    var cameraAssignments: [CameraAssignment] = []
    var keyerAssignments: [KeyerAssignment] = []
    var proPresenterConfigs: [ProPresenterConfig] = []
}
