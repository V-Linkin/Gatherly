import Foundation
import WebKit

/// 酷安解析器 - 双模式：HTTP 快速尝试 + WebView 降级
final class CoolapkParser: ContentParser, @unchecked Sendable {
    
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
        // 1. 先尝试 HTTP 快速获取
        if let content = try? await parseViaHTTP(url: url) {
            return content
        }
        
        // 2. HTTP 失败，使用 WKWebView 降级
        return try await parseViaWebView(url: url)
    }
    
    // MARK: - HTTP 模式（快速尝试）
    
    private func parseViaHTTP(url: URL) async throws -> ParsedContent? {
        let (data, response) = try await session.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            return nil
        }
        
        guard let html = String(data: data, encoding: .utf8) else {
            return nil
        }
        
        // 检查是否有 SSR 数据
        if html.contains("window.__INITIAL_STATE__=") {
            if let content = extractFromSSRData(html, url: url) {
                return content
            }
        }
        
        // 尝试 Meta 标签提取，但只有当有高质量内容时才返回
        if let content = extractFromMetaTags(html, url: url) {
            // 检查内容质量 - 只有当有文章级别的内容时才返回
            if isHighQualityContent(content) {
                return content
            }
        }
        
        // 内容质量不足，返回 nil 以触发 WebView 降级
        return nil
    }
    
    // 检查内容质量
    private func isHighQualityContent(_ content: ParsedContent) -> Bool {
        // 检查标题质量（不能是页面标题）
        if let title = content.title {
            if title == "酷安APP" || title.contains("酷安") && title.count < 10 {
                // 可能是页面标题，不是文章标题
            } else if title.count > 5 {
                return true
            }
        }
        
        // 检查正文质量
        if let body = content.body, body.count > 50 {
            return true
        }
        
        // 检查图片数量
        if !content.imageURLs.isEmpty {
            return true
        }
        
        return false
    }
    
    // MARK: - WebView 模式（稳定降级）
    
    @MainActor
    private func parseViaWebView(url: URL) async throws -> ParsedContent {
        let loader = ZhihuWebLoader()
        guard let result = await loader.loadFullContent(from: url) else {
            throw ParserError.parseFailed(reason: "无法加载酷安页面")
        }
        
        // 解析 COOLAPK_JSON: 前缀的结果
        guard result.hasPrefix("COOLAPK_JSON:") else {
            throw ParserError.parseFailed(reason: "页面解析失败")
        }
        
        let jsonStr = String(result.dropFirst("COOLAPK_JSON:".count))
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
        
        return ParsedContent(
            title: title,
            body: text,
            author: author,
            coverURL: cover,
            imageURLs: images,
            platformContentID: extractContentID(from: url)
        )
    }
    
    // MARK: - SSR 数据解析
    
    private func extractFromSSRData(_ html: String, url: URL) -> ParsedContent? {
        // 尝试提取 window.__INITIAL_STATE__
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
        
        // 尝试从 data 字段提取
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
            title: title,
            body: desc,
            author: author,
            coverURL: coverURL,
            imageURLs: imageURLs,
            platformContentID: extractContentID(from: url)
        )
    }
    
    // MARK: - Meta 标签提取（基础信息）
    
    private func extractFromMetaTags(_ html: String, url: URL) -> ParsedContent? {
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
        
        // 尝试从 HTML 中提取作者
        let htmlAuthor = extractHTMLAuthor(html)
        
        // 只有当有实质性内容时才返回
        if title != nil || desc != nil || cover != nil || author != nil || htmlAuthor != nil {
            return ParsedContent(
                title: title,
                body: desc,
                author: author ?? htmlAuthor,
                coverURL: cover,
                platformContentID: extractContentID(from: url)
            )
        }
        
        return nil
    }
    
    private func extractHTMLAuthor(_ html: String) -> String? {
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
    
    // MARK: - 媒体下载（复用现有逻辑）
    
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
    
    private func downloadFile(from url: URL, to localURL: URL) async -> Bool {
        do {
            let (data, _) = try await session.data(from: url)
            try data.write(to: localURL)
            return true
        } catch { return false }
    }
}
