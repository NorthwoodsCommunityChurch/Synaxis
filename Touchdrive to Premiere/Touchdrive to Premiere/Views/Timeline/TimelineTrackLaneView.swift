//
//  TimelineTrackLaneView.swift
//  Synaxis
//
//  A single horizontal track lane containing positioned clip rectangles.
//

import SwiftUI

struct TimelineTrackLaneView: View {
    let track: TimelineTrackConfig
    let clips: [TimelineClip]
    let canvasWidth: Double
    let pixelsPerFrame: Double
    let trackHeight: CGFloat

    var body: some View {
        ZStack(alignment: .leading) {
            // Track background
            Rectangle()
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.3))

            // Bottom separator
            VStack {
                Spacer()
                Rectangle()
                    .fill(Color.secondary.opacity(0.2))
                    .frame(height: 1)
            }

            // Clips positioned by frame offset
            ForEach(clips) { clip in
                let clipWidth = max(CGFloat(clip.endFrame - clip.startFrame) * pixelsPerFrame, 2)
                let offsetX = CGFloat(clip.startFrame) * pixelsPerFrame

                TimelineClipView(clip: clip, color: track.color)
                    .frame(width: clipWidth, height: trackHeight - 6)
                    .offset(x: offsetX)
            }
        }
        .frame(height: trackHeight)
        .opacity(track.isEnabled ? 1.0 : 0.4)
    }
}
