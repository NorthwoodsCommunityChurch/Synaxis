//
//  XMLPreviewView.swift
//  Synaxis
//
//  Created by Seth Potter on 1/28/26.
//

import SwiftUI

struct XMLPreviewView: View {
    @Environment(SessionManager.self) private var session
    @Environment(SettingsManager.self) private var settings
    @Environment(AssignmentStore.self) private var assignments
    @Environment(\.dismiss) private var dismiss

    @State private var xmlContent: String = ""
    @State private var isGenerating = false
    @State private var trackCount: Int = 0
    @State private var markerCount: Int = 0

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("XML Preview")
                    .font(.title2)
                    .fontWeight(.bold)

                Spacer()

                Button(action: { copyToClipboard() }) {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .disabled(xmlContent.isEmpty)

                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            // Content
            if isGenerating {
                VStack {
                    Spacer()
                    ProgressView("Generating XML...")
                    Spacer()
                }
            } else if xmlContent.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "doc.text")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("No session data available")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("Start recording and generate some events to see XML preview")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        // Stats
                        HStack(spacing: 20) {
                            StatLabel(title: "Events", value: "\(session.eventCount)")
                            StatLabel(title: "Cameras", value: "\(assignments.cameraAssignments.count)")
                            StatLabel(title: "Keyers", value: "\(assignments.keyerAssignments.count)")
                            StatLabel(title: "XML Size", value: formatBytes(xmlContent.utf8.count))
                            StatLabel(title: "Tracks", value: "\(trackCount)")
                            StatLabel(title: "Markers", value: "\(markerCount)")
                            Spacer()
                        }
                        .padding()
                        .background(Color(nsColor: .controlBackgroundColor))
                        .cornerRadius(8)

                        // XML content
                        Text("Generated XML:")
                            .font(.headline)
                            .padding(.top, 8)

                        ScrollView(.horizontal, showsIndicators: true) {
                            Text(xmlContent)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .background(Color(nsColor: .textBackgroundColor))
                        .cornerRadius(4)
                    }
                    .padding()
                }
            }
        }
        .frame(width: 900, height: 700)
        .onAppear {
            generateXML()
        }
    }

    // MARK: - XML Generation

    private func generateXML() {
        isGenerating = true

        Task {
            guard let productionSession = session.currentSession else {
                xmlContent = ""
                trackCount = 0
                markerCount = 0
                isGenerating = false
                return
            }

            var generator = PremiereXMLGenerator(session: productionSession)
            trackCount = generator.trackCount
            markerCount = generator.markerCount
            xmlContent = generator.generateXML()
            isGenerating = false
        }
    }

    // MARK: - Clipboard

    private func copyToClipboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(xmlContent, forType: .string)
    }

    // MARK: - Helpers

    private func formatBytes(_ bytes: Int) -> String {
        if bytes < 1024 {
            return "\(bytes) B"
        } else if bytes < 1024 * 1024 {
            return String(format: "%.1f KB", Double(bytes) / 1024.0)
        } else {
            return String(format: "%.1f MB", Double(bytes) / (1024.0 * 1024.0))
        }
    }
}

// MARK: - Stat Label

struct StatLabel: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.headline)
        }
    }
}
