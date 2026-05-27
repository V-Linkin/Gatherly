import Foundation

/// 导入任务
struct ImportTask: Identifiable, Codable {
    let id: UUID
    var originalURL: String
    var normalizedURL: String
    var platform: Platform?
    var status: TaskStatus
    var progress: Double
    var errorMessage: String?
    var itemID: UUID?
    var createdAt: Date
    var completedAt: Date?
    var retryCount: Int
    
    init(
        id: UUID = UUID(),
        originalURL: String,
        normalizedURL: String = "",
        platform: Platform? = nil,
        status: TaskStatus = .pending,
        progress: Double = 0,
        errorMessage: String? = nil,
        itemID: UUID? = nil,
        createdAt: Date = Date(),
        completedAt: Date? = nil,
        retryCount: Int = 0
    ) {
        self.id = id
        self.originalURL = originalURL
        self.normalizedURL = normalizedURL
        self.platform = platform
        self.status = status
        self.progress = progress
        self.errorMessage = errorMessage
        self.itemID = itemID
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.retryCount = retryCount
    }
}
