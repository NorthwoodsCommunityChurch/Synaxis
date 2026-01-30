import XCTest
@testable import Touchdrive_to_Premiere

@MainActor
final class TimecodeTests: XCTestCase {

    // MARK: - NTSC Detection

    func testIsNTSC() {
        XCTAssertTrue(TimecodeHelpers.isNTSC(23.976), "23.976 should be NTSC")
        XCTAssertTrue(TimecodeHelpers.isNTSC(29.97), "29.97 should be NTSC")
        XCTAssertTrue(TimecodeHelpers.isNTSC(59.94), "59.94 should be NTSC")

        XCTAssertFalse(TimecodeHelpers.isNTSC(24), "24 should not be NTSC")
        XCTAssertFalse(TimecodeHelpers.isNTSC(25), "25 should not be NTSC")
        XCTAssertFalse(TimecodeHelpers.isNTSC(30), "30 should not be NTSC")
        XCTAssertFalse(TimecodeHelpers.isNTSC(60), "60 should not be NTSC")
    }

    // MARK: - Timebase

    func testTimebase() {
        XCTAssertEqual(TimecodeHelpers.timebase(for: 23.976), 24, "23.976 timebase should be 24")
        XCTAssertEqual(TimecodeHelpers.timebase(for: 29.97), 30, "29.97 timebase should be 30")
        XCTAssertEqual(TimecodeHelpers.timebase(for: 59.94), 60, "59.94 timebase should be 60")
        XCTAssertEqual(TimecodeHelpers.timebase(for: 25), 25, "25 timebase should be 25")
        XCTAssertEqual(TimecodeHelpers.timebase(for: 30), 30, "30 timebase should be 30")
    }

    // MARK: - Drop Frame Support

    func testSupportsDropFrame() {
        XCTAssertTrue(TimecodeHelpers.supportsDropFrame(29.97), "29.97 should support drop frame")
        XCTAssertTrue(TimecodeHelpers.supportsDropFrame(59.94), "59.94 should support drop frame")

        XCTAssertFalse(TimecodeHelpers.supportsDropFrame(23.976), "23.976 should not support drop frame")
        XCTAssertFalse(TimecodeHelpers.supportsDropFrame(24), "24 should not support drop frame")
        XCTAssertFalse(TimecodeHelpers.supportsDropFrame(25), "25 should not support drop frame")
        XCTAssertFalse(TimecodeHelpers.supportsDropFrame(30), "30 should not support drop frame")
        XCTAssertFalse(TimecodeHelpers.supportsDropFrame(60), "60 should not support drop frame")
    }

    // MARK: - Timecode to Frames (Non-Drop)

    func testTimecodeToFramesNonDrop() {
        // 01:00:00:00 at 30fps non-drop = 1 * 60 * 60 * 30 = 108000 frames
        let tc = Timecode(string: "01:00:00:00")!
        let frames = TimecodeHelpers.timecodeToFrames(tc, frameRate: 30, dropFrame: false)
        XCTAssertEqual(frames, 108000, "01:00:00:00 at 30fps non-drop should be 108000 frames")
    }

    func testTimecodeToFramesNonDropZero() {
        let tc = Timecode(string: "00:00:00:00")!
        let frames = TimecodeHelpers.timecodeToFrames(tc, frameRate: 30, dropFrame: false)
        XCTAssertEqual(frames, 0, "00:00:00:00 should be 0 frames")
    }

    func testTimecodeToFramesNonDropOneSecond() {
        // 00:00:01:00 at 30fps = 30 frames
        let tc = Timecode(string: "00:00:01:00")!
        let frames = TimecodeHelpers.timecodeToFrames(tc, frameRate: 30, dropFrame: false)
        XCTAssertEqual(frames, 30, "00:00:01:00 at 30fps should be 30 frames")
    }

    // MARK: - Timecode to Frames (Drop Frame 29.97)

    func testTimecodeToFramesDrop2997() {
        // 01:00:00:00 at 29.97 drop frame
        // Standard DF calculation: 1 hour at 29.97df = 107892 frames
        // (30 * 60 * 60 = 108000) - (2 drops/min * 60 min) + (2 added back for 10th-min * 6) = 108000 - 120 + 12 = 107892
        let tc = Timecode(string: "01:00:00:00")!
        let frames = TimecodeHelpers.timecodeToFrames(tc, frameRate: 29.97, dropFrame: true)

        // The standard drop-frame formula for 29.97:
        // Total frames = 108000 - 2*(60-6) = 108000 - 108 = 107892
        XCTAssertEqual(frames, 107892, "01:00:00:00 at 29.97df should be 107892 frames")
    }

    // MARK: - Round Trip

    func testFramesToTimecodeRoundTrip() {
        let testCases: [(String, Double, Bool)] = [
            ("00:00:00:00", 30, false),
            ("00:01:00:00", 30, false),
            ("01:00:00:00", 30, false),
            ("00:00:30:15", 30, false),
            ("01:02:03:04", 24, false),
            ("00:10:00:00", 29.97, true),
            ("01:00:00:00", 29.97, true),
        ]

        for (tcString, frameRate, dropFrame) in testCases {
            guard let tc = Timecode(string: tcString) else {
                XCTFail("Failed to parse timecode string: \(tcString)")
                continue
            }

            let frames = TimecodeHelpers.timecodeToFrames(tc, frameRate: frameRate, dropFrame: dropFrame)
            let result = TimecodeHelpers.framesToTimecode(frames, frameRate: frameRate, dropFrame: dropFrame)

            XCTAssertEqual(result.hours, tc.hours,
                           "Round trip failed for \(tcString) at \(frameRate)fps (drop=\(dropFrame)): hours mismatch")
            XCTAssertEqual(result.minutes, tc.minutes,
                           "Round trip failed for \(tcString) at \(frameRate)fps (drop=\(dropFrame)): minutes mismatch")
            XCTAssertEqual(result.seconds, tc.seconds,
                           "Round trip failed for \(tcString) at \(frameRate)fps (drop=\(dropFrame)): seconds mismatch")
            XCTAssertEqual(result.frames, tc.frames,
                           "Round trip failed for \(tcString) at \(frameRate)fps (drop=\(dropFrame)): frames mismatch")
        }
    }

    // MARK: - String to Frames

    func testStringToFrames() {
        let frames = TimecodeHelpers.stringToFrames("01:00:00:00", frameRate: 30, dropFrame: false)
        XCTAssertNotNil(frames, "stringToFrames should return a value for a valid timecode string")
        XCTAssertEqual(frames, 108000, "01:00:00:00 at 30fps non-drop should be 108000 frames")
    }

    func testStringToFramesInvalidString() {
        let frames = TimecodeHelpers.stringToFrames("invalid", frameRate: 30, dropFrame: false)
        XCTAssertNil(frames, "stringToFrames should return nil for an invalid timecode string")
    }

    // MARK: - Frames to String

    func testFramesToString() {
        let result = TimecodeHelpers.framesToString(108000, frameRate: 30, dropFrame: false)
        XCTAssertEqual(result, "01:00:00:00", "108000 frames at 30fps non-drop should format as 01:00:00:00")
    }

    // MARK: - Timecode String Parsing

    func testTimecodeStringParsing() {
        let tc = Timecode(string: "01:02:03:04")
        XCTAssertNotNil(tc, "Timecode should parse a valid colon-separated string")
        XCTAssertEqual(tc?.hours, 1, "Hours should be 1")
        XCTAssertEqual(tc?.minutes, 2, "Minutes should be 2")
        XCTAssertEqual(tc?.seconds, 3, "Seconds should be 3")
        XCTAssertEqual(tc?.frames, 4, "Frames should be 4")
        XCTAssertFalse(tc?.isDropFrame ?? true, "Colon-separated timecode should not be drop frame")
    }

    func testDropFrameSemicolon() {
        let tc = Timecode(string: "01:00:00;00")
        XCTAssertNotNil(tc, "Timecode should parse a semicolon drop-frame string")
        XCTAssertTrue(tc?.isDropFrame ?? false, "Semicolon-separated frames should indicate drop frame")
        XCTAssertEqual(tc?.hours, 1)
        XCTAssertEqual(tc?.minutes, 0)
        XCTAssertEqual(tc?.seconds, 0)
        XCTAssertEqual(tc?.frames, 0)
    }

    func testTimecodeInvalidStringReturnsNil() {
        XCTAssertNil(Timecode(string: ""), "Empty string should return nil")
        XCTAssertNil(Timecode(string: "abc"), "Non-numeric string should return nil")
        XCTAssertNil(Timecode(string: "01:02"), "Incomplete timecode should return nil")
    }

    // MARK: - Date to Frames

    func testDateToFrames() {
        let sessionStart = Date()
        let tenSecondsLater = sessionStart.addingTimeInterval(10.0)
        let frames = TimecodeHelpers.dateToFrames(tenSecondsLater, sessionStart: sessionStart, frameRate: 29.97)

        // 10 seconds at 29.97fps ~ 299.7 frames, should round to approximately 299 or 300
        XCTAssertTrue(frames >= 299 && frames <= 300,
                      "10 seconds at 29.97fps should produce approximately 299-300 frames, got \(frames)")
    }

    func testDateToFramesZeroElapsed() {
        let sessionStart = Date()
        let frames = TimecodeHelpers.dateToFrames(sessionStart, sessionStart: sessionStart, frameRate: 30)
        XCTAssertEqual(frames, 0, "Zero elapsed time should produce 0 frames")
    }
}
