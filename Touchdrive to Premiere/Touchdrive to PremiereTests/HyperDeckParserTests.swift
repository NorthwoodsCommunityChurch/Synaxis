import XCTest
@testable import Touchdrive_to_Premiere

@MainActor
final class HyperDeckParserTests: XCTestCase {

    // MARK: - Initial State

    func testInitialState() {
        let client = HyperDeckClient()

        XCTAssertFalse(client.isConnected,
                       "A new HyperDeckClient should not be connected")
        XCTAssertEqual(client.transportStatus, "stopped",
                       "Initial transport status should be 'stopped'")
        XCTAssertEqual(client.currentTimecode, "00:00:00:00",
                       "Initial timecode should be 00:00:00:00")
        XCTAssertEqual(client.currentClipName, "",
                       "Initial clip name should be empty")
        XCTAssertNil(client.lastError,
                     "Initial lastError should be nil")
    }

    // MARK: - isRecording Computed Property

    func testIsRecordingDefaultIsFalse() {
        // Default transportStatus is "stopped", so isRecording should be false
        let client = HyperDeckClient()
        XCTAssertFalse(client.isRecording,
                       "isRecording should be false when transportStatus is default 'stopped'")
    }

    // MARK: - SlotInfo

    func testSlotInfoIdentifiable() {
        let slot = HyperDeckClient.SlotInfo(
            id: 1,
            status: "mounted",
            volumeName: "SSD1",
            recordingTime: 3600,
            videoFormat: "1080p2997"
        )

        XCTAssertEqual(slot.id, 1, "SlotInfo id should be 1")
        XCTAssertEqual(slot.status, "mounted", "SlotInfo status should be 'mounted'")
        XCTAssertEqual(slot.volumeName, "SSD1", "SlotInfo volumeName should be 'SSD1'")
        XCTAssertEqual(slot.recordingTime, 3600, "SlotInfo recordingTime should be 3600")
        XCTAssertEqual(slot.videoFormat, "1080p2997", "SlotInfo videoFormat should be '1080p2997'")
    }

    func testSlotInfoMultipleSlots() {
        let slot1 = HyperDeckClient.SlotInfo(
            id: 1,
            status: "mounted",
            volumeName: "SSD1",
            recordingTime: 3600,
            videoFormat: "1080p2997"
        )
        let slot2 = HyperDeckClient.SlotInfo(
            id: 2,
            status: "empty",
            volumeName: "",
            recordingTime: 0,
            videoFormat: ""
        )

        XCTAssertNotEqual(slot1.id, slot2.id, "Two slots should have different ids")
        XCTAssertEqual(slot2.status, "empty", "Second slot should have status 'empty'")
    }

    // MARK: - ClipInfo

    func testClipInfoIdentifiable() {
        let clip = HyperDeckClient.ClipInfo(
            id: 1,
            name: "Clip001.mov",
            startTimecode: "01:00:00:00",
            duration: "00:05:30:00"
        )

        XCTAssertEqual(clip.id, 1, "ClipInfo id should be 1")
        XCTAssertEqual(clip.name, "Clip001.mov", "ClipInfo name should be 'Clip001.mov'")
        XCTAssertEqual(clip.startTimecode, "01:00:00:00", "ClipInfo startTimecode should be '01:00:00:00'")
        XCTAssertEqual(clip.duration, "00:05:30:00", "ClipInfo duration should be '00:05:30:00'")
    }

    func testClipInfoMultipleClips() {
        let clip1 = HyperDeckClient.ClipInfo(
            id: 1,
            name: "Clip001.mov",
            startTimecode: "01:00:00:00",
            duration: "00:05:30:00"
        )
        let clip2 = HyperDeckClient.ClipInfo(
            id: 2,
            name: "Clip002.mov",
            startTimecode: "01:05:30:00",
            duration: "00:10:00:00"
        )

        XCTAssertNotEqual(clip1.id, clip2.id, "Two clips should have different ids")
        XCTAssertEqual(clip2.name, "Clip002.mov", "Second clip name should be 'Clip002.mov'")
    }

    // MARK: - Slots and Clips Arrays

    func testInitialSlotsEmpty() {
        let client = HyperDeckClient()
        XCTAssertTrue(client.slots.isEmpty, "Initial slots array should be empty")
    }

    func testInitialClipsEmpty() {
        let client = HyperDeckClient()
        XCTAssertTrue(client.clips.isEmpty, "Initial clips array should be empty")
    }

    // MARK: - Default State Values

    func testDefaultTransportIsStopped() {
        let client = HyperDeckClient()
        XCTAssertEqual(client.transportStatus, "stopped",
                       "Default transport status should be 'stopped'")
    }

    func testDefaultTimecodeIsZero() {
        let client = HyperDeckClient()
        XCTAssertEqual(client.currentTimecode, "00:00:00:00",
                       "Default timecode should be 00:00:00:00")
    }

    func testDefaultClipNameIsEmpty() {
        let client = HyperDeckClient()
        XCTAssertEqual(client.currentClipName, "",
                       "Default clip name should be empty string")
    }

    func testDefaultLastErrorIsNil() {
        let client = HyperDeckClient()
        XCTAssertNil(client.lastError,
                     "Default lastError should be nil")
    }
}
