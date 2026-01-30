import Foundation

enum AppError: LocalizedError {
    case connectionFailed(service: String, reason: String)
    case connectionTimeout(service: String)
    case invalidPort(Int)
    case invalidHost(String)
    case parseError(protocol: String, detail: String)
    case exportFailed(reason: String)
    case importFailed(reason: String)
    case sessionNotActive
    case fileNotFound(URL)

    var errorDescription: String? {
        switch self {
        case .connectionFailed(let service, let reason):
            return "\(service) connection failed: \(reason)"
        case .connectionTimeout(let service):
            return "\(service) connection timed out"
        case .invalidPort(let port):
            return "Invalid port: \(port)"
        case .invalidHost(let host):
            return "Invalid host: \(host)"
        case .parseError(let proto, let detail):
            return "\(proto) parse error: \(detail)"
        case .exportFailed(let reason):
            return "Export failed: \(reason)"
        case .importFailed(let reason):
            return "Import failed: \(reason)"
        case .sessionNotActive:
            return "No active session"
        case .fileNotFound(let url):
            return "File not found: \(url.lastPathComponent)"
        }
    }
}
