//
//  UpdateManager.swift
//  Synaxis
//
//  Manages checking for and applying app updates via Sparkle.
//

import Foundation
import Sparkle
import Combine

/// Manages checking for updates using Sparkle framework.
@MainActor
@Observable
final class UpdateManager {
    nonisolated deinit { }

    // MARK: - Observable State

    private(set) var canCheckForUpdates: Bool = false

    // MARK: - Private

    private let updaterController: SPUStandardUpdaterController
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Init

    init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )

        // Observe canCheckForUpdates state
        updaterController.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] canCheck in
                self?.canCheckForUpdates = canCheck
            }
            .store(in: &cancellables)
    }

    // MARK: - Public API

    /// Check for updates manually.
    func checkForUpdates(force: Bool = false) {
        guard canCheckForUpdates else { return }
        updaterController.updater.checkForUpdates()
    }

    /// Access to the underlying updater for menu commands.
    var updater: SPUUpdater {
        updaterController.updater
    }
}
