import Foundation

/// 小红书解析器 - 双模式：登录用 HTTP，未登录用 WKWebView
final class XiaohongshuParser: ContentParser, @unchecked Sendable {
    
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
            "Referer": "https://www.xiaohongshu.com/"
        ]
        return URLSession(configuration: config)
    }()
    
    func canParse(url: URL) -> Bool {
        let host = url.host?.lowercased() ?? ""
        return host.contains("xiaohongshu.com") || host.contains("xhslink.com")
    }
    
    func extractContentID(from url: URL) -> String? {
        URLNormalizer.extractContentID(url.absoluteString, platform: .xiaohongshu)
    }
    
    func normalizeURL(_ url: String) -> String {
        URLNormalizer.normalize(url, platform: .xiaohongshu)
    }
    
    func parse(url: URL) async throws -> ParsedContent {
        // 1. 先尝试 HTTP 快速获取（登录状态）
        if let content = try? await parseViaHTTP(url: url) {
            return content
        }
        
        // 2. HTTP 失败，使用 WKWebView 降级（未登录状态）
        return try await parseViaWebView(url: url)
    }
    
    // MARK: - HTTP 模式（登录状态，快速）
    
    private func parseViaHTTP(url: URL) async throws -> ParsedContent? {
        let (data, response) = try await session.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            return nil
        }
        
        guard let html = String(data: data, encoding: .utf8) else {
            return nil
        }
        
        // 检查是否有 SSR 数据（登录状态的标志）
        guard html.contains("window.__INITIAL_STATE__=") else {
            return nil
        }
        
        return extractFromSSRData(html, url: url)
    }
    
    // MARK: - WKWebView 模式（未登录状态，稳定）
    
    @MainActor
    private func parseViaWebView(url: URL) async throws -> ParsedContent {
        let loader = ZhihuWebLoader()
        guard let result = await loader.loadFullContent(from: url) else {
            throw ParserError.parseFailed(reason: "无法加载小红书页面")
        }
        
        // 解析 XIAOHONGSHU_JSON: 前缀的结果
        guard result.hasPrefix("XIAOHONGSHU_JSON:") else {
            throw ParserError.parseFailed(reason: "页面解析失败")
        }
        
        let jsonStr = String(result.dropFirst("XIAOHONGSHU_JSON:".count))
        guard let jsonData = jsonStr.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            throw ParserError.parseFailed(reason: "JSON 解析失败")
        }
        
        let title = json["title"] as? String
        let author = json["author"] as? String
        let text = json["text"] as? String
        let images = json["images"] as? [String] ?? []
        let cover = json["cover"] as? String
        
        guard title != nil || text != nil || !images.isEmpty else {
            throw ParserError.parseFailed(reason: "未获取到内容")
        }
        
        // 去重：如果封面是第一张图，从图片列表中移除
        var uniqueImages = images
        if let coverURL = cover, !coverURL.isEmpty, uniqueImages.first == coverURL {
            uniqueImages.removeFirst()
        }
        
        return ParsedContent(
            title: title,
            body: text,
            author: author,
            coverURL: cover,
            imageURLs: uniqueImages,
            platformContentID: extractContentID(from: url)
        )
    }
    
    // MARK: - SSR 数据解析（复用原有逻辑）
    
    private func extractFromSSRData(_ html: String, url: URL) -> ParsedContent? {
        guard let startRange = html.range(of: "window.__INITIAL_STATE__=") else {
            return nil
        }
        
        guard let endRange = html.range(of: "</script>", range: startRange.upperBound..<html.endIndex) else {
            return nil
        }
        
        var jsonStr = String(html[startRange.upperBound..<endRange.lowerBound])
        jsonStr = jsonStr.replacingOccurrences(of: "undefined", with: "null")
        
        guard let jsonData = jsonStr.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            return nil
        }
        
        var title: String?
        var desc: String?
        var author: String?
        var authorID: String?
        var imageURLs: [String] = []
        var coverURL: String?
        var publishDate: Date?
        
        if let noteDetailMap = json["note"] as? [String: Any],
           let noteDetail = noteDetailMap["noteDetailMap"] as? [String: Any],
           let firstNote = noteDetail.values.first as? [String: Any],
           let note = firstNote["note"] as? [String: Any] {
            
            title = note["title"] as? String
            desc = note["desc"] as? String
            
            if let user = note["user"] as? [String: Any] {
                author = user["nickname"] as? String
                authorID = user["userId"] as? String
            }
            
            if let imageList = note["imageList"] as? [[String: Any]] {
                for image in imageList {
                    if let urlDefault = image["urlDefault"] as? String {
                        imageURLs.append(urlDefault)
                    } else if let url = image["url"] as? String {
                        imageURLs.append(url)
                    }
                }
                coverURL = imageURLs.first
                // 去重：移除第一张图片，避免封面重复
                if imageURLs.count > 0 {
                    imageURLs.removeFirst()
                }
            }
            
            if let time = note["time"] as? Double {
                publishDate = Date(timeIntervalSince1970: time / 1000)
            }
        }
        
        guard title != nil || desc != nil else { return nil }
        
        return ParsedContent(
            title: title,
            body: desc,
            author: author,
            authorID: authorID,
            publishDate: publishDate,
            coverURL: coverURL,
            imageURLs: imageURLs,
            platformContentID: extractContentID(from: url)
        )
    }
    
    // MARK: - Media Download
    
    func downloadMedia(content: ParsedContent, itemID: UUID, mediaDir: URL) async throws -> [MediaAsset] {
        var assets: [MediaAsset] = []
        let fileManager = FileManager.default
        let itemDir = mediaDir.appendingPathComponent(itemID.uuidString)
        try fileManager.createDirectory(at: itemDir, withIntermediateDirectories: true)
        
        if let coverURL = content.coverURL, let url = URL(string: coverURL) {
            let fileName = "cover.jpg"
            let localPath = itemDir.appendingPathComponent(fileName)
            if await downloadFile(from: url, to: localPath) {
                let asset = MediaAsset(
                    itemID: itemID,
                    type: .cover,
                    localPath: "\(itemID.uuidString)/\(fileName)",
                    remoteURL: coverURL,
                    fileName: fileName,
                    downloadStatus: .completed
                )
                try MediaRepository().insert(asset)
                assets.append(asset)
            }
        }
        
        for (index, imageURL) in content.imageURLs.enumerated() {
            guard let url = URL(string: imageURL) else { continue }
            let fileName = "image_\(String(format: "%03d", index + 1)).jpg"
            let localPath = itemDir.appendingPathComponent(fileName)
            if await downloadFile(from: url, to: localPath) {
                let asset = MediaAsset(
                    itemID: itemID,
                    type: .image,
                    localPath: "\(itemID.uuidString)/\(fileName)",
                    remoteURL: imageURL,
                    fileName: fileName,
                    downloadStatus: .completed
                )
                try MediaRepository().insert(asset)
                assets.append(asset)
            }
        }
        
        if let videoURL = content.videoURL, let url = URL(string: videoURL) {
            let fileName = "video.mp4"
            let localPath = itemDir.appendingPathComponent(fileName)
            if await downloadFile(from: url, to: localPath) {
                let fileSize = (try? fileManager.attributesOfItem(atPath: localPath.path)[.size] as? Int64) ?? 0
                let asset = MediaAsset(
                    itemID: itemID, type: .video,
                    localPath: "\(itemID.uuidString)/\(fileName)",
                    remoteURL: videoURL, fileName: fileName,
                    fileSize: fileSize,
                    downloadStatus: .completed
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
    
    // MARK: - Private
    
    private func extractMeta(_ html: String, property: String) -> String? {
        let patterns = [
            "<meta[^>]+property=\"\(property)\"[^>]+content=\"([^\"]+)\"",
            "<meta[^>]+content=\"([^\"]+)\"[^>]+property=\"\(property)\""
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
               let range = Range(match.range(at: 1), in: html) {
                return String(html[range])
            }
        }
        return nil
    }
    
    private func downloadFile(from url: URL, to localURL: URL) async -> Bool {
        do {
            let (data, _) = try await session.data(from: url)
            try data.write(to: localURL)
            return true
        } catch {
            return false
        }
    }
}
