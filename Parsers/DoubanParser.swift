import Foundation
import WebKit

/// 豆瓣请求频率限制器，防止触发风控
private actor DoubanRateLimiter {
    private var lastRequestTime: Date = .distantPast
    private let minimumInterval: TimeInterval = 2.0  // 最少间隔 2 秒

    /// 返回需要等待的秒数，并记录本次请求时间
    func timeToWait() -> TimeInterval {
        let now = Date()
        let elapsed = now.timeIntervalSince(lastRequestTime)
        let wait = max(0, minimumInterval - elapsed)
        lastRequestTime = now.addingTimeInterval(wait)
        return wait
    }
}

final class DoubanParser: ContentParser, @unchecked Sendable {

    /// 请求间隔控制：避免短时间内大量请求触发豆瓣风控
    private static let rateLimiter = DoubanRateLimiter()

    /// 确保请求间隔，避免触发风控
    private static func respectRateLimit() async {
        let waitTime = await rateLimiter.timeToWait()
        if waitTime > 0 {
            try? await Task.sleep(for: .seconds(waitTime))
        }
    }

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            "Accept-Language": "zh-CN,zh;q=0.9,en;q=0.8"
        ]
        return URLSession(configuration: config)
    }()

    func canParse(url: URL) -> Bool {
        let host = url.host?.lowercased() ?? ""
        return host == "douban.com" || host == "www.douban.com"
            || host.hasSuffix(".douban.com")
    }

    func extractContentID(from url: URL) -> String? {
        URLNormalizer.extractContentID(url.absoluteString, platform: .douban)
    }

    func normalizeURL(_ url: String) -> String {
        URLNormalizer.normalize(url, platform: .douban)
    }

    func parse(url: URL) async throws -> ParsedContent {
        if isSubjectURL(url) {
            return try await parseSubjectPage(url)
        }
        if isReviewURL(url) {
            return try await parseReviewPage(url)
        }
        return try await parseGenericPage(url)
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

        return assets
    }

    // MARK: - Subject Page (书/影/音)

    private func parseSubjectPage(_ url: URL) async throws -> ParsedContent {
        // 请求间隔控制
        await Self.respectRateLimit()
        
        let mobileURL = toMobileURL(url)
        let (data, response) = try await session.data(from: mobileURL)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw ParserError.parseFailed(reason: "HTTP 请求失败")
        }
        guard let html = String(data: data, encoding: .utf8) else {
            throw ParserError.parseFailed(reason: "无法解码页面内容")
        }

        let subjectID = extractSubjectID(from: url)
        let title = extractMeta(html, property: "og:title") ?? extractPageTitle(html)
        let cover = extractMeta(html, property: "og:image")
        let author = extractDirector(html) ?? extractAuthor(html)

        // 评分
        var rating: String?
        if let ratingValue = extractMetaItemprop(html, name: "ratingValue") {
            rating = "豆瓣评分: \(ratingValue)"
        }

        // 完整简介（从 subject-intro 区域提取）
        let fullIntro = extractSubjectIntro(html)
        let desc = extractMeta(html, property: "og:description") ?? extractMeta(html, name: "description")

        var body = ""
        if let intro = fullIntro, !intro.isEmpty {
            body = intro
        } else if let desc {
            body = desc
        }
        if let ratingStr = rating {
            if !body.isEmpty { body = "\n\n\(body)" }
            body = "\(ratingStr)\(body)"
        }

        return ParsedContent(
            title: title,
            body: body.isEmpty ? nil : body,
            author: author,
            coverURL: cover,
            platformContentID: subjectID,
            rawMetadata: ["type": "subject"]
        )
    }

    // MARK: - Review Page (影评/书评)

    private func parseReviewPage(_ url: URL) async throws -> ParsedContent {
        let desktopUA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
        let reviewID = extractReviewID(from: url)
        
        // 请求间隔控制
        await Self.respectRateLimit()
        
        // 第一步：用桌面端 UA 获取页面 HTML
        var htmlRequest = URLRequest(url: url)
        htmlRequest.setValue(desktopUA, forHTTPHeaderField: "User-Agent")
        htmlRequest.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        htmlRequest.setValue("zh-CN,zh;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        htmlRequest.setValue("https://movie.douban.com/", forHTTPHeaderField: "Referer")
        
        let (data, response) = try await URLSession.shared.data(for: htmlRequest)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw ParserError.parseFailed(reason: "HTTP 请求失败")
        }
        guard let html = String(data: data, encoding: .utf8) else {
            throw ParserError.parseFailed(reason: "无法解码页面内容")
        }
        
        // 第二步：从 HTML 直接解析所有字段
        let metaTitle = extractMeta(html, property: "og:title") ?? extractPageTitle(html)
        let metaDesc = extractMeta(html, property: "og:description") ?? extractMeta(html, name: "description")
        let metaCover = extractMeta(html, property: "og:image")
        let metaAuthor = extractMeta(html, name: "author")
        
        // 从 HTML 正文区域提取内容
        let htmlBody = extractReviewBodyFromHTML(html)
        
        // 提取作者（从影评页面的特定结构）
        let htmlAuthor = extractReviewAuthorFromHTML(html) ?? metaAuthor
        
        // 组装标题
        var title = metaTitle
        if title == "豆瓣" || (title != nil && title!.count < 3) {
            // og:title 太短，尝试从页面 h1 提取
            if let h1 = extractFirst(html, pattern: #"<h1[^>]*>([^<]+)</h1>"#) {
                title = h1.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        
        // 组装正文：优先 HTML 解析，兜底 meta description
        var body = htmlBody
        if body == nil || body!.isEmpty {
            body = metaDesc
        }
        
        // 组装作者
        let author = htmlAuthor
        
        // 组装封面：优先 meta，兜底从 subject 页面获取
        var cover = metaCover
        let needSubjectCover = (cover == nil) || (cover?.contains("thing_review") == true)
        if needSubjectCover, let subjectID = extractSubjectID(from: url) {
            await Self.respectRateLimit()
            let subjectURL = URL(string: "https://movie.douban.com/subject/\(subjectID)/") ?? url
            var subjectRequest = URLRequest(url: subjectURL)
            subjectRequest.setValue(desktopUA, forHTTPHeaderField: "User-Agent")
            if let (subjectData, _) = try? await URLSession.shared.data(for: subjectRequest),
               let subjectHTML = String(data: subjectData, encoding: .utf8) {
                if let poster = extractMeta(subjectHTML, property: "og:image") {
                    cover = poster
                }
            }
        }
        
        // 第三步：尝试用 WKWebView 补充内容（如果 HTML 解析不够完整）
        let webResult = await loadReviewViaWebView(url.absoluteString)
        
        // 合并结果：webview 优先（如果成功获取到内容）
        let finalTitle = webResult.title ?? title
        let finalBody = (webResult.text != nil && webResult.text!.count > (body?.count ?? 0)) ? webResult.text : body
        let finalAuthor = webResult.author ?? author
        let finalCover = webResult.cover ?? cover
        
        return ParsedContent(
            title: finalTitle,
            body: finalBody,
            author: finalAuthor,
            coverURL: finalCover,
            platformContentID: reviewID,
            rawMetadata: ["type": "review", "source": "html+webview"]
        )
    }



    // MARK: - Generic Page

    private func parseGenericPage(_ url: URL) async throws -> ParsedContent {
        let mobileURL = toMobileURL(url)
        let (data, response) = try await session.data(from: mobileURL)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw ParserError.parseFailed(reason: "HTTP 请求失败")
        }
        guard let html = String(data: data, encoding: .utf8) else {
            throw ParserError.parseFailed(reason: "无法解码页面内容")
        }

        let title = extractMeta(html, property: "og:title") ?? extractPageTitle(html)
        let desc = extractMeta(html, property: "og:description") ?? extractMeta(html, name: "description")
        let cover = extractMeta(html, property: "og:image")
        let subjectID = extractSubjectID(from: url)

        return ParsedContent(
            title: title,
            body: desc,
            author: extractMeta(html, name: "author"),
            coverURL: cover,
            platformContentID: subjectID,
            rawMetadata: ["type": "subject", "source": "meta"]
        )
    }

    // MARK: - WKWebView Loader



    /// WKWebView 返回的结构化数据
    private struct WebContentResult {
        var title: String?
        var text: String?
        var author: String?
        var cover: String?
    }

    /// 通过 WKWebView 获取影评内容，返回结构化结果
    private func loadReviewViaWebView(_ urlString: String) async -> WebContentResult {
        guard let url = URL(string: urlString) else { return WebContentResult() }
        let result = await ZhihuWebLoader().loadFullContent(from: url)
        guard let result else { return WebContentResult() }

        if result.hasPrefix("DOUBAN_JSON:") {
            let jsonStr = String(result.dropFirst(12))
            if let jsonData = jsonStr.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                let title = json["title"] as? String
                let text = json["text"] as? String
                let author = json["author"] as? String
                let cover = json["cover"] as? String
                return WebContentResult(title: title, text: text, author: author, cover: cover)
            }
        } else if result.hasPrefix("DOUBAN:") {
            let text = String(result.dropFirst(7)).trimmingCharacters(in: .whitespacesAndNewlines)
            return WebContentResult(text: text)
        } else if result.hasPrefix("TEXT:") {
            let text = String(result.dropFirst(5)).trimmingCharacters(in: .whitespacesAndNewlines)
                return WebContentResult(text: text)
        } else if result.hasPrefix("HTML:") {
            let htmlContent = String(result.dropFirst(5))
            return WebContentResult(text: cleanHTML(htmlContent))
        } else if result.hasPrefix("ANSWER:") || result.hasPrefix("ARTICLE:") {
            let parts = result.components(separatedBy: ":")
            if parts.count >= 3 {
                let htmlContent = parts[2...].joined(separator: ":")
                return WebContentResult(text: cleanHTML(htmlContent))
            }
        }
        return WebContentResult(text: cleanHTML(result))
    }

    // MARK: - HTML Review Extraction
    
    /// 从 HTML 中提取影评正文
    private func extractReviewBodyFromHTML(_ html: String) -> String? {
        // 尝试多种选择器匹配影评正文区域
        let patterns = [
            #"<div\s+id="link-report"[^>]*>(.*?)</div>"#,
            #"<div\s+class="review-content[^"]*"[^>]*>(.*?)</div>"#,
            #"<div\s+class="main-review[^"]*"[^>]*>(.*?)</div>"#,
            #"<div\s+class="review-body[^"]*"[^>]*>(.*?)</div>"#,
            #"<span\s+class="short"[^>]*>(.*?)</span>"#,
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .dotMatchesLineSeparators),
               let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
               let range = Range(match.range(at: 1), in: html) {
                let content = String(html[range])
                let text = cleanHTML(content)
                if text.count > 30 {
                    return text
                }
            }
        }
        
        // 兜底：从所有 <p> 标签中提取长文本
        let pPattern = #"<p[^>]*>(.*?)</p>"#
        if let regex = try? NSRegularExpression(pattern: pPattern, options: .dotMatchesLineSeparators) {
            let matches = regex.matches(in: html, range: NSRange(html.startIndex..., in: html))
            var paragraphs: [String] = []
            for match in matches {
                if let range = Range(match.range(at: 1), in: html) {
                    let text = cleanHTML(String(html[range]))
                    if text.count > 10 {
                        paragraphs.append(text)
                    }
                }
            }
            if !paragraphs.isEmpty {
                return paragraphs.joined(separator: "\n\n")
            }
        }
        
        return nil
    }
    
    /// 从 HTML 中提取影评作者
    private func extractReviewAuthorFromHTML(_ html: String) -> String? {
        // 豆瓣影评作者通常在这些位置
        let patterns = [
            #"<a[^>]*class="name"[^>]*>([^<]+)</a>"#,
            #"<span[^>]*class="name"[^>]*>\s*<a[^>]*>([^<]+)</a>"#,
            #"<a[^>]*href="https?://www\.douban\.com/people/[^"]*"[^>]*>([^<]+)</a>"#,
            #"<span[^>]*class="author"[^>]*>([^<]+)</span>"#,
        ]
        
        for pattern in patterns {
            if let author = extractFirst(html, pattern: pattern) {
                let trimmed = author.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty && trimmed.count < 30 && trimmed != "豆瓣" {
                    return trimmed
                }
            }
        }
        return nil
    }

    // MARK: - Content Extraction

    private func extractSubjectIntro(_ html: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"<section class="subject-intro">(.*?)</section>"#, options: .dotMatchesLineSeparators),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let range = Range(match.range(at: 1), in: html) else {
            return nil
        }
        let introHTML = String(html[range])
        var text = cleanHTML(introHTML)
        // 去掉开头的标题文字
        let prefixes = ["剧情简介", "内容简介", "简介", "作品简介", "图书简介"]
        for prefix in prefixes {
            if text.hasPrefix(prefix) {
                text = String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
            }
        }
        return text.isEmpty ? nil : text
    }

    private func extractDirector(_ html: String) -> String? {
        let patterns = [
            #"<span class="pl">导演</span>.*?<a[^>]*>([^<]+)</a>"#,
            #"导演.*?<a[^>]*>([^<]+)</a>"#
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .dotMatchesLineSeparators),
               let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
               let range = Range(match.range(at: 1), in: html) {
                return String(html[range]).trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    private func extractAuthor(_ html: String) -> String? {
        let patterns = [
            #"<span class="pl">作者</span>.*?<a[^>]*>([^<]+)</a>"#,
            #"作者.*?<a[^>]*>([^<]+)</a>"#
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .dotMatchesLineSeparators),
               let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
               let range = Range(match.range(at: 1), in: html) {
                return String(html[range]).trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    // MARK: - URL Conversion

    private func toMobileURL(_ url: URL) -> URL {
        var urlString = url.absoluteString
        if urlString.contains("://movie.douban.com/") {
            urlString = urlString.replacingOccurrences(of: "://movie.douban.com/", with: "://m.douban.com/movie/")
        } else if urlString.contains("://book.douban.com/") {
            urlString = urlString.replacingOccurrences(of: "://book.douban.com/", with: "://m.douban.com/book/")
        } else if urlString.contains("://music.douban.com/") {
            urlString = urlString.replacingOccurrences(of: "://music.douban.com/", with: "://m.douban.com/music/")
        } else if urlString.contains("://www.douban.com/") {
            urlString = urlString.replacingOccurrences(of: "://www.douban.com/", with: "://m.douban.com/")
        } else if urlString.contains("://douban.com/") {
            urlString = urlString.replacingOccurrences(of: "://douban.com/", with: "://m.douban.com/")
        }
        return URL(string: urlString) ?? url
    }

    // MARK: - URL Helpers

    private func isSubjectURL(_ url: URL) -> Bool { url.path.contains("/subject/") }
    private func isReviewURL(_ url: URL) -> Bool { url.path.contains("/review/") }

    private func extractSubjectID(from url: URL) -> String? {
        URLNormalizer.extractDoubanID(url.absoluteString)
    }

    private func extractReviewID(from url: URL) -> String? {
        let patterns = ["douban\\.com/[^/]+/review/(\\d+)"]
        return URLNormalizer.extractFirstMatch(url.absoluteString, patterns: patterns)
    }

    // MARK: - JSON Extraction

    private func extractInitialData(from html: String) -> String? {
        if let startRange = html.range(of: "window.__DATA__ = ") {
            var braceCount = 0
            var foundOpening = false
            var endIndex = startRange.upperBound
            for char in html[startRange.upperBound...] {
                if char == "{" { braceCount += 1; foundOpening = true }
                else if char == "}" { braceCount -= 1 }
                if foundOpening && braceCount == 0 { break }
                endIndex = html.index(after: endIndex)
                if endIndex >= html.endIndex { break }
            }
            if foundOpening && braceCount == 0 {
                return String(html[startRange.upperBound..<endIndex])
            }
        }
        return nil
    }

    // MARK: - HTML Helpers

    /// 清理 HTML 标签并保留格式
    private func cleanHTML(_ html: String) -> String {
        var text = html
        // 块级元素转换为换行
        text = text.replacingOccurrences(of: #"<br\s*/?>"#, with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "</p>", with: "\n\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "</div>", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: #"</h[1-6]>"#, with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "</li>", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "</tr>", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: #"<li[^>]*>"#, with: "• ", options: .regularExpression)
        text = text.replacingOccurrences(of: #"<p[^>]*>"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: #"<h[1-6][^>]*>"#, with: "\n", options: .regularExpression)
        // 去除剩余 HTML 标签
        text = text.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        // 解码 HTML 实体
        text = text.replacingOccurrences(of: "&amp;", with: "&")
        text = text.replacingOccurrences(of: "&lt;", with: "<")
        text = text.replacingOccurrences(of: "&gt;", with: ">")
        text = text.replacingOccurrences(of: "&nbsp;", with: " ")
        text = text.replacingOccurrences(of: "&quot;", with: "\"")
        text = text.replacingOccurrences(of: "&#39;", with: "'")
        text = text.replacingOccurrences(of: "&hellip;", with: "…")
        text = text.replacingOccurrences(of: "&mdash;", with: "—")
        text = text.replacingOccurrences(of: "&ndash;", with: "–")
        // 清理空白
        text = text.replacingOccurrences(of: #"\n[ \t]+"#, with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: #"[ \t]+\n"#, with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: #"[ \t]{2,}"#, with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Meta Helpers

    private func extractMeta(_ html: String, property: String) -> String? {
        let pattern = "property=\"\(property)\"\\s+content=\"([^\"]*)\""
        return extractFirst(html, pattern: pattern)
    }

    private func extractMeta(_ html: String, name: String) -> String? {
        let pattern = "name=\"\(name)\"\\s+content=\"([^\"]*)\""
        return extractFirst(html, pattern: pattern)
    }

    private func extractMetaItemprop(_ html: String, name: String) -> String? {
        let pattern = "itemprop=\"\(name)\"\\s+content=\"([^\"]*)\""
        return extractFirst(html, pattern: pattern)
    }

    private func extractPageTitle(_ html: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: "<title>([^<]*)</title>", options: .caseInsensitive),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let range = Range(match.range(at: 1), in: html) else { return nil }
        return String(html[range]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func extractFirst(_ text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }

    private func downloadFile(from url: URL, to localURL: URL) async -> Bool {
        do {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
            request.setValue("https://movie.douban.com/", forHTTPHeaderField: "Referer")
            let (data, _) = try await URLSession.shared.data(for: request)
            guard data.count > 100 else { return false }
            try data.write(to: localURL)
            return true
        } catch { return false }
    }
}
