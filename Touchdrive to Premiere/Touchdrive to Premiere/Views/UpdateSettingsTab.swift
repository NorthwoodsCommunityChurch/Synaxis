//
//  UpdateSettingsTab.swift
//  Synaxis
//
//  Settings tab for checking and installing app updates.
//

import SwiftUI

struct UpdateSettingsTab: View {
    @Environment(UpdateManager.self) private var updateManager

    var body: some View {
        @Bindable var updateManager = updateManager

        Form {
            Section {
                currentVersionSection
            } header: {
                Text("Current Version")
            }

            Section {
                Toggle("Check for updates automatically", isOn: $updateManager.autoCheckEnabled)

                Toggle("Include pre-release versions", isOn: $updateManager.includePreReleases)

                Text("Pre-release versions may contain experimental features and bugs.")
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

    @ViewBuilder
    private var updateStatusSection: some View {
        if updateManager.isChecking {
            HStack {
                ProgressView()
                    .scaleEffect(0.7)
                Text("Checking for updates...")
                    .foregroundStyle(.secondary)
            }
        } else if updateManager.isDownloading {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Downloading update...")
                }

                if updateManager.downloadProgress > 0 {
                    ProgressView(value: updateManager.downloadProgress)
                }
            }
        } else if updateManager.isInstalling {
            HStack {
                ProgressView()
                    .scaleEffect(0.7)
                Text("Installing update...")
                    .foregroundStyle(.secondary)
            }
        } else if let update = updateManager.availableUpdate {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundStyle(.green)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Update Available: \(update.tagName)")
                            .fontWeight(.medium)

                        Text("Released \(update.publishedAt, style: .relative) ago")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }

                if let body = update.body, !body.isEmpty {
                    Text(body)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(5)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(nsColor: .textBackgroundColor))
                        .cornerRadius(6)
                }

                HStack {
                    Button("Download and Install") {
                        updateManager.downloadAndInstallUpdate()
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Dismiss") {
                        updateManager.dismissAvailableUpdate()
                    }
                    .buttonStyle(.bordered)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Synaxis is up to date")
                    Spacer()
                }

                if let lastCheck = updateManager.lastCheckDate {
                    Text("Last checked: \(lastCheck, style: .relative) ago")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let error = updateManager.lastError {
                    Text("Error: \(error)")
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Button("Check Now") {
                    updateManager.checkForUpdates(force: true)
                }
                .buttonStyle(.bordered)
            }
        }
    }
}
