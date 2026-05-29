# GitHub Platform Support + Markdown Rendering Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add GitHub as a supported platform (repo links: README + author + URL), and enable Markdown rendering for body text across all platforms.

**Architecture:** New `GitHubParser` follows the existing `ContentParser` protocol pattern. GitHub API (no auth) fetches repo metadata and README. `MarkdownView` uses `AttributedString(from: markdown)` for zero-dependency Markdown rendering. Auto-platform matching uses the existing `findMatchingCustomPlatform` mechanism.

**Tech Stack:** Swift 6.0, SwiftUI, URLSession (GitHub REST API v3), AttributedString (Markdown)

---

## File Structure

| Action | File | Purpose |
|--------|------|---------|
| Create | `Parsers/GitHubParser.swift` | GitHub content parser |
| Create | `Views/Components/MarkdownView.swift` | Reusable Markdown renderer |
| Modify | `Models/Enums/Platform.swift` | Add `.github` case |
| Modify | `Utilities/URLNormalizer.swift` | Recognize GitHub URLs |
| Modify | `Parsers/PlatformRouter.swift` | Register GitHubParser |
| Modify | `Views/Item/ItemDetailView.swift` | Use MarkdownView for body |

---

### Task 1: Add `.github` to Platform Enum

**Files:**
- Modify: `Models/Enums/Platform.swift`

- [ ] **Step 1: Add the `.github` case**

Add a new case to the `Platform` enum:

```swift
enum Platform: String, Codable, CaseIterable, Identifiable {
    case douyin
    case xiaohongshu
    case coolapk
    case bilibili
    case github
    case custom
```

Update `defaultDisplayName`:

```swift
var defaultDisplayName: String {
    switch self {
    case .douyin: return "抖音"
    case .xiaohongshu: return "小红书"
    case .coolapk: return "酷安"
    case .bilibili: return "B站"
    case .github: return "GitHub"
    case .custom: return "自定义"
    }
}
```

Update `iconName`:

```swift
var iconName: String {
    switch self {
    case .douyin: return "music.note"
    case .xiaohongshu: return "book.fill"
    case .coolapk: return "apps.iphone"
    case .bilibili: return "play.tv"
    case .github: return "chevron.left.forwardslash.chevron.right"
    case .custom: return "star.fill"
    }
}
```

Update `brandColor`:

```swift
var brandColor: Color {
    switch self {
    case .douyin: return .black
    case .xiaohongshu: return .red
    case .coolapk: return .green
    case .bilibili: return .cyan
    case .github: return .primary
    case .custom: return .purple
    }
}
```

- [ ] **Step 2: Build and verify no compile errors**

Run: `cd /Users/lxh/Documents/mimo && xcodegen generate && xcodebuild -project Archiver.xcodeproj -scheme Archiver -configuration Debug build 2>&1 | tail -5`

Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
git add Models/Enums/Platform.swift
git commit -m "feat: add .github platform enum case"
```

---

### Task 2: Add GitHub URL Recognition to URLNormalizer

**Files:**
- Modify: `Utilities/URLNormalizer.swift`

- [ ] **Step 1: Add GitHub domain recognition**

In `recognizePlatform`, add a new block after the bilibili check:

```swift
if lower.contains("github.com") {
    return .github
}
```

- [ ] **Step 2: Add GitHub case to `normalize` switch**

```swift
case .github:
    return normalizeGitHub(urlString)
```

- [ ] **Step 3: Add GitHub case to `extractContentID` switch**

```swift
case .github:
    return extractGitHubID(urlString)
```

- [ ] **Step 4: Add GitHub normalization and ID extraction methods**

Add these private methods in a `// MARK: - GitHub` section:

```swift
// MARK: - GitHub

private static func normalizeGitHub(_ url: String) -> String {
    if let id = extractGitHubID(url) {
        return "github://repo/\(id)"
    }
    return url
}

private static func extractGitHubID(_ url: String) -> String? {
    let patterns = [
        "github\\.com/([a-zA-Z0-9._-]+/[a-zA-Z0-9._-]+)"
    ]
    return extractFirstMatch(url, patterns: patterns)
}
```

- [ ] **Step 5: Build and verify**

Run: `cd /Users/lxh/Documents/mimo && xcodegen generate && xcodebuild -project Archiver.xcodeproj -scheme Archiver -configuration Debug build 2>&1 | tail -5`

Expected: Build succeeds.

- [ ] **Step 6: Commit**

```bash
git add Utilities/URLNormalizer.swift
git commit -m "feat: add GitHub URL recognition and normalization"
```

---

### Task 3: Create GitHubParser

**Files:**
- Create: `Parsers/GitHubParser.swift`

- [ ] **Step 1: Create GitHubParser.swift**

```swift
import Foundation

final class GitHubParser: ContentParser, @unchecked Sendable {

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = [
            "User-Agent": "Archiver/1.0",
            "Accept": "application/vnd.github.v3+json"
        ]
        return URLSession(configuration: config)
    }()

    func canParse(url: URL) -> Bool {
        let host = url.host?.lowercased() ?? ""
        return host == "github.com" || host.hasSuffix(".github.com")
    }

    func extractContentID(from url: URL) -> String? {
        URLNormalizer.extractContentID(url.absoluteString, platform: .github)
    }

    func normalizeURL(_ url: String) -> String {
        URLNormalizer.normalize(url, platform: .github)
    }

    func parse(url: URL) async throws -> ParsedContent {
        guard let (owner, repo) = extractOwnerRepo(from: url) else {
            throw ParserError.parseFailed(reason: "无法从链接中提取仓库信息")
        }

        let repoAPI = "https://api.github.com/repos/\(owner)/\(repo)"
        guard let repoURL = URL(string: repoAPI) else {
            throw ParserError.invalidURL
        }

        let (repoData, _) = try await session.data(from: repoURL)
        let repoJSON = try JSONSerialization.jsonObject(with: repoData) as? [String: Any] ?? [:]

        let description = repoJSON["description"] as? String
        let stars = repoJSON["stargazers_count"] as? Int ?? 0
        let language = repoJSON["language"] as? String
        let ownerJSON = repoJSON["owner"] as? [String: Any]
        let ownerName = ownerJSON?["login"] as? String ?? owner
        let ownerAvatar = ownerJSON?["avatar_url"] as? String

        var readmeContent: String?
        let readmeAPI = "https://api.github.com/repos/\(owner)/\(repo)/readme"
        if let readmeURL = URL(string: readmeAPI) {
            do {
                let (readmeData, _) = try await session.data(from: readmeURL)
                let readmeJSON = try JSONSerialization.jsonObject(with: readmeData) as? [String: Any]
                if let base64Content = readmeJSON?["content"] as? String {
                    readmeContent = Data(base64Encoded: base64Content, options: .ignoreUnknownCharacters)
                        .flatMap { String(data: $0, encoding: .utf8) }
                }
            } catch {
                // README might not exist
            }
        }

        var bodyParts: [String] = []
        if let desc = description, !desc.isEmpty {
            bodyParts.append(desc)
        }
        var statsLine = "⭐ \(stars)"
        if let lang = language {
            statsLine += " | \(lang)"
        }
        bodyParts.append(statsLine)
        if let readme = readmeContent, !readme.isEmpty {
            bodyParts.append(readme)
        }
        let body = bodyParts.joined(separator: "\n\n")

        let title = "\(owner)/\(repo)"

        return ParsedContent(
            title: title,
            body: body,
            author: ownerName,
            authorID: owner,
            publishDate: nil,
            coverURL: ownerAvatar,
            imageURLs: [],
            videoURL: nil,
            platformContentID: "\(owner)/\(repo)",
            rawMetadata: [
                "repo": "\(owner)/\(repo)",
                "description": description ?? "",
                "stars": "\(stars)",
                "language": language ?? ""
            ]
        )
    }

    func downloadMedia(content: ParsedContent, itemID: UUID, mediaDir: URL) async throws -> [MediaAsset] {
        var assets: [MediaAsset] = []
        let fileManager = FileManager.default
        let itemDir = mediaDir.appendingPathComponent(itemID.uuidString)
        try fileManager.createDirectory(at: itemDir, withIntermediateDirectories: true)

        if let coverURLString = content.coverURL, let url = URL(string: coverURLString) {
            let fileName = "cover.jpg"
            let localPath = itemDir.appendingPathComponent(fileName)
            if await downloadFile(from: url, to: localPath) {
                let fileSize = (try? fileManager.attributesOfItem(atPath: localPath.path)[.size] as? Int64) ?? 0
                let asset = MediaAsset(
                    itemID: itemID, type: .cover,
                    localPath: "\(itemID.uuidString)/\(fileName)",
                    remoteURL: coverURLString,
                    fileName: fileName, fileSize: fileSize,
                    downloadStatus: .completed
                )
                assets.append(asset)
            }
        }

        return assets
    }

    // MARK: - Private

    private func extractOwnerRepo(from url: URL) -> (String, String)? {
        let pathComponents = url.pathComponents.filter { $0 != "/" }
        guard pathComponents.count >= 2 else { return nil }
        return (pathComponents[0], pathComponents[1])
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

- [ ] **Step 2: Build and verify**

Run: `cd /Users/lxh/Documents/mimo && xcodegen generate && xcodebuild -project Archiver.xcodeproj -scheme Archiver -configuration Debug build 2>&1 | tail -5`

Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
git add Parsers/GitHubParser.swift
git commit -m "feat: add GitHubParser for repo content"
```

---

### Task 4: Register GitHubParser in PlatformRouter

**Files:**
- Modify: `Parsers/PlatformRouter.swift`

- [ ] **Step 1: Add GitHubParser to parsers array**

In `PlatformRouter.init`, add `GitHubParser()`:

```swift
private init() {
    parsers = [
        DouyinParser(),
        XiaohongshuParser(),
        CoolapkParser(),
        BilibiliParser(),
        GitHubParser()
    ]
}
```

- [ ] **Step 2: Build and verify**

Run: `cd /Users/lxh/Documents/mimo && xcodegen generate && xcodebuild -project Archiver.xcodeproj -scheme Archiver -configuration Debug build 2>&1 | tail -5`

Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
git add Parsers/PlatformRouter.swift
git commit -m "feat: register GitHubParser in PlatformRouter"
```

---

### Task 5: Create MarkdownView Component

**Files:**
- Create: `Views/Components/MarkdownView.swift`

- [ ] **Step 1: Create MarkdownView.swift**

```swift
import SwiftUI

struct MarkdownView: View {
    let text: String

    var body: some View {
        if let attributedString = try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            Text(attributedString)
                .textSelection(.enabled)
        } else {
            Text(stripHTML(text))
                .textSelection(.enabled)
        }
    }
}
```

- [ ] **Step 2: Build and verify**

Run: `cd /Users/lxh/Documents/mimo && xcodegen generate && xcodebuild -project Archiver.xcodeproj -scheme Archiver -configuration Debug build 2>&1 | tail -5`

Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
git add Views/Components/MarkdownView.swift
git commit -m "feat: add MarkdownView component for body rendering"
```

---

### Task 6: Update ItemDetailView to Use MarkdownView

**Files:**
- Modify: `Views/Item/ItemDetailView.swift`

- [ ] **Step 1: Replace bodySection implementation**

Replace the body text rendering in `bodySection`:

```swift
private func bodySection(_ item: Item) -> some View {
    VStack(alignment: .leading, spacing: 8) {
        Text("正文").font(.headline)
        if let body = item.body, !body.isEmpty {
            MarkdownView(text: body)
                .font(.body)
                .foregroundStyle(.primary)
        } else {
            Text("暂无正文内容")
                .font(.body)
                .foregroundStyle(.tertiary)
        }
    }
}
```

- [ ] **Step 2: Build and verify**

Run: `cd /Users/lxh/Documents/mimo && xcodegen generate && xcodebuild -project Archiver.xcodeproj -scheme Archiver -configuration Debug build 2>&1 | tail -5`

Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
git add Views/Item/ItemDetailView.swift
git commit -m "feat: use MarkdownView for body rendering in detail view"
```

---

### Task 7: End-to-End Smoke Test

- [ ] **Step 1: Build the app**

Run: `cd /Users/lxh/Documents/mimo && xcodegen generate && xcodebuild -project Archiver.xcodeproj -scheme Archiver -configuration Debug build 2>&1 | tail -10`

Expected: Build succeeds with 0 errors.

- [ ] **Step 2: Run the app and test GitHub import**

Run the app and paste this URL:
`https://github.com/apple/swift`

Verify:
- Platform recognized as "GitHub"
- Content saved with title "apple/swift"
- Author shows "apple"
- Body contains description + stars + README
- Markdown renders correctly

- [ ] **Step 3: Test Markdown on existing content**

Open an existing item. Verify Markdown renders properly.

- [ ] **Step 4: Test auto-platform matching**

If a custom platform named "GitHub" exists, item is assigned to it. Otherwise it appears in "未分类内容".

---

## Summary

| Task | Files Changed | Description |
|------|--------------|-------------|
| 1 | `Models/Enums/Platform.swift` | Add `.github` case |
| 2 | `Utilities/URLNormalizer.swift` | GitHub URL recognition |
| 3 | `Parsers/GitHubParser.swift` (new) | GitHub API parser |
| 4 | `Parsers/PlatformRouter.swift` | Register parser |
| 5 | `Views/Components/MarkdownView.swift` (new) | Markdown renderer |
| 6 | `Views/Item/ItemDetailView.swift` | Use MarkdownView |
| 7 | - | Smoke test |
