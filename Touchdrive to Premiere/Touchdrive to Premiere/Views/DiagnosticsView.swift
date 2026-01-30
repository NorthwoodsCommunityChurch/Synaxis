//
//  DiagnosticsView.swift
//  Synaxis
//
//  Connection diagnostics and test event generation view.
//

import SwiftUI

struct DiagnosticsView: View {
    @Environment(ConnectionManager.self) private var connections
    @Environment(SessionManager.self) private var session
    @Environment(SettingsManager.self) private var settings
    @Environment(AssignmentStore.self) private var assignments

    @State private var testKeyerNumber: Int = 1
    @State private var testSlideIndex: Int = 0

    private static let timestampFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm:ss.SSS"
        return fmt
    }()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Connection Diagnostics")
                    .font(.title2)
                    .fontWeight(.bold)

                // TSL Listener
                tslSection

                // ProPresenter machines
                ForEach(assignments.proPresenterConfigs) { config in
                    proPresenterCard(config: config)
                }

                // HyperDeck
                hyperDeckSection

                Divider()

                // Test Events
                testEventsSection

                Divider()

                // Recent Events
                recentEventsSection
            }
            .padding()
        }
    }

    // MARK: - TSL (Carbonite) Section

    private var tslSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle()
                    .fill(connections.isTSLConnected ? Color.green : Color.red)
                    .frame(width: 12, height: 12)

                Text("TSL (Carbonite)")
                    .font(.headline)

                Spacer()

                if connections.isTSLConnected {
                    Button("Stop Listening") {
                        connections.stopTSLListener()
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button("Start Listening") {
                        connections.startTSLListener(port: settings.tslPort)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            HStack {
                Label("\(settings.tslHost):\(settings.tslPort)", systemImage: "network")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Text(connections.isTSLConnected ? "Connected" : "Disconnected")
                    .font(.caption)
                    .foregroundColor(connections.isTSLConnected ? .green : .red)
            }

            if let error = connections.tslClient.lastError {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }
                .padding(8)
                .background(Color.red.opacity(0.1))
                .cornerRadius(4)
            }

            // Last raw hex dump
            if !connections.tslClient.lastRawHex.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Last Raw Data:")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text(connections.tslClient.lastRawHex)
                        .font(.system(.caption, design: .monospaced))
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.black.opacity(0.85))
                        .foregroundColor(.green)
                        .cornerRadius(4)
                }
            }

            // Bus state summary
            let busLabels = connections.busState.busLabels
            if !busLabels.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Bus State:")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    ForEach(busLabels, id: \.self) { busLabel in
                        HStack(spacing: 8) {
                            Text(busLabel)
                                .font(.system(.caption, design: .monospaced))
                                .fontWeight(.medium)
                                .frame(width: 80, alignment: .leading)

                            if let pgmIndex = connections.busState.programSourcePerBus[busLabel],
                               let pgmSource = connections.busState.sources[pgmIndex] {
                                HStack(spacing: 4) {
                                    Circle().fill(Color.red).frame(width: 6, height: 6)
                                    Text("PGM: \(pgmSource.sourceLabel)")
                                        .font(.caption)
                                }
                            }

                            if let pvwIndex = connections.busState.previewSourcePerBus[busLabel],
                               let pvwSource = connections.busState.sources[pvwIndex] {
                                HStack(spacing: 4) {
                                    Circle().fill(Color.green).frame(width: 6, height: 6)
                                    Text("PVW: \(pvwSource.sourceLabel)")
                                        .font(.caption)
                                }
                            }

                            Spacer()
                        }
                    }
                }
                .padding(8)
                .background(Color(nsColor: .textBackgroundColor))
                .cornerRadius(4)
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }

    // MARK: - ProPresenter Section (per machine)

    private func proPresenterCard(config: ProPresenterConfig) -> some View {
        let isActive = connections.isProPresenterConnected(id: config.id)
        let client = connections.proPresenterClient(for: config.id)

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle()
                    .fill(isActive ? Color.green : Color.red)
                    .frame(width: 12, height: 12)

                Text(config.name)
                    .font(.headline)

                Spacer()

                if isActive {
                    Button("Disconnect") {
                        connections.disconnectProPresenter(id: config.id)
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button("Connect") {
                        connections.connectProPresenter(config: config)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(config.host.isEmpty)
                }
            }

            HStack {
                Label(config.baseURL, systemImage: "network")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)

                Spacer()

                Text(isActive ? "Connected" : "Disconnected")
                    .font(.caption)
                    .foregroundColor(isActive ? .green : .red)
            }

            if let error = client?.lastError {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }
                .padding(8)
                .background(Color.red.opacity(0.1))
                .cornerRadius(4)
            }

            if isActive, let client {
                VStack(alignment: .leading, spacing: 8) {
                    if !client.currentPresentationName.isEmpty {
                        HStack {
                            Text("Presentation:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(client.currentPresentationName)
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                    }

                    HStack {
                        Text("Slide \(client.currentSlideIndex)")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        if !client.currentSlideText.isEmpty {
                            Text("--")
                                .foregroundColor(.secondary)
                            Text(client.currentSlideText)
                                .font(.caption)
                                .lineLimit(2)
                        }
                    }

                    if let thumbnail = client.currentSlideThumbnail {
                        Image(nsImage: thumbnail)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: 280)
                            .cornerRadius(4)
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                            )
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .textBackgroundColor))
                .cornerRadius(4)
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }

    // MARK: - HyperDeck Section

    private var hyperDeckSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle()
                    .fill(connections.isHyperDeckConnected ? Color.green : Color.red)
                    .frame(width: 12, height: 12)

                Text("HyperDeck")
                    .font(.headline)

                Spacer()

                if connections.isHyperDeckConnected {
                    HStack(spacing: 8) {
                        if connections.hyperDeckClient.isRecording {
                            Button {
                                connections.stopHyperDeckRecording()
                            } label: {
                                Label("Stop", systemImage: "stop.fill")
                            }
                            .buttonStyle(.bordered)
                            .tint(.red)
                        } else {
                            Button {
                                connections.startHyperDeckRecording()
                            } label: {
                                Label("Record", systemImage: "record.circle")
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.red)
                        }

                        Button("Disconnect") {
                            connections.disconnectHyperDeck()
                        }
                        .buttonStyle(.bordered)
                    }
                } else {
                    Button("Connect") {
                        connections.connectHyperDeck(
                            host: settings.hyperDeckHost,
                            port: settings.hyperDeckPort
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(settings.hyperDeckHost.isEmpty)
                }
            }

            HStack {
                Label(
                    "\(settings.hyperDeckHost):\(settings.hyperDeckPort)",
                    systemImage: "internaldrive"
                )
                .font(.caption)
                .foregroundColor(.secondary)

                Spacer()

                Text(connections.isHyperDeckConnected ? "Connected" : "Disconnected")
                    .font(.caption)
                    .foregroundColor(connections.isHyperDeckConnected ? .green : .red)
            }

            if let error = connections.hyperDeckClient.lastError {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }
                .padding(8)
                .background(Color.red.opacity(0.1))
                .cornerRadius(4)
            }

            if connections.isHyperDeckConnected {
                HStack(spacing: 12) {
                    // Transport status
                    HStack(spacing: 4) {
                        Image(systemName: transportIcon(for: connections.hyperDeckClient.transportStatus))
                            .foregroundColor(transportColor(for: connections.hyperDeckClient.transportStatus))
                        Text(connections.hyperDeckClient.transportStatus.capitalized)
                            .font(.caption)
                    }

                    // Timecode
                    Text(connections.hyperDeckClient.currentTimecode)
                        .font(.system(.caption, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.black.opacity(0.1))
                        .cornerRadius(4)

                    // Clip count
                    Text("\(connections.hyperDeckClient.clips.count) clips")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .textBackgroundColor))
                .cornerRadius(4)
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }

    // MARK: - Test Events Section

    private var testEventsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Test Events")
                    .font(.headline)

                Spacer()

                Text("Simulate events to test the system")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Basic switcher tests
            HStack(spacing: 8) {
                Button(action: { sendTestCut() }) {
                    Label("Test Cut", systemImage: "scissors")
                }
                .buttonStyle(.bordered)

                Button(action: { sendTestTransition() }) {
                    Label("Test Transition", systemImage: "arrow.right")
                }
                .buttonStyle(.bordered)
            }

            Divider()

            // Keyer tests with number selector
            HStack(spacing: 12) {
                Text("Keyer:")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Picker("Keyer", selection: $testKeyerNumber) {
                    ForEach(1...8, id: \.self) { num in
                        Text("\(num)").tag(num)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 200)

                Button(action: { sendTestKeyOn() }) {
                    Label("Key ON", systemImage: "square.stack.3d.up.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)

                Button(action: { sendTestKeyOff() }) {
                    Label("Key OFF", systemImage: "square.stack.3d.up")
                }
                .buttonStyle(.bordered)
                .tint(.orange)
            }

            Divider()

            // Slide change test
            HStack(spacing: 12) {
                Text("Slide:")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Stepper(value: $testSlideIndex, in: 0...99) {
                    Text("\(testSlideIndex)")
                        .frame(width: 30)
                }

                Button(action: { sendTestSlideChange() }) {
                    Label("Send Slide Change", systemImage: "text.below.photo")
                }
                .buttonStyle(.bordered)
            }

            Divider()

            // Full sequence test
            HStack(spacing: 8) {
                Text("Sequence:")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Button(action: { runFullTestSequence() }) {
                    Label("Run Full Test", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)

                Text("Simulates: Cut -> Key ON -> Slide changes -> Key OFF")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }

    // MARK: - Recent Events Section

    private var recentEventsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Recent Events")
                    .font(.headline)

                Spacer()

                Text("\(session.eventCount) total")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if session.events.isEmpty {
                Text("No events received yet")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(session.events.suffix(10).reversed()) { event in
                        EventDiagnosticRow(event: event)
                    }
                }
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }

    // MARK: - Transport Helpers

    private func transportIcon(for status: String) -> String {
        switch status.lowercased() {
        case "stopped": return "stop.fill"
        case "play": return "play.fill"
        case "record": return "record.circle.fill"
        case "shuttle": return "forward.fill"
        case "jog": return "dial.medium"
        case "preview": return "eye.fill"
        default: return "questionmark"
        }
    }

    private func transportColor(for status: String) -> Color {
        switch status.lowercased() {
        case "record": return .red
        case "play": return .green
        default: return .secondary
        }
    }

    // MARK: - Test Event Methods

    private func sendTestCut() {
        let event = ProductionEvent(
            type: .programCut,
            payload: .programCut(sourceIndex: 3, sourceName: "CAM 1", busName: "ME1PGM")
        )
        session.eventLogger.logEvent(event)
    }

    private func sendTestTransition() {
        let event = ProductionEvent(
            type: .transition,
            payload: .transition(sourceIndex: 5, sourceName: "CAM 3", busName: "ME1PGM", type: "AUTO")
        )
        session.eventLogger.logEvent(event)
    }

    private func sendTestKeyOn() {
        let event = ProductionEvent(
            type: .keyerOn,
            payload: .keyerOn(meNumber: 1, keyerNumber: testKeyerNumber)
        )
        session.eventLogger.logEvent(event)
    }

    private func sendTestKeyOff() {
        let event = ProductionEvent(
            type: .keyerOff,
            payload: .keyerOff(meNumber: 1, keyerNumber: testKeyerNumber)
        )
        session.eventLogger.logEvent(event)
    }

    private func sendTestSlideChange() {
        testSlideIndex += 1
        let event = ProductionEvent(
            type: .slideChange,
            payload: .slideChange(
                presentationName: "Test Presentation",
                slideIndex: testSlideIndex,
                slideText: "Test Slide \(testSlideIndex)"
            )
        )
        session.eventLogger.logEvent(event)
    }

    private func runFullTestSequence() {
        Task {
            // 1. Initial cut to camera 1
            sendTestCut()
            try? await Task.sleep(nanoseconds: 500_000_000)

            // 2. Keyer ON
            sendTestKeyOn()
            try? await Task.sleep(nanoseconds: 1_000_000_000)

            // 3. First slide
            sendTestSlideChange()
            try? await Task.sleep(nanoseconds: 2_000_000_000)

            // 4. Second slide
            sendTestSlideChange()
            try? await Task.sleep(nanoseconds: 2_000_000_000)

            // 5. Third slide
            sendTestSlideChange()
            try? await Task.sleep(nanoseconds: 1_500_000_000)

            // 6. Keyer OFF
            sendTestKeyOff()
            try? await Task.sleep(nanoseconds: 500_000_000)

            // 7. Cut to camera 2
            let cutEvent = ProductionEvent(
                type: .programCut,
                payload: .programCut(sourceIndex: 2, sourceName: "CAM 2", busName: "ME1PGM")
            )
            session.eventLogger.logEvent(cutEvent)
        }
    }
}

// MARK: - Event Diagnostic Row

struct EventDiagnosticRow: View {
    let event: ProductionEvent

    private static let timestampFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm:ss.SSS"
        return fmt
    }()

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: event.type.iconName)
                .foregroundColor(eventColor)
                .frame(width: 16)

            Text(Self.timestampFormatter.string(from: event.timestamp))
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .leading)

            Text(event.type.label)
                .font(.caption)
                .fontWeight(.medium)
                .frame(width: 80, alignment: .leading)

            Text(event.timecode)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 90, alignment: .leading)

            Text(event.description)
                .font(.caption)
                .lineLimit(1)

            Spacer()
        }
        .padding(.vertical, 2)
    }

    private var eventColor: Color {
        switch event.type {
        case .programCut: return .blue
        case .transition: return .cyan
        case .keyerOn: return .green
        case .keyerOff: return .orange
        case .slideChange: return .purple
        case .fadeToBlack: return .indigo
        case .recordStart: return .red
        case .recordStop: return .gray
        case .connectionChange: return .yellow
        }
    }
}
