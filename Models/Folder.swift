import Foundation

struct Folder: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var parentID: UUID?
    var platform: Platform
    var customPlatformID: UUID?
    var createdAt: Date
    var sortOrder: Int
    
    init(
        id: UUID = UUID(),
        name: String,
        parentID: UUID? = nil,
        platform: Platform,
        customPlatformID: UUID? = nil,
        createdAt: Date = Date(),
        sortOrder: Int = 0
    ) {
        self.id = id
        self.name = name
        self.parentID = parentID
        self.platform = platform
        self.customPlatformID = customPlatformID
        self.createdAt = createdAt
        self.sortOrder = sortOrder
    }
}
