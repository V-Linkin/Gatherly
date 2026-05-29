import Foundation
import WebKit

final class ZhihuParser: ContentParser, @unchecked Sendable {

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
            "Accept": "application/json, text/html, */*",
            "Accept-Language": "zh-CN,zh;q=0.9,en;q=0.8",
            "x-requested-with": "fetch"
        ]
        return URLSession(configuration: config)
    }()

    func canParse(url: URL) -> Bool {
        let host = url.host?.lowercased() ?? ""
        return host == "zhihu.com" || host == "www.zhihu.com"
            || host == "m.zhihu.com" || host == "zhuanlan.zhihu.com"
    }

    func extractContentID(from url: URL) -> String? {
        URLNormalizer.extractContentID(url.absoluteString, platform: .zhihu)
    }

    func normalizeURL(_ url: String) -> String {
        URLNormalizer.normalize(url, platform: .zhihu)
    }

    func parse(url: URL) async throws -> ParsedContent {
        if let answerID = extractAnswerID(from: url) {
            return try await fetchAnswerAPI(answerID: answerID)
        }
        if let articleID = extractArticleID(from: url) {
            return try await fetchArticleAPI(articleID: articleID)
        }
        return try await parseMobilePage(url)
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

    // MARK: - Answer API

    private func fetchAnswerAPI(answerID: String) async throws -> ParsedContent {
        let apiURL = URL(string: "https://api.zhihu.com/answers/\(answerID)?include=content,excerpt,question")!
        let (data, response) = try await session.data(from: apiURL)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            return try await fetchFullContentViaWebView(
                urlString: "https://www.zhihu.com/question/0/answer/\(answerID)",
                contentID: answerID, type: "answer"
            )
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ParserError.parseFailed(reason: "无法解析知乎 API 响应")
        }

        if let error = json["error"] as? [String: Any] {
            let message = error["message"] as? String ?? "未知错误"
            throw ParserError.parseFailed(reason: "知乎 API 错误: \(message)")
        }

        let apiContent = json["content"] as? String ?? ""
        let isTruncated = json["content_need_truncated"] as? Bool ?? false

        var questionTitle: String?
        if let question = json["question"] as? [String: Any] {
            questionTitle = question["title"] as? String
        }

        var author: String?
        var authorID: String?
        if let authorData = json["author"] as? [String: Any] {
            author = authorData["name"] as? String
            authorID = authorData["url_token"] as? String
        }

        var publishDate: Date?
        if let created = json["created_time"] as? Double {
            publishDate = Date(timeIntervalSince1970: created)
        }

        var body: String
        var imageURLs: [String]

        if isTruncated, apiContent.count < 2000 {
            // 内容被截断，用 WKWebView 获取完整内容
            // 先获取 question ID 来构造正确的 URL
            var questionURL = "https://www.zhihu.com/question/0/answer/\(answerID)"
            if let qID = (json["question"] as? [String: Any])?["id"] as? String {
                questionURL = "https://www.zhihu.com/question/\(qID)/answer/\(answerID)"
            }
            let webResult = await loadViaWebView(questionURL)
            if let fullHTML = webResult.html, fullHTML.count > apiContent.count {
                body = convertHTMLToMarkdown(fullHTML)
                imageURLs = extractImagesFromHTML(fullHTML)
            } else {
                body = convertHTMLToMarkdown(apiContent)
                imageURLs = extractImagesFromHTML(apiContent)
            }
        } else {
            body = convertHTMLToMarkdown(apiContent)
            imageURLs = extractImagesFromHTML(apiContent)
        }

        var fullBody = ""
        if let qTitle = questionTitle {
            fullBody += "**问题：** \(qTitle)\n\n"
        }
        fullBody += body

        return ParsedContent(
            title: questionTitle ?? "知乎回答",
            body: fullBody,
            author: author,
            authorID: authorID,
            publishDate: publishDate,
            imageURLs: imageURLs,
            platformContentID: answerID,
            rawMetadata: ["type": "answer"]
        )
    }

    // MARK: - Article API

    private func fetchArticleAPI(articleID: String) async throws -> ParsedContent {
        let apiURL = URL(string: "https://api.zhihu.com/articles/\(articleID)?include=content,excerpt")!
        let (data, response) = try await session.data(from: apiURL)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            return try await fetchFullContentViaWebView(
                urlString: "https://zhuanlan.zhihu.com/p/\(articleID)",
                contentID: articleID, type: "article"
            )
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ParserError.parseFailed(reason: "无法解析知乎 API 响应")
        }

        if let error = json["error"] as? [String: Any] {
            let message = error["message"] as? String ?? "未知错误"
            throw ParserError.parseFailed(reason: "知乎 API 错误: \(message)")
        }

        let title = json["title"] as? String
        let apiContent = json["content"] as? String ?? ""
        let isTruncated = json["content_need_truncated"] as? Bool ?? false

        var author: String?
        var authorID: String?
        if let authorData = json["author"] as? [String: Any] {
            author = authorData["name"] as? String
            authorID = authorData["url_token"] as? String
        }

        var publishDate: Date?
        if let created = json["created"] as? Double {
            publishDate = Date(timeIntervalSince1970: created)
        }

        var body: String
        var imageURLs: [String]

        if isTruncated, apiContent.count < 2000 {
            let webResult = await loadViaWebView("https://zhuanlan.zhihu.com/p/\(articleID)")
            if let fullHTML = webResult.html, fullHTML.count > apiContent.count {
                body = convertHTMLToMarkdown(fullHTML)
                imageURLs = extractImagesFromHTML(fullHTML)
            } else {
                body = convertHTMLToMarkdown(apiContent)
                imageURLs = extractImagesFromHTML(apiContent)
            }
        } else {
            body = convertHTMLToMarkdown(apiContent)
            imageURLs = extractImagesFromHTML(apiContent)
        }

        return ParsedContent(
            title: title,
            body: body,
            author: author,
            authorID: authorID,
            publishDate: publishDate,
            imageURLs: imageURLs,
            platformContentID: articleID,
            rawMetadata: ["type": "article"]
        )
    }

    // MARK: - WKWebView Fallback

    private func fetchFullContentViaWebView(urlString: String, contentID: String, type: String) async throws -> ParsedContent {
        let webResult = await loadViaWebView(urlString)
        if let fullHTML = webResult.html {
            let body = convertHTMLToMarkdown(fullHTML)
            let imageURLs = extractImagesFromHTML(fullHTML)

            return ParsedContent(
                title: nil,
                body: body,
                imageURLs: imageURLs,
                platformContentID: contentID,
                rawMetadata: ["type": type, "source": "webview"]
            )
        }

        throw ParserError.parseFailed(reason: "无法获取知乎内容")
    }

    /// 通过 WKWebView 获取内容，返回 (html: String?, questionTitle: String?, author: String?)
    private func loadViaWebView(_ urlString: String) async -> (html: String?, questionTitle: String?, author: String?) {
        guard let url = URL(string: urlString) else { return (nil, nil, nil) }
        let result = await ZhihuWebLoader().loadFullContent(from: url)
        guard let result else { return (nil, nil, nil) }

        if result.hasPrefix("ANSWER:") {
            let parts = result.components(separatedBy: ":")
            // ANSWER:id:htmlContent
            if parts.count >= 3 {
                let htmlContent = parts[2...].joined(separator: ":")
                return (htmlContent, nil, nil)
            }
        } else if result.hasPrefix("ARTICLE:") {
            let parts = result.components(separatedBy: ":")
            if parts.count >= 3 {
                let htmlContent = parts[2...].joined(separator: ":")
                return (htmlContent, nil, nil)
            }
        } else if result.hasPrefix("HTML:") || result.hasPrefix("BODY:") {
            let htmlContent = String(result.dropFirst(5))
            return (htmlContent, nil, nil)
        }
        return (result, nil, nil)
    }

    // MARK: - Mobile Page Fallback

    private func parseMobilePage(_ url: URL) async throws -> ParsedContent {
        let mobileURL = toMobileURL(url)
        let (data, response) = try await session.data(from: mobileURL)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw ParserError.parseFailed(reason: "HTTP 请求失败")
        }
        guard let html = String(data: data, encoding: .utf8) else {
            throw ParserError.parseFailed(reason: "无法解码页面内容")
        }

        guard let initialData = extractInitialData(from: html),
              let jsonData = initialData.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let initialState = json["initialState"] as? [String: Any],
              let entities = initialState["entities"] as? [String: Any] else {
            return parseMetaFallback(html, url: url)
        }

        if let answers = entities["answers"] as? [String: Any],
           let (_, raw) = answers.first,
           let answerData = raw as? [String: Any],
           let firstKey = answers.keys.first {
            return buildAnswerFromDict(answerData, answerID: firstKey, url: url)
        }

        if let articles = entities["articles"] as? [String: Any],
           let (_, raw) = articles.first,
           let articleData = raw as? [String: Any] {
            return buildArticleFromDict(articleData, url: url)
        }

        return parseMetaFallback(html, url: url)
    }

    private func buildAnswerFromDict(_ data: [String: Any], answerID: String, url: URL) -> ParsedContent {
        let content = data["content"] as? String ?? ""
        let body = convertHTMLToMarkdown(content)

        var questionTitle: String?
        if let question = data["question"] as? [String: Any] {
            questionTitle = question["title"] as? String
        }

        var author: String?
        var authorID: String?
        if let authorData = data["author"] as? [String: Any] {
            author = authorData["name"] as? String
            authorID = authorData["urlToken"] as? String
        }

        var publishDate: Date?
        if let created = data["createdTime"] as? Double {
            publishDate = Date(timeIntervalSince1970: created)
        }

        var fullBody = ""
        if let qTitle = questionTitle {
            fullBody += "**问题：** \(qTitle)\n\n"
        }
        fullBody += body

        return ParsedContent(
            title: questionTitle ?? "知乎回答",
            body: fullBody,
            author: author,
            authorID: authorID,
            publishDate: publishDate,
            imageURLs: extractImagesFromHTML(content),
            platformContentID: answerID,
            rawMetadata: ["type": "answer"]
        )
    }

    private func buildArticleFromDict(_ data: [String: Any], url: URL) -> ParsedContent {
        let title = data["title"] as? String
        let content = data["content"] as? String ?? ""
        let body = convertHTMLToMarkdown(content)

        var author: String?
        var authorID: String?
        if let authorData = data["author"] as? [String: Any] {
            author = authorData["name"] as? String
            authorID = authorData["urlToken"] as? String
        }

        var publishDate: Date?
        if let created = data["created"] as? Double {
            publishDate = Date(timeIntervalSince1970: created)
        }

        let articleID = extractArticleID(from: url)

        return ParsedContent(
            title: title,
            body: body,
            author: author,
            authorID: authorID,
            publishDate: publishDate,
            imageURLs: extractImagesFromHTML(content),
            platformContentID: articleID,
            rawMetadata: ["type": "article"]
        )
    }

    // MARK: - Meta Fallback

    private func parseMetaFallback(_ html: String, url: URL) -> ParsedContent {
        let title = extractMeta(html, property: "og:title") ?? extractMeta(html, name: "title")
        let desc = extractMeta(html, property: "og:description") ?? extractMeta(html, name: "description")
        let cover = extractMeta(html, property: "og:image")
        let contentID = url.path.contains("/answer/") ? extractAnswerID(from: url) : extractArticleID(from: url)

        return ParsedContent(
            title: title,
            body: desc,
            coverURL: cover,
            platformContentID: contentID,
            rawMetadata: ["type": "unknown", "source": "meta_fallback"]
        )
    }

    // MARK: - URL Helpers

    private func toMobileURL(_ url: URL) -> URL {
        var urlString = url.absoluteString
        urlString = urlString.replacingOccurrences(of: "://www.zhihu.com", with: "://m.zhihu.com")
        if urlString.contains("zhuanlan.zhihu.com/p/") {
            urlString = urlString.replacingOccurrences(of: "zhuanlan.zhihu.com/p/", with: "m.zhihu.com/article/")
        }
        return URL(string: urlString) ?? url
    }

    private func extractAnswerID(from url: URL) -> String? {
        URLNormalizer.extractFirstMatch(url.absoluteString, patterns: ["zhihu\\.com/question/\\d+/answer/(\\d+)"])
    }

    private func extractArticleID(from url: URL) -> String? {
        URLNormalizer.extractFirstMatch(url.absoluteString, patterns: ["zhihu\\.com/p/(\\d+)", "zhihu\\.com/article/(\\d+)"])
    }

    // MARK: - JSON Extraction

    private func extractInitialData(from html: String) -> String? {
        if let startRange = html.range(of: "window.__INITIAL_STATE__=") {
            return extractJSONFromBraces(html, startRange: startRange.upperBound)
        }
        if let startRange = html.range(of: "id=\"js-initialData\" type=\"text/json\">") {
            let contentStart = startRange.upperBound
            if let endRange = html.range(of: "</script>", range: contentStart..<html.endIndex) {
                return String(html[contentStart..<endRange.lowerBound])
            }
        }
        return nil
    }

    private func extractJSONFromBraces(_ html: String, startRange: String.Index) -> String? {
        var braceCount = 0
        var foundOpening = false
        var endIndex = startRange
        for char in html[startRange...] {
            if char == "{" { braceCount += 1; foundOpening = true }
            else if char == "}" { braceCount -= 1 }
            if foundOpening && braceCount == 0 { break }
            endIndex = html.index(after: endIndex)
            if endIndex >= html.endIndex { break }
        }
        if foundOpening && braceCount == 0 {
            return String(html[startRange..<endIndex])
        }
        return nil
    }

    // MARK: - HTML to Markdown

    private func convertHTMLToMarkdown(_ html: String) -> String {
        var text = html
        text = text.replacingOccurrences(of: #"<img[^>]*data-original="([^"]*)"[^>]*>"#, with: "![]($1)", options: .regularExpression)
        text = text.replacingOccurrences(of: #"<img[^>]*data-actualsrc="([^"]*)"[^>]*>"#, with: "![]($1)", options: .regularExpression)
        text = text.replacingOccurrences(of: #"<img[^>]*src="([^"]*)"[^>]*>"#, with: "![]($1)", options: .regularExpression)
        text = text.replacingOccurrences(of: #"<br\s*/?>"#, with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "</p>", with: "\n\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "</div>", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: #"<h[1-6][^>]*>"#, with: "\n## ", options: .regularExpression)
        text = text.replacingOccurrences(of: #"</h[1-6]>"#, with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "<b>", with: "**", options: .caseInsensitive)
        text = text.replacingOccurrences(of: "</b>", with: "**", options: .caseInsensitive)
        text = text.replacingOccurrences(of: "<strong>", with: "**", options: .caseInsensitive)
        text = text.replacingOccurrences(of: "</strong>", with: "**", options: .caseInsensitive)
        text = text.replacingOccurrences(of: #"<li[^>]*>"#, with: "- ", options: .regularExpression)
        text = text.replacingOccurrences(of: "</li>", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "&amp;", with: "&")
        text = text.replacingOccurrences(of: "&lt;", with: "<")
        text = text.replacingOccurrences(of: "&gt;", with: ">")
        text = text.replacingOccurrences(of: "&nbsp;", with: " ")
        text = text.replacingOccurrences(of: "&quot;", with: "\"")
        text = text.replacingOccurrences(of: "&#39;", with: "'")
        text = text.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func extractImagesFromHTML(_ html: String) -> [String] {
        var urls: [String] = []
        let patterns = [
            #"data-original="([^"]*)""#,
            #"data-actualsrc="([^"]*)""#,
            #"src="(https?://[^"]*\.(jpg|jpeg|png|gif|webp)[^"]*)""#
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let matches = regex.matches(in: html, range: NSRange(html.startIndex..., in: html))
                for match in matches {
                    if let range = Range(match.range(at: 1), in: html) {
                        let url = String(html[range])
                        if !urls.contains(url) { urls.append(url) }
                    }
                }
            }
        }
        return Array(urls.prefix(9))
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
