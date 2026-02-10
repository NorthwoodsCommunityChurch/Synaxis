//
//  TimelineTrackConfig.swift
//  Synaxis
//
//  Configuration for a single track lane in the timeline view.
//

import Foundation
import SwiftUI

// MARK: - Track Source Type

/// Identifies what device or data source drives a timeline track.
enum TimelineTrackSource: Codable, Equatable, Hashable {
    /// Program cut track (the switched output).
    case programCut
    /// ISO track for a specific camera (by CameraAssignment id).
    case cameraISO(cameraId: UUID)
    /// Graphics/keyer track (ProPresenter slides while keyer is ON).
    case graphics
    /// ProPresenter slide track for a specific machine (by ProPresenterConfig id).
    case proPresenter(configId: UUID)
    /// ISO track for a system output (program out, clean feed, etc.) by id.
    case systemOutput(outputId: UUID)
    /// HyperDeck recorder transport track.
    case hyperDeck
}

// MARK: - Track Color

/// Color palette for timeline track clips, matching Premiere/DaVinci conventions.
enum TrackColor: String, Codable, CaseIterable {
    case blue, cyan, green, orange, purple, red, yellow, gray

    var swiftUIColor: Color {
        switch self {
        case .blue:   return .blue
        case .cyan:   return .cyan
        case .green:  return .green
        case .orange: return .orange
        case .purple: return .purple
        case .red:    return .red
        case .yellow: return .yellow
        case .gray:   return .gray
        }
    }
}

// MARK: - Track Configuration

/// A single track lane in the timeline. Persisted to UserDefaults.
struct TimelineTrackConfig: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var source: TimelineTrackSource
    var label: String
    var color: TrackColor
    var isEnabled: Bool = true
    /// Vertical order index (0 = topmost track).
    var sortOrder: Int

    init(source: TimelineTrackSource, label: String, color: TrackColor = .blue, sortOrder: Int = 0) {
        self.source = source
        self.label = label
        self.color = color
        self.sortOrder = sortOrder
    }
}
