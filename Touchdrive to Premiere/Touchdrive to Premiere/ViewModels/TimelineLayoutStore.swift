//
//  TimelineLayoutStore.swift
//  Synaxis
//
//  Manages timeline track configuration, ordering, persistence, zoom,
//  and the computation of display clips from live production events.
//

import Foundation
import Observation
import OSLog
import SwiftUI

@Observable
final class TimelineLayoutStore {
    nonisolated deinit { }

    // MARK: - Track Configuration (Persisted)

    var tracks: [TimelineTrackConfig] = []

    // MARK: - Zoom & Scroll (View State, Not Persisted)

    /// Pixels per frame. At 29.97 fps a value of 2.0 means ~60 px/second.
    var pixelsPerFrame: Double = 2.0

    static let minPixelsPerFrame: Double = 0.1
    static let maxPixelsPerFrame: Double = 10.0

    /// Track lane height in points.
    var trackHeight: CGFloat = 48

    // MARK: - Sorted Tracks

    var sortedTracks: [TimelineTrackConfig] {
        tracks.sorted { $0.sortOrder < $1.sortOrder }
    }

    // MARK: - Init

    init() {
        load()
    }

    // MARK: - Track CRUD

    func addTrack(source: TimelineTrackSource, label: String, color: TrackColor = .blue) {
        let nextOrder = (tracks.map(\.sortOrder).max() ?? -1) + 1
        let track = TimelineTrackConfig(source: source, label: label, color: color, sortOrder: nextOrder)
        tracks.append(track)
        save()
    }

    func removeTrack(id: UUID) {
        tracks.removeAll { $0.id == id }
        reindex()
        save()
    }

    func moveTrack(from source: IndexSet, to destination: Int) {
        var sorted = sortedTracks
        sorted.move(fromOffsets: source, toOffset: destination)
        for (index, _) in sorted.enumerated() {
            if let trackIndex = tracks.firstIndex(where: { $0.id == sorted[index].id }) {
                tracks[trackIndex].sortOrder = index
            }
        }
        save()
    }

    func toggleTrack(id: UUID) {
        if let index = tracks.firstIndex(where: { $0.id == id }) {
            tracks[index].isEnabled.toggle()
            save()
        }
    }

    /// Generates a default track layout from current assignments (first-time setup).
    func generateDefaultTracks(assignments: AssignmentStore) {
        guard tracks.isEmpty else { return }

        var order = 0

        // Program cut track
        addTrack(source: .programCut, label: "Program", color: .blue)
        order += 1

        // One ISO track per camera
        let isoColors: [TrackColor] = [.cyan, .green, .orange, .yellow, .purple, .red]
        for (i, camera) in assignments.cameraAssignments.enumerated() {
            let color = isoColors[i % isoColors.count]
            addTrack(source: .cameraISO(cameraId: camera.id), label: camera.name, color: color)
            order += 1
        }

        // Graphics track
        addTrack(source: .graphics, label: "Graphics", color: .purple)
        order += 1

        // ProPresenter tracks
        for config in assignments.proPresenterConfigs {
            addTrack(source: .proPresenter(configId: config.id), label: config.name, color: .purple)
            order += 1
        }

        // HyperDeck track
        addTrack(source: .hyperDeck, label: "HyperDeck", color: .red)
    }

    /// Returns true if a source is already represented in the track list.
    func hasTrack(for source: TimelineTrackSource) -> Bool {
        tracks.contains { $0.source == source }
    }

    // MARK: - Clip Computation

    /// Derives TimelineClip arrays per track from the live event list.
    func computeClips(
        events: [ProductionEvent],
        session: ProductionSession?,
        frameRate: Double,
        liveDate: Date = Date()
    ) -> [UUID: [TimelineClip]] {
        guard let session else { return [:] }

        let sessionDurationFrames = {
            let endDate = session.endTime ?? liveDate
            return TimecodeHelpers.dateToFrames(endDate, sessionStart: session.startTime, frameRate: frameRate)
        }()

        var result: [UUID: [TimelineClip]] = [:]

        for track in tracks where track.isEnabled {
            let clips: [TimelineClip]
            switch track.source {
            case .programCut:
                clips = computeProgramCutClips(
                    events: events, session: session, frameRate: frameRate,
                    sessionDurationFrames: sessionDurationFrames, isLive: session.endTime == nil
                )
            case .cameraISO(let cameraId):
                clips = computeISOClip(
                    cameraId: cameraId, session: session,
                    sessionDurationFrames: sessionDurationFrames, isLive: session.endTime == nil
                )
            case .graphics:
                clips = computeGraphicsClips(
                    events: events, session: session, frameRate: frameRate
                )
            case .proPresenter(let configId):
                clips = computeProPresenterClips(
                    configId: configId, events: events, session: session,
                    frameRate: frameRate, sessionDurationFrames: sessionDurationFrames,
                    isLive: session.endTime == nil
                )
            case .hyperDeck:
                clips = computeHyperDeckClips(
                    events: events, session: session, frameRate: frameRate,
                    sessionDurationFrames: sessionDurationFrames, isLive: session.endTime == nil
                )
            }
            result[track.id] = clips
        }

        return result
    }

    // MARK: - Zoom

    func zoomIn() {
        pixelsPerFrame = min(pixelsPerFrame * 1.5, Self.maxPixelsPerFrame)
    }

    func zoomOut() {
        pixelsPerFrame = max(pixelsPerFrame / 1.5, Self.minPixelsPerFrame)
    }

    func zoomToFit(sessionDurationFrames: Int, viewWidth: CGFloat) {
        guard sessionDurationFrames > 0, viewWidth > 0 else { return }
        pixelsPerFrame = max(Self.minPixelsPerFrame, Double(viewWidth) / Double(sessionDurationFrames))
    }

    // MARK: - Persistence

    func load() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: Keys.timelineTracks),
           let stored = try? JSONDecoder().decode([TimelineTrackConfig].self, from: data) {
            tracks = stored
        }
        Log.ui.debug("Timeline layout loaded: \(self.tracks.count) tracks")
    }

    func save() {
        if let data = try? JSONEncoder().encode(tracks) {
            UserDefaults.standard.set(data, forKey: Keys.timelineTracks)
        }
        Log.ui.debug("Timeline layout saved")
    }

    // MARK: - Private Helpers

    private func reindex() {
        let sorted = tracks.sorted { $0.sortOrder < $1.sortOrder }
        for (index, track) in sorted.enumerated() {
            if let i = tracks.firstIndex(where: { $0.id == track.id }) {
                tracks[i].sortOrder = index
            }
        }
    }

    // MARK: - Program Cut Clips

    /// Mirrors PremiereXMLGenerator.programCutSegments().
    private func computeProgramCutClips(
        events: [ProductionEvent],
        session: ProductionSession,
        frameRate: Double,
        sessionDurationFrames: Int,
        isLive: Bool
    ) -> [TimelineClip] {
        let cutEvents = events.filter { $0.type == .programCut || $0.type == .transition }
        guard !cutEvents.isEmpty else { return [] }

        var clips: [TimelineClip] = []

        for (index, event) in cutEvents.enumerated() {
            guard let sourceIdx = event.payload.sourceIndex else { continue }

            let startFrame = TimecodeHelpers.dateToFrames(
                event.timestamp, sessionStart: session.startTime, frameRate: frameRate
            )

            let endFrame: Int
            let clipIsLive: Bool
            if index + 1 < cutEvents.count {
                endFrame = TimecodeHelpers.dateToFrames(
                    cutEvents[index + 1].timestamp,
                    sessionStart: session.startTime,
                    frameRate: frameRate
                )
                clipIsLive = false
            } else {
                endFrame = sessionDurationFrames
                clipIsLive = isLive
            }

            if endFrame > startFrame {
                let name = event.payload.sourceName ?? "Source \(sourceIdx)"
                clips.append(TimelineClip(
                    label: name,
                    startFrame: startFrame,
                    endFrame: endFrame,
                    sourceIndex: sourceIdx,
                    sourceName: name,
                    trackSource: .programCut,
                    isLive: clipIsLive
                ))
            }
        }

        return clips
    }

    // MARK: - ISO Clips

    private func computeISOClip(
        cameraId: UUID,
        session: ProductionSession,
        sessionDurationFrames: Int,
        isLive: Bool
    ) -> [TimelineClip] {
        guard let camera = session.cameraAssignments.first(where: { $0.id == cameraId }) else {
            return []
        }
        guard sessionDurationFrames > 0 else { return [] }

        return [TimelineClip(
            label: camera.name,
            startFrame: 0,
            endFrame: sessionDurationFrames,
            sourceIndex: camera.tslIndex,
            sourceName: camera.name,
            trackSource: .cameraISO(cameraId: cameraId),
            isLive: isLive
        )]
    }

    // MARK: - Graphics Clips

    /// Mirrors PremiereXMLGenerator.graphicsSegments().
    private func computeGraphicsClips(
        events: [ProductionEvent],
        session: ProductionSession,
        frameRate: Double
    ) -> [TimelineClip] {
        struct KeyerState {
            var isOn: Bool = false
            var segmentStartFrame: Int = 0
            var presentation: String?
            var slideIndex: Int?
            var slideText: String?
        }

        var keyerStates: [Int: KeyerState] = [:]
        for assignment in session.keyerAssignments {
            keyerStates[assignment.keyerNumber] = KeyerState()
        }

        var clips: [TimelineClip] = []

        for event in events {
            switch event.type {
            case .keyerOn:
                guard let keyerNum = event.payload.keyerNumber else { continue }
                let frame = TimecodeHelpers.dateToFrames(
                    event.timestamp, sessionStart: session.startTime, frameRate: frameRate
                )
                var state = keyerStates[keyerNum] ?? KeyerState()
                state.isOn = true
                state.segmentStartFrame = frame
                keyerStates[keyerNum] = state

            case .keyerOff:
                guard let keyerNum = event.payload.keyerNumber else { continue }
                let frame = TimecodeHelpers.dateToFrames(
                    event.timestamp, sessionStart: session.startTime, frameRate: frameRate
                )
                guard var state = keyerStates[keyerNum], state.isOn else { continue }

                if frame > state.segmentStartFrame {
                    let name = buildSlideClipName(
                        presentation: state.presentation,
                        slideIndex: state.slideIndex,
                        slideText: state.slideText,
                        keyerNumber: keyerNum
                    )
                    clips.append(TimelineClip(
                        label: name,
                        startFrame: state.segmentStartFrame,
                        endFrame: frame,
                        sourceIndex: nil,
                        sourceName: name,
                        trackSource: .graphics
                    ))
                }
                state.isOn = false
                state.segmentStartFrame = 0
                keyerStates[keyerNum] = state

            case .slideChange:
                guard let slideIdx = event.payload.slideIndex,
                      let presentation = event.payload.presentationName else { continue }
                let slideText = event.payload.slideText

                let matchingKeyerNum = session.keyerAssignments
                    .first(where: { $0.source == .proPresenter })?.keyerNumber ?? 1

                let frame = TimecodeHelpers.dateToFrames(
                    event.timestamp, sessionStart: session.startTime, frameRate: frameRate
                )

                if var state = keyerStates[matchingKeyerNum], state.isOn {
                    if frame > state.segmentStartFrame {
                        let name = buildSlideClipName(
                            presentation: state.presentation,
                            slideIndex: state.slideIndex,
                            slideText: state.slideText,
                            keyerNumber: matchingKeyerNum
                        )
                        clips.append(TimelineClip(
                            label: name,
                            startFrame: state.segmentStartFrame,
                            endFrame: frame,
                            sourceIndex: nil,
                            sourceName: name,
                            trackSource: .graphics
                        ))
                    }
                    state.segmentStartFrame = frame
                    state.presentation = presentation
                    state.slideIndex = slideIdx
                    state.slideText = slideText
                    keyerStates[matchingKeyerNum] = state
                } else {
                    var state = keyerStates[matchingKeyerNum] ?? KeyerState()
                    state.presentation = presentation
                    state.slideIndex = slideIdx
                    state.slideText = slideText
                    keyerStates[matchingKeyerNum] = state
                }

            default:
                break
            }
        }

        return clips
    }

    // MARK: - ProPresenter Clips

    private func computeProPresenterClips(
        configId: UUID,
        events: [ProductionEvent],
        session: ProductionSession,
        frameRate: Double,
        sessionDurationFrames: Int,
        isLive: Bool
    ) -> [TimelineClip] {
        let config = session.proPresenterConfigs.first(where: { $0.id == configId })
        let machineName = config?.name

        let slideEvents = events.filter { event in
            guard event.type == .slideChange else { return false }
            if let mn = machineName, let eventMachine = event.payload.machineName {
                return eventMachine == mn
            }
            return true
        }

        guard !slideEvents.isEmpty else { return [] }

        var clips: [TimelineClip] = []

        for (index, event) in slideEvents.enumerated() {
            guard let presentation = event.payload.presentationName,
                  let slideIdx = event.payload.slideIndex else { continue }

            let startFrame = TimecodeHelpers.dateToFrames(
                event.timestamp, sessionStart: session.startTime, frameRate: frameRate
            )

            let endFrame: Int
            let clipIsLive: Bool
            if index + 1 < slideEvents.count {
                endFrame = TimecodeHelpers.dateToFrames(
                    slideEvents[index + 1].timestamp,
                    sessionStart: session.startTime,
                    frameRate: frameRate
                )
                clipIsLive = false
            } else {
                endFrame = sessionDurationFrames
                clipIsLive = isLive
            }

            let slideText = event.payload.slideText ?? ""
            let label = slideText.isEmpty
                ? "\(presentation) - Slide \(slideIdx + 1)"
                : "\(presentation) - \(slideText.prefix(30))"

            if endFrame > startFrame {
                clips.append(TimelineClip(
                    label: label,
                    startFrame: startFrame,
                    endFrame: endFrame,
                    sourceIndex: nil,
                    sourceName: label,
                    trackSource: .proPresenter(configId: configId),
                    isLive: clipIsLive
                ))
            }
        }

        return clips
    }

    // MARK: - HyperDeck Clips

    private func computeHyperDeckClips(
        events: [ProductionEvent],
        session: ProductionSession,
        frameRate: Double,
        sessionDurationFrames: Int,
        isLive: Bool
    ) -> [TimelineClip] {
        var clips: [TimelineClip] = []
        var recordStartFrame: Int?
        var recordClipName: String?

        for event in events {
            switch event.type {
            case .recordStart:
                let frame = TimecodeHelpers.dateToFrames(
                    event.timestamp, sessionStart: session.startTime, frameRate: frameRate
                )
                recordStartFrame = frame
                if case .recordStart(let name) = event.payload {
                    recordClipName = name
                }

            case .recordStop:
                if let startFrame = recordStartFrame {
                    let endFrame = TimecodeHelpers.dateToFrames(
                        event.timestamp, sessionStart: session.startTime, frameRate: frameRate
                    )
                    let label = recordClipName ?? "Recording"
                    if endFrame > startFrame {
                        clips.append(TimelineClip(
                            label: label,
                            startFrame: startFrame,
                            endFrame: endFrame,
                            sourceIndex: nil,
                            sourceName: label,
                            trackSource: .hyperDeck
                        ))
                    }
                    recordStartFrame = nil
                    recordClipName = nil
                }

            default:
                break
            }
        }

        // If still recording, extend to session end
        if let startFrame = recordStartFrame {
            let label = recordClipName ?? "Recording"
            clips.append(TimelineClip(
                label: label,
                startFrame: startFrame,
                endFrame: sessionDurationFrames,
                sourceIndex: nil,
                sourceName: label,
                trackSource: .hyperDeck,
                isLive: isLive
            ))
        }

        return clips
    }

    // MARK: - Slide Clip Name

    private func buildSlideClipName(
        presentation: String?,
        slideIndex: Int?,
        slideText: String?,
        keyerNumber: Int
    ) -> String {
        var parts: [String] = []
        if let presentation, !presentation.isEmpty {
            parts.append(presentation)
        }
        if let index = slideIndex {
            parts.append("Slide \(index + 1)")
        }
        if let text = slideText, !text.isEmpty {
            let truncated = text.count > 30 ? String(text.prefix(30)) + "..." : text
            parts.append(truncated)
        }
        return parts.isEmpty ? "Keyer \(keyerNumber)" : parts.joined(separator: " - ")
    }

    // MARK: - Keys

    private enum Keys {
        static let timelineTracks = "timelineTracks_v1"
    }
}
