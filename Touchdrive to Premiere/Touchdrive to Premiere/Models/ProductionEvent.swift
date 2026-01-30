import Foundation

// MARK: - Event Type

enum EventType: String, Codable, CaseIterable {
    case programCut
    case transition
    case keyerOn
    case keyerOff
    case slideChange
    case fadeToBlack
    case recordStart
    case recordStop
    case connectionChange

    var label: String {
        switch self {
        case .programCut: return "Cut"
        case .transition: return "Transition"
        case .keyerOn: return "Keyer On"
        case .keyerOff: return "Keyer Off"
        case .slideChange: return "Slide"
        case .fadeToBlack: return "FTB"
        case .recordStart: return "Rec Start"
        case .recordStop: return "Rec Stop"
        case .connectionChange: return "Connection"
        }
    }

    var iconName: String {
        switch self {
        case .programCut: return "film"
        case .transition: return "arrow.right.arrow.left"
        case .keyerOn: return "square.stack.3d.up.fill"
        case .keyerOff: return "square.stack.3d.up.slash"
        case .slideChange: return "text.below.photo"
        case .fadeToBlack: return "moon.fill"
        case .recordStart: return "record.circle"
        case .recordStop: return "stop.circle"
        case .connectionChange: return "network"
        }
    }
}

// MARK: - Event Payload

enum EventPayload: Codable, Equatable {
    case programCut(sourceIndex: Int, sourceName: String, busName: String)
    case transition(sourceIndex: Int, sourceName: String, busName: String, type: String?)
    case keyerOn(meNumber: Int, keyerNumber: Int)
    case keyerOff(meNumber: Int, keyerNumber: Int)
    case slideChange(presentationName: String, slideIndex: Int, slideText: String, machineName: String? = nil)
    case fadeToBlack(active: Bool)
    case recordStart(clipName: String?)
    case recordStop(clipName: String?)
    case connectionChange(service: String, connected: Bool, detail: String?)

    var sourceIndex: Int? {
        switch self {
        case .programCut(let idx, _, _), .transition(let idx, _, _, _): return idx
        default: return nil
        }
    }

    var sourceName: String? {
        switch self {
        case .programCut(_, let name, _), .transition(_, let name, _, _): return name
        default: return nil
        }
    }

    var busName: String? {
        switch self {
        case .programCut(_, _, let bus), .transition(_, _, let bus, _): return bus
        default: return nil
        }
    }

    var meNumber: Int? {
        switch self {
        case .keyerOn(let me, _), .keyerOff(let me, _): return me
        default: return nil
        }
    }

    var keyerNumber: Int? {
        switch self {
        case .keyerOn(_, let k), .keyerOff(_, let k): return k
        default: return nil
        }
    }

    var slideText: String? {
        switch self {
        case .slideChange(_, _, let text, _): return text
        default: return nil
        }
    }

    var presentationName: String? {
        switch self {
        case .slideChange(let name, _, _, _): return name
        default: return nil
        }
    }

    var slideIndex: Int? {
        switch self {
        case .slideChange(_, let idx, _, _): return idx
        default: return nil
        }
    }

    var machineName: String? {
        switch self {
        case .slideChange(_, _, _, let name): return name
        default: return nil
        }
    }
}

// MARK: - Production Event

struct ProductionEvent: Identifiable, Codable, Equatable {
    let id: UUID
    let timestamp: Date
    let timecode: String
    let type: EventType
    let payload: EventPayload

    init(type: EventType, payload: EventPayload, timecode: String = "00:00:00:00", timestamp: Date = Date()) {
        self.id = UUID()
        self.timestamp = timestamp
        self.timecode = timecode
        self.type = type
        self.payload = payload
    }

    var description: String {
        switch payload {
        case .programCut(_, let name, let bus):
            return "Cut to \(name) on \(bus)"
        case .transition(_, let name, let bus, let transType):
            let t = transType.map { " (\($0))" } ?? ""
            return "Transition to \(name) on \(bus)\(t)"
        case .keyerOn(let me, let keyer):
            return "Keyer \(keyer) ON (ME\(me))"
        case .keyerOff(let me, let keyer):
            return "Keyer \(keyer) OFF (ME\(me))"
        case .slideChange(let pres, let idx, _, let machine):
            let prefix = machine.map { "[\($0)] " } ?? ""
            return "\(prefix)Slide \(idx) — \(pres)"
        case .fadeToBlack(let active):
            return active ? "Fade to Black" : "Fade from Black"
        case .recordStart(let clip):
            return "Recording started\(clip.map { ": \($0)" } ?? "")"
        case .recordStop(let clip):
            return "Recording stopped\(clip.map { ": \($0)" } ?? "")"
        case .connectionChange(let service, let connected, let detail):
            let state = connected ? "connected" : "disconnected"
            return "\(service) \(state)\(detail.map { " — \($0)" } ?? "")"
        }
    }
}
