import Foundation

/// 解析后的内容数据
struct ParsedContent: Sendable {
    let title: String?
    let body: String?
    let author: String?
    let authorID: String?
    let publishDate: Date?
    let coverURL: String?
    let imageURLs: [String]
    let videoURL: String?
    let platformContentID: String?
    let rawMetadata: [String: String]
    
    init(
        title: String? = nil,
        body: String? = nil,
        author: String? = nil,
        authorID: String? = nil,
        publishDate: Date? = nil,
        coverURL: String? = nil,
        imageURLs: [String] = [],
        videoURL: String? = nil,
        platformContentID: String? = nil,
        rawMetadata: [String: String] = [:]
    ) {
        self.title = title
        self.body = body
        self.author = author
        self.authorID = authorID
        self.publishDate = publishDate
        self.coverURL = coverURL
        self.imageURLs = imageURLs
        self.videoURL = videoURL
        self.platformContentID = platformContentID
        self.rawMetadata = rawMetadata
    }
}

/// 平台解析器协议
protocol ContentParser: Sendable {
    /// 是否能解析该 URL
    func canParse(url: URL) -> Bool
    
    /// 从 URL 提取内容 ID
    func extractContentID(from url: URL) -> String?
    
    /// 标准化 URL
    func normalizeURL(_ url: String) -> String
    
    /// 解析内容
    func parse(url: URL) async throws -> ParsedContent
    
    /// 下载媒体文件，返回下载后的资产信息
    func downloadMedia(content: ParsedContent, itemID: UUID, mediaDir: URL) async throws -> [MediaAsset]
}
