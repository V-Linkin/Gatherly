# YouTube Platform Support Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add YouTube as a supported platform in 拾屿 Archiver, supporting video links and channel pages with embedded JSON parsing (no API key required).

**Architecture:** Follow the existing parser pattern (ContentParser protocol + PlatformRouter registration). YouTubeParser extracts `ytInitialPlayerResponse` (videos) and `ytInitialData` (channels) from page HTML, similar to how BilibiliParser extracts `window.__INITIAL_STATE__`. No new dependencies.

**Tech Stack:** Swift 6.0, URLSession, JSONSerialization (same as existing parsers)

---

## Files Overview

| Action | File | Purpose |
|--------|------|---------|
| Modify | `Models/Enums/Platform.swift` | Add `.youtube` case to Platform enum |
| Modify | `Utilities/URLNormalizer.swift` | Add YouTube URL recognition, normalization, and content ID extraction |
| Create | `Parsers/YouTubeParser.swift` | New parser: video pages + channel pages |
| Modify | `Parsers/PlatformRouter.swift` | Register YouTubeParser in parsers array |

---

## Task 1: Add `.youtube` to Platform Enum

**Files:**
- Modify: `Models/Enums/Platform.swift`

- [ ] **Step 1: Add `.youtube` case**

Add `.youtube` after `.github` in the enum:

```swift
// Models/Enums/Platform.swift

enum Platform: String, Codable, CaseIterable, Identifiable {
    case douyin
    case xiaohongshu
    case coolapk
    case bilibili
    case github
    case youtube
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
        case .custom: return .purple
        }
    }
}
```

- [ ] **Step 2: Build to verify no compile errors**

Run: `cd /Users/lxh/Documents/mimo && xcodegen generate && xcodebuild -project Archiver.xcodeproj -scheme Archiver build 2>&1 | tail -5`

Expected: BUILD SUCCEEDED (the Platform enum cases are exhaustive, so existing switch statements may show warnings but should still compile since all existing switches cover the enum).

- [ ] **Step 3: Commit**

```bash
cd /Users/lxh/Documents/mimo
git add Models/Enums/Platform.swift
git commit -m "feat: add YouTube case to Platform enum"
```

---

## Task 2: Add YouTube URL Recognition to URLNormalizer

**Files:**
- Modify: `Utilities/URLNormalizer.swift`

- [ ] **Step 1: Add YouTube cases to recognizePlatform**

In `URLNormalizer.swift`, add YouTube detection in `recognizePlatform()`:

```swift
// In recognizePlatform(), add before the final `return nil`:
if lower.contains("youtube.com") || lower.contains("youtu.be") {
    return .youtube
}
```

The complete function should look like:

```swift
static func recognizePlatform(_ urlString: String) -> Platform? {
    let lower = urlString.lowercased()

    if lower.contains("douyin.com") || lower.contains("iesdouyin.com") {
        return .douyin
    }
    if lower.contains("xiaohongshu.com") || lower.contains("xhslink.com") {
        return .xiaohongshu
    }
    if lower.contains("coolapk.com") || lower.contains("coolapk1s.com") {
        return .coolapk
    }
    if lower.contains("bilibili.com") || lower.contains("b23.tv") {
        return .bilibili
    }
    if lower.contains("github.com") {
        return .github
    }
    if lower.contains("youtube.com") || lower.contains("youtu.be") {
        return .youtube
    }

    return nil
}
```

- [ ] **Step 2: Add YouTube cases to normalize()**

In `normalize()`, add:

```swift
case .youtube:
    return normalizeYouTube(urlString)
```

- [ ] **Step 3: Add YouTube cases to extractContentID()**

In `extractContentID()`, add:

```swift
case .youtube:
    return extractYouTubeID(urlString)
```

- [ ] **Step 4: Add YouTube private helper methods**

Add these methods to URLNormalizer:

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
        // youtube.com/watch?v=VIDEO_ID
        "youtube\\.com/watch\\?.*v=([a-zA-Z0-9_-]{11})",
        // youtu.be/VIDEO_ID
        "youtu\\.be/([a-zA-Z0-9_-]{11})",
        // youtube.com/embed/VIDEO_ID
        "youtube\\.com/embed/([a-zA-Z0-9_-]{11})",
        // youtube.com/shorts/VIDEO_ID
        "youtube\\.com/shorts/([a-zA-Z0-9_-]{11})",
        // youtube.com/channel/CHANNEL_ID
        "youtube\\.com/channel/([a-zA-Z0-9_-]+)",
        // youtube.com/@handle
        "youtube\\.com/@([a-zA-Z0-9._-]+)",
        // youtube.com/c/NAME
        "youtube\\.com/c/([a-zA-Z0-9._-]+)",
        // youtube.com/user/NAME
        "youtube\\.com/user/([a-zA-Z0-9._-]+)"
    ]
    return extractFirstMatch(url, patterns: patterns)
}
```

- [ ] **Step 5: Build to verify**

Run: `cd /Users/lxh/Documents/mimo && xcodegen generate && xcodebuild -project Archiver.xcodeproj -scheme Archiver build 2>&1 | tail -5`

Expected: BUILD SUCCEEDED

- [ ] **Step 6: Commit**

```bash
cd /Users/lxh/Documents/mimo
git add Utilities/URLNormalizer.swift
git commit -m "feat: add YouTube URL recognition and normalization"
```

---

## Task 3: Create YouTubeParser

**Files:**
- Create: `Parsers/YouTubeParser.swift`

This is the core task. The parser handles two types of YouTube content:

### Video Pages

YouTube embeds a `ytInitialPlayerResponse` JSON object in the HTML `<script>` tag. Key paths:

```
ytInitialPlayerResponse.videoDetails.title
ytInitialPlayerResponse.videoDetails.lengthSeconds
ytInitialPlayerResponse.videoDetails.shortDescription
ytInitialPlayerResponse.videoDetails.channelId
ytInitialPlayerResponse.videoDetails.author
ytInitialPlayerResponse.videoDetails.thumbnail.thumbnails[].url
ytInitialPlayerResponse.microformat.playerMicroformatRenderer.publishDate
ytInitialPlayerResponse.microformat.playerMicroformatRenderer.uploadDate
```

### Channel Pages

YouTube embeds `ytInitialData` JSON. For channels, the structure is under header:

```
ytInitialData.header.c4TabbedHeaderRenderer.title
ytInitialData.header.c4TabbedHeaderRenderer.avatar.thumbnails[].url
ytInitialData.metadata.channelMetadataRenderer.description
ytInitialData.metadata.channelMetadataRenderer.vanityChannelUrl
```

- [ ] **Step 1: Create YouTubeParser.swift**

Create file `Parsers/YouTubeParser.swift` with the following complete content:

```swift
import Foundation

final class YouTubeParser: ContentParser, @unchecked Sendable {

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
            "Accept-Language": "en-US,en;q=0.9",
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
        ]
        return URLSession(configuration: config)
    }()

    // MARK: - ContentParser

    func canParse(url: URL) -> Bool {
        let host = url.host?.lowercased() ?? ""
        return host == "youtube.com" || host == "www.youtube.com"
            || host == "youtu.be" || host.hasSuffix(".youtube.com")
    }

    func extractContentID(from url: URL) -> String? {
        URLNormalizer.extractContentID(url.absoluteString, platform: .youtube)
    }

    func normalizeURL(_ url: String) -> String {
        URLNormalizer.normalize(url, platform: .youtube)
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

        // 判断是视频页面还是频道页面
        if isVideoURL(url) {
            return try parseVideoPage(html, url: url)
        } else if isChannelURL(url) {
            return try parseChannelPage(html, url: url)
        } else {
            // 尝试作为视频页面解析
            return try parseVideoPage(html, url: url)
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

        return assets
    }

    // MARK: - Video Parsing

    private func parseVideoPage(_ html: String, url: URL) throws -> ParsedContent {
        guard let jsonStr = extractJSON(html: html, key: "ytInitialPlayerResponse") else {
            throw ParserError.parseFailed(reason: "无法提取视频数据")
        }

        guard let jsonData = jsonStr.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            throw ParserError.parseFailed(reason: "无法解析视频 JSON 数据")
        }

        var title: String?
        var description: String?
        var author: String?
        var authorID: String?
        var coverURL: String?
        var publishDate: Date?

        // videoDetails
        if let videoDetails = json["videoDetails"] as? [String: Any] {
            title = videoDetails["title"] as? String
            description = videoDetails["shortDescription"] as? String
            author = videoDetails["author"] as? String
            authorID = videoDetails["channelId"] as? String

            if let thumbnails = videoDetails["thumbnail"] as? [String: Any],
               let thumbnailList = thumbnails["thumbnails"] as? [[String: Any]],
               let bestThumbnail = thumbnailList.last,
               let thumbURL = bestThumbnail["url"] as? String {
                coverURL = thumbURL
            }
        }

        // microformat
        if let microformat = json["microformat"] as? [String: Any],
           let playerMicro = microformat["playerMicroformatRenderer"] as? [String: Any] {
            if publishDate == nil {
                let dateStr = playerMicro["publishDate"] as? String
                    ?? playerMicro["uploadDate"] as? String
                if let dateStr {
                    publishDate = parseYouTubeDate(dateStr)
                }
            }
            if description == nil {
                description = playerMicro["description"] as? [String: Any]
                    .flatMap { $0["simpleText"] as? String }
            }
        }

        let contentID = extractVideoID(from: url)

        return ParsedContent(
            title: title,
            body: description,
            author: author,
            authorID: authorID,
            publishDate: publishDate,
            coverURL: coverURL,
            imageURLs: [],
            videoURL: url.absoluteString,
            platformContentID: contentID,
            rawMetadata: [
                "type": "video",
                "channelID": authorID ?? ""
            ]
        )
    }

    // MARK: - Channel Parsing

    private func parseChannelPage(_ html: String, url: URL) throws -> ParsedContent {
        guard let jsonStr = extractJSON(html: html, key: "ytInitialData") else {
            throw ParserError.parseFailed(reason: "无法提取频道数据")
        }

        guard let jsonData = jsonStr.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            throw ParserError.parseFailed(reason: "无法解析频道 JSON 数据")
        }

        var title: String?
        var description: String?
        var avatarURL: String?
        var channelID: String?

        // header.c4TabbedHeaderRenderer
        if let header = json["header"] as? [String: Any],
           let c4Header = header["c4TabbedHeaderRenderer"] as? [String: Any] {
            title = c4Header["title"] as? String

            if let avatar = c4Header["avatar"] as? [String: Any],
               let thumbnails = avatar["thumbnails"] as? [[String: Any]],
               let bestAvatar = thumbnails.last,
               let avatarStr = bestAvatar["url"] as? String {
                avatarURL = avatarStr
            }

            channelID = c4Header["channelId"] as? String
        }

        // metadata.channelMetadataRenderer
        if let metadata = json["metadata"] as? [String: Any],
           let channelMeta = metadata["channelMetadataRenderer"] as? [String: Any] {
            if title == nil {
                title = channelMeta["title"] as? String
            }
            description = channelMeta["description"] as? String
            if channelID == nil {
                channelID = channelMeta["externalId"] as? String
            }
            if avatarURL == nil {
                avatarURL = channelMeta["avatar"] as? [String: Any]
                    .flatMap { $0["thumbnails"] as? [[String: Any]] }
                    .flatMap { $0.last }
                    .flatMap { $0["url"] as? String }
            }
        }

        guard title != nil else {
            throw ParserError.parseFailed(reason: "无法提取频道名称")
        }

        let contentID = channelID ?? extractChannelHandle(from: url)

        return ParsedContent(
            title: title,
            body: description,
            author: title,
            authorID: contentID,
            publishDate: nil,
            coverURL: avatarURL,
            imageURLs: avatarURL.isEmpty ? [] : [avatarURL],
            videoURL: nil,
            platformContentID: contentID,
            rawMetadata: [
                "type": "channel",
                "channelID": contentID ?? ""
            ]
        )
    }

    // MARK: - Helpers

    private func isVideoURL(_ url: URL) -> Bool {
        let path = url.path
        let host = url.host?.lowercased() ?? ""

        // youtu.be short links are always videos
        if host == "youtu.be" { return true }

        // youtube.com/watch, youtube.com/shorts, youtube.com/embed
        if path.contains("/watch") || path.contains("/shorts/") || path.contains("/embed/") {
            return true
        }

        // Check for v= parameter
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let queryItems = components.queryItems,
           queryItems.contains(where: { $0.name == "v" }) {
            return true
        }

        return false
    }

    private func isChannelURL(_ url: URL) -> Bool {
        let path = url.path
        return path.contains("/channel/") || path.contains("/@")
            || path.contains("/c/") || path.contains("/user/")
    }

    private func extractVideoID(from url: URL) -> String? {
        // Try path first
        let patterns = [
            "/watch\\?.*v=([a-zA-Z0-9_-]{11})",
            "youtu\\.be/([a-zA-Z0-9_-]{11})",
            "/embed/([a-zA-Z0-9_-]{11})",
            "/shorts/([a-zA-Z0-9_-]{11})"
        ]
        let urlString = url.absoluteString
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: urlString, range: NSRange(urlString.startIndex..., in: urlString)),
               let range = Range(match.range(at: 1), in: urlString) {
                return String(urlString[range])
            }
        }
        return nil
    }

    private func extractChannelHandle(from url: URL) -> String? {
        let path = url.path
        if let range = path.range(of: "/@") {
            return String(path[range.upperBound...])
        }
        if let range = path.range(of: "/channel/") {
            return String(path[range.upperBound...])
        }
        if let range = path.range(of: "/c/") {
            return String(path[range.upperBound...])
        }
        if let range = path.range(of: "/user/") {
            return String(path[range.upperBound...])
        }
        return nil
    }

    /// 从 HTML 中提取 `varName = {...};` 格式的 JSON
    private func extractJSON(html: String, key: String) -> String? {
        let searchPatterns = [
            "var \(key) = ",
            "\(key) = ",
            "window[\(key)] = "
        ]

        for pattern in searchPatterns {
            guard let startRange = html.range(of: pattern) else { continue }

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

                if foundOpening && braceCount == 0 {
                    break
                }
                endIndex = html.index(after: endIndex)
                if endIndex >= html.endIndex { break }
            }

            if foundOpening && braceCount == 0 {
                return String(html[startRange.upperBound..<endIndex])
            }
        }

        return nil
    }

    private func parseYouTubeDate(_ dateStr: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.date(from: dateStr)
    }

    private func downloadFile(from url: URL, to localPath: URL) async -> Bool {
        do {
            let (data, _) = try await session.data(from: url)
            try data.write(to: localPath)
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
git add Parsers/YouTubeParser.swift
git commit -m "feat: add YouTubeParser with video and channel page support"
```

---

## Task 4: Register YouTubeParser in PlatformRouter

**Files:**
- Modify: `Parsers/PlatformRouter.swift`

- [ ] **Step 1: Add YouTubeParser to parsers array**

In `PlatformRouter.swift`, add `YouTubeParser()` to the parsers array:

```swift
private init() {
    parsers = [
        DouyinParser(),
        XiaohongshuParser(),
        CoolapkParser(),
        BilibiliParser(),
        GitHubParser(),
        YouTubeParser()
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
git commit -m "feat: register YouTubeParser in PlatformRouter"
```

---

## Task 5: End-to-End Smoke Test

**Files:** None (testing only)

- [ ] **Step 1: Build the full app**

Run: `cd /Users/lxh/Documents/mimo && xcodegen generate && xcodebuild -project Archiver.xcodeproj -scheme Archiver build 2>&1 | tail -5`

Expected: BUILD SUCCEEDED

- [ ] **Step 2: Manual test - Video URL**

1. Run the app
2. Paste a YouTube video URL (e.g., `https://www.youtube.com/watch?v=dQw4w9WgXcQ`)
3. Verify: platform auto-detected as YouTube
4. Verify: title, description, author, cover thumbnail are saved
5. Verify: content appears in YouTube platform (or custom platform named "YouTube")
6. Verify: cover image downloads and displays

- [ ] **Step 3: Manual test - Channel URL**

1. Paste a YouTube channel URL (e.g., `https://www.youtube.com/@mkbhd`)
2. Verify: platform auto-detected as YouTube
3. Verify: channel name, description, avatar are saved
4. Verify: content appears under YouTube platform

- [ ] **Step 4: Manual test - Duplicate detection**

1. Re-import the same YouTube video URL
2. Verify: shows duplicate message instead of creating a new record

- [ ] **Step 5: Final commit**

```bash
cd /Users/lxh/Documents/mimo
git add -A
git commit -m "feat: YouTube platform support - video and channel parsing complete"
```

---

## Notes

- **No API key required**: All data is extracted from the HTML page itself
- **YouTube anti-scraping**: The parser uses proper User-Agent and Accept headers. If YouTube changes their HTML structure in the future, the `extractJSON` method may need updating
- **Video download not supported**: YouTube video downloading is intentionally not included (complex, legal concerns). The app saves metadata + cover image only
- **Channel content type**: Channel items are saved with `rawMetadata["type"] = "channel"` to distinguish from video items in the detail view
