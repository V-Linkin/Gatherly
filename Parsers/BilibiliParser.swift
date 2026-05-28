import Foundation

final class BilibiliParser: ContentParser, @unchecked Sendable {
    
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
            "Referer": "https://www.bilibili.com/"
        ]
        return URLSession(configuration: config)
    }()
    
    func canParse(url: URL) -> Bool {
        let host = url.host?.lowercased() ?? ""
        return host.contains("bilibili.com") || host.contains("b23.tv")
    }
    
    func extractContentID(from url: URL) -> String? {
        URLNormalizer.extractContentID(url.absoluteString, platform: .bilibili)
    }
    
    func normalizeURL(_ url: String) -> String {
        URLNormalizer.normalize(url, platform: .bilibili)
    }
    
    func parse(url: URL) async throws -> ParsedContent {
        let resolvedURL = try await resolveShortURL(url)
        
        let (data, response) = try await session.data(from: resolvedURL)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw ParserError.parseFailed(reason: "HTTP 请求失败")
        }
        
        guard let html = String(data: data, encoding: .utf8) else {
            throw ParserError.parseFailed(reason: "无法解码页面内容")
        }
        
        if let content = extractFromSSRData(html, url: resolvedURL) {
            return content
        }
        
        return extractFromMetaTags(html, url: resolvedURL)
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
        
        for (index, imageURL) in content.imageURLs.prefix(9).enumerated() {
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
        
        return assets
    }
    
    private func resolveShortURL(_ url: URL) async throws -> URL {
        let host = url.host?.lowercased() ?? ""
        guard host.contains("b23.tv") else { return url }
        
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        
        let (_, response) = try await session.data(for: request)
        if let httpResponse = response as? HTTPURLResponse,
           let location = httpResponse.value(forHTTPHeaderField: "Location"),
           let resolved = URL(string: location) {
            return resolved
        }
        return url
    }
    
    private func extractFromSSRData(_ html: String, url: URL) -> ParsedContent? {
        guard let startRange = html.range(of: "window.__INITIAL_STATE__=") else {
            return nil
        }
        
        if let endRange = html.range(of: ";(function()", range: startRange.upperBound..<html.endIndex) {
            let jsonStr = String(html[startRange.upperBound..<endRange.lowerBound])
            return parseBilibiliJSON(jsonStr, url: url)
        }
        
        if let endRange2 = html.range(of: "</script>", range: startRange.upperBound..<html.endIndex) {
            let jsonStr = String(html[startRange.upperBound..<endRange2.lowerBound])
            return parseBilibiliJSON(jsonStr, url: url)
        }
        
        return nil
    }
    
    private func parseBilibiliJSON(_ jsonStr: String, url: URL) -> ParsedContent? {
        guard let jsonData = jsonStr.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            return nil
        }
        
        var title: String?
        var desc: String?
        var author: String?
        var coverURL: String?
        var publishDate: Date?
        var imageURLs: [String] = []
        
        if let videoData = json["videoData"] as? [String: Any] {
            title = videoData["title"] as? String
            desc = videoData["desc"] as? String
            coverURL = videoData["pic"] as? String
            
            if let owner = videoData["owner"] as? [String: Any] {
                author = owner["name"] as? String
            }
            
            if let pubdate = videoData["pubdate"] as? Double {
                publishDate = Date(timeIntervalSince1970: pubdate)
            }
        }
        
        if let readInfo = json["readInfo"] as? [String: Any] {
            title = readInfo["title"] as? String
            desc = readInfo["summary"] as? String
            if let imageURLList = readInfo["imageURLs"] as? [String] {
                imageURLs = imageURLList
            }
        }
        
        guard title != nil || desc != nil else { return nil }
        
        // 去除 HTML 标签
        let cleanDesc = desc.map { Self.stripHTML($0) }
        
        return ParsedContent(
            title: title,
            body: cleanDesc,
            author: author,
            publishDate: publishDate,
            coverURL: coverURL,
            imageURLs: imageURLs,
            videoURL: nil,
            platformContentID: extractContentID(from: url)
        )
    }
    
    private func extractFromMetaTags(_ html: String, url: URL) -> ParsedContent {
        let title = extractMeta(html, property: "og:title")
            ?? extractMeta(html, name: "title")
        let desc = extractMeta(html, property: "og:description")
            ?? extractMeta(html, name: "description")
        let cover = extractMeta(html, property: "og:image")
        
        let cleanDesc = desc.map { Self.stripHTML($0) }
        
        return ParsedContent(
            title: title,
            body: cleanDesc,
            coverURL: cover,
            platformContentID: extractContentID(from: url)
        )
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
    
    /// 去除 HTML 标签，保留纯文本
    static func stripHTML(_ html: String) -> String {
        var result = html
        result = result.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: "&amp;", with: "&")
        result = result.replacingOccurrences(of: "&lt;", with: "<")
        result = result.replacingOccurrences(of: "&gt;", with: ">")
        result = result.replacingOccurrences(of: "&nbsp;", with: " ")
        result = result.replacingOccurrences(of: "&quot;", with: "\"")
        result = result.replacingOccurrences(of: "&#39;", with: "'")
        result = result.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
