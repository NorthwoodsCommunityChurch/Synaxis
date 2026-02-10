import XCTest
@testable import Synaxis

@MainActor
final class TSLParserTests: XCTestCase {

    var busState: BusStateModel!

    override func setUp() {
        super.setUp()
        busState = BusStateModel()
    }

    override func tearDown() {
        busState = nil
        super.tearDown()
    }

    // MARK: - Program / Preview Updates

    func testBusStateUpdateProgramChange() {
        let tally = TallyState(program: true, preview: false, brightness: 3)
        _ = busState.update(index: 1, tally: tally, busLabel: "ME1PGM", sourceLabel: "CAM 1")

        XCTAssertEqual(busState.programSourcePerBus["ME1PGM"], 1,
                       "Program source for ME1PGM should be index 1 after a program tally update")
    }

    func testBusStateUpdatePreview() {
        let tally = TallyState(program: false, preview: true, brightness: 3)
        _ = busState.update(index: 2, tally: tally, busLabel: "ME1PVW", sourceLabel: "CAM 2")

        XCTAssertEqual(busState.previewSourcePerBus["ME1PVW"], 2,
                       "Preview source for ME1PVW should be index 2 after a preview tally update")
    }

    // MARK: - Bus Labels

    func testBusLabels() {
        let tallyA = TallyState(program: true, preview: false, brightness: 3)
        let tallyB = TallyState(program: false, preview: true, brightness: 3)

        _ = busState.update(index: 1, tally: tallyA, busLabel: "ME1PGM", sourceLabel: "CAM 1")
        _ = busState.update(index: 2, tally: tallyB, busLabel: "ME2PGM", sourceLabel: "CAM 2")
        _ = busState.update(index: 3, tally: tallyA, busLabel: "AUX1", sourceLabel: "CAM 3")

        let labels = busState.busLabels
        XCTAssertTrue(labels.contains("ME1PGM"), "busLabels should contain ME1PGM")
        XCTAssertTrue(labels.contains("ME2PGM"), "busLabels should contain ME2PGM")
        XCTAssertTrue(labels.contains("AUX1"), "busLabels should contain AUX1")
    }

    // MARK: - Current Program Source

    func testCurrentProgramSource() {
        let tally = TallyState(program: true, preview: false, brightness: 3)
        _ = busState.update(index: 5, tally: tally, busLabel: "ME1PGM", sourceLabel: "CAM 5")

        let source = busState.currentProgramSource(for: "ME1PGM")
        XCTAssertNotNil(source, "currentProgramSource should return a SourceState for an active bus")
        XCTAssertEqual(source?.index, 5, "The returned source index should be 5")
        XCTAssertEqual(source?.sourceLabel, "CAM 5", "The returned source label should be CAM 5")
    }

    func testCurrentProgramSourceReturnsNilForUnknownBus() {
        let result = busState.currentProgramSource(for: "NONEXISTENT")
        XCTAssertNil(result, "currentProgramSource should return nil for a bus with no program source")
    }

    // MARK: - Reset

    func testBusStateReset() {
        let tally = TallyState(program: true, preview: false, brightness: 3)
        _ = busState.update(index: 1, tally: tally, busLabel: "ME1PGM", sourceLabel: "CAM 1")

        XCTAssertFalse(busState.sources.isEmpty, "sources should not be empty before reset")

        busState.reset()

        XCTAssertTrue(busState.sources.isEmpty, "sources should be empty after reset")
        XCTAssertTrue(busState.programSourcePerBus.isEmpty, "programSourcePerBus should be empty after reset")
        XCTAssertTrue(busState.previewSourcePerBus.isEmpty, "previewSourcePerBus should be empty after reset")
    }

    // MARK: - TallyState

    func testTallyStateEquality() {
        let off = TallyState(program: false, preview: false, brightness: 0)
        let alsoOff = TallyState(program: false, preview: false, brightness: 0)
        let on = TallyState(program: true, preview: false, brightness: 3)

        XCTAssertEqual(off, alsoOff, "Two off tally states should be equal")
        XCTAssertNotEqual(off, on, "An off tally state should not equal an on tally state")
        XCTAssertFalse(off.program, "Off tally should have program == false")
        XCTAssertFalse(off.preview, "Off tally should have preview == false")
        XCTAssertEqual(off.brightness, 0, "Off tally should have brightness == 0")
    }

    // MARK: - SourceState Full Label

    func testSourceStateFullLabel() {
        let tally = TallyState(program: true, preview: false, brightness: 3)

        // Update with both bus and source labels
        _ = busState.update(index: 1, tally: tally, busLabel: "ME1PGM", sourceLabel: "CAM 1")

        let source = busState.sources[1]
        XCTAssertNotNil(source, "Source at index 1 should exist")
        XCTAssertEqual(source?.busLabel, "ME1PGM", "Bus label should be ME1PGM")
        XCTAssertEqual(source?.sourceLabel, "CAM 1", "Source label should be CAM 1")
    }

    func testSourceStateWithEmptyLabels() {
        let tally = TallyState(program: false, preview: false, brightness: 0)
        _ = busState.update(index: 0, tally: tally, busLabel: "", sourceLabel: "")

        let source = busState.sources[0]
        XCTAssertNotNil(source, "Source at index 0 should exist even with empty labels")
        XCTAssertEqual(source?.busLabel, "", "Bus label should be empty string")
        XCTAssertEqual(source?.sourceLabel, "", "Source label should be empty string")
    }
}
