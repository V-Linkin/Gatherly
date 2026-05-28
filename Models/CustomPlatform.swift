import Foundation

struct CustomPlatform: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var logoPath: String?
    var createdAt: Date
    var sortOrder: Int
    
    init(id: UUID = UUID(), name: String, logoPath: String? = nil, createdAt: Date = Date(), sortOrder: Int = 0) {
        self.id = id
        self.name = name
        self.logoPath = logoPath
        self.createdAt = createdAt
        self.sortOrder = sortOrder
    }
}
