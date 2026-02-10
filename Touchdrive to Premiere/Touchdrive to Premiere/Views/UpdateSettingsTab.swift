//
//  UpdateSettingsTab.swift
//  Synaxis
//
//  Settings tab for checking and installing app updates.
//

import SwiftUI
import Sparkle

struct UpdateSettingsTab: View {
    @Environment(UpdateManager.self) private var updateManager

    @State private var automaticallyChecksForUpdates: Bool = true
    @State private var automaticallyDownloadsUpdates: Bool = false

    var body: some View {
        Form {
            Section {
                currentVersionSection
            } header: {
                Text("Current Version")
            }

            Section {
                Toggle("Check for updates automatically", isOn: $automaticallyChecksForUpdates)
                    .onChange(of: automaticallyChecksForUpdates) { _, newValue in
                        updateManager.updater.automaticallyChecksForUpdates = newValue
                    }

                Toggle("Download updates automatically", isOn: $automaticallyDownloadsUpdates)
                    .onChange(of: automaticallyDownloadsUpdates) { _, newValue in
                        updateManager.updater.automaticallyDownloadsUpdates = newValue
                    }

                Text("When automatic downloads are enabled, updates will be downloaded in the background and installed when you quit the app.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text("Update Preferences")
            }

            Section {
                updateStatusSection
            } header: {
                Text("Update Status")
            }
        }
        .formStyle(.grouped)
        .onAppear {
            automaticallyChecksForUpdates = updateManager.updater.automaticallyChecksForUpdates
            automaticallyDownloadsUpdates = updateManager.updater.automaticallyDownloadsUpdates
        }
    }

    // MARK: - Current Version

    private var currentVersionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Synaxis")
                    .font(.headline)

                Spacer()

                Text("v\(Version.current.description)")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text("Architecture:")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("Apple Silicon (aarch64)")
                    .font(.caption)
            }
        }
    }

    // MARK: - Update Status

    private var updateStatusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Synaxis is up to date")
                Spacer()
            }

            if let lastCheck = updateManager.updater.lastUpdateCheckDate {
                Text("Last checked: \(lastCheck, style: .relative) ago")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button("Check Now") {
                updateManager.checkForUpdates(force: true)
            }
            .buttonStyle(.bordered)
            .disabled(!updateManager.canCheckForUpdates)
        }
    }
}
