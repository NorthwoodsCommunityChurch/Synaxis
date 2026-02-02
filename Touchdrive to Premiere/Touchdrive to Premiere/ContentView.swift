//
//  ContentView.swift
//  Synaxis
//
//  Created by Seth Potter on 1/28/26.
//

import SwiftUI

// MARK: - Sidebar Item

enum SidebarItem: String, Identifiable, CaseIterable {
    case dashboard
    case timeline
    case eventLog
    case diagnostics
    case assignments
    case proPresenter
    case hyperDeck
    case settings

    var id: String { rawValue }

    var label: String {
        switch self {
        case .dashboard:     return "Dashboard"
        case .timeline:      return "Timeline"
        case .eventLog:      return "Event Log"
        case .diagnostics:   return "Diagnostics"
        case .assignments:   return "Cameras"
        case .proPresenter:  return "ProPresenter"
        case .hyperDeck:     return "HyperDeck"
        case .settings:      return "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard:     return "gauge.with.dots.needle.33percent"
        case .timeline:      return "timeline.selection"
        case .eventLog:      return "list.bullet.rectangle"
        case .diagnostics:   return "stethoscope"
        case .assignments:   return "video"
        case .proPresenter:  return "display.2"
        case .hyperDeck:     return "internaldrive"
        case .settings:      return "gear"
        }
    }

    /// Which section this item belongs to.
    enum Section: String, CaseIterable {
        case monitor = "Monitor"
        case configuration = "Configuration"
        case tools = "Tools"
    }

    var section: Section {
        switch self {
        case .dashboard, .timeline:
            return .monitor
        case .assignments, .proPresenter, .hyperDeck:
            return .configuration
        case .settings, .eventLog, .diagnostics:
            return .tools
        }
    }

    static func items(for section: Section) -> [SidebarItem] {
        allCases.filter { $0.section == section }
    }
}

// MARK: - Content View

struct ContentView: View {
    @Environment(SessionManager.self) private var sessionManager
    @Environment(ConnectionManager.self) private var connectionManager
    @Environment(SettingsManager.self) private var settings
    @Environment(AssignmentStore.self) private var assignments

    @State private var selectedItem: SidebarItem? = .dashboard

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detailContent
        }
        .toolbar {
            ToolbarItem(placement: .status) {
                recordingStatusIndicator
            }
        }
        .keyboardShortcut(KeyEquivalent("r"), modifiers: .command, action: toggleRecording)
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: $selectedItem) {
            ForEach(SidebarItem.Section.allCases, id: \.self) { section in
                Section(section.rawValue) {
                    ForEach(SidebarItem.items(for: section)) { item in
                        Label(item.label, systemImage: item.systemImage)
                            .tag(item)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 200)
    }

    // MARK: - Detail

    private var detailContent: some View {
        Group {
            switch selectedItem {
            case .dashboard:
                DashboardView()
            case .timeline:
                TimelineView()
            case .eventLog:
                EventLogView()
                    .padding()
            case .diagnostics:
                DiagnosticsView()
            case .assignments:
                AssignmentsView()
            case .proPresenter:
                ProPresenterConfigView()
            case .hyperDeck:
                HyperDeckConfigView()
            case .settings:
                SettingsView()
            case .none:
                DashboardView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Recording Status Indicator

    private var recordingStatusIndicator: some View {
        Group {
            if sessionManager.isRecording {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 8, height: 8)
                    Text("Recording")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            } else {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.secondary.opacity(0.4))
                        .frame(width: 8, height: 8)
                    Text("Idle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Actions

    private func toggleRecording() {
        if sessionManager.isRecording {
            sessionManager.stopSession(settings: settings)
        } else {
            sessionManager.startSession(settings: settings, assignments: assignments)
        }
    }
}

// MARK: - Keyboard Shortcut Modifier

private extension View {
    /// Adds a keyboard shortcut that triggers the given action.
    func keyboardShortcut(_ key: KeyEquivalent, modifiers: EventModifiers, action: @escaping () -> Void) -> some View {
        self.background(
            Button("", action: action)
                .keyboardShortcut(key, modifiers: modifiers)
                .hidden()
        )
    }
}
