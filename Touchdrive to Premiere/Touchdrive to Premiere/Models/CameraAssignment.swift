import Foundation

struct CameraAssignment: Identifiable, Codable, Equatable {
    var id = UUID()
    var tslIndex: Int
    var name: String
    var fileURL: URL?
    var hyperDeckChannel: Int?

    init(tslIndex: Int = 1, name: String = "", fileURL: URL? = nil, hyperDeckChannel: Int? = nil) {
        self.tslIndex = tslIndex
        self.name = name
        self.fileURL = fileURL
        self.hyperDeckChannel = hyperDeckChannel
    }
}
