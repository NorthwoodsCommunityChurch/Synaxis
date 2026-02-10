import Foundation

struct FTPTransferStatus: Identifiable {
    let id = UUID()
    let fileName: String
    var bytesReceived: Int64
    var isComplete: Bool
    var error: String?
    let startTime: Date

    init(fileName: String) {
        self.fileName = fileName
        self.bytesReceived = 0
        self.isComplete = false
        self.error = nil
        self.startTime = Date()
    }
}
