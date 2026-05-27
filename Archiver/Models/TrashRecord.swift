import Foundation

/// 回收站记录
struct TrashRecord: Identifiable, Codable {
    let id: UUID
    var itemID: UUID
    var deletedAt: Date
    var autoDeleteAt: Date
    var originalFolderID: UUID?
    var originalArchiveStatus: ArchiveStatus
    var mediaPaths: [String]
    
    init(
        id: UUID = UUID(),
        itemID: UUID,
        deletedAt: Date = Date(),
        autoDeleteAt: Date? = nil,
        originalFolderID: UUID? = nil,
        originalArchiveStatus: ArchiveStatus = .pending,
        mediaPaths: [String] = []
    ) {
        self.id = id
        self.itemID = itemID
        self.deletedAt = deletedAt
        self.autoDeleteAt = autoDeleteAt ?? Calendar.current.date(byAdding: .day, value: 30, to: Date())!
        self.originalFolderID = originalFolderID
        self.originalArchiveStatus = originalArchiveStatus
        self.mediaPaths = mediaPaths
    }
}
