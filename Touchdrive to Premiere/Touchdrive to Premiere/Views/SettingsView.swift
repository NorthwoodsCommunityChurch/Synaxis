//
//  SettingsView.swift
//  Synaxis
//
//  Settings scene (Cmd+,) with tabs for Connections, Project, Export, and Timecode.
//

import AppKit
import SwiftUI

struct SettingsView: View {
    @Environment(SettingsManager.self) private var settings

    var body: some View {
        @Bindable var settings = settings

        TabView {
            ProjectSettingsTab()
                .tabItem {
                    Label("Project", systemImage: "film")
                }

            ExportSettingsTab()
                .tabItem {
                    Label("Export", systemImage: "square.and.arrow.up")
                }

            TimecodeSettingsTab()
                .tabItem {
                    Label("Timecode", systemImage: "timer")
                }

            UpdateSettingsTab()
                .tabItem {
                    Label("Updates", systemImage: "arrow.triangle.2.circlepath")
                }
        }
        .onDisappear {
            settings.save()
        }
    }
}

// MARK: - Project Tab

struct ProjectSettingsTab: View {
    @Environment(SettingsManager.self) private var settings

    private let frameRates: [Double] = [23.976, 24, 25, 29.97, 30, 50, 59.94, 60]

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section {
                Picker("Frame Rate", selection: $settings.frameRate) {
                    ForEach(frameRates, id: \.self) { rate in
                        Text(formatFrameRate(rate)).tag(rate)
                    }
                }

                TextField("Start Timecode", text: $settings.startTimecode)
                    .textFieldStyle(.roundedBorder)

                Toggle("Drop Frame Timecode", isOn: $settings.dropFrame)

                if settings.dropFrame && settings.frameRate != 29.97 && settings.frameRate != 59.94 {
                    Text("Drop frame is only meaningful at 29.97 or 59.94 fps.")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            } header: {
                Text("Timeline Settings")
            }

            Section {
                HStack {
                    TextField("Width", value: $settings.resolution.width, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)

                    Text("x")

                    TextField("Height", value: $settings.resolution.height, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                }

                HStack {
                    Button("1080p") {
                        settings.resolution = .hd1080
                    }
                    .buttonStyle(.bordered)

                    Button("4K") {
                        settings.resolution = .uhd4k
                    }
                    .buttonStyle(.bordered)

                    Button("720p") {
                        settings.resolution = .hd720
                    }
                    .buttonStyle(.bordered)
                }
            } header: {
                Text("Resolution")
            }
        }
        .formStyle(.grouped)
        .onChange(of: settings.frameRate) { settings.save() }
        .onChange(of: settings.resolution) { settings.save() }
        .onChange(of: settings.startTimecode) { settings.save() }
        .onChange(of: settings.dropFrame) { settings.save() }
    }

    private func formatFrameRate(_ rate: Double) -> String {
        if rate == rate.rounded() {
            return "\(Int(rate)) fps"
        } else {
            return String(format: "%.3f fps", rate)
        }
    }
}

// MARK: - Export Tab

struct ExportSettingsTab: View {
    @Environment(SettingsManager.self) private var settings

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section {
                HStack {
                    TextField("Default Export Path", text: $settings.defaultExportPath)
                        .textFieldStyle(.roundedBorder)

                    Button("Browse...") {
                        // Defer to next run-loop iteration so SwiftUI's
                        // button action completes before the modal runs.
                        DispatchQueue.main.async {
                            let panel = NSOpenPanel()
                            panel.canChooseFiles = false
                            panel.canChooseDirectories = true
                            panel.allowsMultipleSelection = false
                            panel.prompt = "Select"
                            panel.message = "Choose a default export folder"
                            if panel.runModal() == .OK, let url = panel.url {
                                settings.defaultExportPath = url.path
                                settings.save()
                            }
                        }
                    }
                    .buttonStyle(.bordered)
                }

                Toggle("Auto-export when recording stops", isOn: $settings.autoExportOnStop)

                Text("When enabled, the Premiere XML will be automatically exported to the default path when you stop recording.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text("Export Location")
            }

            Section {
                HStack {
                    TextField("HyperDeck Media Root", text: $settings.hyperDeckMediaRoot)
                        .textFieldStyle(.roundedBorder)

                    Button("Browse...") {
                        DispatchQueue.main.async {
                            let panel = NSOpenPanel()
                            panel.canChooseFiles = false
                            panel.canChooseDirectories = true
                            panel.allowsMultipleSelection = false
                            panel.prompt = "Select"
                            panel.message = "Choose the HyperDeck media root folder"
                            if panel.runModal() == .OK, let url = panel.url {
                                settings.hyperDeckMediaRoot = url.path
                                settings.save()
                            }
                        }
                    }
                    .buttonStyle(.bordered)
                }

                Text("Root folder on the HyperDeck where ISO recordings are stored. Used to build file paths in the exported XML.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text("HyperDeck Media")
            }

            Section {
                TextField("File Name Pattern", text: $settings.exportFileNamePattern)
                    .textFieldStyle(.roundedBorder)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Available tokens:")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("{session}").font(.system(.caption, design: .monospaced))
                            Text("{date}").font(.system(.caption, design: .monospaced))
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("- Session name").font(.caption2).foregroundColor(.secondary)
                            Text("- Current date (YYYY-MM-DD)").font(.caption2).foregroundColor(.secondary)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("{time}").font(.system(.caption, design: .monospaced))
                            Text("{count}").font(.system(.caption, design: .monospaced))
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("- Current time (HH-MM-SS)").font(.caption2).foregroundColor(.secondary)
                            Text("- Event count").font(.caption2).foregroundColor(.secondary)
                        }
                    }
                }
            } header: {
                Text("File Naming")
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Preview:")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text(generatePreviewFileName())
                        .font(.system(.body, design: .monospaced))
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(nsColor: .textBackgroundColor))
                        .cornerRadius(4)
                }
            } header: {
                Text("Preview")
            }
        }
        .formStyle(.grouped)
        .onChange(of: settings.defaultExportPath) { settings.save() }
        .onChange(of: settings.hyperDeckMediaRoot) { settings.save() }
        .onChange(of: settings.autoExportOnStop) { settings.save() }
        .onChange(of: settings.exportFileNamePattern) { settings.save() }
    }

    private func generatePreviewFileName() -> String {
        var name = settings.exportFileNamePattern

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH-mm-ss"

        name = name.replacingOccurrences(of: "{session}", with: "MySession")
        name = name.replacingOccurrences(of: "{date}", with: dateFormatter.string(from: Date()))
        name = name.replacingOccurrences(of: "{time}", with: timeFormatter.string(from: Date()))
        name = name.replacingOccurrences(of: "{count}", with: "0")

        return name + ".xml"
    }
}

// MARK: - Timecode Tab

struct TimecodeSettingsTab: View {
    @Environment(SettingsManager.self) private var settings
    @Environment(ConnectionManager.self) private var connections
    @Environment(SessionManager.self) private var session

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section {
                Picker("Timecode Source", selection: $settings.timecodeSource) {
                    ForEach(TimecodeSource.allCases, id: \.self) { source in
                        Text(source.rawValue).tag(source)
                    }
                }

                switch settings.timecodeSource {
                case .hyperDeck:
                    Text("Timecode will be synced from the connected HyperDeck recorder.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if !settings.hyperDeckEnabled {
                        Text("HyperDeck is not enabled. Enable it in the HyperDeck tab.")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }

                case .systemClock:
                    Text("Timecode will be generated from the system clock when recording starts.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                case .manual:
                    Text("You will manually set the timecode start value in the Project tab.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } header: {
                Text("Timecode Source")
            }

            Section {
                Toggle("Use Drop Frame Timecode", isOn: $settings.dropFrame)

                if settings.dropFrame {
                    Text("Drop frame timecode (29.97df, 59.94df) maintains sync with real-world clock time.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("Non-drop frame timecode counts every frame sequentially but drifts from real time at 29.97/59.94 fps.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } header: {
                Text("Drop Frame")
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Current Timecode:")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Spacer()

                        Text(connections.currentTimecode)
                            .font(.system(.title2, design: .monospaced))
                            .fontWeight(.medium)
                    }

                    if session.isRecording {
                        HStack {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 8, height: 8)
                            Text("Recording...")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }
                }
            } header: {
                Text("Status")
            }
        }
        .formStyle(.grouped)
        .onChange(of: settings.timecodeSource) { settings.save() }
        .onChange(of: settings.dropFrame) { settings.save() }
    }
}
