//
//  HyperDeckConfigView.swift
//  Synaxis
//

import SwiftUI

struct HyperDeckConfigView: View {
    @Environment(ConnectionManager.self) private var connections
    @Environment(SettingsManager.self) private var settings

    @State private var host: String = ""
    @State private var portString: String = "9993"
    @State private var enabled: Bool = false

    var body: some View {
        Form {
            // MARK: - Connection Section

            Section("Connection") {
                TextField("Host", text: $host, prompt: Text("192.168.1.200"))
                    .textFieldStyle(.roundedBorder)

                TextField("Port", text: $portString, prompt: Text("9993"))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 100)

                HStack(spacing: 12) {
                    if connections.isHyperDeckConnected {
                        Button("Disconnect") {
                            connections.disconnectHyperDeck()
                        }
                        .buttonStyle(.bordered)
                    } else {
                        Button("Connect") {
                            saveSettings()
                            let port = Int(portString) ?? 9993
                            connections.connectHyperDeck(host: host, port: port)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(host.isEmpty)
                    }
                }

                // Connection status
                HStack(spacing: 8) {
                    Circle()
                        .fill(connections.isHyperDeckConnected ? Color.green : Color.red)
                        .frame(width: 10, height: 10)
                    Text(connections.isHyperDeckConnected ? "Connected" : "Disconnected")
                        .foregroundColor(connections.isHyperDeckConnected ? .green : .secondary)
                }

                if let error = connections.hyperDeckClient.lastError {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }

                Toggle("Connect on launch", isOn: $enabled)
            }

            // MARK: - Transport Section

            if connections.isHyperDeckConnected {
                Section("Transport") {
                    HStack(spacing: 12) {
                        // Transport status with icon and color
                        HStack(spacing: 4) {
                            Image(systemName: transportIcon)
                                .foregroundColor(transportColor)
                            Text(connections.hyperDeckClient.transportStatus.capitalized)
                                .fontWeight(.medium)
                        }

                        Spacer()

                        // Timecode display
                        Text(connections.hyperDeckClient.currentTimecode)
                            .font(.system(.title3, design: .monospaced))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                            .background(Color.black.opacity(0.1))
                            .cornerRadius(6)
                    }

                    if !connections.hyperDeckClient.currentClipName.isEmpty {
                        LabeledContent("Current Clip") {
                            Text(connections.hyperDeckClient.currentClipName)
                                .lineLimit(1)
                        }
                    }

                    // Record / Stop buttons
                    HStack(spacing: 12) {
                        Button(action: {
                            connections.startHyperDeckRecording()
                        }) {
                            Label("Record", systemImage: "record.circle")
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.bordered)
                        .disabled(connections.hyperDeckClient.isRecording)

                        Button(action: {
                            connections.stopHyperDeckRecording()
                        }) {
                            Label("Stop", systemImage: "stop.fill")
                        }
                        .buttonStyle(.bordered)
                        .disabled(!connections.hyperDeckClient.isRecording)
                    }
                }

                // MARK: - Slots Section

                if !connections.hyperDeckClient.slots.isEmpty {
                    Section("Slots") {
                        ForEach(connections.hyperDeckClient.slots) { slot in
                            HStack(spacing: 8) {
                                Image(systemName: slot.status == "mounted" ? "internaldrive.fill" : "internaldrive")
                                    .foregroundColor(slot.status == "mounted" ? .green : .secondary)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Slot \(slot.id)")
                                        .fontWeight(.medium)
                                    Text(slot.volumeName.isEmpty ? slot.status.capitalized : slot.volumeName)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                if !slot.videoFormat.isEmpty {
                                    Text(slot.videoFormat)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Text(slot.status.capitalized)
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(slot.status == "mounted" ? Color.green.opacity(0.15) : Color.secondary.opacity(0.15))
                                    .cornerRadius(4)
                            }
                        }
                    }
                }

                // MARK: - Clips Section

                Section {
                    if connections.hyperDeckClient.clips.isEmpty {
                        Text("No clips found")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    } else {
                        ForEach(connections.hyperDeckClient.clips) { clip in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(clip.name)
                                        .lineLimit(1)
                                    HStack(spacing: 8) {
                                        Text("In: \(clip.startTimecode)")
                                        Text("Dur: \(clip.duration)")
                                    }
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .font(.system(.caption, design: .monospaced))
                                }

                                Spacer()

                                Text("#\(clip.id)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text("Clips")
                        Spacer()
                        Button(action: {
                            connections.hyperDeckClient.queryClipList()
                        }) {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(.borderless)
                        .help("Refresh clip list")
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            loadSettings()
        }
        .onChange(of: host) { _, _ in saveSettings() }
        .onChange(of: portString) { _, _ in saveSettings() }
        .onChange(of: enabled) { _, _ in saveSettings() }
    }

    // MARK: - Transport Helpers

    private var transportIcon: String {
        switch connections.hyperDeckClient.transportStatus {
        case "record": return "record.circle.fill"
        case "play": return "play.fill"
        case "stopped": return "stop.fill"
        case "shuttle": return "forward.fill"
        case "jog": return "dial.medium"
        case "preview": return "eye.fill"
        default: return "questionmark"
        }
    }

    private var transportColor: Color {
        switch connections.hyperDeckClient.transportStatus {
        case "record": return .red
        case "play": return .green
        default: return .secondary
        }
    }

    // MARK: - Settings Sync

    private func loadSettings() {
        host = settings.hyperDeckHost
        portString = "\(settings.hyperDeckPort)"
        enabled = settings.hyperDeckEnabled
    }

    private func saveSettings() {
        settings.hyperDeckHost = host
        settings.hyperDeckPort = Int(portString) ?? 9993
        settings.hyperDeckEnabled = enabled
        settings.save()
    }
}
