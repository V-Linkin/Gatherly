import Foundation

final class GitHubParser: ContentParser, @unchecked Sendable {
    
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
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
            throw ParserError.parseFailed(reason: "无法从 URL 提取仓库信息")
        }
        
        let (data, response) = try await session.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw ParserError.parseFailed(reason: "HTTP 请求失败")
        }
        
        guard let html = String(data: data, encoding: .utf8) else {
            throw ParserError.parseFailed(reason: "无法解码页面内容")
        }
        
        let title = extractMeta(html, property: "og:title")
            .replacingOccurrences(of: "GitHub - ", with: "")
            .components(separatedBy: ":").first?.trimmingCharacters(in: .whitespaces)
            ?? "\(owner)/\(repo)"
        
        let description = extractMeta(html, property: "og:description")
            .components(separatedBy: ". Contribute to").first
            ?? extractMeta(html, property: "og:description")
        
        let coverURL = extractMeta(html, property: "og:image")
        
        let stars = extractFirst(html, pattern: #"(\d[\d,]*)\s*stargazers?"#) ?? "0"
        let forks = extractFirst(html, pattern: #"(\d[\d,]*)\s*forks?"#) ?? "0"
        let language = extractFirst(html, pattern: #"itemprop="programmingLanguage">([^<]*)<"#)
        
        var bodyParts: [String] = []
        if !description.isEmpty {
            bodyParts.append(description)
        }
        bodyParts.append("⭐ \(stars)  🍴 \(forks)")
        if let lang = language, !lang.isEmpty {
            bodyParts.append("语言: \(lang)")
        }
        
        if let readme = try? await fetchREADME(owner: owner, repo: repo) {
            bodyParts.append(readme)
        }
        
        let publishDate: Date? = {
            if let dateStr = extractFirst(html, pattern: #"datetime="([^"]*)"#) {
                let formatter = ISO8601DateFormatter()
                return formatter.date(from: dateStr)
            }
            return nil
        }()
        
        let authorAvatar = extractFirst(html, pattern: #"avatar-user[^"]*"[^>]*src="([^"]*)""#)
            ?? coverURL
        
        return ParsedContent(
            title: title,
            body: bodyParts.joined(separator: "\n\n"),
            author: owner,
            authorID: owner,
            publishDate: publishDate,
            coverURL: authorAvatar,
            imageURLs: authorAvatar.isEmpty ? [] : [authorAvatar],
            videoURL: nil,
            platformContentID: "\(owner)/\(repo)",
            rawMetadata: [
                "stars": stars,
                "forks": forks,
                "language": language ?? ""
            ]
        )
    }
    
    func downloadMedia(content: ParsedContent, itemID: UUID, mediaDir: URL) async throws -> [MediaAsset] {
        var assets: [MediaAsset] = []
        let fileManager = FileManager.default
        let itemDir = mediaDir.appendingPathComponent(itemID.uuidString)
        try fileManager.createDirectory(at: itemDir, withIntermediateDirectories: true)
        
        if let coverURL = content.coverURL, let url = URL(string: coverURL) {
            let fileName = "avatar.png"
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
    
    // MARK: - Private
    
    private func fetchREADME(owner: String, repo: String) async throws -> String? {
        let readmeURL = URL(string: "https://github.com/\(owner)/\(repo)")!
        var request = URLRequest(url: readmeURL)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36", forHTTPHeaderField: "User-Agent")
        
        let (data, _) = try await session.data(for: request)
        guard let html = String(data: data, encoding: .utf8) else { return nil }
        
        if let readmeStart = html.range(of: "<article"),
           let readmeEnd = html.range(of: "</article>", range: readmeStart.upperBound..<html.endIndex) {
            var readmeHTML = String(html[readmeStart.lowerBound..<readmeEnd.upperBound])
            // Fix relative image URLs to absolute
            readmeHTML = readmeHTML.replacingOccurrences(
                of: #"(src=")(/[^"]*)"#,
                with: "$1https://github.com$2",
                options: .regularExpression
            )
            readmeHTML = stripHTMLTags(readmeHTML)
            readmeHTML = decodeHTMLEntities(readmeHTML)
            readmeHTML = readmeHTML.trimmingCharacters(in: .whitespacesAndNewlines)
            if readmeHTML.count > 5000 {
                readmeHTML = String(readmeHTML.prefix(5000)) + "\n\n...(README 已截断)"
            }
            return readmeHTML
        }
        
        return nil
    }
    
    private func extractOwnerRepo(from url: URL) -> (String, String)? {
        let pathComponents = url.pathComponents.filter { $0 != "/" }
        guard pathComponents.count >= 2 else { return nil }
        let owner = pathComponents[0]
        let repo = pathComponents[1]
        if ["topics", "collections", "organizations", "settings", "notifications", "search", "login", "signup", "explore", "trending", "stars", "watching"].contains(repo) {
            return nil
        }
        return (owner, repo)
    }
    
    private func extractMeta(_ html: String, property: String) -> String {
        let pattern = "\(property)\"\\s+content=\"([^\"]*)\""
        return extractFirst(html, pattern: pattern) ?? ""
    }
    
    private func extractFirst(_ text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }
    
    private func stripHTMLTags(_ html: String) -> String {
        var text = html
        // Convert img tags to markdown image syntax BEFORE stripping HTML
        text = text.replacingOccurrences(
            of: #"<img[^>]*src="([^"]*)"[^>]*alt="([^"]*)"[^>]*>"#,
            with: "![$2]($1)",
            options: .regularExpression
        )
        text = text.replacingOccurrences(
            of: #"<img[^>]*src="([^"]*)"[^>]*>"#,
            with: "![image]($1)",
            options: .regularExpression
        )
        text = text.replacingOccurrences(of: #"<br\s*/?>"#, with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "</p>", with: "\n\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "</div>", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: #"</h[1-6]>"#, with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "</li>", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func decodeHTMLEntities(_ text: String) -> String {
        var result = text
        let entities: [(String, String)] = [
            ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
            ("&nbsp;", " "), ("&quot;", "\""), ("&#39;", "'"),
            ("&rsquo;", "'"), ("&ldquo;", "\u{201C}"), ("&rdquo;", "\u{201D}"),
            ("&mdash;", "—"), ("&ndash;", "–"), ("&hellip;", "…"),
        ]
        for (entity, char) in entities {
            result = result.replacingOccurrences(of: entity, with: char)
        }
        return result
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
