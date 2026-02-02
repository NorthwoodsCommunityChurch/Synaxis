//
//  TimelineClipView.swift
//  Synaxis
//
//  A single clip rectangle on a timeline track lane.
//

import SwiftUI

struct TimelineClipView: View {
    let clip: TimelineClip
    let color: TrackColor

    var body: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(color.swiftUIColor.opacity(0.7))
            .overlay(alignment: .leading) {
                Text(clip.label)
                    .font(.system(size: 10))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .padding(.horizontal, 4)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .strokeBorder(
                        clip.isLive ? color.swiftUIColor : color.swiftUIColor.opacity(0.5),
                        lineWidth: clip.isLive ? 2 : 0.5
                    )
            )
            .padding(.vertical, 3)
    }
}
