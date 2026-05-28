import Foundation

/// 内容主体
struct Item: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String?
    var body: String?
    var originalURL: String
    var platform: Platform
    var platformContentID: String?
    var normalizedURL: String
    
    var author: String?
    var authorID: String?
    var publishDate: Date?
    var importDate: Date
    var modifyDate: Date
    
    var contentStatus: ContentStatus
    var archiveStatus: ArchiveStatus
    var mediaStatus: MediaStatus
    
    var coverAssetID: UUID?
    var folderID: UUID?
    var customPlatformID: UUID?
    
    var remark: String?
    
    var isStarred: Bool
    var version: Int
    var deletedAt: Date?
    
    // MARK: - Initializer
    
    init(
        id: UUID = UUID(),
        title: String? = nil,
        body: String? = nil,
        originalURL: String,
        platform: Platform,
        platformContentID: String? = nil,
        normalizedURL: String,
        author: String? = nil,
        authorID: String? = nil,
        publishDate: Date? = nil,
        importDate: Date = Date(),
        contentStatus: ContentStatus = .normal,
        archiveStatus: ArchiveStatus = .pending,
        mediaStatus: MediaStatus = .textOnly,
        coverAssetID: UUID? = nil,
        folderID: UUID? = nil,
        remark: String? = nil,
        isStarred: Bool = false,
        version: Int = 1,
        deletedAt: Date? = nil,
        customPlatformID: UUID? = nil
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.originalURL = originalURL
        self.platform = platform
        self.platformContentID = platformContentID
        self.normalizedURL = normalizedURL
        self.author = author
        self.authorID = authorID
        self.publishDate = publishDate
        self.importDate = importDate
        self.modifyDate = Date()
        self.contentStatus = contentStatus
        self.archiveStatus = archiveStatus
        self.mediaStatus = mediaStatus
        self.coverAssetID = coverAssetID
        self.folderID = folderID
        self.remark = remark
        self.isStarred = isStarred
        self.version = version
        self.deletedAt = deletedAt
        self.customPlatformID = customPlatformID
    }
    
    // MARK: - Computed
    
    var isInTrash: Bool { deletedAt != nil }
    
    var displayTitle: String {
        title ?? "未命名内容"
    }
    
    var displayAuthor: String {
        author ?? "未知作者"
    }
}
