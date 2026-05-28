import Foundation

/// 酷安解析器
final class CoolapkParser: ContentParser {
    
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
            "Referer": "https://www.coolapk.com/"
        ]
        return URLSession(configuration: config)
    }()
    
    func canParse(url: URL) -> Bool {
        let host = url.host?.lowercased() ?? ""
        return host.contains("coolapk.com") || host.contains("coolapk1s.com")
    }
    
    func extractContentID(from url: URL) -> String? {
        URLNormalizer.extractContentID(url.absoluteString, platform: .coolapk)
    }
    
    func normalizeURL(_ url: String) -> String {
        URLNormalizer.normalize(url, platform: .coolapk)
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
                    itemID: itemID, type: .cover,
                    localPath: "\(itemID.uuidString)/\(fileName)",
                    remoteURL: coverURL, fileName: fileName,
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
                    itemID: itemID, type: .image,
                    localPath: "\(itemID.uuidString)/\(fileName)",
                    remoteURL: imageURL, fileName: fileName,
                    downloadStatus: .completed
                )
                try MediaRepository().insert(asset)
                assets.append(asset)
            }
        }
        
        return assets
    }
    
    // MARK: - Private
    
    private func extractFromSSRData(_ html: String, url: URL) -> ParsedContent? {
        // 酷安可能有 JSON-LD
        if let jsonldRange = html.range(of: "<script type=\"application/ld+json\">"),
           let endRange = html.range(of: "</script>", range: jsonldRange.upperBound..<html.endIndex) {
            let jsonStr = String(html[jsonldRange.upperBound..<endRange.lowerBound])
            if let jsonData = jsonStr.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                let title = json["headline"] as? String ?? json["name"] as? String
                let desc = json["description"] as? String
                var author: String?
                if let authorObj = json["author"] as? [String: Any] {
                    author = authorObj["name"] as? String
                } else if let authorStr = json["author"] as? String {
                    author = authorStr
                }
                var imageURLs: [String] = []
                if let images = json["image"] as? [String] {
                    imageURLs = images
                } else if let image = json["image"] as? String {
                    imageURLs = [image]
                }
                if title != nil || desc != nil {
                    return ParsedContent(
                        title: title, body: desc, author: author,
                        coverURL: imageURLs.first, imageURLs: imageURLs,
                        platformContentID: extractContentID(from: url)
                    )
                }
            }
        }
        
        // 尝试酷安特有的 SSR 数据
        if let startRange = html.range(of: "window.__INITIAL_STATE__=") {
            if let endRange = html.range(of: "</script>", range: startRange.upperBound..<html.endIndex) {
                var jsonStr = String(html[startRange.upperBound..<endRange.lowerBound])
                jsonStr = jsonStr.replacingOccurrences(of: "undefined", with: "null")
                if let jsonData = jsonStr.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                    return parseCoolapkJSON(json, url: url)
                }
            }
        }
        
        return nil
    }
    
    private func parseCoolapkJSON(_ json: [String: Any], url: URL) -> ParsedContent? {
        var title: String?
        var desc: String?
        var author: String?
        var imageURLs: [String] = []
        var coverURL: String?
        
        if let data = json["data"] as? [String: Any] {
            title = data["title"] as? String
            desc = data["description"] as? String ?? data["content"] as? String
            if let user = data["user"] as? [String: Any] {
                author = user["username"] as? String ?? user["nickname"] as? String
            }
            if let pics = data["pics"] as? [String] {
                imageURLs = pics
            }
            coverURL = imageURLs.first ?? data["pic"] as? String
        }
        
        guard title != nil || desc != nil else { return nil }
        
        return ParsedContent(
            title: title, body: desc, author: author,
            coverURL: coverURL, imageURLs: imageURLs,
            platformContentID: extractContentID(from: url)
        )
    }
    
    private func extractFromMetaTags(_ html: String, url: URL) -> ParsedContent {
        let title = extractMeta(html, property: "og:title")
            ?? extractMeta(html, name: "title")
            ?? extractMeta(html, property: "twitter:title")
        let desc = extractMeta(html, property: "og:description")
            ?? extractMeta(html, name: "description")
            ?? extractMeta(html, name: "twitter:description")
        let cover = extractMeta(html, property: "og:image")
            ?? extractMeta(html, name: "twitter:image")
        let author = extractMeta(html, name: "author")
            ?? extractMeta(html, name: "twitter:creator")
            ?? extractMeta(html, property: "og:article:author")
        
        // 尝试从 HTML 中提取作者（酷安的 feed 页面结构）
        let htmlAuthor = extractHTMLAuthor(html)
        
        return ParsedContent(
            title: title,
            body: desc,
            author: author ?? htmlAuthor,
            coverURL: cover,
            platformContentID: extractContentID(from: url)
        )
    }
    
    private func extractHTMLAuthor(_ html: String) -> String? {
        // 酷安 feed 页面中作者名通常在 <span class="feed-reply-username"> 或类似结构中
        let patterns = [
            "class=\"feed-reply-username\"[^>]*>([^<]+)<",
            "class=\"username\"[^>]*>([^<]+)<",
            "class=\"author\"[^>]*>([^<]+)<",
            "\"username\":\"([^\"]+)\"",
            "\"nickname\":\"([^\"]+)\""
        ]
        for pattern in patterns {
            if let result = match(html, pattern: pattern) {
                return result.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return nil
    }
    
    private func extractMeta(_ html: String, property: String) -> String? {
        let pattern = "<meta[^>]+property=\"\(property)\"[^>]+content=\"([^\"]+)\""
        return match(html, pattern: pattern)
    }
    
    private func extractMeta(_ html: String, name: String) -> String? {
        let pattern = "<meta[^>]+name=\"\(name)\"[^>]+content=\"([^\"]+)\""
        return match(html, pattern: pattern)
    }
    
    private func match(_ text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let m = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let r = Range(m.range(at: 1), in: text) else { return nil }
        return String(text[r])
    }
    
    private func downloadFile(from url: URL, to localURL: URL) async -> Bool {
        do {
            let (data, _) = try await session.data(from: url)
            try data.write(to: localURL)
            return true
        } catch { return false }
    }
}
