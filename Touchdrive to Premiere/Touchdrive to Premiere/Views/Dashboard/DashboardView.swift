//
//  DashboardView.swift
//  Synaxis
//
//  Main dashboard showing live production status.
//

import SwiftUI

struct DashboardView: View {
    @Environment(ConnectionManager.self) private var connectionManager
    @Environment(SessionManager.self) private var sessionManager
    @Environment(AssignmentStore.self) private var assignments

    var body: some View {
        VStack(spacing: 0) {
            // Recording status banner (read-only — controls live in Timeline tab)
            if sessionManager.isRecording {
                recordingBanner
            }

            HSplitView {
                // MARK: Left Column — Connections, Program Source, Timecode
                leftColumn
                    .frame(minWidth: 280, idealWidth: 340, maxWidth: 420)

                // MARK: Right Column — ProPresenter Slide, Recent Events
                rightColumn
                    .frame(minWidth: 300)
            }
            .padding()
        }
    }

    // MARK: - Recording Status Banner

    private var recordingBanner: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color.red)
                .frame(width: 8, height: 8)

            Text("Recording")
                .fontWeight(.medium)
                .foregroundStyle(.red)

            if !sessionManager.sessionName.isEmpty {
                Text(sessionManager.sessionName)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text("\(sessionManager.eventCount) events")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.red.opacity(0.08))
    }

    // MARK: - Left Column

    private var leftColumn: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                connectionStatusSection
                programSourceSection
                timecodeSection
            }
            .padding()
        }
    }

    // MARK: - Connection Status

    private var connectionStatusSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Connections")
                .font(.headline)

            connectionRow(
                name: "TSL (Carbonite)",
                isActive: connectionManager.isTSLConnected,
                detail: connectionManager.isTSLConnected ? "Connected" : "Disconnected"
            )

            ForEach(assignments.proPresenterConfigs) { config in
                let isActive = connectionManager.isProPresenterConnected(id: config.id)
                let client = connectionManager.proPresenterClient(for: config.id)
                connectionRow(
                    name: config.name,
                    isActive: isActive,
                    detail: isActive
                        ? (client?.currentPresentationName.isEmpty ?? true)
                            ? "Connected"
                            : client!.currentPresentationName
                        : "Disconnected"
                )
            }

            connectionRow(
                name: "HyperDeck",
                isActive: connectionManager.isHyperDeckConnected,
                detail: connectionManager.isHyperDeckConnected ? "Connected" : "Disconnected"
            )
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }

    private func connectionRow(name: String, isActive: Bool, detail: String) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(isActive ? Color.green : Color.red)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .fontWeight(.medium)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text(isActive ? "Active" : "Inactive")
                .font(.caption)
                .foregroundStyle(isActive ? .green : .secondary)
        }
    }

    // MARK: - Program Source

    private var programSourceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Program Source")
                .font(.headline)

            let busLabels = connectionManager.busState.busLabels

            if busLabels.isEmpty {
                Text("No TSL data")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
            } else {
                ForEach(busLabels, id: \.self) { bus in
                    if let source = connectionManager.busState.currentProgramSource(for: bus) {
                        HStack {
                            Text(bus)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 80, alignment: .leading)

                            Text(source.sourceLabel.isEmpty ? "Source \(source.index)" : source.sourceLabel)
                                .font(.system(.body, design: .monospaced))
                                .fontWeight(.semibold)
                                .foregroundStyle(.primary)

                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }

    // MARK: - Timecode

    private var timecodeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Timecode")
                .font(.headline)

            Text(connectionManager.currentTimecode)
                .font(.system(.title, design: .monospaced))
                .fontWeight(.medium)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 8)

            HStack {
                Text("Source: HyperDeck")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                if connectionManager.isHyperDeckConnected {
                    Text("Locked")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else {
                    Text("Free Run")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }

    // MARK: - Right Column

    private var rightColumn: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                proPresenterSection
                recentEventsSection
            }
            .padding()
        }
    }

    // MARK: - ProPresenter Current Slide

    private var proPresenterSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ProPresenter")
                .font(.headline)

            if assignments.proPresenterConfigs.isEmpty {
                Text("No machines configured")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
            } else {
                ForEach(assignments.proPresenterConfigs) { config in
                    let isActive = connectionManager.isProPresenterConnected(id: config.id)
                    let client = connectionManager.proPresenterClient(for: config.id)

                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(isActive ? Color.green : Color.red)
                                .frame(width: 8, height: 8)
                            Text(config.name)
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }

                        if isActive, let client {
                            if !client.currentPresentationName.isEmpty {
                                HStack {
                                    Text("Presentation:")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(client.currentPresentationName)
                                        .font(.callout)
                                        .fontWeight(.medium)
                                        .lineLimit(1)
                                }
                            }

                            HStack {
                                Text("Slide:")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("\(client.currentSlideIndex)")
                                    .font(.system(.callout, design: .monospaced))
                            }

                            if !client.currentSlideText.isEmpty {
                                Text(client.currentSlideText)
                                    .font(.body)
                                    .padding(10)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color(nsColor: .textBackgroundColor))
                                    .cornerRadius(6)
                            }
                        } else {
                            Text("Not connected")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }

    // MARK: - Recent Events Feed

    private var recentEventsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Recent Events")
                    .font(.headline)

                Spacer()

                Text("\(sessionManager.eventCount) total")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            let recentEvents = Array(sessionManager.events.suffix(20).reversed())

            if recentEvents.isEmpty {
                Text("No events recorded yet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(recentEvents) { event in
                        recentEventRow(event)
                    }
                }
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }

    private func recentEventRow(_ event: ProductionEvent) -> some View {
        HStack(spacing: 8) {
            Image(systemName: event.type.iconName)
                .font(.caption)
                .foregroundStyle(colorForEventType(event.type))
                .frame(width: 16)

            Text(event.timecode)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)

            Text(event.type.label)
                .font(.caption)
                .fontWeight(.medium)
                .frame(width: 70, alignment: .leading)

            Text(event.description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer()
        }
        .padding(.vertical, 3)
    }

    private func colorForEventType(_ type: EventType) -> Color {
        switch type {
        case .programCut:        return .blue
        case .transition:        return .cyan
        case .keyerOn:           return .green
        case .keyerOff:          return .orange
        case .slideChange:       return .purple
        case .fadeToBlack:       return .gray
        case .recordStart:       return .red
        case .recordStop:        return .red
        case .connectionChange:  return .yellow
        }
    }
}
