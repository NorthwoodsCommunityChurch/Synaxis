//
//  AssignmentsView.swift
//  Synaxis
//
//  Cameras tab: TSL connection, camera assignments (from TSL sources),
//  and keyer assignments.
//

import SwiftUI

struct AssignmentsView: View {
    @Environment(SettingsManager.self) private var settings
    @Environment(ConnectionManager.self) private var connections
    @Environment(AssignmentStore.self) private var assignments

    @State private var showingSourcePicker = false
    @State private var showingOutputPicker = false
    @State private var showingKeyerPicker = false

    private var statusColor: Color {
        if connections.tslClient.isConnected { return .green }
        if connections.tslClient.isListening { return .yellow }
        return .red
    }

    private var statusText: String {
        if connections.tslClient.isConnected { return "Connected" }
        if connections.tslClient.isListening { return "Listening" }
        return "Stopped"
    }

    var body: some View {
        @Bindable var settings = settings
        @Bindable var assignments = assignments

        Form {
            // MARK: - TSL Connection

            Section {
                TextField("Port", value: $settings.tslPort, format: .number.grouping(.never))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 140)

                HStack(spacing: 12) {
                    if connections.isTSLConnected {
                        Button("Stop Listening") {
                            connections.stopTSLListener()
                        }
                        .buttonStyle(.bordered)
                    } else {
                        Button("Start Listening") {
                            settings.save()
                            connections.startTSLListener(port: settings.tslPort)
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    Spacer()

                    HStack(spacing: 6) {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 8, height: 8)
                        Text(statusText)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                if connections.tslClient.isListening {
                    if connections.tslClient.isConnected {
                        let count = connections.busState.sources.count
                        Text("\(count) source\(count == 1 ? "" : "s") discovered")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("Listening on port \(settings.tslPort) — waiting for Carbonite to connect")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                if let peer = connections.tslClient.connectedPeer {
                    Text("Connected from \(peer)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if let error = connections.tslClient.lastError {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }

                Toggle("Listen on launch", isOn: $settings.tslEnabled)

                Text("Configure the Carbonite to send TSL to this Mac's IP on the port above.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text("TSL Listener (Carbonite)")
            }

            // MARK: - FTP Server

            Section {
                Toggle("Enable FTP Server", isOn: $settings.ftpEnabled)

                if settings.ftpEnabled {
                    TextField("Port", value: $settings.ftpPort, format: .number.grouping(.never))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 140)

                    HStack(spacing: 12) {
                        TextField("Username", text: $settings.ftpUsername)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 160)

                        SecureField("Password", text: $settings.ftpPassword)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 160)
                    }

                    HStack {
                        TextField("Transfer Base Path", text: $settings.ftpBasePath)
                            .textFieldStyle(.roundedBorder)

                        Button("Browse...") {
                            DispatchQueue.main.async {
                                let panel = NSOpenPanel()
                                panel.canChooseFiles = false
                                panel.canChooseDirectories = true
                                panel.allowsMultipleSelection = false
                                panel.message = "Choose the base folder for FTP file transfers"

                                if panel.runModal() == .OK, let url = panel.url {
                                    settings.ftpBasePath = url.path
                                    // Store security-scoped bookmark for sandbox access
                                    if let bookmark = try? url.bookmarkData(options: .withSecurityScope) {
                                        settings.ftpBasePathBookmark = bookmark
                                    }
                                    settings.save()
                                }
                            }
                        }
                        .buttonStyle(.bordered)
                    }

                    HStack(spacing: 12) {
                        if connections.isFTPListening {
                            Button("Stop Server") {
                                connections.stopFTPServer()
                            }
                            .buttonStyle(.bordered)
                        } else {
                            Button("Start Server") {
                                settings.save()
                                connections.startFTPServer(port: settings.ftpPort, settings: settings)
                            }
                            .buttonStyle(.borderedProminent)
                        }

                        Spacer()

                        HStack(spacing: 6) {
                            Circle()
                                .fill(connections.isFTPListening ? Color.green : Color.red)
                                .frame(width: 8, height: 8)
                            Text(connections.isFTPListening ? "Listening" : "Stopped")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    if connections.isFTPListening {
                        let count = connections.ftpServer.activeSessionCount
                        Text("\(count) active connection\(count == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    if let error = connections.ftpServer.lastError {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }

                    Text("Files saved to: {base path}/{date}/")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("On the Canon C200, set the FTP server to this Mac's IP and port \(settings.ftpPort) with the username and password above.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } header: {
                Text("FTP Server (Canon C200)")
            }

            // MARK: - Cameras

            Section {
                if assignments.cameraAssignments.isEmpty {
                    Text("No cameras assigned. Add cameras from TSL sources or manually.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.vertical, 4)
                } else {
                    ForEach($assignments.cameraAssignments) { $camera in
                        HStack {
                            CameraAssignmentRow(camera: $camera)

                            Button(action: { self.assignments.removeCamera(id: camera.id) }) {
                                Image(systemName: "trash")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.borderless)
                            .help("Remove camera")
                        }
                    }
                }
            } header: {
                HStack {
                    Text("Cameras")
                    Spacer()
                    Button(action: { showingSourcePicker = true }) {
                        Label("Add Cameras", systemImage: "plus")
                    }
                    .buttonStyle(.borderless)
                }
            }

            // MARK: - System Outputs

            Section {
                if assignments.systemOutputs.isEmpty {
                    Text("No system outputs assigned. Add outputs like program out, clean feed, or ME outputs.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.vertical, 4)
                } else {
                    ForEach($assignments.systemOutputs) { $output in
                        HStack {
                            CameraAssignmentRow(camera: $output)

                            Button(action: { self.assignments.removeSystemOutput(id: output.id) }) {
                                Image(systemName: "trash")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.borderless)
                            .help("Remove output")
                        }
                    }
                }
            } header: {
                HStack {
                    Text("System Outputs")
                    Spacer()
                    Button(action: { showingOutputPicker = true }) {
                        Label("Add Outputs", systemImage: "plus")
                    }
                    .buttonStyle(.borderless)
                }
            }

            // MARK: - Keyers

            Section {
                if assignments.keyerAssignments.isEmpty {
                    Text("No keyers assigned. Add keyers to track downstream key events.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.vertical, 4)
                } else {
                    ForEach($assignments.keyerAssignments) { $keyer in
                        HStack {
                            KeyerAssignmentRow(keyer: $keyer)

                            Button(action: { self.assignments.removeKeyer(id: keyer.id) }) {
                                Image(systemName: "trash")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.borderless)
                            .help("Remove keyer")
                        }
                    }
                }
            } header: {
                HStack {
                    Text("Keyers")
                    Spacer()
                    Button(action: { showingKeyerPicker = true }) {
                        Label("Add Keyer", systemImage: "plus")
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showingSourcePicker) {
            CameraSourcePickerSheet()
        }
        .sheet(isPresented: $showingOutputPicker) {
            SystemOutputPickerSheet()
        }
        .sheet(isPresented: $showingKeyerPicker) {
            KeyerPickerSheet()
        }
        .onChange(of: settings.tslPort) { settings.save() }
        .onChange(of: settings.tslEnabled) { settings.save() }
        .onChange(of: settings.ftpEnabled) { settings.save() }
        .onChange(of: settings.ftpPort) { settings.save() }
        .onChange(of: settings.ftpBasePath) { settings.save() }
        .onChange(of: settings.ftpUsername) { settings.save() }
        .onChange(of: settings.ftpPassword) { settings.save() }
    }
}

// MARK: - Camera Source Picker Sheet

struct CameraSourcePickerSheet: View {
    @Environment(ConnectionManager.self) private var connections
    @Environment(AssignmentStore.self) private var assignments
    @Environment(\.dismiss) private var dismiss

    @State private var selectedIndices: Set<Int> = []

    private var sortedSources: [SourceState] {
        connections.busState.sources.values.sorted { $0.index < $1.index }
    }

    private var assignedIndices: Set<Int> {
        Set(assignments.cameraAssignments.map(\.tslIndex))
            .union(assignments.systemOutputs.map(\.tslIndex))
    }

    private var newSelectionCount: Int {
        selectedIndices.subtracting(assignedIndices).count
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Add Cameras")
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()

            Divider()

            if sortedSources.isEmpty {
                // No TSL sources available
                VStack(spacing: 12) {
                    Image(systemName: "antenna.radiowaves.left.and.right.slash")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("No TSL sources available")
                        .font(.headline)
                    Text("Connect to TSL to discover sources from the switcher.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                // Source list
                List(sortedSources) { source in
                    let isAssigned = assignedIndices.contains(source.index)
                    let isSelected = selectedIndices.contains(source.index)

                    HStack(spacing: 12) {
                        // Checkbox
                        if isAssigned {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        } else {
                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(isSelected ? .accentColor : .secondary)
                        }

                        // Tally indicator
                        Circle()
                            .fill(tallyColor(for: source))
                            .frame(width: 8, height: 8)

                        // Source info
                        VStack(alignment: .leading, spacing: 2) {
                            Text(source.sourceLabel.isEmpty ? "Source \(source.index)" : source.sourceLabel)
                                .fontWeight(isAssigned ? .medium : .regular)
                            HStack(spacing: 8) {
                                Text("TSL \(source.index)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                if !source.busLabel.isEmpty {
                                    Text(source.busLabel)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }

                        Spacer()

                        if isAssigned {
                            Text("Assigned")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard !isAssigned else { return }
                        if isSelected {
                            selectedIndices.remove(source.index)
                        } else {
                            selectedIndices.insert(source.index)
                        }
                    }
                }
                .listStyle(.plain)
            }

            Divider()

            // Footer
            HStack {
                Button("Add Manually") {
                    assignments.addCamera()
                    dismiss()
                }
                .buttonStyle(.bordered)

                Spacer()

                if !sortedSources.isEmpty {
                    Button("Add \(newSelectionCount) Camera\(newSelectionCount == 1 ? "" : "s")") {
                        addSelected()
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(newSelectionCount == 0)
                }
            }
            .padding()
        }
        .frame(minWidth: 450, idealWidth: 500, minHeight: 350, idealHeight: 450)
    }

    private func tallyColor(for source: SourceState) -> Color {
        if source.tally.program { return .red }
        if source.tally.preview { return .green }
        return Color.secondary.opacity(0.3)
    }

    private func addSelected() {
        let newIndices = selectedIndices.subtracting(assignedIndices).sorted()
        for index in newIndices {
            let source = connections.busState.sources[index]
            let name: String
            if let label = source?.sourceLabel, !label.isEmpty {
                name = label
            } else {
                name = "Camera \(assignments.cameraAssignments.count + 1)"
            }
            let camera = CameraAssignment(tslIndex: index, name: name)
            assignments.cameraAssignments.append(camera)
        }
        assignments.save()
    }
}

// MARK: - System Output Picker Sheet

struct SystemOutputPickerSheet: View {
    @Environment(ConnectionManager.self) private var connections
    @Environment(AssignmentStore.self) private var assignments
    @Environment(\.dismiss) private var dismiss

    @State private var selectedIndices: Set<Int> = []

    private var sortedSources: [SourceState] {
        connections.busState.sources.values.sorted { $0.index < $1.index }
    }

    private var assignedIndices: Set<Int> {
        Set(assignments.cameraAssignments.map(\.tslIndex))
            .union(assignments.systemOutputs.map(\.tslIndex))
    }

    private var newSelectionCount: Int {
        selectedIndices.subtracting(assignedIndices).count
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Add System Outputs")
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()

            Divider()

            if sortedSources.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "antenna.radiowaves.left.and.right.slash")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("No TSL sources available")
                        .font(.headline)
                    Text("Connect to TSL to discover sources from the switcher.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                List(sortedSources) { source in
                    let isAssigned = assignedIndices.contains(source.index)
                    let isSelected = selectedIndices.contains(source.index)

                    HStack(spacing: 12) {
                        if isAssigned {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        } else {
                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(isSelected ? .accentColor : .secondary)
                        }

                        Circle()
                            .fill(tallyColor(for: source))
                            .frame(width: 8, height: 8)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(source.sourceLabel.isEmpty ? "Source \(source.index)" : source.sourceLabel)
                                .fontWeight(isAssigned ? .medium : .regular)
                            HStack(spacing: 8) {
                                Text("TSL \(source.index)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                if !source.busLabel.isEmpty {
                                    Text(source.busLabel)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }

                        Spacer()

                        if isAssigned {
                            Text("Assigned")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard !isAssigned else { return }
                        if isSelected {
                            selectedIndices.remove(source.index)
                        } else {
                            selectedIndices.insert(source.index)
                        }
                    }
                }
                .listStyle(.plain)
            }

            Divider()

            HStack {
                Button("Add Manually") {
                    assignments.addSystemOutput()
                    dismiss()
                }
                .buttonStyle(.bordered)

                Spacer()

                if !sortedSources.isEmpty {
                    Button("Add \(newSelectionCount) Output\(newSelectionCount == 1 ? "" : "s")") {
                        addSelected()
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(newSelectionCount == 0)
                }
            }
            .padding()
        }
        .frame(minWidth: 450, idealWidth: 500, minHeight: 350, idealHeight: 450)
    }

    private func tallyColor(for source: SourceState) -> Color {
        if source.tally.program { return .red }
        if source.tally.preview { return .green }
        return Color.secondary.opacity(0.3)
    }

    private func addSelected() {
        let newIndices = selectedIndices.subtracting(assignedIndices).sorted()
        for index in newIndices {
            let source = connections.busState.sources[index]
            let name: String
            if let label = source?.sourceLabel, !label.isEmpty {
                name = label
            } else {
                name = "Output \(assignments.systemOutputs.count + 1)"
            }
            let output = CameraAssignment(tslIndex: index, name: name)
            assignments.systemOutputs.append(output)
        }
        assignments.save()
    }
}

// MARK: - Keyer Picker Sheet

struct KeyerPickerSheet: View {
    @Environment(AssignmentStore.self) private var assignments
    @Environment(\.dismiss) private var dismiss

    @State private var meNumber: Int = 1
    @State private var keyerNumber: Int = 1
    @State private var label: String = ""
    @State private var source: KeyerSource = .proPresenter

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Add Keyer")
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()

            Divider()

            Form {
                Picker("ME Number", selection: $meNumber) {
                    ForEach(1...4, id: \.self) { me in
                        Text("ME \(me)").tag(me)
                    }
                }
                .pickerStyle(.menu)

                Picker("Keyer Number", selection: $keyerNumber) {
                    ForEach(1...8, id: \.self) { keyer in
                        Text("Keyer \(keyer)").tag(keyer)
                    }
                }
                .pickerStyle(.menu)

                TextField("Label", text: $label, prompt: Text("e.g. Lower Third"))
                    .textFieldStyle(.roundedBorder)

                Picker("Source", selection: $source) {
                    ForEach(KeyerSource.allCases, id: \.self) { s in
                        Text(s.rawValue).tag(s)
                    }
                }
                .pickerStyle(.menu)
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Spacer()
                Button("Add Keyer") {
                    let keyer = KeyerAssignment(
                        meNumber: meNumber,
                        keyerNumber: keyerNumber,
                        label: label.isEmpty ? "Keyer \(keyerNumber)" : label,
                        source: source
                    )
                    assignments.keyerAssignments.append(keyer)
                    assignments.save()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(minWidth: 350, idealWidth: 400, minHeight: 300, idealHeight: 350)
    }
}
