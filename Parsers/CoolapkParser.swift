import Foundation
import WebKit

/// 酷安解析器 - 优先使用镜像站 coolapk1s.com 绕过反爬
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
        // 1. 优先尝试镜像站 coolapk1s.com（无反爬，SSR 数据完整）
        if let content = try? await parseViaMirror(url: url) {
            return content
        }
        
        // 2. 镜像站失败，尝试原站 HTTP
        if let content = try? await parseViaHTTP(url: url) {
            return content
        }
        
        // 3. 都失败，使用 WKWebView 降级
        return try await parseViaWebView(url: url)
    }
    
    // MARK: - 镜像站模式（优先）
    
    private func parseViaMirror(url: URL) async throws -> ParsedContent? {
        // 将 coolapk.com 转换为 coolapk1s.com
        guard let mirrorURL = convertToMirrorURL(url) else { return nil }
        
        
        let (data, response) = try await session.data(from: mirrorURL)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            return nil
        }
        
        guard let html = String(data: data, encoding: .utf8) else { return nil }
        
        // 提取 __NEXT_DATA__ JSON
        return extractFromNextData(html, url: url)
    }
    
    private func convertToMirrorURL(_ url: URL) -> URL? {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.host = "www.coolapk1s.com"
        return components?.url
    }
    
    private func extractFromNextData(_ html: String, url: URL) -> ParsedContent? {
        // 提取 <script id="__NEXT_DATA__" type="application/json">...</script>
        guard let startRange = html.range(of: "<script id=\"__NEXT_DATA__\" type=\"application/json\">"),
              let endRange = html.range(of: "</script>", range: startRange.upperBound..<html.endIndex) else {
            return nil
        }
        
        let jsonStr = String(html[startRange.upperBound..<endRange.lowerBound])
        guard let jsonData = jsonStr.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            return nil
        }
        
        guard let pageProps = json["props"] as? [String: Any],
              let feedProps = pageProps["pageProps"] as? [String: Any],
              let feed = feedProps["feed"] as? [String: Any] else {
            return nil
        }
        
        // 提取字段
        let title = feed["title"] as? String
        let username = feed["username"] as? String
        let message = feed["message"] as? String
        let picArr = feed["picArr"] as? [String] ?? []
        let messageCover = feed["message_cover"] as? String
        
        // 封面：优先用 message_cover，否则用第一张图片
        let coverURL = messageCover?.isEmpty == false ? messageCover : picArr.first
        
        // 图片URL需要转换为镜像站的代理URL（避免酷安防盗链）
        var imageURLs = picArr.compactMap { convertToProxyURL($0) }
        
        // 首图去重：封面来自第一张图片时，从正文图片列表中移除
        if let coverProxy = convertToProxyURL(coverURL),
           imageURLs.first == coverProxy {
            imageURLs.removeFirst()
        }
        
        // 清理正文：移除HTML标签、酷安表情标签
        var cleanBody = message ?? ""
        cleanBody = cleanBody.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        cleanBody = cleanBody.replacingOccurrences(of: "\\[[^\\]]+\\]", with: "", options: .regularExpression)
        cleanBody = cleanBody.trimmingCharacters(in: .whitespacesAndNewlines)

        // 如果feed为null（内容不存在），返回nil
        guard title != nil || cleanBody != nil else {
            return nil
        }
        
        
        return ParsedContent(
            title: title,
            body: cleanBody,
            author: username,
            coverURL: convertToProxyURL(coverURL),
            imageURLs: imageURLs,
            platformContentID: extractContentID(from: url)
        )
    }
    
    /// 将酷安图片URL转换为镜像站代理URL，绕过防盗链
    private func convertToProxyURL(_ urlString: String?) -> String? {
        guard let urlString = urlString, !urlString.isEmpty else { return nil }
        // 镜像站代理：https://image.coolapk1s.com/proxy?url={encoded_url}
        let encoded = urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? urlString
        return "https://image.coolapk1s.com/proxy?url=\(encoded)"
    }
    
    // MARK: - HTTP 模式（原站，兜底）
    
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
        
        // 尝试 Meta 标签提取
        if let content = extractFromMetaTags(html, url: url) {
            if isHighQualityContent(content) {
                return content
            }
        }
        
        return nil
    }
    
    private func isHighQualityContent(_ content: ParsedContent) -> Bool {
        if let title = content.title {
            if title == "酷安APP" || (title.contains("酷安") && title.count < 10) {
                // 可能是页面标题，不是文章标题
            } else if title.count > 5 {
                return true
            }
        }
        
        if let body = content.body, body.count > 50 {
            return true
        }
        
        if !content.imageURLs.isEmpty {
            return true
        }
        
        return false
    }
    
    // MARK: - WebView 模式（最终降级）
    
    @MainActor
    private func parseViaWebView(url: URL) async throws -> ParsedContent {
        let loader = ZhihuWebLoader()
        guard let result = await loader.loadFullContent(from: url) else {
            throw ParserError.parseFailed(reason: "无法加载酷安页面（WebView 返回 nil）")
        }
        
        guard result.hasPrefix("COOLAPK_JSON:") else {
            throw ParserError.parseFailed(reason: "页面解析失败（缺少 COOLAPK_JSON 前缀）")
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
        
        return ParsedContent(
            title: title,
            body: text,
            author: author,
            coverURL: cover,
            imageURLs: images,
            platformContentID: extractContentID(from: url)
        )
    }
    
    // MARK: - SSR 数据解析（原站）
    
    private func extractFromSSRData(_ html: String, url: URL) -> ParsedContent? {
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
            author = data["username"] as? String ?? data["author"] as? String
            if let pics = data["picArr"] as? [String] {
                imageURLs = pics
            }
            coverURL = data["message_cover"] as? String
        }
        
        if title != nil || desc != nil {
            if coverURL == nil && !imageURLs.isEmpty {
                coverURL = imageURLs.first
            }
            return ParsedContent(
                title: title,
                body: desc,
                author: author,
                coverURL: coverURL,
                imageURLs: imageURLs,
                platformContentID: extractContentID(from: url)
            )
        }
        return nil
    }
    
    // MARK: - Meta 标签提取
    
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
        
        let htmlAuthor = extractHTMLAuthor(html)
        
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
    
    // MARK: - 媒体下载
    
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
            let ext = url.pathExtension.isEmpty ? "jpg" : url.pathExtension
            let fileName = "image_\(String(format: "%03d", index + 1)).\(ext)"
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
