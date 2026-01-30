import XCTest
@testable import Touchdrive_to_Premiere

@MainActor
final class EventLoggerTests: XCTestCase {

    var logger: EventLogger!

    override func setUp() {
        super.setUp()
        logger = EventLogger()
    }

    override func tearDown() {
        logger = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func defaultSettings() -> SessionSettings {
        SessionSettings(
            frameRate: 29.97,
            resolution: .hd1080,
            startTimecode: "01:00:00:00",
            timecodeSource: .hyperDeck,
            dropFrame: true,
            cameraAssignments: [],
            keyerAssignments: [],
            proPresenterConfig: ProPresenterConfig()
        )
    }

    private func makeEvent(_ type: EventType) -> ProductionEvent {
        switch type {
        case .programCut:
            return ProductionEvent(
                type: .programCut,
                payload: .programCut(sourceIndex: 1, sourceName: "CAM 1", busName: "ME1PGM")
            )
        case .slideChange:
            return ProductionEvent(
                type: .slideChange,
                payload: .slideChange(presentationName: "Test", slideIndex: 0, slideText: "Hello")
            )
        case .keyerOn:
            return ProductionEvent(
                type: .keyerOn,
                payload: .keyerOn(meNumber: 1, keyerNumber: 1)
            )
        case .keyerOff:
            return ProductionEvent(
                type: .keyerOff,
                payload: .keyerOff(meNumber: 1, keyerNumber: 1)
            )
        default:
            return ProductionEvent(
                type: type,
                payload: .connectionChange(service: "Test", connected: true, detail: nil)
            )
        }
    }

    // MARK: - Session Lifecycle

    func testStartSession() {
        logger.startSession(name: "Sunday Service", settings: defaultSettings())

        XCTAssertTrue(logger.isRecording, "isRecording should be true after starting a session")
        XCTAssertNotNil(logger.currentSession, "currentSession should not be nil after starting")
        XCTAssertEqual(logger.currentSession?.name, "Sunday Service",
                       "Session name should match the provided name")
    }

    func testStopSession() {
        logger.startSession(name: "Test Session", settings: defaultSettings())
        XCTAssertTrue(logger.isRecording)

        logger.stopSession()

        XCTAssertFalse(logger.isRecording, "isRecording should be false after stopping")
        XCTAssertNotNil(logger.currentSession?.endTime,
                        "endTime should be set after stopping the session")
    }

    func testStopSessionWithoutStarting() {
        // Stopping without a session should not crash
        logger.stopSession()
        XCTAssertFalse(logger.isRecording, "isRecording should remain false")
        XCTAssertNil(logger.currentSession, "currentSession should remain nil")
    }

    // MARK: - Event Logging

    func testLogEvent() {
        logger.startSession(name: "Test", settings: defaultSettings())

        let event = makeEvent(.programCut)
        logger.logEvent(event)

        XCTAssertEqual(logger.events.count, 1,
                       "Events count should be 1 after logging one event")
        XCTAssertEqual(logger.events.first?.type, .programCut,
                       "The logged event type should be .programCut")
    }

    func testLogMultipleEvents() {
        logger.startSession(name: "Test", settings: defaultSettings())

        logger.logEvent(makeEvent(.programCut))
        logger.logEvent(makeEvent(.slideChange))
        logger.logEvent(makeEvent(.keyerOn))

        XCTAssertEqual(logger.events.count, 3,
                       "Events count should be 3 after logging three events")
    }

    func testEventsLoggedWithoutSession() {
        // EventLogger does NOT guard against logging without an active session;
        // that guard is in SessionManager.handleEvent. Events are appended regardless.
        let event = makeEvent(.programCut)
        logger.logEvent(event)

        XCTAssertEqual(logger.events.count, 1,
                       "EventLogger should append the event even without an active session")
    }

    // MARK: - Filter by Type

    func testFilterByType() {
        logger.startSession(name: "Test", settings: defaultSettings())

        logger.logEvent(makeEvent(.programCut))
        logger.logEvent(makeEvent(.programCut))
        logger.logEvent(makeEvent(.slideChange))
        logger.logEvent(makeEvent(.keyerOn))
        logger.logEvent(makeEvent(.keyerOff))

        let cuts = logger.events(ofType: .programCut)
        XCTAssertEqual(cuts.count, 2,
                       "Filtering by .programCut should return 2 events")

        let slides = logger.events(ofType: .slideChange)
        XCTAssertEqual(slides.count, 1,
                       "Filtering by .slideChange should return 1 event")

        let keyerOns = logger.events(ofType: .keyerOn)
        XCTAssertEqual(keyerOns.count, 1,
                       "Filtering by .keyerOn should return 1 event")

        let keyerOffs = logger.events(ofType: .keyerOff)
        XCTAssertEqual(keyerOffs.count, 1,
                       "Filtering by .keyerOff should return 1 event")
    }

    // MARK: - Program Cuts

    func testProgramCuts() {
        logger.startSession(name: "Test", settings: defaultSettings())

        logger.logEvent(makeEvent(.programCut))
        logger.logEvent(makeEvent(.slideChange))
        logger.logEvent(makeEvent(.programCut))
        logger.logEvent(makeEvent(.keyerOn))
        logger.logEvent(makeEvent(.programCut))

        let cuts = logger.programCuts
        XCTAssertEqual(cuts.count, 3,
                       "programCuts should return only .programCut events")

        for cut in cuts {
            XCTAssertEqual(cut.type, .programCut,
                           "Every item in programCuts should have type .programCut")
        }
    }

    func testProgramCutsEmpty() {
        logger.startSession(name: "Test", settings: defaultSettings())

        logger.logEvent(makeEvent(.slideChange))
        logger.logEvent(makeEvent(.keyerOn))

        let cuts = logger.programCuts
        XCTAssertTrue(cuts.isEmpty,
                      "programCuts should be empty when no program cut events exist")
    }

    // MARK: - Export / Import Round Trip

    func testExportImportRoundTrip() {
        logger.startSession(name: "Export Test", settings: defaultSettings())
        logger.logEvent(makeEvent(.programCut))
        logger.logEvent(makeEvent(.slideChange))
        logger.logEvent(makeEvent(.keyerOn))

        let jsonData = logger.exportSessionJSON()
        XCTAssertNotNil(jsonData, "exportSessionJSON should return non-nil data")

        guard let data = jsonData else { return }

        do {
            let importedSession = try logger.importSession(from: data)
            XCTAssertEqual(importedSession.name, "Export Test",
                           "Imported session name should match the original")
            XCTAssertEqual(importedSession.events.count, 3,
                           "Imported session should have 3 events")
        } catch {
            XCTFail("importSession threw an error: \(error)")
        }
    }

    func testExportWithoutSession() {
        // No session started, export should return nil or empty
        let jsonData = logger.exportSessionJSON()
        // exportSessionJSON may return nil if no session exists
        // This is acceptable behavior
        if let data = jsonData {
            XCTAssertTrue(data.count > 0, "If data is returned, it should not be empty")
        }
    }

    func testImportInvalidData() {
        let invalidData = "not valid json".data(using: .utf8)!

        XCTAssertThrowsError(try logger.importSession(from: invalidData),
                             "importSession should throw for invalid JSON data")
    }

    // MARK: - Clear Events

    func testClearEvents() {
        logger.startSession(name: "Test", settings: defaultSettings())
        logger.logEvent(makeEvent(.programCut))
        logger.logEvent(makeEvent(.slideChange))
        logger.logEvent(makeEvent(.keyerOn))

        XCTAssertEqual(logger.events.count, 3, "Should have 3 events before clearing")

        logger.clearEvents()

        XCTAssertEqual(logger.events.count, 0,
                       "Events count should be 0 after clearEvents")
    }

    func testClearEventsWhenAlreadyEmpty() {
        logger.clearEvents()
        XCTAssertEqual(logger.events.count, 0,
                       "Clearing an already-empty event list should not crash")
    }

    // MARK: - Reset

    func testReset() {
        logger.startSession(name: "Reset Test", settings: defaultSettings())
        logger.logEvent(makeEvent(.programCut))
        logger.logEvent(makeEvent(.slideChange))

        XCTAssertNotNil(logger.currentSession, "Session should exist before reset")
        XCTAssertEqual(logger.events.count, 2, "Should have 2 events before reset")

        logger.reset()

        XCTAssertNil(logger.currentSession,
                     "currentSession should be nil after reset")
        XCTAssertTrue(logger.events.isEmpty,
                      "events should be empty after reset")
        XCTAssertFalse(logger.isRecording,
                       "isRecording should be false after reset")
    }

    func testResetWithoutSession() {
        // Resetting when nothing is active should not crash
        logger.reset()
        XCTAssertNil(logger.currentSession)
        XCTAssertTrue(logger.events.isEmpty)
    }
}
