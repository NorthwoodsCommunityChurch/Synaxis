import Foundation

struct KeyerAssignment: Identifiable, Codable, Equatable {
    var id = UUID()
    var meNumber: Int
    var keyerNumber: Int
    var label: String
    var source: KeyerSource

    init(meNumber: Int = 1, keyerNumber: Int = 1, label: String = "", source: KeyerSource = .proPresenter) {
        self.meNumber = meNumber
        self.keyerNumber = keyerNumber
        self.label = label
        self.source = source
    }
}

enum KeyerSource: String, Codable, CaseIterable {
    case proPresenter = "ProPresenter"
    case graphicsFolder = "Graphics Folder"
    case other = "Other"
}
