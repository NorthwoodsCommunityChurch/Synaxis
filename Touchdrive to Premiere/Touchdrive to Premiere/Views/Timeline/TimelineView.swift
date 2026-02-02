//
//  TimelineView.swift
//  Synaxis
//
//  Main container for the Timeline tab. Hosts recording controls at top,
//  an HSplitView with track headers and scrollable canvas, and a toolbar.
//

import SwiftUI

struct TimelineView: View {
    @Environment(SessionManager.self) private var sessionManager
    @Environment(AssignmentStore.self) private var assignments
    @Environment(TimelineLayoutStore.self) private var layout

    var body: some View {
        VStack(spacing: 0) {
            // Recording, preview, and export controls (moved from Dashboard)
            RecordingControlsView()
                .padding()

            Divider()

            // Main timeline area
            if layout.tracks.isEmpty {
                emptyState
            } else {
                HSplitView {
                    // Left: Track headers (fixed width)
                    TimelineHeaderColumn()
                        .frame(minWidth: 140, idealWidth: 180, maxWidth: 240)

                    // Right: Scrollable timeline canvas
                    TimelineCanvasView()
                }
            }

            Divider()

            // Bottom toolbar: timecode + zoom
            TimelineToolbar()
        }
        .onAppear {
            layout.generateDefaultTracks(assignments: assignments)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "timeline.selection")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)

            Text("No Tracks Configured")
                .font(.title3)
                .fontWeight(.medium)

            Text("Add cameras, ProPresenter machines, or HyperDecks\nfrom the Configuration tab, then add them as tracks here.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button(action: { layout.generateDefaultTracks(assignments: assignments) }) {
                Label("Generate Default Layout", systemImage: "wand.and.stars")
            }
            .buttonStyle(.bordered)
            .disabled(assignments.cameraAssignments.isEmpty
                      && assignments.proPresenterConfigs.isEmpty)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
