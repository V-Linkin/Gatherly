# 微博、知乎、豆瓣平台支持实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Weibo, Zhihu, and Douban as supported platforms with HTML scraping + embedded JSON parsing.

**Architecture:** Follow existing parser pattern (ContentParser protocol + PlatformRouter registration). Each platform has its own parser class. All parsers use URLSession to fetch HTML, extract embedded JSON data, and fall back to meta tags.

**Tech Stack:** Swift 6.0, URLSession, JSONSerialization (same as existing parsers)

---

## Files Overview

| Action | File | Purpose |
|--------|------|---------|
| Modify | `Models/Enums/Platform.swift` | Add `.weibo`, `.zhihu`, `.douban` cases |
| Modify | `Utilities/URLNormalizer.swift` | Add three platforms' URL recognition and normalization |
| Create | `Parsers/WeiboParser.swift` | Weibo parser (single post with images) |
| Create | `Parsers/ZhihuParser.swift` | Zhihu parser (answers, articles, columns) |
| Create | `Parsers/DoubanParser.swift` | Douban parser (book/movie/music reviews) |
| Modify | `Parsers/PlatformRouter.swift` | Register three new parsers |

---

## Task 1: Add Platform Enum Cases

**Files:**
- Modify: `Models/Enums/Platform.swift`

- [ ] **Step 1: Add three new cases to Platform enum**

Replace the entire file with:

```swift
// Models/Enums/Platform.swift

import Foundation
import SwiftUI

enum Platform: String, Codable, CaseIterable, Identifiable {
    case douyin
    case xiaohongshu
    case coolapk
    case bilibili
    case github
    case youtube
    case weibo
    case zhihu
    case douban
    case custom

    var id: String { rawValue }

    var defaultDisplayName: String {
        switch self {
        case .douyin: return "抖音"
        case .xiaohongshu: return "小红书"
        case .coolapk: return "酷安"
        case .bilibili: return "B站"
        case .github: return "GitHub"
        case .youtube: return "YouTube"
        case .weibo: return "微博"
        case .zhihu: return "知乎"
        case .douban: return "豆瓣"
        case .custom: return "自定义"
        }
    }

    var displayName: String {
        PlatformCustomization.displayName(for: self)
    }

    var iconName: String {
        switch self {
        case .douyin: return "music.note"
        case .xiaohongshu: return "book.fill"
        case .coolapk: return "apps.iphone"
        case .bilibili: return "play.tv"
        case .github: return "chevron.left.forwardslash.chevron.right"
        case .youtube: return "play.rectangle.fill"
        case .weibo: return "bubble.left.and.bubble.right.fill"
        case .zhihu: return "text.bubble.fill"
        case .douban: return "book.closed.fill"
        case .custom: return "star.fill"
        }
    }

    var brandColor: Color {
        switch self {
        case .douyin: return .black
        case .xiaohongshu: return .red
        case .coolapk: return .green
        case .bilibili: return .cyan
        case .github: return .primary
        case .youtube: return .red
        case .weibo: return Color(red: 255/255, green: 96/255, blue: 0/255)
        case .zhihu: return Color(red: 0/255, green: 102/255, blue: 255/255)
        case .douban: return Color(red: 0/255, green: 150/255, blue: 0/255)
        case .custom: return .purple
        }
    }
}
```

- [ ] **Step 2: Build to verify**

Run: `cd /Users/lxh/Documents/mimo && xcodegen generate && xcodebuild -project Archiver.xcodeproj -scheme Archiver build 2>&1 | tail -5`

Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
cd /Users/lxh/Documents/mimo
git add Models/Enums/Platform.swift
git commit -m "feat: add weibo, zhihu, douban to Platform enum"
```

---

## Task 2: Add URL Recognition for Three Platforms

**Files:**
- Modify: `Utilities/URLNormalizer.swift`

- [ ] **Step 1: Add recognition in recognizePlatform()**

Add these blocks before the final `return nil`:

```swift
if lower.contains("weibo.com") || lower.contains("m.weibo.cn") {
    return .weibo
}
if lower.contains("zhihu.com") {
    return .zhihu
}
if lower.contains("douban.com") {
    return .douban
}
```

- [ ] **Step 2: Add YouTube case to normalize()**

The normalize switch needs YouTube too (from the YouTube plan that hasn't been executed yet). Add all four new cases:

```swift
case .youtube:
    return normalizeYouTube(urlString)
case .weibo:
    return normalizeWeibo(urlString)
case .zhihu:
    return normalizeZhihu(urlString)
case .douban:
    return normalizeDouban(urlString)
```

- [ ] **Step 3: Add to extractContentID()**

Add cases:

```swift
case .youtube:
    return extractYouTubeID(urlString)
case .weibo:
    return extractWeiboID(urlString)
case .zhihu:
    return extractZhihuID(urlString)
case .douban:
    return extractDoubanID(urlString)
```

- [ ] **Step 4: Add YouTube private helpers (from YouTube plan)**

```swift
// MARK: - YouTube

private static func normalizeYouTube(_ url: String) -> String {
    if let id = extractYouTubeID(url) {
        return "youtube://video/\(id)"
    }
    return url
}

private static func extractYouTubeID(_ url: String) -> String? {
    let patterns = [
        "youtube\\.com/watch\\?.*v=([a-zA-Z0-9_-]{11})",
        "youtu\\.be/([a-zA-Z0-9_-]{11})",
        "youtube\\.com/embed/([a-zA-Z0-9_-]{11})",
        "youtube\\.com/shorts/([a-zA-Z0-9_-]{11})",
        "youtube\\.com/channel/([a-zA-Z0-9_-]+)",
        "youtube\\.com/@([a-zA-Z0-9._-]+)"
    ]
    return extractFirstMatch(url, patterns: patterns)
}
```

- [ ] **Step 5: Add Weibo helpers**

```swift
// MARK: - 微博

private static func normalizeWeibo(_ url: String) -> String {
    if let id = extractWeiboID(url) {
        return "weibo://status/\(id)"
    }
    return url
}

private static func extractWeiboID(_ url: String) -> String? {
    let patterns = [
        "weibo\\.com/status/(\\d+)",
        "m\\.weibo\\.cn/detail/(\\d+)",
        "m\\.weibo\\.cn/status/(\\d+)"
    ]
    return extractFirstMatch(url, patterns: patterns)
}
```

- [ ] **Step 6: Add Zhihu helpers**

```swift
// MARK: - 知乎

private static func normalizeZhihu(_ url: String) -> String {
    if let id = extractZhihuID(url) {
        return "zhihu://content/\(id)"
    }
    return url
}

private static func extractZhihuID(_ url: String) -> String? {
    let patterns = [
        "zhihu\\.com/question/\\d+/answer/(\\d+)",
        "zhihu\\.com/p/(\\d+)",
        "zhihu\\.com/column/([a-zA-Z0-9_-]+)"
    ]
    return extractFirstMatch(url, patterns: patterns)
}
```

- [ ] **Step 7: Add Douban helpers**

```swift
// MARK: - 豆瓣

private static func normalizeDouban(_ url: String) -> String {
    if let id = extractDoubanID(url) {
        return "douban://subject/\(id)"
    }
    return url
}

private static func extractDoubanID(_ url: String) -> String? {
    let patterns = [
        "douban\\.com/subject/(\\d+)"
    ]
    return extractFirstMatch(url, patterns: patterns)
}
```

- [ ] **Step 8: Build to verify**

Run: `cd /Users/lxh/Documents/mimo && xcodegen generate && xcodebuild -project Archiver.xcodeproj -scheme Archiver build 2>&1 | tail -5`

Expected: BUILD SUCCEEDED

- [ ] **Step 9: Commit**

```bash
cd /Users/lxh/Documents/mimo
git add Utilities/URLNormalizer.swift
git commit -m "feat: add URL recognition for weibo, zhihu, douban, youtube"
```

---

## Task 3: Create WeiboParser

**Files:**
- Create: `Parsers/WeiboParser.swift`

**Parsing strategy:**
- Primary: Fetch `m.weibo.cn/detail/{ID}` → extract `$render_data` JSON → `status.text` (HTML), `status.pic` (image URLs), `status.user.screen_name`, `status.created_at`
- Fallback: Fetch `weibo.com/status/{ID}` → extract `og:title`, `og:description`, `og:image` meta tags
- Images: Replace URL patterns `orj360`, `orj480`, `thumb`, `thumbnail` with `large` to get full-size images

- [ ] **Step 1: Create WeiboParser.swift**

Create `Parsers/WeiboParser.swift` with the following complete content:

```swift
import Foundation

final class WeiboParser: ContentParser, @unchecked Sendable {

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            "Accept-Language": "zh-CN,zh;q=0.9,en;q=0.8",
            "Referer": "https://m.weibo.cn/"
        ]
        return URLSession(configuration: config)
    }()

    func canParse(url: URL) -> Bool {
        let host = url.host?.lowercased() ?? ""
        return host == "weibo.com" || host == "www.weibo.com"
            || host == "m.weibo.cn" || host.hasSuffix(".weibo.com")
    }

    func extractContentID(from url: URL) -> String? {
        URLNormalizer.extractContentID(url.absoluteString, platform: .weibo)
    }

    func normalizeURL(_ url: String) -> String {
        URLNormalizer.normalize(url, platform: .weibo)
    }

    func parse(url: URL) async throws -> ParsedContent {
        guard let statusID = extractWeiboStatusID(from: url) else {
            throw ParserError.parseFailed(reason: "无法从链接提取微博 ID")
        }

        // 优先尝试移动端 m.weibo.cn
        let mobileURL = URL(string: "https://m.weibo.cn/detail/\(statusID)")!
        if let content = try? await parseMobilePage(mobileURL, statusID: statusID) {
            return content
        }

        // 兜底：桌面端
        let desktopURL = URL(string: "https://weibo.com/status/\(statusID)")!
        return try await parseDesktopPage(desktopURL, statusID: statusID)
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

        // 下载正文图片（最多9张）
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

    // MARK: - Mobile Page Parsing (m.weibo.cn)

    private func parseMobilePage(_ url: URL, statusID: String) async throws -> ParsedContent? {
        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            return nil
        }

        guard let html = String(data: data, encoding: .utf8) else {
            return nil
        }

        // 提取 $render_data
        guard let renderDataStr = extractRenderData(from: html) else {
            return nil
        }

        guard let renderData = renderDataStr.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: renderData) as? [String: Any],
              let dataDict = json["data"] as? [String: Any],
              let status = dataDict["status"] as? [String: Any] else {
            return nil
        }

        // 正文（HTML 格式，需去标签）
        let rawText = status["text"] as? String ?? ""
        let text = Self.stripHTML(rawText)

        // 图片
        var imageURLs: [String] = []
        if let pics = status["pics"] as? [[String: Any]] {
            for pic in pics {
                if let large = pic["large"] as? [String: Any],
                   let urlStr = large["url"] as? String {
                    imageURLs.append(urlStr)
                } else if let urlStr = pic["url"] as? String {
                    imageURLs.append(makeWeiboImageLarge(urlStr))
                }
            }
        }

        // 作者
        var author: String?
        var authorID: String?
        if let user = status["user"] as? [String: Any] {
            author = user["screen_name"] as? String
            authorID = user["id_str"] as? String ?? (user["id"] as? Int).map { String($0) }
        }

        // 发布时间
        var publishDate: Date?
        if let createdAt = status["created_at"] as? String {
            publishDate = parseWeiboDate(createdAt)
        }

        let title = text.isEmpty ? "微博 \(statusID)" : String(text.prefix(50))

        return ParsedContent(
            title: title,
            body: text,
            author: author,
            authorID: authorID,
            publishDate: publishDate,
            coverURL: imageURLs.first,
            imageURLs: imageURLs,
            videoURL: nil,
            platformContentID: statusID,
            rawMetadata: ["type": "status"]
        )
    }

    // MARK: - Desktop Page Parsing (weibo.com)

    private func parseDesktopPage(_ url: URL, statusID: String) async throws -> ParsedContent {
        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw ParserError.parseFailed(reason: "HTTP 请求失败")
        }

        guard let html = String(data: data, encoding: .utf8) else {
            throw ParserError.parseFailed(reason: "无法解码页面内容")
        }

        let title = extractMeta(html, property: "og:title")
            ?? "微博 \(statusID)"
        let desc = extractMeta(html, property: "og:description")
        let cover = extractMeta(html, property: "og:image")

        let body = desc.map { Self.stripHTML($0) } ?? ""

        return ParsedContent(
            title: title,
            body: body.isEmpty ? nil : body,
            coverURL: cover,
            platformContentID: statusID,
            rawMetadata: ["type": "status", "source": "desktop"]
        )
    }

    // MARK: - Helpers

    private func extractWeiboStatusID(from url: URL) -> String? {
        let urlString = url.absoluteString
        let patterns = [
            "weibo\\.com/status/(\\d+)",
            "m\\.weibo\\.cn/detail/(\\d+)",
            "m\\.weibo\\.cn/status/(\\d+)"
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: urlString, range: NSRange(urlString.startIndex..., in: urlString)),
               let range = Range(match.range(at: 1), in: urlString) {
                return String(urlString[range])
            }
        }
        return nil
    }

    private func extractRenderData(from html: String) -> String? {
        // m.weibo.cn 的 $render_data 格式: var $render_data = [{...}][0]
        let patterns = [
            "\\$render_data\\s*=\\s*(\\[.*?\\])\\s*\\[0\\]",
            "\\$render_data\\s*=\\s*(\\[.*?\\]);"
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .dotMatchesLineSeparators),
               let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
               let range = Range(match.range(at: 1), in: html) {
                return String(html[range])
            }
        }

        // 也尝试 var $render_data = [{...}][0] 这种格式
        if let startRange = html.range(of: "var $render_data = ") {
            let afterEquals = html[startRange.upperBound...]
            if let bracketStart = afterEquals.firstIndex(of: "["),
               let bracketEnd = afterEquals.firstIndex(of: "]") {
                // 找到第一个完整的数组
                let arrayStr = String(afterEquals[bracketStart...bracketEnd])
                // 解析为 JSON 取第一个元素
                if let arrayData = arrayStr.data(using: .utf8),
                   let array = try? JSONSerialization.jsonObject(with: arrayData) as? [Any],
                   let first = array.first {
                    if let data = try? JSONSerialization.data(withJSONObject: first) {
                        return String(data: data, encoding: .utf8)
                    }
                }
            }
        }

        return nil
    }

    private func makeWeiboImageLarge(_ url: String) -> String {
        var result = url
        let replacements = ["orj360": "large", "orj480": "large", "thumb": "large", "thumbnail": "large"]
        for (old, new) in replacements {
            result = result.replacingOccurrences(of: old, with: new)
        }
        return result
    }

    private func parseWeiboDate(_ dateStr: String) -> Date? {
        // 微博日期格式: "Sun May 28 14:30:00 +0800 2024"
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE MMM dd HH:mm:ss Z yyyy"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.date(from: dateStr)
    }

    private func extractMeta(_ html: String, property: String) -> String? {
        let pattern = "\(property)\"\\s+content=\"([^\"]*)\""
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
        } catch {
            return false
        }
    }

    static func stripHTML(_ html: String) -> String {
        var result = html
        result = result.replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: .regularExpression)
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
```

- [ ] **Step 2: Build to verify**

Run: `cd /Users/lxh/Documents/mimo && xcodegen generate && xcodebuild -project Archiver.xcodeproj -scheme Archiver build 2>&1 | tail -5`

Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
cd /Users/lxh/Documents/mimo
git add Parsers/WeiboParser.swift
git commit -m "feat: add WeiboParser with mobile/desktop fallback"
```

---

## Task 4: Create ZhihuParser

**Files:**
- Create: `Parsers/ZhihuParser.swift`

**Parsing strategy:**
- Answers: Fetch page → extract `window.__INITIAL_STATE__` JSON → `initialState.entities.answers[id].content` (HTML), question title from `question.title`
- Articles: Fetch page → extract `window.__INITIAL_STATE__` JSON → `initialState.entities.articles[id]`
- Columns: Fetch page → extract meta tags → title, description, author
- All HTML content converted to Markdown (images → `![alt](url)` syntax)

- [ ] **Step 1: Create ZhihuParser.swift**

Create `Parsers/ZhihuParser.swift` with the following complete content:

```swift
import Foundation

final class ZhihuParser: ContentParser, @unchecked Sendable {

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            "Accept-Language": "zh-CN,zh;q=0.9,en;q=0.8"
        ]
        return URLSession(configuration: config)
    }()

    func canParse(url: URL) -> Bool {
        let host = url.host?.lowercased() ?? ""
        return host == "zhihu.com" || host == "www.zhihu.com"
    }

    func extractContentID(from url: URL) -> String? {
        URLNormalizer.extractContentID(url.absoluteString, platform: .zhihu)
    }

    func normalizeURL(_ url: String) -> String {
        URLNormalizer.normalize(url, platform: .zhihu)
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

        // 判断类型
        if isAnswerURL(url) {
            return try parseAnswerPage(html, url: url)
        } else if isArticleURL(url) {
            return try parseArticlePage(html, url: url)
        } else if isColumnURL(url) {
            return try parseColumnPage(html, url: url)
        } else {
            // 尝试作为文章解析
            return try parseArticlePage(html, url: url)
        }
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

        // 下载正文图片（最多9张）
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

    // MARK: - Answer Page

    private func parseAnswerPage(_ html: String, url: URL) throws -> ParsedContent {
        guard let initialState = extractInitialState(from: html) else {
            return try parseAnswerMetaFallback(html, url: url)
        }

        guard let jsonData = initialState.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            return try parseAnswerMetaFallback(html, url: url)
        }

        guard let entities = json["entities"] as? [String: Any],
              let answers = entities["answers"] as? [String: Any] else {
            return try parseAnswerMetaFallback(html, url: url)
        }

        // 找到第一个回答
        guard let (_, answerData) = answers.first as? (String, [String: Any]) else {
            return try parseAnswerMetaFallback(html, url: url)
        }

        let content = answerData["content"] as? String ?? ""
        let body = convertHTMLToMarkdown(content)

        // 提问人和问题信息
        var questionTitle: String?
        var questionAuthor: String?
        if let question = answerData["question"] as? [String: Any] {
            questionTitle = question["title"] as? String
            if let author = question["author"] as? [String: Any] {
                questionAuthor = author["name"] as? String
            }
        }

        // 回答者
        var answerAuthor: String?
        var authorID: String?
        if let author = answerData["author"] as? [String: Any] {
            answerAuthor = author["name"] as? String
            authorID = author["urlToken"] as? String
        }

        // 发布时间
        var publishDate: Date?
        if let created = answerData["createdTime"] as? Double {
            publishDate = Date(timeIntervalSince1970: created)
        } else if let updated = answerData["updatedTime"] as? Double {
            publishDate = Date(timeIntervalSince1970: updated)
        }

        let answerID = extractAnswerID(from: url)

        // 构建完整正文：问题 + 回答
        var fullBody = ""
        if let qTitle = questionTitle {
            fullBody += "**问题：** \(qTitle)\n\n"
        }
        fullBody += body

        let title = questionTitle ?? "知乎回答"

        return ParsedContent(
            title: title,
            body: fullBody,
            author: answerAuthor,
            authorID: authorID,
            publishDate: publishDate,
            coverURL: nil,
            imageURLs: extractImagesFromHTML(content),
            videoURL: nil,
            platformContentID: answerID,
            rawMetadata: [
                "type": "answer",
                "questionTitle": questionTitle ?? "",
                "questionAuthor": questionAuthor ?? ""
            ]
        )
    }

    private func parseAnswerMetaFallback(_ html: String, url: URL) throws -> ParsedContent {
        let title = extractMeta(html, property: "og:title")
            ?? extractMeta(html, name: "title")
        let desc = extractMeta(html, property: "og:description")
            ?? extractMeta(html, name: "description")
        let cover = extractMeta(html, property: "og:image")

        let answerID = extractAnswerID(from: url)

        return ParsedContent(
            title: title,
            body: desc,
            coverURL: cover,
            platformContentID: answerID,
            rawMetadata: ["type": "answer", "source": "meta_fallback"]
        )
    }

    // MARK: - Article Page

    private func parseArticlePage(_ html: String, url: URL) throws -> ParsedContent {
        guard let initialState = extractInitialState(from: html) else {
            return try parseArticleMetaFallback(html, url: url)
        }

        guard let jsonData = initialState.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            return try parseArticleMetaFallback(html, url: url)
        }

        guard let entities = json["entities"] as? [String: Any],
              let articles = entities["articles"] as? [String: Any],
              let (_, articleData) = articles.first as? (String, [String: Any]) else {
            return try parseArticleMetaFallback(html, url: url)
        }

        let title = articleData["title"] as? String
        let content = articleData["content"] as? String ?? ""
        let body = convertHTMLToMarkdown(content)

        var author: String?
        var authorID: String?
        if let authorData = articleData["author"] as? [String: Any] {
            author = authorData["name"] as? String
            authorID = authorData["urlToken"] as? String
        }

        var publishDate: Date?
        if let created = articleData["created"] as? Double {
            publishDate = Date(timeIntervalSince1970: created)
        }

        let articleID = extractArticleID(from: url)

        return ParsedContent(
            title: title,
            body: body,
            author: author,
            authorID: authorID,
            publishDate: publishDate,
            coverURL: nil,
            imageURLs: extractImagesFromHTML(content),
            videoURL: nil,
            platformContentID: articleID,
            rawMetadata: ["type": "article"]
        )
    }

    private func parseArticleMetaFallback(_ html: String, url: URL) throws -> ParsedContent {
        let title = extractMeta(html, property: "og:title")
            ?? extractMeta(html, name: "title")
        let desc = extractMeta(html, property: "og:description")
            ?? extractMeta(html, name: "description")
        let cover = extractMeta(html, property: "og:image")

        let articleID = extractArticleID(from: url)

        return ParsedContent(
            title: title,
            body: desc,
            coverURL: cover,
            platformContentID: articleID,
            rawMetadata: ["type": "article", "source": "meta_fallback"]
        )
    }

    // MARK: - Column Page

    private func parseColumnPage(_ html: String, url: URL) throws -> ParsedContent {
        let title = extractMeta(html, property: "og:title")
            ?? extractMeta(html, name: "title")
        let desc = extractMeta(html, property: "og:description")
            ?? extractMeta(html, name: "description")
        let cover = extractMeta(html, property: "og:image")

        let columnID = extractColumnID(from: url)

        guard title != nil || desc != nil else {
            throw ParserError.parseFailed(reason: "无法提取专栏信息")
        }

        return ParsedContent(
            title: title,
            body: desc,
            coverURL: cover,
            platformContentID: columnID,
            rawMetadata: ["type": "column"]
        )
    }

    // MARK: - Helpers

    private func isAnswerURL(_ url: URL) -> Bool {
        return url.path.contains("/question/") && url.path.contains("/answer/")
    }

    private func isArticleURL(_ url: URL) -> Bool {
        return url.path.hasPrefix("/p/")
    }

    private func isColumnURL(_ url: URL) -> Bool {
        return url.path.hasPrefix("/column/")
    }

    private func extractAnswerID(from url: URL) -> String? {
        let patterns = ["zhihu\\.com/question/\\d+/answer/(\\d+)"]
        return extractFirstMatch(url.absoluteString, patterns: patterns)
    }

    private func extractArticleID(from url: URL) -> String? {
        let patterns = ["zhihu\\.com/p/(\\d+)"]
        return extractFirstMatch(url.absoluteString, patterns: patterns)
    }

    private func extractColumnID(from url: String) -> String? {
        let patterns = ["zhihu\\.com/column/([a-zA-Z0-9_-]+)"]
        return extractFirstMatch(url, patterns: patterns)
    }

    private func extractInitialState(from html: String) -> String? {
        let patterns = [
            "window\\.__INITIAL_STATE__\\s*=\\s*(\\{.+?\\})\\s*;\\s*<",
            "window\\.__INITIAL_STATE__\\s*=\\s*(\\{.+?\\});\\s*</script>"
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .dotMatchesLineSeparators),
               let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
               let range = Range(match.range(at: 1), in: html) {
                return String(html[range])
            }
        }

        // 更宽松的匹配
        if let startRange = html.range(of: "window.__INITIAL_STATE__=") {
            var braceCount = 0
            var foundOpening = false
            var endIndex = startRange.upperBound

            for char in html[startRange.upperBound...] {
                if char == "{" {
                    braceCount += 1
                    foundOpening = true
                } else if char == "}" {
                    braceCount -= 1
                }
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

    private func convertHTMLToMarkdown(_ html: String) -> String {
        var text = html
        // 转换 img 标签为 Markdown 图片语法
        text = text.replacingOccurrences(
            of: #"<img[^>]*data-original="([^"]*)"[^>]*>"#,
            with: "![]($1)",
            options: .regularExpression
        )
        text = text.replacingOccurrences(
            of: #"<img[^>]*src="([^"]*)"[^>]*>"#,
            with: "![]($1)",
            options: .regularExpression
        )
        // 常用 HTML 标签转换
        text = text.replacingOccurrences(of: #"<br\s*/?>"#, with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "</p>", with: "\n\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "</div>", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: #"<h[1-6][^>]*>"#, with: "\n## ", options: .regularExpression)
        text = text.replacingOccurrences(of: #"</h[1-6]>"#, with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "<b>", with: "**", options: .caseInsensitive)
        text = text.replacingOccurrences(of: "</b>", with: "**", options: .caseInsensitive)
        text = text.replacingOccurrences(of: "<strong>", with: "**", options: .caseInsensitive)
        text = text.replacingOccurrences(of: "</strong>", with: "**", options: .caseInsensitive)
        text = text.replacingOccurrences(of: "<i>", with: "*", options: .caseInsensitive)
        text = text.replacingOccurrences(of: "</i>", with: "*", options: .caseInsensitive)
        text = text.replacingOccurrences(of: "<em>", with: "*", options: .caseInsensitive)
        text = text.replacingOccurrences(of: "</em>", with: "*", options: .caseInsensitive)
        text = text.replacingOccurrences(of: #"<li[^>]*>"#, with: "- ", options: .regularExpression)
        text = text.replacingOccurrences(of: "</li>", with: "\n", options: .regularExpression)
        // 去除剩余 HTML 标签
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
            #"src="(https?://[^"]*\.(jpg|jpeg|png|gif|webp)[^"]*)""#
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let matches = regex.matches(in: html, range: NSRange(html.startIndex..., in: html))
                for match in matches {
                    if let range = Range(match.range(at: 1), in: html) {
                        let url = String(html[range])
                        if !urls.contains(url) {
                            urls.append(url)
                        }
                    }
                }
            }
        }
        return Array(urls.prefix(9))
    }

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

    private func extractFirstMatch(_ text: String, patterns: [String]) -> String? {
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               let range = Range(match.range(at: 1), in: text) {
                return String(text[range])
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
```

- [ ] **Step 2: Build to verify**

Run: `cd /Users/lxh/Documents/mimo && xcodegen generate && xcodebuild -project Archiver.xcodeproj -scheme Archiver build 2>&1 | tail -5`

Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
cd /Users/lxh/Documents/mimo
git add Parsers/ZhihuParser.swift
git commit -m "feat: add ZhihuParser with answer, article, column support"
```

---

## Task 5: Create DoubanParser

**Files:**
- Create: `Parsers/DoubanParser.swift`

**Parsing strategy:**
- Book/Movie/Music: Fetch `douban.com/subject/{ID}` → extract `application/ld+json` structured data or `window.__DATA__` JSON → title, rating, review, cover, author
- Fallback: meta tags (`og:title`, `og:description`, `og:image`)
- Reserved: group posts (`douban.com/group/topic/ID`), diary (`douban.com/note/ID`) — URL recognized but returns parseFailed for now

- [ ] **Step 1: Create DoubanParser.swift**

Create `Parsers/DoubanParser.swift` with the following complete content:

```swift
import Foundation

final class DoubanParser: ContentParser, @unchecked Sendable {

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            "Accept-Language": "zh-CN,zh;q=0.9,en;q=0.8"
        ]
        return URLSession(configuration: config)
    }()

    func canParse(url: URL) -> Bool {
        let host = url.host?.lowercased() ?? ""
        return host == "douban.com" || host == "www.douban.com"
    }

    func extractContentID(from url: URL) -> String? {
        URLNormalizer.extractContentID(url.absoluteString, platform: .douban)
    }

    func normalizeURL(_ url: String) -> String {
        URLNormalizer.normalize(url, platform: .douban)
    }

    func parse(url: URL) async throws -> ParsedContent {
        // 只支持 subject 页面（书/影/音）
        if isSubjectURL(url) {
            return try await parseSubjectPage(url)
        }

        // 预留：小组帖子、日记文章
        if isGroupTopicURL(url) || isNoteURL(url) {
            throw ParserError.parseFailed(reason: "暂不支持该类型页面，后续版本将支持")
        }

        throw ParserError.parseFailed(reason: "无法识别的豆瓣链接类型")
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

        return assets
    }

    // MARK: - Subject Page (书/影/音)

    private func parseSubjectPage(_ url: URL) async throws -> ParsedContent {
        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw ParserError.parseFailed(reason: "HTTP 请求失败")
        }

        guard let html = String(data: data, encoding: .utf8) else {
            throw ParserError.parseFailed(reason: "无法解码页面内容")
        }

        // 尝试 application/ld+json
        if let content = extractFromLDJSON(html, url: url) {
            return content
        }

        // 尝试 window.__DATA__
        if let content = extractFromWindowData(html, url: url) {
            return content
        }

        // 兜底：meta 标签
        return extractFromMetaTags(html, url: url)
    }

    private func extractFromLDJSON(_ html: String, url: URL) -> ParsedContent? {
        let pattern = #"application/ld\+json[^>]*>([^<]*)<"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .dotMatchesLineSeparators),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let range = Range(match.range(at: 1), in: html) else {
            return nil
        }

        let jsonStr = String(html[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let jsonData = jsonStr.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            return nil
        }

        let title = json["name"] as? String

        var body = ""
        if let description = json["description"] as? String {
            body = description
        }

        // 评分
        var rating: String?
        if let aggregateRating = json["aggregateRating"] as? [String: Any],
           let ratingValue = aggregateRating["ratingValue"] as? String {
            rating = "评分: \(ratingValue)"
        }

        if var ratingStr = rating {
            if !body.isEmpty { ratingStr = "\n\n\(ratingStr)" }
            body += ratingStr
        }

        // 作者
        var author: String?
        if let authorData = json["author"] as? [String: Any] {
            author = authorData["name"] as? String
        } else if let authorStr = json["author"] as? String {
            author = authorStr
        }

        // 封面
        var coverURL: String?
        if let image = json["image"] as? String {
            coverURL = image
        }

        let subjectID = extractSubjectID(from: url)

        return ParsedContent(
            title: title,
            body: body.isEmpty ? nil : body,
            author: author,
            coverURL: coverURL,
            platformContentID: subjectID,
            rawMetadata: ["type": "subject", "source": "ld+json"]
        )
    }

    private func extractFromWindowData(_ html: String, url: URL) -> ParsedContent? {
        guard let startRange = html.range(of: "window.__DATA__ = ") else {
            return nil
        }

        var braceCount = 0
        var foundOpening = false
        var endIndex = startRange.upperBound

        for char in html[startRange.upperBound...] {
            if char == "{" {
                braceCount += 1
                foundOpening = true
            } else if char == "}" {
                braceCount -= 1
            }
            if foundOpening && braceCount == 0 { break }
            endIndex = html.index(after: endIndex)
            if endIndex >= html.endIndex { break }
        }

        guard foundOpening && braceCount == 0 else { return nil }

        let jsonStr = String(html[startRange.upperBound..<endIndex])
        guard let jsonData = jsonStr.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            return nil
        }

        // window.__DATA__ 的结构因页面而异，这里做基本提取
        let title = json["title"] as? String
        var body = json["description"] as? String ?? json["summary"] as? String ?? ""
        let coverURL = json["cover"] as? String ?? json["image"] as? String
        var author = json["author"] as? String ?? json["directors"] as? String

        // 尝试从嵌套结构获取
        if let subject = json["subject"] as? [String: Any] {
            let title2 = subject["title"] as? String
            let body2 = subject["description"] as? String ?? subject["summary"] as? String ?? ""
            let cover2 = subject["cover"] as? String ?? subject["image"] as? String
            let author2 = subject["author"] as? String

            if title2 != nil { body = body2 }
            if !body2.isEmpty { body = body2 }
            if cover2 != nil { }
            if author2 != nil { author = author2 }
        }

        let subjectID = extractSubjectID(from: url)

        return ParsedContent(
            title: title,
            body: body.isEmpty ? nil : body,
            author: author,
            coverURL: coverURL,
            platformContentID: subjectID,
            rawMetadata: ["type": "subject", "source": "window_data"]
        )
    }

    private func extractFromMetaTags(_ html: String, url: URL) -> ParsedContent {
        let title = extractMeta(html, property: "og:title")
        let desc = extractMeta(html, property: "og:description")
            ?? extractMeta(html, name: "description")
        let cover = extractMeta(html, property: "og:image")
        let author = extractMeta(html, name: "author")

        let subjectID = extractSubjectID(from: url)

        return ParsedContent(
            title: title,
            body: desc,
            author: author,
            coverURL: cover,
            platformContentID: subjectID,
            rawMetadata: ["type": "subject", "source": "meta"]
        )
    }

    // MARK: - URL Type Detection

    private func isSubjectURL(_ url: URL) -> Bool {
        return url.path.contains("/subject/")
    }

    private func isGroupTopicURL(_ url: URL) -> Bool {
        return url.path.contains("/group/topic/")
    }

    private func isNoteURL(_ url: URL) -> Bool {
        return url.path.contains("/note/")
    }

    private func extractSubjectID(from url: URL) -> String? {
        let patterns = ["douban\\.com/subject/(\\d+)"]
        return extractFirstMatch(url.absoluteString, patterns: patterns)
    }

    // MARK: - Helpers

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

    private func extractFirstMatch(_ text: String, patterns: [String]) -> String? {
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               let range = Range(match.range(at: 1), in: text) {
                return String(text[range])
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
```

- [ ] **Step 2: Build to verify**

Run: `cd /Users/lxh/Documents/mimo && xcodegen generate && xcodebuild -project Archiver.xcodeproj -scheme Archiver build 2>&1 | tail -5`

Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
cd /Users/lxh/Documents/mimo
git add Parsers/DoubanParser.swift
git commit -m "feat: add DoubanParser with subject page and reserved interfaces"
```

---

## Task 6: Register All Three Parsers in PlatformRouter

**Files:**
- Modify: `Parsers/PlatformRouter.swift`

- [ ] **Step 1: Add parsers to the array**

```swift
private init() {
    parsers = [
        DouyinParser(),
        XiaohongshuParser(),
        CoolapkParser(),
        BilibiliParser(),
        GitHubParser(),
        YouTubeParser(),
        WeiboParser(),
        ZhihuParser(),
        DoubanParser()
    ]
}
```

- [ ] **Step 2: Build to verify**

Run: `cd /Users/lxh/Documents/mimo && xcodegen generate && xcodebuild -project Archiver.xcodeproj -scheme Archiver build 2>&1 | tail -5`

Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
cd /Users/lxh/Documents/mimo
git add Parsers/PlatformRouter.swift
git commit -m "feat: register weibo, zhihu, douban parsers in PlatformRouter"
```

---

## Task 7: End-to-End Smoke Test

**Files:** None (testing only)

- [ ] **Step 1: Full build**

Run: `cd /Users/lxh/Documents/mimo && xcodegen generate && xcodebuild -project Archiver.xcodeproj -scheme Archiver build 2>&1 | tail -5`

Expected: BUILD SUCCEEDED

- [ ] **Step 2: Manual test - Weibo**

1. Run the app
2. Paste a Weibo status URL (e.g., `https://weibo.com/status/4988881234567` or `https://m.weibo.cn/detail/4988881234567`)
3. Verify: platform detected as 微博
4. Verify: text + images saved
5. Verify: content appears under 微博 platform

- [ ] **Step 3: Manual test - Zhihu Answer**

1. Paste a Zhihu answer URL (e.g., `https://www.zhihu.com/question/123456/answer/789012`)
2. Verify: question title + answer body saved
3. Verify: author saved
4. Verify: body renders with Markdown + inline images

- [ ] **Step 4: Manual test - Zhihu Article**

1. Paste a Zhihu article URL (e.g., `https://www.zhihu.com/p/12345678`)
2. Verify: title + article body saved
3. Verify: images render inline

- [ ] **Step 5: Manual test - Douban**

1. Paste a Douban subject URL (e.g., `https://movie.douban.com/subject/12345678/`)
2. Verify: title + description + cover saved
3. Verify: content appears under 豆瓣 platform

- [ ] **Step 6: Manual test - Duplicate detection**

1. Re-import any of the above URLs
2. Verify: duplicate message shown

- [ ] **Step 7: Final commit**

```bash
cd /Users/lxh/Documents/mimo
git add -A
git commit -m "feat: weibo, zhihu, douban platform support complete"
```

---

## Notes

- **Weibo mobile优先**: 微博解析器优先使用 `m.weibo.cn` 端，数据更结构化。桌面端作为兜底
- **Zhihu Markdown**: 知乎正文的 HTML 自动转换为 Markdown（加粗、图片、换行），通过 MarkdownView 渲染
- **Douban reserved**: 小组帖子和日记文章的 URL 识别已预留，返回友好错误提示
- **No video download**: 三个平台都不做视频下载，只保存元数据 + 图片
- **Image optimization**: 微博图片 URL 自动替换为原图（`large`）；知乎图片支持 `data-original` 属性（懒加载原图）
