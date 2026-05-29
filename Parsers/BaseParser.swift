import Foundation

/// 解析器基类 - 抽取公共逻辑
class BaseParser: ContentParser, @unchecked Sendable {
    
    let session: URLSession
    
    /// 初始化解析器，支持自定义额外 headers
    init(additionalHeaders: [String: String] = [:]) {
        let config = URLSessionConfiguration.default
        var headers: [String: String] = [
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
        ]
        for (key, value) in additionalHeaders {
            headers[key] = value
        }
        config.httpAdditionalHeaders = headers
        self.session = URLSession(configuration: config)
    }
    
    // MARK: - ContentParser 协议默认实现
    
    func canParse(url: URL) -> Bool {
        fatalError("子类必须实现 canParse(url:)")
    }
    
    func extractContentID(from url: URL) -> String? {
        fatalError("子类必须实现 extractContentID(from:)")
    }
    
    func normalizeURL(_ url: String) -> String {
        fatalError("子类必须实现 normalizeURL(_:)")
    }
    
    func parse(url: URL) async throws -> ParsedContent {
        fatalError("子类必须实现 parse(url:)")
    }
    
    func downloadMedia(content: ParsedContent, itemID: UUID, mediaDir: URL) async throws -> [MediaAsset] {
        var assets: [MediaAsset] = []
        let fileManager = FileManager.default
        let itemDir = mediaDir.appendingPathComponent(itemID.uuidString)
        try fileManager.createDirectory(at: itemDir, withIntermediateDirectories: true)
        
        // 下载封面图
        if let coverURL = content.coverURL, let url = URL(string: coverURL) {
            let fileName = "cover.jpg"
            let localPath = itemDir.appendingPathComponent(fileName)
            if await downloadFile(from: url, to: localPath) {
                let fileSize = (try? fileManager.attributesOfItem(atPath: localPath.path)[.size] as? Int64) ?? 0
                let asset = MediaAsset(
                    itemID: itemID, type: .cover,
                    localPath: "\(itemID.uuidString)/\(fileName)",
                    remoteURL: coverURL, fileName: fileName,
                    fileSize: fileSize, downloadStatus: .completed
                )
                try MediaRepository().insert(asset)
                assets.append(asset)
            }
        }
        
        // 下载图片列表
        for (index, imageURL) in content.imageURLs.enumerated() {
            guard let url = URL(string: imageURL) else { continue }
            let fileName = "image_\(String(format: "%03d", index + 1)).jpg"
            let localPath = itemDir.appendingPathComponent(fileName)
            if await downloadFile(from: url, to: localPath) {
                let fileSize = (try? fileManager.attributesOfItem(atPath: localPath.path)[.size] as? Int64) ?? 0
                let asset = MediaAsset(
                    itemID: itemID, type: .image,
                    localPath: "\(itemID.uuidString)/\(fileName)",
                    remoteURL: imageURL, fileName: fileName,
                    fileSize: fileSize, downloadStatus: .completed
                )
                try MediaRepository().insert(asset)
                assets.append(asset)
            }
        }
        
        // 下载视频
        if let videoURL = content.videoURL, let url = URL(string: videoURL) {
            let fileName = "video.mp4"
            let localPath = itemDir.appendingPathComponent(fileName)
            if await downloadFile(from: url, to: localPath) {
                let fileSize = (try? fileManager.attributesOfItem(atPath: localPath.path)[.size] as? Int64) ?? 0
                let asset = MediaAsset(
                    itemID: itemID, type: .video,
                    localPath: "\(itemID.uuidString)/\(fileName)",
                    remoteURL: videoURL, fileName: fileName,
                    fileSize: fileSize, downloadStatus: .completed
                )
                try MediaRepository().insert(asset)
                assets.append(asset)
            } else {
                let asset = MediaAsset(
                    itemID: itemID, type: .video,
                    remoteURL: videoURL, fileName: "video.mp4",
                    downloadStatus: .failed
                )
                try MediaRepository().insert(asset)
                assets.append(asset)
            }
        }
        
        return assets
    }
    
    // MARK: - 公共工具方法
    
    func downloadFile(from url: URL, to localPath: URL) async -> Bool {
        do {
            let (data, _) = try await session.data(from: url)
            try data.write(to: localPath)
            return true
        } catch {
            return false
        }
    }
    
    func extractMeta(_ html: String, property: String) -> String? {
        let patterns = [
            "<meta[^>]+property=\"\(property)\"[^>]+content=\"([^\"]+)\"",
            "<meta[^>]+content=\"([^\"]+)\"[^>]+property=\"\(property)\""
        ]
        return extractFirstMatch(html, patterns: patterns)
    }
    
    func extractMeta(_ html: String, name: String) -> String? {
        let patterns = [
            "<meta[^>]+name=\"\(name)\"[^>]+content=\"([^\"]+)\"",
            "<meta[^>]+content=\"([^\"]+)\"[^>]+name=\"\(name)\""
        ]
        return extractFirstMatch(html, patterns: patterns)
    }
    
    func extractFirstMatch(_ text: String, patterns: [String]) -> String? {
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               let range = Range(match.range(at: 1), in: text) {
                return String(text[range])
            }
        }
        return nil
    }
    
    func extractFirstMatch(_ text: String, pattern: String) -> String? {
        extractFirstMatch(text, patterns: [pattern])
    }
    
    func stripHTMLTags(_ html: String) -> String {
        var text = html
        text = text.replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "</p>", with: "\n\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "</div>", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "</li>", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "&amp;", with: "&")
        text = text.replacingOccurrences(of: "&lt;", with: "<")
        text = text.replacingOccurrences(of: "&gt;", with: ">")
        text = text.replacingOccurrences(of: "&nbsp;", with: " ")
        text = text.replacingOccurrences(of: "&quot;", with: "\"")
        text = text.replacingOccurrences(of: "&#39;", with: "'")
        text = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
