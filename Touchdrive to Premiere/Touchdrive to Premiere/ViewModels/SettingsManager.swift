import Foundation
import Observation
import OSLog

/// Centralized app settings backed by UserDefaults with `register(defaults:)` for correct first-launch values.
///
/// Covers TSL listener port, ProPresenter/HyperDeck connection details,
/// project settings (frame rate, resolution, timecode), and export preferences.
@Observable
final class SettingsManager {
    nonisolated deinit { }

    // MARK: - TSL Settings

    var tslHost: String = ""
    var tslPort: UInt16 = 5201
    var tslEnabled: Bool = false

    // MARK: - HyperDeck Settings

    var hyperDeckHost: String = ""
    var hyperDeckPort: Int = 9993
    var hyperDeckEnabled: Bool = false

    // MARK: - Project Settings

    var frameRate: Double = 29.97
    var resolution: Resolution = .hd1080
    var startTimecode: String = "01:00:00:00"
    var dropFrame: Bool = true
    var timecodeSource: TimecodeSource = .hyperDeck

    // MARK: - Export Settings

    var defaultExportPath: String = ""
    var autoExportOnStop: Bool = false
    var exportFileNamePattern: String = "{session}_{date}"

    // MARK: - Initialization

    init() {
        registerDefaults()
        load()
    }

    /// Registers sane defaults so that `UserDefaults.standard` returns correct
    /// values on first launch — before the user has ever saved.
    private func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            Keys.tslPort: 5201,
            Keys.hyperDeckPort: 9993,
            Keys.frameRate: 29.97,
            Keys.resolutionWidth: 1920,
            Keys.resolutionHeight: 1080,
            Keys.startTimecode: "01:00:00:00",
            Keys.dropFrame: true,
            Keys.timecodeSource: TimecodeSource.hyperDeck.rawValue,
            Keys.exportFileNamePattern: "{session}_{date}",
        ])
    }

    // MARK: - Load

    func load() {
        let defaults = UserDefaults.standard

        // TSL
        tslHost = defaults.string(forKey: Keys.tslHost) ?? ""
        let storedPort = defaults.integer(forKey: Keys.tslPort)
        tslPort = storedPort > 0 ? UInt16(clamping: storedPort) : 5201
        tslEnabled = defaults.bool(forKey: Keys.tslEnabled)

        // HyperDeck
        hyperDeckHost = defaults.string(forKey: Keys.hyperDeckHost) ?? ""
        let hdPort = defaults.integer(forKey: Keys.hyperDeckPort)
        hyperDeckPort = hdPort > 0 ? hdPort : 9993
        hyperDeckEnabled = defaults.bool(forKey: Keys.hyperDeckEnabled)

        // Project
        let rate = defaults.double(forKey: Keys.frameRate)
        frameRate = rate > 0 ? rate : 29.97

        let w = defaults.integer(forKey: Keys.resolutionWidth)
        let h = defaults.integer(forKey: Keys.resolutionHeight)
        resolution = (w > 0 && h > 0) ? Resolution(width: w, height: h) : .hd1080

        startTimecode = defaults.string(forKey: Keys.startTimecode) ?? "01:00:00:00"
        dropFrame = defaults.bool(forKey: Keys.dropFrame)

        if let sourceRaw = defaults.string(forKey: Keys.timecodeSource),
           let source = TimecodeSource(rawValue: sourceRaw) {
            timecodeSource = source
        }

        // Export
        defaultExportPath = defaults.string(forKey: Keys.defaultExportPath) ?? ""
        autoExportOnStop = defaults.bool(forKey: Keys.autoExportOnStop)
        exportFileNamePattern = defaults.string(forKey: Keys.exportFileNamePattern) ?? "{session}_{date}"

        Log.session.info("Settings loaded")
    }

    // MARK: - Save

    func save() {
        let defaults = UserDefaults.standard

        defaults.set(tslHost, forKey: Keys.tslHost)
        defaults.set(Int(tslPort), forKey: Keys.tslPort)
        defaults.set(tslEnabled, forKey: Keys.tslEnabled)

        defaults.set(hyperDeckHost, forKey: Keys.hyperDeckHost)
        defaults.set(hyperDeckPort, forKey: Keys.hyperDeckPort)
        defaults.set(hyperDeckEnabled, forKey: Keys.hyperDeckEnabled)

        defaults.set(frameRate, forKey: Keys.frameRate)
        defaults.set(resolution.width, forKey: Keys.resolutionWidth)
        defaults.set(resolution.height, forKey: Keys.resolutionHeight)
        defaults.set(startTimecode, forKey: Keys.startTimecode)
        defaults.set(dropFrame, forKey: Keys.dropFrame)
        defaults.set(timecodeSource.rawValue, forKey: Keys.timecodeSource)

        defaults.set(defaultExportPath, forKey: Keys.defaultExportPath)
        defaults.set(autoExportOnStop, forKey: Keys.autoExportOnStop)
        defaults.set(exportFileNamePattern, forKey: Keys.exportFileNamePattern)

        Log.session.debug("Settings saved")
    }

    // MARK: - UserDefaults Keys

    private enum Keys {
        static let tslHost = "tslHost"
        static let tslPort = "tslPort"
        static let tslEnabled = "tslEnabled"
        static let hyperDeckHost = "hyperDeckHost"
        static let hyperDeckPort = "hyperDeckPort"
        static let hyperDeckEnabled = "hyperDeckEnabled"
        static let frameRate = "frameRate"
        static let resolutionWidth = "resolutionWidth"
        static let resolutionHeight = "resolutionHeight"
        static let startTimecode = "startTimecode"
        static let dropFrame = "dropFrame"
        static let timecodeSource = "timecodeSource"
        static let defaultExportPath = "defaultExportPath"
        static let autoExportOnStop = "autoExportOnStop"
        static let exportFileNamePattern = "exportFileNamePattern"
    }
}
