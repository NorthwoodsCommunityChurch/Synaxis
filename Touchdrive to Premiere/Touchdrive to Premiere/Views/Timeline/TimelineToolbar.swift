//
//  TimelineToolbar.swift
//  Synaxis
//
//  Bottom toolbar with current timecode readout and zoom controls.
//

import SwiftUI

struct TimelineToolbar: View {
    @Environment(TimelineLayoutStore.self) private var layout
    @Environment(ConnectionManager.self) private var connectionManager
    @Environment(SessionManager.self) private var sessionManager
    @Environment(SettingsManager.self) private var settings

    var body: some View {
        @Bindable var layout = layout

        HStack(spacing: 12) {
            // Current timecode
            Text(connectionManager.currentTimecode)
                .font(.system(.body, design: .monospaced))
                .frame(width: 120, alignment: .leading)

            // Event count
            if sessionManager.isRecording {
                Text("\(sessionManager.eventCount) events")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Zoom controls
            Button(action: { layout.zoomOut() }) {
                Image(systemName: "minus.magnifyingglass")
            }
            .buttonStyle(.borderless)

            Slider(
                value: $layout.pixelsPerFrame,
                in: TimelineLayoutStore.minPixelsPerFrame...TimelineLayoutStore.maxPixelsPerFrame
            )
            .frame(width: 120)

            Button(action: { layout.zoomIn() }) {
                Image(systemName: "plus.magnifyingglass")
            }
            .buttonStyle(.borderless)

            Button("Fit") {
                let session = sessionManager.currentSession
                let frameRate = settings.frameRate
                if let session {
                    let endDate = session.endTime ?? Date()
                    let duration = TimecodeHelpers.dateToFrames(
                        endDate, sessionStart: session.startTime, frameRate: frameRate
                    )
                    // Approximate visible width; actual GeometryReader-based fit would be more precise
                    layout.zoomToFit(sessionDurationFrames: duration, viewWidth: 800)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}
