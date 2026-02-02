//
//  TimelineHeaderColumn.swift
//  Synaxis
//
//  Left-side column showing track labels with drag-to-reorder and add button.
//

import SwiftUI

struct TimelineHeaderColumn: View {
    @Environment(TimelineLayoutStore.self) private var layout

    @State private var showingAddTrackPopover = false

    var body: some View {
        VStack(spacing: 0) {
            // Gap aligned with ruler height
            Rectangle()
                .fill(Color(nsColor: .controlBackgroundColor))
                .frame(height: 28)
                .overlay(alignment: .leading) {
                    Text("Tracks")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 8)
                }

            Divider()

            // Track headers
            List {
                ForEach(layout.sortedTracks) { track in
                    TimelineTrackHeaderView(
                        track: track,
                        onToggle: { layout.toggleTrack(id: track.id) },
                        onRemove: { layout.removeTrack(id: track.id) }
                    )
                    .frame(height: layout.trackHeight - 1)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                }
                .onMove { source, destination in
                    layout.moveTrack(from: source, to: destination)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)

            Divider()

            // Add track button
            Button(action: { showingAddTrackPopover = true }) {
                Label("Add Track", systemImage: "plus")
                    .font(.system(size: 11))
            }
            .buttonStyle(.borderless)
            .padding(8)
            .popover(isPresented: $showingAddTrackPopover) {
                AddTrackPopover()
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }
}
