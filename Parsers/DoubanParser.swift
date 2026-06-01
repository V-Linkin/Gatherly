import Foundation
import WebKit
import os.log

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

    private let logger = Logger(subsystem: "com.archiver.app", category: "DoubanParser")

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

        // 下载正文图片
        if let bodyImageURLsStr = content.rawMetadata["bodyImageURLs"] {
            let imageURLs = bodyImageURLsStr.components(separatedBy: "||")
            for (index, imageURLStr) in imageURLs.enumerated() {
                guard let url = URL(string: imageURLStr) else { continue }
                let ext = url.pathExtension.isEmpty ? "jpg" : url.pathExtension
                let fileName = "image_\(index).\(ext)"
                let localPath = itemDir.appendingPathComponent(fileName)
                if await downloadFile(from: url, to: localPath) {
                    let fileSize = (try? fileManager.attributesOfItem(atPath: localPath.path)[.size] as? Int64) ?? 0
                    let asset = MediaAsset(
                        itemID: itemID, type: .image,
                        localPath: "\(itemID.uuidString)/\(fileName)",
                        remoteURL: imageURLStr, fileName: fileName,
                        fileSize: fileSize, downloadStatus: .completed
                    )
                    try MediaRepository().insert(asset)
                    assets.append(asset)
                }
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

        let directorResult = extractDirector(html)
        let authorResult = extractAuthor(html)

        let author = directorResult ?? authorResult

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
        let metaAuthor = extractMeta(html, name: "author")
        
        // 从 HTML 正文区域提取内容
        let htmlBody = extractReviewBodyFromHTML(html)
        
        // 提取正文中的图片 URL
        let bodyImageURLs = extractReviewImageURLs(from: html)
        
        let metaCover = extractMeta(html, property: "og:image")
        
        // 提取作者（从影评页面的特定结构）
        let reviewAuthorResult = extractReviewAuthorFromHTML(html)
        logger.info("extractReviewAuthorFromHTML 结果: \(reviewAuthorResult ?? "nil", privacy: .public)")
        let htmlAuthor = reviewAuthorResult ?? metaAuthor
        
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
        
        // 组装封面：从 JSON-LD 获取电影海报（最可靠）
        var cover: String? = nil
        cover = extractMoviePosterFromReviewHTML(html)
        if cover == nil {
            cover = metaCover
        }
        
        // 第三步：尝试用 WKWebView 补充内容（如果 HTML 解析不够完整）
        let webResult = await loadReviewViaWebView(url.absoluteString)
        
        // 合并结果：webview 优先（如果成功获取到内容）
        let finalTitle = webResult.title ?? title
        // 优先使用 webview 结果（如果包含真实内容而非模板代码）
        let finalBody: String?
        if let webText = webResult.text, !webText.isEmpty, !webText.contains("{{=") {
            finalBody = webText
        } else {
            finalBody = body
        }
        let finalAuthor = webResult.author ?? author
        let finalCover = cover
        
        var metadata: [String: String] = ["type": "review", "source": "html+webview"]
        if !bodyImageURLs.isEmpty {
            metadata["bodyImageURLs"] = bodyImageURLs.joined(separator: "||")
        }
        
        return ParsedContent(
            title: finalTitle,
            body: finalBody,
            author: finalAuthor,
            coverURL: finalCover,
            platformContentID: reviewID,
            rawMetadata: metadata
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
        // 按优先级尝试匹配影评正文区域，使用嵌套标签匹配而非简单正则
        let containerPatterns: [(name: String, pattern: String)] = [
            ("review-content", #"class="review-content[^"]*""#),
            ("link-report", #"id="link-report[^"]*""#),
            ("main-review", #"class="main-review[^"]*""#),
            ("review-body", #"class="review-body[^"]*""#),
        ]
        
        for (name, attrPattern) in containerPatterns {
            if let fullContent = extractNestedDivContent(html, containing: attrPattern) {
                let text = cleanHTML(fullContent)
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
    
    /// 提取正文中的图片 URL 列表
    func extractReviewImageURLs(from html: String) -> [String] {
        // 先找到正文容器
        let containerPatterns = [
            #"class="review-content[^"]*""#,
            #"id="link-report[^"]*""#,
            #"class="main-review[^"]*""#,
        ]
        
        var bodyHTML = ""
        for attrPattern in containerPatterns {
            if let content = extractNestedDivContent(html, containing: attrPattern) {
                bodyHTML = content
                break
            }
        }
        
        // 如果没有找到容器，使用整个 HTML
        if bodyHTML.isEmpty {
            bodyHTML = html
        }
        
        // 提取所有 <img> 标签的 src
        var imageURLs: [String] = []
        let imgPattern = #"<img[^>]*\bsrc="([^"]*)"[^>]*/?>"#
        if let regex = try? NSRegularExpression(pattern: imgPattern, options: .caseInsensitive) {
            let matches = regex.matches(in: bodyHTML, range: NSRange(bodyHTML.startIndex..., in: bodyHTML))
            for match in matches {
                if let range = Range(match.range(at: 1), in: bodyHTML) {
                    var src = String(bodyHTML[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                    // 过滤掉表情、小图标等
                    if src.contains("img") && (src.contains("doubanio.com") || src.contains("douban.com")) {
                        // 转为原图 URL（去掉缩略图后缀）
                        src = src.replacingOccurrences(of: #"\/s_ratio_poster\/"#, with: "/raw/")
                        src = src.replacingOccurrences(of: #"\/m_ratio_poster\/"#, with: "/raw/")
                        src = src.replacingOccurrences(of: #"\/s_crop_poster\/"#, with: "/raw/")
                        // 确保是 https
                        if src.hasPrefix("//") {
                            src = "https:" + src
                        }
                        if !imageURLs.contains(src) {
                            imageURLs.append(src)
                        }
                    }
                }
            }
        }
        
        // 也尝试 data-src（懒加载图片）
        let dataSrcPattern = #"<img[^>]*\bdata-src="([^"]*)"[^>]*/?>"#
        if let regex = try? NSRegularExpression(pattern: dataSrcPattern, options: .caseInsensitive) {
            let matches = regex.matches(in: bodyHTML, range: NSRange(bodyHTML.startIndex..., in: bodyHTML))
            for match in matches {
                if let range = Range(match.range(at: 1), in: bodyHTML) {
                    var src = String(bodyHTML[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if src.contains("doubanio.com") || src.contains("douban.com") {
                        if src.hasPrefix("//") { src = "https:" + src }
                        if !imageURLs.contains(src) {
                            imageURLs.append(src)
                        }
                    }
                }
            }
        }
        
        return imageURLs
    }
    
    /// 通过追踪嵌套深度提取 <div> 内容（解决正则 .\*? 截断问题）
    private func extractNestedDivContent(_ html: String, containing attrPattern: String) -> String? {
        // 找到包含指定属性的 <div> 开始标签
        let divPattern = "<div[^>]*\(attrPattern)[^>]*>"
        guard let regex = try? NSRegularExpression(pattern: divPattern, options: .dotMatchesLineSeparators),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)) else {
            return nil
        }
        
        let matchRange = match.range
        guard let contentStart = Range(NSRange(location: matchRange.upperBound, length: 0), in: html) else {
            return nil
        }
        
        // 从 <div 开始标签的 < 处追踪嵌套深度
        let tagStart = Range(NSRange(location: matchRange.location, length: 0), in: html)!
        var depth = 1
        var pos = contentStart.lowerBound
        var endPos = html.endIndex
        
        while pos < html.endIndex && depth > 0 {
            // 查找下一个 <div 或 </div>
            if html[pos...].hasPrefix("<div") || html[pos...].hasPrefix("<DIV") {
                // 检查是 <div> 还是 </div>
                if pos != html.startIndex {
                    let prevIndex = html.index(before: pos)
                    if html[prevIndex] == "/" {
                        depth -= 1
                        if depth == 0 {
                            // 找到 </div> 的结束位置
                            if let closeEnd = html.range(of: ">", range: pos..<html.endIndex) {
                                endPos = closeEnd.upperBound
                            }
                            break
                        }
                    } else {
                        depth += 1
                    }
                }
            } else if html[pos...].hasPrefix("</div>") || html[pos...].hasPrefix("</DIV>") {
                depth -= 1
                if depth == 0 {
                    if let closeEnd = html.range(of: ">", range: pos..<html.endIndex) {
                        endPos = closeEnd.upperBound
                    }
                    break
                }
                pos = html.index(pos, offsetBy: 6)
                continue
            }
            pos = html.index(after: pos)
        }
        
        if depth == 0 {
            return String(html[contentStart.lowerBound..<endPos])
        }
        return nil
    }
    
    /// 从 HTML 中提取影评作者
    private func extractReviewAuthorFromHTML(_ html: String) -> String? {
        // 策略1: 从 JSON-LD 结构化数据中提取作者（最可靠）
        if let authorFromLD = extractAuthorFromJSONLD(html) {
            return authorFromLD
        }
        
        // 策略2: 从 data-author 属性提取
        if let dataAuthor = extractFirst(html, pattern: #"data-author="([^"]+)""#) {
            let trimmed = dataAuthor.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty && trimmed.count < 30 && trimmed != "豆瓣" {
                return trimmed
            }
        }
        
        // 策略3: 从 <header class="main-hd"> 区域提取作者链接
        if let authorFromHeader = extractAuthorFromHeaderArea(html) {
            return authorFromHeader
        }
        
        // 策略4: 找到所有 douban.com/people/ 的链接，取第一个有文字内容的
        if let authorFromPeopleLink = extractFirstPeopleLinkWithText(html) {
            return authorFromPeopleLink
        }
        
        // 策略5: 旧版模式匹配
        let patterns = [
            #"<a[^>]*class="name"[^>]*>([^<]+)</a>"#,
            #"<span[^>]*class="name"[^>]*>\s*<a[^>]*>([^<]+)</a>"#,
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
    
    /// 从 JSON-LD 结构化数据中提取作者名
    private func extractAuthorFromJSONLD(_ html: String) -> String? {
        // 匹配 <script type="application/ld+json"> 块
        guard let scriptRegex = try? NSRegularExpression(pattern: #"<script\s+type="application/ld\+json">(.*?)</script>"#, options: .dotMatchesLineSeparators) else { return nil }
        let matches = scriptRegex.matches(in: html, range: NSRange(html.startIndex..., in: html))
        
        for match in matches {
            guard let range = Range(match.range(at: 1), in: html) else { continue }
            let jsonStr = String(html[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard let jsonData = jsonStr.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else { continue }
            
            // 直接从顶层 author 字段提取
            if let author = json["author"] as? [String: Any],
               let name = author["name"] as? String,
               !name.isEmpty {
                return name
            }
        }
        return nil
    }
    
    /// 从 <header class="main-hd"> 区域提取作者名
    private func extractAuthorFromHeaderArea(_ html: String) -> String? {
        // 找到 main-hd 区域（包含 header 标签本身）
        guard let headerTagRange = html.range(of: #"<header class="main-hd""#) else { return nil }
        // 从 header 标签开始搜索 3000 字符
        let searchStart = headerTagRange.lowerBound
        let searchEndIndex = html.index(searchStart, offsetBy: min(3000, html.distance(from: searchStart, to: html.endIndex)), limitedBy: html.endIndex) ?? html.endIndex
        let headerArea = String(html[searchStart..<searchEndIndex])
        
        // 策略1: 找 douban.com/people/ 链接，捕获链接内的纯文本
        let peopleLinkPattern = #"<a[^>]*href="[^"]*douban\.com/people/[^"]*"[^>]*>([^<]+)</a>"#
        if let author = extractFirst(headerArea, pattern: peopleLinkPattern) {
            let trimmed = author.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty && trimmed.count < 30 && trimmed != "豆瓣" {
                return trimmed
            }
        }
        
        // 策略2: 找 <a> 标签内含有 "people" 链接的，不管内部是否嵌套了其他标签
        // 提取所有 <a> 标签内容，找含 people 链接的
        if let aTagRegex = try? NSRegularExpression(pattern: #"<a[^>]*href="[^"]*douban\.com/people/[^"]*"[^>]*>(.*?)</a>"#, options: .dotMatchesLineSeparators) {
            let matches = aTagRegex.matches(in: headerArea, range: NSRange(headerArea.startIndex..., in: headerArea))
            for match in matches {
                if let innerRange = Range(match.range(at: 1), in: headerArea) {
                    let inner = String(headerArea[innerRange])
                    // 如果内部是纯文本（不含标签），直接取
                    if !inner.contains("<") {
                        let trimmed = inner.trimmingCharacters(in: .whitespacesAndNewlines)
                        logger.info("[extractAuthorFromHeader] 策略2纯文本匹配: \(trimmed, privacy: .public)")
                        if !trimmed.isEmpty && trimmed.count < 30 && trimmed != "豆瓣" {
                            return trimmed
                        }
                    }
                    // 如果内部含 <img> 标签，跳过（是头像）
                    // 如果内部有其他文本，清理 HTML 后取
                    let cleaned = inner.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !cleaned.isEmpty && cleaned.count < 30 && cleaned != "豆瓣" && !cleaned.contains("http") {
                        return cleaned
                    }
                }
            }
        }
        
        // 策略3: 在 header 后的区域中找任何 <a> 标签，取第一个有 < 20 字纯文本的（可能是作者名）
        if let aTagRegex = try? NSRegularExpression(pattern: #"<a[^>]*>([^<]{1,20})</a>"#, options: []) {
            let matches = aTagRegex.matches(in: headerArea, range: NSRange(headerArea.startIndex..., in: headerArea))
            for match in matches.prefix(5) {
                if let textRange = Range(match.range(at: 1), in: headerArea) {
                    let text = String(headerArea[textRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                    // 排除导航链接、短文本
                    if !text.isEmpty && text.count >= 2 && text.count <= 20 
                        && text != "豆瓣" && text != "首页" && text != "读书" && text != "电影" && text != "音乐"
                        && text != "小组" && text != "阅读" && text != "FM" && text != "时间" && text != "豆品" {
                        return text
                    }
                }
            }
        }
        
        return nil
    }
    
    /// 找到 HTML 中所有 douban.com/people/ 链接，返回第一个有文字内容的
    private func extractFirstPeopleLinkWithText(_ html: String) -> String? {
        // 策略1: 纯文本链接（不含嵌套标签）
        let textPattern = #"<a[^>]*href="[^"]*douban\.com/people/[^"]*"[^>]*>([^<]+)</a>"#
        if let regex = try? NSRegularExpression(pattern: textPattern, options: .caseInsensitive) {
            let matches = regex.matches(in: html, range: NSRange(html.startIndex..., in: html))
            for match in matches {
                if let range = Range(match.range(at: 1), in: html) {
                    let name = String(html[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !name.isEmpty && name.count < 30 && name != "豆瓣" {
                                        return name
                    }
                }
            }
        }
        
        // 策略2: 宽松匹配（允许内部嵌套标签，清理后取纯文本）
        let loosePattern = #"<a[^>]*href="[^"]*douban\.com/people/[^"]*"[^>]*>(.*?)</a>"#
        if let regex = try? NSRegularExpression(pattern: loosePattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) {
            let matches = regex.matches(in: html, range: NSRange(html.startIndex..., in: html))
            for match in matches {
                if let range = Range(match.range(at: 1), in: html) {
                    let inner = String(html[range])
                    // 跳过只含 <img> 的链接（头像）
                    if inner.contains("<img") && !inner.replacingOccurrences(of: #"<img[^>]*>"#, with: "", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                        // Has img but also has text
                    }
                    let cleaned = inner.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !cleaned.isEmpty && cleaned.count >= 2 && cleaned.count < 30 && cleaned != "豆瓣" {
                                        return cleaned
                    }
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
            // 新版豆瓣: <span class="info-item-key">导演:</span> <span class="info-item-val">李安</span>
            #"<span[^>]*class="info-item-key"[^>]*>\s*导演\s*:?</span>\s*<span[^>]*class="info-item-val"[^>]*>([^<]+)</span>"#,
            // 旧版豆瓣
            #"<span class="pl">导演</span>.*?<a[^>]*>([^<]+)</a>"#,
            #"<span[^>]*>导演\s*:</span>\s*<span[^>]*>([^<]+)</span>"#,
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
            // 新版豆瓣: <span class="info-item-key">作者:</span> <span class="info-item-val">余华</span>
            #"<span[^>]*class="info-item-key"[^>]*>\s*作者\s*:?</span>\s*<span[^>]*class="info-item-val"[^>]*>([^<]+)</span>"#,
            // 旧版豆瓣
            #"<span class="pl">作者</span>.*?<a[^>]*>([^<]+)</a>"#,
            #"<span[^>]*>作者\s*:</span>\s*<span[^>]*>([^<]+)</span>"#,
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


    // MARK: - Debug Helper

    private func debugSearchAuthorPatterns(in html: String) {
        // 搜索所有包含 "作者" 或 "导演" 的片段
        let keywords = ["作者", "导演", "编剧", "主演", "author", "director"]
        for keyword in keywords {
            if let range = html.range(of: keyword) {
                // 安全提取上下文片段
                let lowerOffset = max(0, html.distance(from: html.startIndex, to: range.lowerBound) - 100)
                let upperOffset = min(html.count, html.distance(from: html.startIndex, to: range.upperBound) + 200)
                let startIndex = html.index(html.startIndex, offsetBy: lowerOffset)
                let endIndex = html.index(html.startIndex, offsetBy: upperOffset)
                let snippet = String(html[startIndex..<endIndex])
                    .replacingOccurrences(of: "\n", with: " ")
                    .replacingOccurrences(of: "\r", with: " ")
                logger.info("[\(keyword)] 上下文片段: ...\(snippet, privacy: .public)...")
            } else {
                logger.info("[\(keyword)] 在 HTML 中未找到")
            }
        }

        // 搜索 og:video:director meta 标签
        let directorPatterns = [
            "og:video:director",
            "itemprop=.director",
            "class=.pl.>导演",
            "class=.pl.>作者",
        ]
        for pattern in directorPatterns {
            if html.contains(pattern) {
                logger.info("找到模式: \(pattern, privacy: .public)")
            } else {
                logger.info("未找到模式: \(pattern, privacy: .public)")
            }
        }

        // 提取前 3000 字符看结构
        let sampleSize = min(3000, html.count)
        let sample = String(html.prefix(sampleSize))
        logger.info("HTML 前 3000 字符: \(sample, privacy: .public)")
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

    /// 从影评页面 HTML 的 JSON-LD 中提取电影海报 URL
    private func extractMoviePosterFromReviewHTML(_ html: String) -> String? {
        guard let scriptRegex = try? NSRegularExpression(pattern: #"<script\s+type="application/ld\+json">(.*?)</script>"#, options: .dotMatchesLineSeparators) else { return nil }
        let matches = scriptRegex.matches(in: html, range: NSRange(html.startIndex..., in: html))
        
        for match in matches {
            guard let range = Range(match.range(at: 1), in: html) else { continue }
            let jsonStr = String(html[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard let jsonData = jsonStr.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else { continue }
            
            // itemReviewed.image 就是电影海报
            if let itemReviewed = json["itemReviewed"] as? [String: Any],
               let imageURL = itemReviewed["image"] as? String,
               !imageURL.isEmpty {
                return imageURL
            }
        }
        return nil
    }
    
    /// 从影评页面 HTML 中提取影片 subject ID
    private func extractSubjectIDFromReviewHTML(_ html: String) -> String? {
        // 策略1: 从 JSON-LD 结构化数据的 itemReviewed.url 提取
        if let scriptRegex = try? NSRegularExpression(pattern: #"<script\s+type="application/ld\+json">(.*?)</script>"#, options: .dotMatchesLineSeparators) {
            let matches = scriptRegex.matches(in: html, range: NSRange(html.startIndex..., in: html))
            for match in matches {
                guard let range = Range(match.range(at: 1), in: html) else { continue }
                let jsonStr = String(html[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                guard let jsonData = jsonStr.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else { continue }
                if let itemReviewed = json["itemReviewed"] as? [String: Any],
                   let itemURL = itemReviewed["url"] as? String {
                    // URL 格式: "/subject/1301168/" 或 "https://movie.douban.com/subject/1301168/"
                    if let match = itemURL.range(of: #"/subject/(\d+)"#, options: .regularExpression) {
                        let matched = String(itemURL[match])
                        let digits = matched.filter { $0.isNumber }
                        if !digits.isEmpty { return digits }
                    }
                }
            }
        }
        
        // 策略2: 从页面链接中找 /subject/ID 格式
        let linkPattern = #"douban\.com/subject/(\d+)"#
        if let match = extractFirst(html, pattern: linkPattern) {
            return match
        }
        
        return nil
    }
    
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
