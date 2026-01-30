import Foundation
import Observation
import OSLog
import SwiftUI

/// CRUD store for camera assignments, keyer assignments, and ProPresenter configurations.
///
/// All mutations automatically persist to `UserDefaults`. Keys are versioned
/// so the new model types never collide with legacy data.
@Observable
final class AssignmentStore {
    nonisolated deinit { }

    // MARK: - State

    var cameraAssignments: [CameraAssignment] = []
    var keyerAssignments: [KeyerAssignment] = []
    var proPresenterConfigs: [ProPresenterConfig] = []

    // MARK: - Init

    init() {
        load()
    }

    // MARK: - Camera CRUD

    func addCamera() {
        let nextIndex = (cameraAssignments.map(\.tslIndex).max() ?? 0) + 1
        let assignment = CameraAssignment(
            tslIndex: nextIndex,
            name: "Camera \(cameraAssignments.count + 1)"
        )
        cameraAssignments.append(assignment)
        save()
    }

    func removeCamera(at offsets: IndexSet) {
        cameraAssignments.remove(atOffsets: offsets)
        save()
    }

    func removeCamera(id: UUID) {
        cameraAssignments.removeAll { $0.id == id }
        save()
    }

    func updateCamera(_ assignment: CameraAssignment) {
        if let index = cameraAssignments.firstIndex(where: { $0.id == assignment.id }) {
            cameraAssignments[index] = assignment
            save()
        }
    }

    // MARK: - Keyer CRUD

    func addKeyer() {
        let nextKeyer = (keyerAssignments.map(\.keyerNumber).max() ?? 0) + 1
        let assignment = KeyerAssignment(
            meNumber: 1,
            keyerNumber: nextKeyer,
            label: "Keyer \(nextKeyer)"
        )
        keyerAssignments.append(assignment)
        save()
    }

    func removeKeyer(at offsets: IndexSet) {
        keyerAssignments.remove(atOffsets: offsets)
        save()
    }

    func removeKeyer(id: UUID) {
        keyerAssignments.removeAll { $0.id == id }
        save()
    }

    func updateKeyer(_ assignment: KeyerAssignment) {
        if let index = keyerAssignments.firstIndex(where: { $0.id == assignment.id }) {
            keyerAssignments[index] = assignment
            save()
        }
    }

    // MARK: - ProPresenter Config CRUD

    @discardableResult
    func addProPresenterConfig() -> ProPresenterConfig {
        let nextNumber = proPresenterConfigs.count + 1
        let config = ProPresenterConfig(name: "ProPresenter \(nextNumber)")
        proPresenterConfigs.append(config)
        save()
        return config
    }

    func removeProPresenterConfig(id: UUID) {
        proPresenterConfigs.removeAll { $0.id == id }
        save()
    }

    func updateProPresenterConfig(_ config: ProPresenterConfig) {
        if let index = proPresenterConfigs.firstIndex(where: { $0.id == config.id }) {
            proPresenterConfigs[index] = config
            save()
        }
    }

    // MARK: - Persistence

    func load() {
        let defaults = UserDefaults.standard
        let decoder = JSONDecoder()

        if let data = defaults.data(forKey: Keys.cameraAssignments),
           let cameras = try? decoder.decode([CameraAssignment].self, from: data) {
            cameraAssignments = cameras
        }

        if let data = defaults.data(forKey: Keys.keyerAssignments),
           let keyers = try? decoder.decode([KeyerAssignment].self, from: data) {
            keyerAssignments = keyers
        }

        // ProPresenter configs: try new array key first, then migrate from legacy single config
        if let data = defaults.data(forKey: Keys.proPresenterConfigs),
           let configs = try? decoder.decode([ProPresenterConfig].self, from: data) {
            proPresenterConfigs = configs
        } else if let data = defaults.data(forKey: Keys.legacyProPresenterConfig),
                  var config = try? decoder.decode(ProPresenterConfig.self, from: data) {
            // Migration: wrap single config in array
            if config.name == "ProPresenter" {
                config.name = "ProPresenter 1"
            }
            proPresenterConfigs = [config]
            save()
            defaults.removeObject(forKey: Keys.legacyProPresenterConfig)
            Log.session.info("Migrated single ProPresenter config to multi-machine format")
        }

        Log.session.info("Assignments loaded: \(self.cameraAssignments.count) cameras, \(self.keyerAssignments.count) keyers, \(self.proPresenterConfigs.count) ProPresenter machines")
    }

    func save() {
        let defaults = UserDefaults.standard
        let encoder = JSONEncoder()

        if let data = try? encoder.encode(cameraAssignments) {
            defaults.set(data, forKey: Keys.cameraAssignments)
        }

        if let data = try? encoder.encode(keyerAssignments) {
            defaults.set(data, forKey: Keys.keyerAssignments)
        }

        if let data = try? encoder.encode(proPresenterConfigs) {
            defaults.set(data, forKey: Keys.proPresenterConfigs)
        }

        Log.session.debug("Assignments saved")
    }

    // MARK: - Keys

    private enum Keys {
        static let cameraAssignments = "cameraAssignments_v2"
        static let keyerAssignments = "keyerAssignments_v2"
        static let proPresenterConfigs = "proPresenterConfigs_v3"
        static let legacyProPresenterConfig = "proPresenterConfig_v2"
    }
}
