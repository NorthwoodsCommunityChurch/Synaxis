import OSLog

enum Log {
    static let tsl = Logger(subsystem: "com.northwoods.touchdrive", category: "TSL")
    static let proPresenter = Logger(subsystem: "com.northwoods.touchdrive", category: "ProPresenter")
    static let hyperDeck = Logger(subsystem: "com.northwoods.touchdrive", category: "HyperDeck")
    static let session = Logger(subsystem: "com.northwoods.touchdrive", category: "Session")
    static let export = Logger(subsystem: "com.northwoods.touchdrive", category: "Export")
    static let ui = Logger(subsystem: "com.northwoods.touchdrive", category: "UI")
    static let ftp = Logger(subsystem: "com.northwoods.touchdrive", category: "FTP")
    static let update = Logger(subsystem: "com.northwoods.touchdrive", category: "Update")
}
