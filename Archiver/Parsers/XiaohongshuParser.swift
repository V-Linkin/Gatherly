import Foundation

/// 小红书解析器
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
        let (data, response) = try await session.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw ParserError.parseFailed(reason: "HTTP 请求失败")
        }
        
        guard let html = String(data: data, encoding: .utf8) else {
            throw ParserError.parseFailed(reason: "无法解码页面内容")
        }
        
        if let content = extractFromSSRData(html, url: url) {
            return content
        }
        
        return extractFromMetaTags(html, url: url)
    }
    
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
        
        // 尝试下载视频
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
                // 视频下载失败，记录为跳过
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
    
    private func extractFromMetaTags(_ html: String, url: URL) -> ParsedContent {
        let title = extractMeta(html, property: "og:title")
        let desc = extractMeta(html, property: "og:description")
        let cover = extractMeta(html, property: "og:image")
        
        return ParsedContent(
            title: title,
            body: desc,
            coverURL: cover,
            platformContentID: extractContentID(from: url)
        )
    }
    
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
