//
//  TimelineTrackHeaderView.swift
//  Synaxis
//
//  A single track header row showing color swatch, label, and enable toggle.
//

import SwiftUI

struct TimelineTrackHeaderView: View {
    let track: TimelineTrackConfig
    let onToggle: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            // Color swatch
            RoundedRectangle(cornerRadius: 2)
                .fill(track.color.swiftUIColor)
                .frame(width: 4)

            // Track label
            Text(track.label)
                .font(.system(size: 11))
                .fontWeight(.medium)
                .lineLimit(1)
                .foregroundStyle(track.isEnabled ? .primary : .secondary)

            Spacer()

            // Mute/enable toggle
            Button(action: onToggle) {
                Image(systemName: track.isEnabled ? "eye" : "eye.slash")
                    .font(.system(size: 10))
                    .foregroundStyle(track.isEnabled ? .secondary : .tertiary)
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 8)
        .opacity(track.isEnabled ? 1.0 : 0.5)
        .contextMenu {
            Button("Remove Track", role: .destructive, action: onRemove)
        }
    }
}
