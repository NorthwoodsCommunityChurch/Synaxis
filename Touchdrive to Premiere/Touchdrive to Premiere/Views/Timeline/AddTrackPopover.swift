//
//  AddTrackPopover.swift
//  Synaxis
//
//  Popover listing available device sources that can be added as timeline tracks.
//

import SwiftUI

struct AddTrackPopover: View {
    @Environment(TimelineLayoutStore.self) private var layout
    @Environment(AssignmentStore.self) private var assignments
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Add Track")
                .font(.headline)
                .padding(.bottom, 4)

            let available = availableSources()

            if available.isEmpty {
                Text("All configured devices are already in the timeline.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            } else {
                ForEach(available, id: \.label) { item in
                    Button(action: {
                        layout.addTrack(source: item.source, label: item.label, color: item.color)
                        dismiss()
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: item.icon)
                                .frame(width: 16)
                            Text(item.label)
                            Spacer()
                            Circle()
                                .fill(item.color.swiftUIColor)
                                .frame(width: 8, height: 8)
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 2)
                }
            }
        }
        .padding()
        .frame(width: 260)
    }

    // MARK: - Available Sources

    private struct AvailableTrackSource {
        let source: TimelineTrackSource
        let label: String
        let icon: String
        let color: TrackColor
    }

    private func availableSources() -> [AvailableTrackSource] {
        var sources: [AvailableTrackSource] = []

        // Program cut
        if !layout.hasTrack(for: .programCut) {
            sources.append(AvailableTrackSource(
                source: .programCut, label: "Program", icon: "film", color: .blue
            ))
        }

        // Camera ISOs
        for camera in assignments.cameraAssignments {
            let source = TimelineTrackSource.cameraISO(cameraId: camera.id)
            if !layout.hasTrack(for: source) {
                sources.append(AvailableTrackSource(
                    source: source, label: camera.name, icon: "video", color: .cyan
                ))
            }
        }

        // System Outputs
        for output in assignments.systemOutputs {
            let source = TimelineTrackSource.systemOutput(outputId: output.id)
            if !layout.hasTrack(for: source) {
                sources.append(AvailableTrackSource(
                    source: source, label: output.name, icon: "rectangle.on.rectangle", color: .orange
                ))
            }
        }

        // Graphics
        if !layout.hasTrack(for: .graphics) {
            sources.append(AvailableTrackSource(
                source: .graphics, label: "Graphics", icon: "square.stack.3d.up.fill", color: .green
            ))
        }

        // ProPresenter machines
        for config in assignments.proPresenterConfigs {
            let source = TimelineTrackSource.proPresenter(configId: config.id)
            if !layout.hasTrack(for: source) {
                sources.append(AvailableTrackSource(
                    source: source, label: config.name, icon: "display.2", color: .purple
                ))
            }
        }

        // HyperDeck
        if !layout.hasTrack(for: .hyperDeck) {
            sources.append(AvailableTrackSource(
                source: .hyperDeck, label: "HyperDeck", icon: "internaldrive", color: .red
            ))
        }

        return sources
    }
}
