import Foundation

/// 媒体资产
struct MediaAsset: Identifiable, Codable, Hashable {
    let id: UUID
    var itemID: UUID
    var type: MediaType
    var localPath: String?
    var remoteURL: String?
    var fileName: String
    var fileSize: Int64
    var mimeType: String?
    var width: Int?
    var height: Int?
    var duration: Double?
    var checksum: String?
    var downloadStatus: DownloadStatus
    var thumbnailPath: String?
    var createdAt: Date
    
    init(
        id: UUID = UUID(),
        itemID: UUID,
        type: MediaType,
        localPath: String? = nil,
        remoteURL: String? = nil,
        fileName: String,
        fileSize: Int64 = 0,
        mimeType: String? = nil,
        width: Int? = nil,
        height: Int? = nil,
        duration: Double? = nil,
        checksum: String? = nil,
        downloadStatus: DownloadStatus = .pending,
        thumbnailPath: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.itemID = itemID
        self.type = type
        self.localPath = localPath
        self.remoteURL = remoteURL
        self.fileName = fileName
        self.fileSize = fileSize
        self.mimeType = mimeType
        self.width = width
        self.height = height
        self.duration = duration
        self.checksum = checksum
        self.downloadStatus = downloadStatus
        self.thumbnailPath = thumbnailPath
        self.createdAt = createdAt
    }
}
