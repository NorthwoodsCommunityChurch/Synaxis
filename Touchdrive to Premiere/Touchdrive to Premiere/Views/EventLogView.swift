//
//  EventLogView.swift
//  Synaxis
//
//  Created by Seth Potter on 1/28/26.
//

import SwiftUI

struct EventLogView: View {
    @Environment(SessionManager.self) private var session
    @State private var autoScroll = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Event Log")
                    .font(.headline)

                Spacer()

                Text("\(session.eventCount) events")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Toggle("Auto-scroll", isOn: $autoScroll)
                    .toggleStyle(.checkbox)
                    .font(.caption)

                Button(action: { session.eventLogger.clearEvents() }) {
                    Label("Clear", systemImage: "trash")
                }
                .buttonStyle(.borderless)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(session.events) { event in
                            EventRow(event: event)
                                .id(event.id)
                        }
                    }
                    .padding(.horizontal, 8)
                }
                .onChange(of: session.eventCount) { _, _ in
                    if autoScroll, let lastEvent = session.events.last {
                        withAnimation {
                            proxy.scrollTo(lastEvent.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }
}

// MARK: - Event Row

struct EventRow: View {
    let event: ProductionEvent

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: event.type.iconName)
                .foregroundColor(colorForType(event.type))
                .frame(width: 16)

            Text(event.timecode)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.primary)
                .frame(width: 100, alignment: .leading)

            Text(Self.timeFormatter.string(from: event.timestamp))
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 90, alignment: .leading)

            Text(event.description)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(1)

            Spacer()
        }
        .padding(.vertical, 2)
    }

    // MARK: - Color Mapping

    private func colorForType(_ type: EventType) -> Color {
        switch type {
        case .programCut:
            return .red
        case .transition:
            return .orange
        case .keyerOn:
            return .green
        case .keyerOff:
            return .gray
        case .slideChange:
            return .blue
        case .fadeToBlack:
            return .purple
        case .recordStart:
            return .red
        case .recordStop:
            return .gray
        case .connectionChange:
            return connectionColor
        case .ftpTransfer:
            return .teal
        }
    }

    private var connectionColor: Color {
        if case .connectionChange(_, let connected, _) = event.payload {
            return connected ? .green : .red
        }
        return .secondary
    }
}
