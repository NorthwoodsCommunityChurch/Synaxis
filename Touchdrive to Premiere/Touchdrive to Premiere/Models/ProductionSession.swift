import Foundation

struct ProductionSession: Codable, Identifiable {
    var id = UUID()
    var name: String
    var startTime: Date
    var endTime: Date?
    var events: [ProductionEvent] = []
    var cameraAssignments: [CameraAssignment] = []
    var systemOutputs: [CameraAssignment] = []
    var keyerAssignments: [KeyerAssignment] = []
    var proPresenterConfigs: [ProPresenterConfig] = []
    var frameRate: Double = 29.97
    var resolution: Resolution = Resolution()
    var startTimecode: String = "01:00:00:00"
    var timecodeSource: TimecodeSource = .hyperDeck
    var dropFrame: Bool = true

    init(name: String, startTime: Date = Date()) {
        self.name = name
        self.startTime = startTime
    }
}

struct Resolution: Codable, Equatable {
    var width: Int = 1920
    var height: Int = 1080

    var label: String { "\(width)x\(height)" }

    static let hd1080 = Resolution(width: 1920, height: 1080)
    static let uhd4k = Resolution(width: 3840, height: 2160)
    static let hd720 = Resolution(width: 1280, height: 720)
}

enum TimecodeSource: String, Codable, CaseIterable {
    case hyperDeck = "HyperDeck"
    case systemClock = "System Clock"
    case manual = "Manual"
}
