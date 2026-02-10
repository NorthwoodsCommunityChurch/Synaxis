import Foundation

struct CameraAssignment: Identifiable, Codable, Equatable {
    var id = UUID()
    var tslIndex: Int
    var name: String
    var hyperDeckChannel: Int?

    init(tslIndex: Int = 1, name: String = "", hyperDeckChannel: Int? = nil) {
        self.tslIndex = tslIndex
        self.name = name
        self.hyperDeckChannel = hyperDeckChannel
    }
}
