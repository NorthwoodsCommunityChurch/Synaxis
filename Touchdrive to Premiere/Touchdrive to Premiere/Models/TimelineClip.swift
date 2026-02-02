//
//  TimelineClip.swift
//  Synaxis
//
//  A computed display model representing a clip rectangle on a timeline track.
//  Not persisted — derived from live production events each render cycle.
//

import Foundation

struct TimelineClip: Identifiable {
    let id: UUID = UUID()
    let label: String
    let startFrame: Int
    let endFrame: Int
    let sourceIndex: Int?
    let sourceName: String
    let trackSource: TimelineTrackSource
    /// Whether this clip is still open (session is live, no end event yet).
    var isLive: Bool = false
}
