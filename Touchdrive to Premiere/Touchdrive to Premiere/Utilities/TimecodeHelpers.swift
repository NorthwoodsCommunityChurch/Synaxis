import Foundation

struct Timecode: Equatable, Codable, CustomStringConvertible {
    var hours: Int
    var minutes: Int
    var seconds: Int
    var frames: Int

    var description: String {
        let separator = isDropFrame ? ";" : ":"
        return String(format: "%02d:%02d:%02d%@%02d", hours, minutes, seconds, separator, frames)
    }

    var isDropFrame: Bool = false

    init(hours: Int = 0, minutes: Int = 0, seconds: Int = 0, frames: Int = 0, dropFrame: Bool = false) {
        self.hours = hours
        self.minutes = minutes
        self.seconds = seconds
        self.frames = frames
        self.isDropFrame = dropFrame
    }

    init?(string: String) {
        let dropFrame = string.contains(";")
        let cleaned = string.replacingOccurrences(of: ";", with: ":")
        let parts = cleaned.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 4 else { return nil }
        self.hours = parts[0]
        self.minutes = parts[1]
        self.seconds = parts[2]
        self.frames = parts[3]
        self.isDropFrame = dropFrame
    }
}

enum TimecodeHelpers {

    /// Whether a frame rate is NTSC (requires special timecode handling)
    static func isNTSC(_ frameRate: Double) -> Bool {
        let ntscRates: [Double] = [23.976, 29.97, 59.94]
        return ntscRates.contains(where: { abs($0 - frameRate) < 0.01 })
    }

    /// The integer timebase for a given frame rate (used in xmeml)
    static func timebase(for frameRate: Double) -> Int {
        if abs(frameRate - 23.976) < 0.01 { return 24 }
        if abs(frameRate - 29.97) < 0.01 { return 30 }
        if abs(frameRate - 59.94) < 0.01 { return 60 }
        return Int(frameRate.rounded())
    }

    /// Whether drop-frame should be used for this frame rate
    static func supportsDropFrame(_ frameRate: Double) -> Bool {
        abs(frameRate - 29.97) < 0.01 || abs(frameRate - 59.94) < 0.01
    }

    /// Convert timecode to total frame count
    static func timecodeToFrames(_ tc: Timecode, frameRate: Double, dropFrame: Bool) -> Int {
        let tb = timebase(for: frameRate)
        let totalFrames = tc.hours * 3600 * tb
            + tc.minutes * 60 * tb
            + tc.seconds * tb
            + tc.frames

        if dropFrame && supportsDropFrame(frameRate) {
            // Drop-frame skips frame numbers 0 and 1 at the start of each minute,
            // EXCEPT every 10th minute.
            // For 29.97: drop 2 frames. For 59.94: drop 4 frames.
            let dropCount = (abs(frameRate - 59.94) < 0.01) ? 4 : 2
            let totalMinutes = tc.hours * 60 + tc.minutes
            let tens = totalMinutes / 10
            let units = totalMinutes % 10
            let dropped = dropCount * (totalMinutes - tens)
            // Alternatively, a more standard formula:
            // dropped = dropCount * (totalMinutes - totalMinutes / 10)
            return totalFrames - dropped
        }

        return totalFrames
    }

    /// Convert total frame count to timecode
    static func framesToTimecode(_ totalFrames: Int, frameRate: Double, dropFrame: Bool) -> Timecode {
        let tb = timebase(for: frameRate)

        if dropFrame && supportsDropFrame(frameRate) {
            let dropCount = (abs(frameRate - 59.94) < 0.01) ? 4 : 2
            let framesPerMinute = tb * 60 - dropCount
            let framesPer10Min = framesPerMinute * 10 + dropCount

            let d = totalFrames / framesPer10Min
            let m = totalFrames % framesPer10Min

            var adjustedFrames: Int
            if m < dropCount {
                adjustedFrames = totalFrames + dropCount * d * 9
            } else {
                adjustedFrames = totalFrames
                    + dropCount * d * 9
                    + dropCount * ((m - dropCount) / framesPerMinute)
            }

            // Now convert adjusted non-drop frame count
            let f = adjustedFrames % tb
            let s = (adjustedFrames / tb) % 60
            let min = (adjustedFrames / (tb * 60)) % 60
            let h = adjustedFrames / (tb * 3600)

            return Timecode(hours: h, minutes: min, seconds: s, frames: f, dropFrame: true)
        }

        let f = totalFrames % tb
        let s = (totalFrames / tb) % 60
        let min = (totalFrames / (tb * 60)) % 60
        let h = totalFrames / (tb * 3600)

        return Timecode(hours: h, minutes: min, seconds: s, frames: f, dropFrame: false)
    }

    /// Convert a timecode string to total frames
    static func stringToFrames(_ tcString: String, frameRate: Double, dropFrame: Bool) -> Int? {
        guard let tc = Timecode(string: tcString) else { return nil }
        return timecodeToFrames(tc, frameRate: frameRate, dropFrame: dropFrame)
    }

    /// Convert total frames to a timecode string
    static func framesToString(_ totalFrames: Int, frameRate: Double, dropFrame: Bool) -> String {
        framesToTimecode(totalFrames, frameRate: frameRate, dropFrame: dropFrame).description
    }

    /// Convert a Date to a frame count relative to a session start
    static func dateToFrames(_ date: Date, sessionStart: Date, frameRate: Double) -> Int {
        let elapsed = date.timeIntervalSince(sessionStart)
        return Int(elapsed * frameRate)
    }

    /// Validate a timecode string format
    static func isValidTimecode(_ string: String) -> Bool {
        Timecode(string: string) != nil
    }
}
