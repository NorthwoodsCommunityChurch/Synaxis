//
//  ProPresenterConfigView.swift
//  Synaxis
//
//  Multi-machine ProPresenter 7 connection settings.
//  Each machine gets its own bordered card.
//

import SwiftUI
import AppKit

// MARK: - ProPresenterConfigView

struct ProPresenterConfigView: View {
    @Environment(AssignmentStore.self) private var assignments
    @Environment(ConnectionManager.self) private var connections

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                if assignments.proPresenterConfigs.isEmpty {
                    VStack(spacing: 16) {
                        Spacer()

                        Image(systemName: "tv.slash")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)

                        Text("No ProPresenter machines configured")
                            .font(.headline)
                            .foregroundColor(.secondary)

                        Text("Add a ProPresenter machine to start tracking slides.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        addMachineButton
                            .padding(.top, 4)

                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                } else {
                    ForEach(assignments.proPresenterConfigs) { config in
                        ProPresenterMachineCard(configID: config.id)
                    }

                    addMachineButton
                }
            }
            .padding()
        }
    }

    // MARK: - Add Machine Button

    private var addMachineButton: some View {
        Button {
            assignments.addProPresenterConfig()
        } label: {
            VStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.title2)
                    .foregroundColor(.secondary)
                Text("Add ProPresenter Machine")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 80)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(
                        style: StrokeStyle(lineWidth: 1, dash: [6, 3])
                    )
                    .foregroundColor(.secondary.opacity(0.5))
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - ProPresenterMachineCard

struct ProPresenterMachineCard: View {
    let configID: UUID

    @Environment(AssignmentStore.self) private var assignments
    @Environment(ConnectionManager.self) private var connections

    // Local editing state
    @State private var name: String = ""
    @State private var host: String = ""
    @State private var apiPortString: String = ""
    @State private var enabled: Bool = false
    @State private var remotePortString: String = ""
    @State private var remotePassword: String = ""
    @State private var remoteEnabled: Bool = false
    @State private var meNumber: Int = 1
    @State private var keyerNumber: Int = 1
    @State private var isTesting: Bool = false
    @State private var testResult: Bool?

    private var config: ProPresenterConfig? {
        assignments.proPresenterConfigs.first(where: { $0.id == configID })
    }

    private var isConnected: Bool {
        connections.isProPresenterConnected(id: configID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Circle()
                    .fill(isConnected ? Color.green : Color.red)
                    .frame(width: 10, height: 10)

                Text(name.isEmpty ? "Unnamed Machine" : name)
                    .font(.headline)

                Spacer()

                Button {
                    connections.disconnectProPresenter(id: configID)
                    assignments.removeProPresenterConfig(id: configID)
                } label: {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
                .help("Remove this machine")
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // Content
            VStack(alignment: .leading, spacing: 12) {
                // Machine name
                LabeledContent("Machine Name") {
                    TextField("", text: $name, prompt: Text("e.g. FOH, Broadcast"))
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 240)
                }

                // Host / IP
                LabeledContent("Host / IP Address") {
                    TextField("", text: $host, prompt: Text("e.g. 10.10.11.134"))
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 240)
                }

                // Port
                LabeledContent("Port") {
                    TextField("", text: $apiPortString, prompt: Text("e.g. 57131"))
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 120)
                }

                // API URL preview
                if !host.isEmpty && !apiPortString.isEmpty {
                    Text("API URL: http://\(host):\(apiPortString)")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                Text("Use the Port shown at the top of ProPresenter > Settings > Network (not the TCP/IP port). Make sure Enable Network is on in Pro7.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Divider()

                // Connect / Disconnect / Test
                HStack(spacing: 12) {
                    if isConnected {
                        Button("Disconnect") {
                            connections.disconnectProPresenter(id: configID)
                        }
                        .buttonStyle(.bordered)
                    } else {
                        Button("Connect") {
                            saveConfig()
                            if let cfg = config {
                                connections.connectProPresenter(config: cfg)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(host.isEmpty || apiPortString.isEmpty)
                    }

                    Button("Test Connection") {
                        testConnection()
                    }
                    .buttonStyle(.bordered)
                    .disabled(host.isEmpty || apiPortString.isEmpty || isTesting)

                    if isTesting {
                        ProgressView()
                            .controlSize(.small)
                    }

                    if let result = testResult {
                        Image(systemName: result ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundColor(result ? .green : .red)
                    }
                }

                Toggle("Connect on launch", isOn: $enabled)

                Divider()

                // Status
                if isConnected {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 10, height: 10)
                        Text("Connected")
                            .foregroundColor(.green)
                    }

                    if let client = connections.proPresenterClient(for: configID) {
                        LabeledContent("Presentation") {
                            Text(client.currentPresentationName.isEmpty
                                 ? "None"
                                 : client.currentPresentationName)
                        }

                        LabeledContent("Slide Index") {
                            Text("\(client.currentSlideIndex)")
                                .font(.system(.body, design: .monospaced))
                        }

                        if !client.currentSlideText.isEmpty {
                            LabeledContent("Slide Text") {
                                Text(client.currentSlideText)
                                    .lineLimit(3)
                                    .font(.caption)
                            }
                        }

                        if let thumbnail = client.currentSlideThumbnail {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Current Slide")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Image(nsImage: thumbnail)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(maxWidth: 320)
                                    .cornerRadius(4)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 4)
                                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                                    )
                            }
                        }

                        if let error = client.lastError {
                            HStack(spacing: 4) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                Text(error)
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }
                        }
                    }
                } else {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 10, height: 10)
                        Text("Disconnected")
                            .foregroundColor(.secondary)
                    }

                    if let client = connections.proPresenterClient(for: configID),
                       let error = client.lastError {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }
                }
            }
            .padding()
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
        )
        .onAppear {
            loadConfig()
        }
        .onChange(of: name) { _, _ in saveConfig() }
        .onChange(of: host) { _, _ in saveConfig() }
        .onChange(of: apiPortString) { _, _ in saveConfig() }
        .onChange(of: enabled) { _, _ in saveConfig() }
        .onChange(of: remotePortString) { _, _ in saveConfig() }
        .onChange(of: remotePassword) { _, _ in saveConfig() }
        .onChange(of: remoteEnabled) { _, _ in saveConfig() }
        .onChange(of: meNumber) { _, _ in saveConfig() }
        .onChange(of: keyerNumber) { _, _ in saveConfig() }
    }

    // MARK: - Config Sync

    private func loadConfig() {
        guard let config = assignments.proPresenterConfigs.first(where: { $0.id == configID }) else { return }
        name = config.name
        host = config.host
        apiPortString = config.apiPort > 0 ? "\(config.apiPort)" : ""
        enabled = config.enabled
        remotePortString = config.remotePort > 0 ? "\(config.remotePort)" : ""
        remotePassword = config.remotePassword
        remoteEnabled = config.remoteEnabled
        meNumber = config.meNumber
        keyerNumber = config.keyerNumber
    }

    private func saveConfig() {
        let apiPort = Int(apiPortString) ?? 0
        let remotePort = Int(remotePortString) ?? 0
        let config = ProPresenterConfig(
            id: configID,
            name: name,
            host: host,
            apiPort: apiPort,
            enabled: enabled,
            remotePort: remotePort,
            remotePassword: remotePassword,
            remoteEnabled: remoteEnabled,
            meNumber: meNumber,
            keyerNumber: keyerNumber
        )
        assignments.updateProPresenterConfig(config)
    }

    // MARK: - Test

    private func testConnection() {
        isTesting = true
        testResult = nil

        let port = Int(apiPortString) ?? 0
        let client = connections.proPresenterClient(for: configID) ?? ProPresenterClient()

        Task {
            let success = await client.testConnection(host: host, port: port)
            isTesting = false
            testResult = success

            Task {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                testResult = nil
            }
        }
    }
}
