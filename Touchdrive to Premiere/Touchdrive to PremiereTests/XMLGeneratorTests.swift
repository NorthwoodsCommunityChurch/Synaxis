import XCTest
@testable import Synaxis

@MainActor
final class XMLGeneratorTests: XCTestCase {

    // MARK: - Helpers

    private func makeSession(
        name: String = "Test Session",
        frameRate: Double = 29.97,
        resolution: Resolution = .hd1080,
        events: [ProductionEvent] = [],
        cameraAssignments: [CameraAssignment] = [],
        systemOutputs: [CameraAssignment] = [],
        keyerAssignments: [KeyerAssignment] = [],
        startTimecode: String = "01:00:00:00",
        dropFrame: Bool = true
    ) -> ProductionSession {
        var session = ProductionSession(name: name, startTime: Date())
        session.endTime = Date().addingTimeInterval(3600)
        session.events = events
        session.cameraAssignments = cameraAssignments
        session.systemOutputs = systemOutputs
        session.keyerAssignments = keyerAssignments
        session.frameRate = frameRate
        session.resolution = resolution
        session.startTimecode = startTimecode
        session.dropFrame = dropFrame
        return session
    }

    // MARK: - Empty Session XML Structure

    func testEmptySessionGeneratesValidXML() {
        let session = makeSession()
        var generator = PremiereXMLGenerator(session: session)
        let xml = generator.generateXML()

        XCTAssertTrue(xml.contains("<?xml"), "XML should contain the XML declaration")
        XCTAssertTrue(xml.contains("<xmeml"), "XML should contain the xmeml root element")
        XCTAssertTrue(xml.contains("<sequence"), "XML should contain a sequence element")
    }

    // MARK: - Session Name

    func testXMLContainsSessionName() {
        let session = makeSession(name: "Sunday Morning Service")
        var generator = PremiereXMLGenerator(session: session)
        let xml = generator.generateXML()

        XCTAssertTrue(xml.contains("Sunday Morning Service"),
                      "XML should contain the session name")
    }

    func testXMLContainsCustomSessionName() {
        let session = makeSession(name: "Wednesday Night")
        var generator = PremiereXMLGenerator(session: session)
        let xml = generator.generateXML()

        XCTAssertTrue(xml.contains("Wednesday Night"),
                      "XML should contain the custom session name")
    }

    // MARK: - Frame Rate

    func testXMLContainsFrameRate() {
        let session = makeSession(frameRate: 29.97)
        var generator = PremiereXMLGenerator(session: session)
        let xml = generator.generateXML()

        // The timebase for 29.97 should be 30
        XCTAssertTrue(xml.contains("<timebase>30</timebase>"),
                      "XML should contain timebase 30 for 29.97fps")
    }

    func testXMLContainsFrameRate24() {
        let session = makeSession(frameRate: 24, dropFrame: false)
        var generator = PremiereXMLGenerator(session: session)
        let xml = generator.generateXML()

        XCTAssertTrue(xml.contains("<timebase>24</timebase>"),
                      "XML should contain timebase 24 for 24fps")
    }

    func testXMLContainsFrameRate25() {
        let session = makeSession(frameRate: 25, dropFrame: false)
        var generator = PremiereXMLGenerator(session: session)
        let xml = generator.generateXML()

        XCTAssertTrue(xml.contains("<timebase>25</timebase>"),
                      "XML should contain timebase 25 for 25fps")
    }

    // MARK: - Resolution

    func testXMLContainsResolution() {
        let session = makeSession(resolution: .hd1080)
        var generator = PremiereXMLGenerator(session: session)
        let xml = generator.generateXML()

        XCTAssertTrue(xml.contains("<width>1920</width>"),
                      "XML should contain width 1920 for 1080p")
        XCTAssertTrue(xml.contains("<height>1080</height>"),
                      "XML should contain height 1080 for 1080p")
    }

    // MARK: - NTSC Flag

    func testXMLContainsNTSCFlag() {
        let session = makeSession(frameRate: 29.97)
        var generator = PremiereXMLGenerator(session: session)
        let xml = generator.generateXML()

        XCTAssertTrue(xml.contains("<ntsc>TRUE</ntsc>"),
                      "XML should contain <ntsc>TRUE</ntsc> for 29.97fps NTSC")
    }

    func testXMLContainsNTSCFalseForPAL() {
        let session = makeSession(frameRate: 25, dropFrame: false)
        var generator = PremiereXMLGenerator(session: session)
        let xml = generator.generateXML()

        XCTAssertTrue(xml.contains("<ntsc>FALSE</ntsc>"),
                      "XML should contain <ntsc>FALSE</ntsc> for 25fps PAL")
    }

    // MARK: - Track Count

    func testTrackCountForEmptySession() {
        let session = makeSession()
        var generator = PremiereXMLGenerator(session: session)

        // An empty session should still have at least a baseline number of tracks
        XCTAssertGreaterThanOrEqual(generator.trackCount, 0,
                                     "Track count should be non-negative for an empty session")
    }

    // MARK: - Marker Count

    func testMarkerCountForEmptySession() {
        let session = makeSession()
        var generator = PremiereXMLGenerator(session: session)

        XCTAssertEqual(generator.markerCount, 0,
                       "Marker count should be 0 for a session with no keyer or slide events")
    }

    // MARK: - System Outputs

    func testSystemOutputTracksInXML() {
        let outputs = [
            CameraAssignment(tslIndex: 10, name: "PGM Out", hyperDeckChannel: 5),
            CameraAssignment(tslIndex: 11, name: "Clean Feed", hyperDeckChannel: 6),
        ]
        let session = makeSession(systemOutputs: outputs)
        var generator = PremiereXMLGenerator(session: session)
        let xml = generator.generateXML()

        XCTAssertTrue(xml.contains("PGM Out"),
                      "XML should contain system output name 'PGM Out'")
        XCTAssertTrue(xml.contains("Clean Feed"),
                      "XML should contain system output name 'Clean Feed'")
    }

    func testTrackCountIncludesSystemOutputs() {
        let cameras = [CameraAssignment(tslIndex: 1, name: "Cam 1")]
        let outputs = [CameraAssignment(tslIndex: 10, name: "PGM Out")]
        let sessionWithOutputs = makeSession(cameraAssignments: cameras, systemOutputs: outputs)
        let sessionWithoutOutputs = makeSession(cameraAssignments: cameras)

        var genWith = PremiereXMLGenerator(session: sessionWithOutputs)
        var genWithout = PremiereXMLGenerator(session: sessionWithoutOutputs)

        XCTAssertGreaterThan(genWith.trackCount, genWithout.trackCount,
                             "Track count should increase when system outputs are present")
    }

    // MARK: - Media Root

    func testMediaRootPathInXML() {
        let cameras = [CameraAssignment(tslIndex: 1, name: "Cam 1")]
        let session = makeSession(cameraAssignments: cameras)
        var generator = PremiereXMLGenerator(session: session, mediaRoot: "/Volumes/HyperDeck/Media")
        let xml = generator.generateXML()

        XCTAssertTrue(xml.contains("HyperDeck/Media"),
                      "XML should contain the media root path")
    }

    func testEmptyMediaRootOmitsPathURL() {
        let cameras = [CameraAssignment(tslIndex: 1, name: "Cam 1")]
        let session = makeSession(cameraAssignments: cameras)
        var generator = PremiereXMLGenerator(session: session, mediaRoot: "")
        let xml = generator.generateXML()

        XCTAssertFalse(xml.contains("<pathurl>"),
                       "XML should not contain pathurl when media root is empty")
    }

    // MARK: - File Save

    func testSaveToFile() throws {
        let session = makeSession()
        var generator = PremiereXMLGenerator(session: session)

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_output_\(UUID().uuidString).xml")

        try generator.saveToFile(at: tempURL)

        let fileExists = FileManager.default.fileExists(atPath: tempURL.path)
        XCTAssertTrue(fileExists, "The XML file should be written to disk")

        let contents = try String(contentsOf: tempURL, encoding: .utf8)
        XCTAssertTrue(contents.contains("<?xml"), "The saved file should contain valid XML")

        // Clean up
        try? FileManager.default.removeItem(at: tempURL)
    }
}
