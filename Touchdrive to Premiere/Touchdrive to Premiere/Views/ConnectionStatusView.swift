//
//  ConnectionStatusView.swift
//  Synaxis
//
//  Compact connection status panel used in the dashboard.
//

import SwiftUI

struct ConnectionStatusView: View {
    @Environment(ConnectionManager.self) private var connections
    @Environment(SettingsManager.self) private var settings
    @Environment(AssignmentStore.self) private var assignments

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Connections")
                .font(.headline)

            // TSL (Carbonite)
            ConnectionRow(
                name: "TSL (Carbonite)",
                icon: "antenna.radiowaves.left.and.right",
                statusDot: connections.isTSLConnected ? .green : .red,
                statusLabel: connections.isTSLConnected ? "Connected" : "Disconnected",
                detail: settings.tslEnabled
                    ? "\(settings.tslHost):\(settings.tslPort)"
                    : "Disabled"
            )

            // ProPresenter machines
            ForEach(assignments.proPresenterConfigs) { config in
                let isActive = connections.isProPresenterConnected(id: config.id)
                let client = connections.proPresenterClient(for: config.id)
                ConnectionRow(
                    name: config.name,
                    icon: "text.below.photo",
                    statusDot: isActive ? .green : .red,
                    statusLabel: isActive ? "Connected" : "Disconnected",
                    detail: config.enabled ? config.baseURL : "Disabled",
                    supplementary: isActive && !(client?.currentSlideText.isEmpty ?? true)
                        ? client!.currentSlideText
                        : nil
                )
            }

            // HyperDeck
            ConnectionRow(
                name: "HyperDeck",
                icon: "internaldrive",
                statusDot: connections.isHyperDeckConnected ? .green : .red,
                statusLabel: connections.isHyperDeckConnected ? "Connected" : "Disconnected",
                detail: settings.hyperDeckEnabled
                    ? "\(settings.hyperDeckHost):\(settings.hyperDeckPort)"
                    : "Disabled",
                supplementary: connections.isHyperDeckConnected
                    ? "\(connections.hyperDeckClient.transportStatus.capitalized) -- \(connections.hyperDeckClient.currentTimecode)"
                    : nil
            )

            Divider()

            HStack {
                Button {
                    connections.connectAll(settings: settings, assignments: assignments)
                } label: {
                    Label("Connect All", systemImage: "link")
                }
                .buttonStyle(.borderedProminent)

                Button {
                    connections.disconnectAll()
                } label: {
                    Label("Disconnect All", systemImage: "link.badge.xmark")
                }
                .buttonStyle(.bordered)
                .disabled(!connections.anyConnected)
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }
}

// MARK: - Connection Row

private struct ConnectionRow: View {
    let name: String
    let icon: String
    let statusDot: Color
    let statusLabel: String
    let detail: String
    var supplementary: String? = nil

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(statusDot)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Label(name, systemImage: icon)
                        .fontWeight(.medium)
                        .labelStyle(.titleOnly)

                    Text(detail)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if let supplementary {
                    Text(supplementary)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Text(statusLabel)
                .font(.caption)
                .foregroundColor(statusDot)
        }
        .padding(.vertical, 4)
    }
}
