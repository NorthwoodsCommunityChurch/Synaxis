import Foundation

struct ProPresenterConfig: Codable, Equatable, Identifiable {
    var id: UUID = UUID()

    /// Human-readable name for this machine (e.g. "FOH", "Broadcast").
    var name: String = "ProPresenter"

    // MARK: - API Connection (Slide Status)

    /// IP address of the ProPresenter machine.
    var host: String = ""

    /// Pro7 network port — the Port at the top of Pro7 Settings > Network.
    var apiPort: Int = 0

    /// Master enable for ProPresenter integration.
    var enabled: Bool = false

    // MARK: - Remote Connection

    /// Main Pro7 network port — found in Pro7 Settings > Network (Port field).
    var remotePort: Int = 0

    /// ProPresenter Remote password — found in Pro7 Settings > Network > ProPresenter Remote.
    var remotePassword: String = ""

    /// Whether remote control is enabled.
    var remoteEnabled: Bool = false

    // MARK: - Keyer Assignment

    var meNumber: Int = 1
    var keyerNumber: Int = 1

    // MARK: - Computed

    /// Base URL for REST API requests (e.g. http://10.10.11.134:57137).
    var baseURL: String {
        "http://\(host):\(apiPort)"
    }

    /// True when there is enough info to attempt a connection.
    var isConfigured: Bool {
        !host.isEmpty && apiPort > 0
    }

    // MARK: - Codable (migration from "port" → "apiPort")

    private enum CodingKeys: String, CodingKey {
        case id, name
        case host, apiPort, enabled
        case remotePort, remotePassword, remoteEnabled
        case meNumber, keyerNumber
        // Legacy key from before the rename
        case legacyPort = "port"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "ProPresenter"
        host = try c.decodeIfPresent(String.self, forKey: .host) ?? ""
        // Prefer "apiPort"; fall back to legacy "port" key
        if let ap = try c.decodeIfPresent(Int.self, forKey: .apiPort) {
            apiPort = ap
        } else {
            apiPort = try c.decodeIfPresent(Int.self, forKey: .legacyPort) ?? 0
        }
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        remotePort = try c.decodeIfPresent(Int.self, forKey: .remotePort) ?? 0
        remotePassword = try c.decodeIfPresent(String.self, forKey: .remotePassword) ?? ""
        remoteEnabled = try c.decodeIfPresent(Bool.self, forKey: .remoteEnabled) ?? false
        meNumber = try c.decodeIfPresent(Int.self, forKey: .meNumber) ?? 1
        keyerNumber = try c.decodeIfPresent(Int.self, forKey: .keyerNumber) ?? 1
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(host, forKey: .host)
        try c.encode(apiPort, forKey: .apiPort)
        try c.encode(enabled, forKey: .enabled)
        try c.encode(remotePort, forKey: .remotePort)
        try c.encode(remotePassword, forKey: .remotePassword)
        try c.encode(remoteEnabled, forKey: .remoteEnabled)
        try c.encode(meNumber, forKey: .meNumber)
        try c.encode(keyerNumber, forKey: .keyerNumber)
    }

    // Memberwise init (Codable custom init suppresses the auto-generated one)
    init(
        id: UUID = UUID(),
        name: String = "ProPresenter",
        host: String = "",
        apiPort: Int = 0,
        enabled: Bool = false,
        remotePort: Int = 0,
        remotePassword: String = "",
        remoteEnabled: Bool = false,
        meNumber: Int = 1,
        keyerNumber: Int = 1
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.apiPort = apiPort
        self.enabled = enabled
        self.remotePort = remotePort
        self.remotePassword = remotePassword
        self.remoteEnabled = remoteEnabled
        self.meNumber = meNumber
        self.keyerNumber = keyerNumber
    }
}
