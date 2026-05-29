import Foundation
import WebKit

final class DoubanParser: ContentParser, @unchecked Sendable {

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
        // 先从桌面端获取 meta 信息（包含 og 标签）
        let (data, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw ParserError.parseFailed(reason: "HTTP 请求失败")
        }
        guard let html = String(data: data, encoding: .utf8) else {
            throw ParserError.parseFailed(reason: "无法解码页面内容")
        }

        // meta 标签获取基本信息
        let metaTitle = extractMeta(html, property: "og:title") ?? extractPageTitle(html)
        let metaDesc = extractMeta(html, property: "og:description") ?? extractMeta(html, name: "description")
        let metaCover = extractMeta(html, property: "og:image")
        let reviewID = extractReviewID(from: url)

        // 用 WKWebView 加载桌面端 URL（会自动完成 JS challenge）
        let webResult = await loadReviewViaWebView(url.absoluteString)

        // 组装标题：优先 meta，兜底 webview
        let title = metaTitle

        // 组装正文：优先 webview 完整文本，兜底 meta description
        var body = webResult.text
        if body == nil || body!.count <= (metaDesc?.count ?? 0) {
                body = metaDesc
        } else {
            }

        // 组装作者：优先 webview 提取，兜底 meta
        let author = webResult.author ?? extractMeta(html, name: "author")

        // 组装封面：优先 webview 提取，兜底 meta
        let cover = webResult.cover ?? metaCover

        return ParsedContent(
            title: title,
            body: body,
            author: author,
            coverURL: cover,
            platformContentID: reviewID,
            rawMetadata: ["type": "review", "source": "webview"]
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
                let text = json["text"] as? String
                let author = json["author"] as? String
                let cover = json["cover"] as? String
                return WebContentResult(text: text, author: author, cover: cover)
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
            let (data, _) = try await session.data(from: url)
            try data.write(to: localURL)
            return true
        } catch { return false }
    }
}
