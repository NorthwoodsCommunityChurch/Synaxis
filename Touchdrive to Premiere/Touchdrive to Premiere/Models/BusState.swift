import Foundation
import Observation

struct TallyState: Equatable, Codable, Sendable {
    var program: Bool = false
    var preview: Bool = false
    var brightness: Int = 0

    static let off = TallyState()
}

struct SourceState: Identifiable, Equatable, Codable, Sendable {
    var id: Int { index }
    let index: Int
    var busLabel: String
    var sourceLabel: String
    var tally: TallyState

    var fullLabel: String {
        if sourceLabel.isEmpty { return busLabel }
        if busLabel.isEmpty { return sourceLabel }
        return "\(busLabel):\(sourceLabel)"
    }
}

/// Tracks the complete TSL state model — which source is on program/preview for each bus.
@Observable
final class BusStateModel {
    nonisolated deinit { }

    /// All known sources keyed by TSL index
    var sources: [Int: SourceState] = [:]

    /// Current program source index per bus (e.g., "ME1PGM" -> 3)
    var programSourcePerBus: [String: Int] = [:]

    /// Current preview source index per bus
    var previewSourcePerBus: [String: Int] = [:]

    /// Called when a TSL message updates a source's state.
    /// Returns the bus name if the program source changed, nil otherwise.
    @discardableResult
    func update(index: Int, tally: TallyState, busLabel: String, sourceLabel: String) -> String? {
        let newSource = SourceState(index: index, busLabel: busLabel, sourceLabel: sourceLabel, tally: tally)
        let previous = sources[index]
        sources[index] = newSource

        var programChanged: String? = nil

        // Track program source per bus
        if tally.program {
            let previousProgram = programSourcePerBus[busLabel]
            programSourcePerBus[busLabel] = index
            // Only emit a change when a bus was already tracked with a different source.
            // First time seeing a bus (previousProgram == nil) is initial state, not a cut.
            if let prev = previousProgram, prev != index {
                programChanged = busLabel
            }
        }

        // Track preview source per bus
        if tally.preview {
            previewSourcePerBus[busLabel] = index
        }

        return programChanged
    }

    /// Get the current program source index for a bus
    func currentProgramSource(for bus: String) -> SourceState? {
        guard let index = programSourcePerBus[bus] else { return nil }
        return sources[index]
    }

    /// Get all known bus labels
    var busLabels: [String] {
        Array(Set(sources.values.map(\.busLabel))).sorted()
    }

    /// Reset all state
    func reset() {
        sources.removeAll()
        programSourcePerBus.removeAll()
        previewSourcePerBus.removeAll()
    }
}
