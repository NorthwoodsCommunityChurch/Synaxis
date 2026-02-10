//
//  RecordingControlsView.swift
//  Synaxis
//
//  Created by Seth Potter on 1/28/26.
//

import SwiftUI
import UniformTypeIdentifiers

struct RecordingControlsView: View {
    @Environment(SessionManager.self) private var session
    @Environment(SettingsManager.self) private var settings
    @Environment(AssignmentStore.self) private var assignments
    @Environment(ConnectionManager.self) private var connection

    @State private var showingXMLPreview = false
    @State private var exportError: String?
    @State private var pulsingOpacity: Double = 1.0

    var body: some View {
        @Bindable var session = session

        VStack(alignment: .leading, spacing: 12) {
            Text("Recording")
                .font(.headline)

            HStack(spacing: 16) {
                // Session name
                TextField("Session Name", text: $session.sessionName)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)

                Spacer()

                // Recording status indicator
                if session.isRecording {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 8, height: 8)
                            .opacity(pulsingOpacity)
                            .onAppear {
                                withAnimation(
                                    .easeInOut(duration: 0.8)
                                        .repeatForever(autoreverses: true)
                                ) {
                                    pulsingOpacity = 0.3
                                }
                            }
                            .onDisappear {
                                pulsingOpacity = 1.0
                            }

                        Text("Recording")
                            .foregroundColor(.red)
                            .fontWeight(.medium)
                    }
                }
            }

            HStack(spacing: 12) {
                // Start / Stop recording
                if session.isRecording {
                    Button(action: { session.stopSession(settings: settings) }) {
                        Label("Stop Recording", systemImage: "stop.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                } else {
                    Button(action: {
                        session.startSession(settings: settings, assignments: assignments)
                    }) {
                        Label("Start Recording", systemImage: "record.circle")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }

                // HyperDeck record button (only when connected)
                if connection.isHyperDeckConnected {
                    Divider()
                        .frame(height: 24)

                    if connection.hyperDeckClient.isRecording {
                        Button(action: { connection.stopHyperDeckRecording() }) {
                            Label("Stop HyperDeck", systemImage: "stop.circle")
                        }
                        .buttonStyle(.bordered)
                        .tint(.orange)
                    } else {
                        Button(action: { connection.startHyperDeckRecording() }) {
                            Label("Record HyperDeck", systemImage: "record.circle.fill")
                        }
                        .buttonStyle(.bordered)
                        .tint(.orange)
                    }
                }

                Divider()
                    .frame(height: 24)

                // Preview button
                Button(action: { showingXMLPreview = true }) {
                    Label("Preview XML", systemImage: "eye")
                }
                .buttonStyle(.bordered)
                .disabled(session.currentSession == nil)

                // Export Premiere XML
                Button(action: exportPremiereXML) {
                    Label("Export Premiere XML", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
                .disabled(session.currentSession == nil)

                // Export Session JSON
                Button(action: exportSessionJSON) {
                    Label("Export Session", systemImage: "doc.badge.arrow.up")
                }
                .buttonStyle(.bordered)
                .disabled(session.currentSession == nil)

                // Import Session JSON
                Button(action: importSession) {
                    Label("Import Session", systemImage: "doc.badge.arrow.down")
                }
                .buttonStyle(.bordered)
            }
            .keyboardShortcut("r", modifiers: .command)

            if let error = exportError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
        .sheet(isPresented: $showingXMLPreview) {
            XMLPreviewView()
        }
    }

    // MARK: - Export / Import Actions

    private func exportPremiereXML() {
        guard let productionSession = session.currentSession else {
            exportError = "No active session to export"
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.xml]
        panel.nameFieldStringValue = "\(session.sessionName.isEmpty ? "Production" : session.sessionName).xml"

        if panel.runModal() == .OK, let url = panel.url {
            do {
                var generator = PremiereXMLGenerator(session: productionSession, mediaRoot: settings.hyperDeckMediaRoot)
                try generator.saveToFile(at: url)
                exportError = nil
            } catch {
                exportError = "Export failed: \(error.localizedDescription)"
            }
        }
    }

    private func exportSessionJSON() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.json]
        panel.nameFieldStringValue = "\(session.sessionName.isEmpty ? "Production" : session.sessionName).json"

        if panel.runModal() == .OK, let url = panel.url {
            do {
                try session.exportSessionJSON(to: url)
                exportError = nil
            } catch {
                exportError = "Export failed: \(error.localizedDescription)"
            }
        }
    }

    private func importSession() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [UTType.json]

        if panel.runModal() == .OK, let url = panel.url {
            do {
                try session.importSession(from: url)
                exportError = nil
            } catch {
                exportError = "Import failed: \(error.localizedDescription)"
            }
        }
    }
}
