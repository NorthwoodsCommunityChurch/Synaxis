//
//  TimelineCanvasView.swift
//  Synaxis
//
//  Scrollable timeline area: timecode ruler at top + track lanes below.
//

import Combine
import SwiftUI

struct TimelineCanvasView: View {
    @Environment(SessionManager.self) private var sessionManager
    @Environment(SettingsManager.self) private var settings
    @Environment(TimelineLayoutStore.self) private var layout

    /// Ticks at 0.5 s to grow the live final clip.
    @State private var liveTickDate = Date()

    var body: some View {
        let events = sessionManager.events
        let session = sessionManager.currentSession
        let frameRate = settings.frameRate
        let clips = layout.computeClips(
            events: events, session: session,
            frameRate: frameRate, liveDate: liveTickDate
        )

        let sessionDurationFrames = computeSessionDuration(
            session: session, frameRate: frameRate
        )
        let canvasWidth = max(Double(sessionDurationFrames) * layout.pixelsPerFrame, 100)

        VStack(spacing: 0) {
            // Timecode ruler — scrolls horizontally with canvas
            ScrollView(.horizontal, showsIndicators: false) {
                TimelineRulerView(
                    durationFrames: sessionDurationFrames,
                    pixelsPerFrame: layout.pixelsPerFrame,
                    frameRate: frameRate,
                    dropFrame: settings.dropFrame,
                    startTimecode: settings.startTimecode
                )
                .frame(width: canvasWidth)
            }

            // Track lanes
            ScrollView([.horizontal, .vertical]) {
                VStack(spacing: 0) {
                    ForEach(layout.sortedTracks) { track in
                        TimelineTrackLaneView(
                            track: track,
                            clips: clips[track.id] ?? [],
                            canvasWidth: canvasWidth,
                            pixelsPerFrame: layout.pixelsPerFrame,
                            trackHeight: layout.trackHeight
                        )
                    }
                }
                .frame(width: canvasWidth)
            }
        }
        .onReceive(
            Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()
        ) { date in
            if sessionManager.isRecording {
                liveTickDate = date
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func computeSessionDuration(session: ProductionSession?, frameRate: Double) -> Int {
        guard let session else { return 0 }
        let endDate = session.endTime ?? liveTickDate
        return TimecodeHelpers.dateToFrames(
            endDate, sessionStart: session.startTime, frameRate: frameRate
        )
    }
}
