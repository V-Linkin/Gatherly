import Foundation

final class YouTubeParser: ContentParser, @unchecked Sendable {
    
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
            "Accept-Language": "en-US,en;q=0.9",
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
        ]
        config.httpCookieAcceptPolicy = .always
        config.httpShouldSetCookies = true
        return URLSession(configuration: config)
    }()
    
    func canParse(url: URL) -> Bool {
        let host = url.host?.lowercased() ?? ""
        return host == "youtube.com" || host == "www.youtube.com" || host == "m.youtube.com" || host == "youtu.be"
    }
    
    func extractContentID(from url: URL) -> String? {
        URLNormalizer.extractYouTubeID(url.absoluteString)
    }
    
    func normalizeURL(_ url: String) -> String {
        URLNormalizer.normalize(url, platform: .youtube)
    }
    
    func parse(url: URL) async throws -> ParsedContent {
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw ParserError.parseFailed(reason: "HTTP 请求失败")
        }
        
        guard let html = String(data: data, encoding: .utf8) else {
            throw ParserError.parseFailed(reason: "无法解码页面内容")
        }
        
        let finalURL = httpResponse.url ?? url
        let isChannel = finalURL.path.lowercased().contains("/channel/")
            || finalURL.absoluteString.lowercased().contains("/@")
            || finalURL.path.lowercased().contains("/c/")
            || finalURL.path.lowercased().contains("/user/")
            || finalURL.path.lowercased().contains("/videos")
        
        if isChannel {
            return parseChannelPage(html: html, url: finalURL)
        }
        
        return parseVideoPage(html: html, url: finalURL)
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
    
    // MARK: - Video Page Parsing
    
    private func parseVideoPage(html: String, url: URL) -> ParsedContent {
        // Strategy 1: Try ytInitialPlayerResponse JSON
        if let result = tryParsePlayerResponse(html: html) {
            return result
        }
        
        // Strategy 2: Try meta tags (og:*)
        if let result = tryParseMetaTags(html: html, url: url) {
            return result
        }
        
        // Strategy 3: Minimal fallback with just the URL
        return ParsedContent(
            title: extractFirst(html, pattern: #"<title>([^<]*)</title>"#)?
                .replacingOccurrences(of: " - YouTube", with: "")
                .trimmingCharacters(in: .whitespaces),
            body: nil,
            author: nil,
            coverURL: nil,
            platformContentID: extractVideoID(from: url),
            rawMetadata: ["type": "video", "parseMethod": "fallback"]
        )
    }
    
    private func tryParsePlayerResponse(html: String) -> ParsedContent? {
        guard let jsonString = extractJSON(html: html, key: "ytInitialPlayerResponse"),
              let jsonData = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            return nil
        }
        
        let videoDetails = json["videoDetails"] as? [String: Any] ?? [:]
        let title = videoDetails["title"] as? String
        let author = videoDetails["author"] as? String
        let shortDescription = videoDetails["shortDescription"] as? String
        let lengthSeconds = videoDetails["lengthSeconds"] as? String
        let videoId = videoDetails["videoId"] as? String
        
        let thumbnails = videoDetails["thumbnail"] as? [String: Any]
        let thumbnailImages = thumbnails?["thumbnails"] as? [[String: Any]]
        let coverURL = thumbnailImages?.last?["url"] as? String
        
        let microformat = json["microformat"] as? [String: Any]
        let playerMicroformat = microformat?["playerMicroformatRenderer"] as? [String: Any]
        let publishDateStr = playerMicroformat?["publishDate"] as? String
        let viewCount = playerMicroformat?["viewCount"] as? String
        
        var bodyParts: [String] = []
        if let desc = shortDescription, !desc.isEmpty {
            bodyParts.append(desc)
        }
        if let views = viewCount {
            bodyParts.append("播放量: \(views)")
        }
        if let duration = lengthSeconds, let seconds = Int(duration) {
            let minutes = seconds / 60
            let secs = seconds % 60
            bodyParts.append("时长: \(minutes):\(String(format: "%02d", secs))")
        }
        
        return ParsedContent(
            title: title,
            body: bodyParts.isEmpty ? nil : bodyParts.joined(separator: "\n\n"),
            author: author,
            authorID: author,
            publishDate: publishDateStr.flatMap { parseYouTubeDate($0) },
            coverURL: coverURL,
            imageURLs: coverURL != nil ? [coverURL!] : [],
            platformContentID: videoId,
            rawMetadata: [
                "type": "video",
                "videoId": videoId ?? "",
                "viewCount": viewCount ?? "",
                "lengthSeconds": lengthSeconds ?? "",
                "parseMethod": "playerResponse"
            ]
        )
    }
    
    private func tryParseMetaTags(html: String, url: URL) -> ParsedContent? {
        let title = extractFirst(html, pattern: #"og:title"\s+content="([^"]*)""#)
            ?? extractFirst(html, pattern: #"<title>([^<]*)</title>"#)?
                .replacingOccurrences(of: " - YouTube", with: "")
                .trimmingCharacters(in: .whitespaces)
        
        guard title != nil else { return nil }
        
        let description = extractFirst(html, pattern: #"og:description"\s+content="([^"]*)""#)
        let coverURL = extractFirst(html, pattern: #"og:image"\s+content="([^"]*)""#)
        let author = extractFirst(html, pattern: #"name"\s+content="([^"]*)""#)?
            .replacingOccurrences(of: " - YouTube", with: "")
        
        return ParsedContent(
            title: title,
            body: description,
            author: author,
            coverURL: coverURL,
            imageURLs: coverURL != nil ? [coverURL!] : [],
            platformContentID: extractVideoID(from: url),
            rawMetadata: [
                "type": "video",
                "parseMethod": "metaTags"
            ]
        )
    }
    
    // MARK: - Channel Page Parsing
    
    private func parseChannelPage(html: String, url: URL) -> ParsedContent {
        let channelName = extractFirst(html, pattern: #"prop="name"\s+content="([^"]*)""#)
            ?? extractFirst(html, pattern: #"og:title"\s+content="([^"]*)""#)?
                .replacingOccurrences(of: " - YouTube", with: "")
            ?? url.lastPathComponent
        
        let description = extractFirst(html, pattern: #"og:description"\s+content="([^"]*)""#)
        let avatarURL = extractFirst(html, pattern: #"prop="image"\s+content="([^"]*)""#)
            ?? extractFirst(html, pattern: #"og:image"\s+content="([^"]*)""#)
        
        let subscriberCount = extractFirst(html, pattern: #"(\d[\d,.]*[KMB]?)\s*subscriber"#)
        
        var bodyParts: [String] = []
        if let desc = description, !desc.isEmpty {
            bodyParts.append(desc)
        }
        if let subs = subscriberCount {
            bodyParts.append("订阅者: \(subs)")
        }
        bodyParts.append(url.absoluteString)
        
        return ParsedContent(
            title: channelName,
            body: bodyParts.joined(separator: "\n\n"),
            author: channelName,
            coverURL: avatarURL,
            imageURLs: avatarURL != nil ? [avatarURL!] : [],
            platformContentID: url.absoluteString,
            rawMetadata: [
                "type": "channel",
                "subscriberCount": subscriberCount ?? "",
                "parseMethod": "metaTags"
            ]
        )
    }
    
    // MARK: - Helpers
    
    private func extractVideoID(from url: URL) -> String? {
        if let v = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "v" })?.value {
            return v
        }
        let path = url.path
        if path.contains("/shorts/") {
            return path.components(separatedBy: "/shorts/").last
        }
        if url.host == "youtu.be" {
            return path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
        return nil
    }
    
    private func extractJSON(html: String, key: String) -> String? {
        let searchPatterns = [
            "var \(key) = ",
            "\(key) = "
        ]
        
        for pattern in searchPatterns {
            guard let startRange = html.range(of: pattern) else { continue }
            
            var braceCount = 0
            var foundOpening = false
            var endIndex = startRange.upperBound
            var current = startRange.upperBound
            
            while current < html.endIndex {
                let char = html[current]
                if char == "{" {
                    braceCount += 1
                    foundOpening = true
                } else if char == "}" {
                    braceCount -= 1
                }
                
                if foundOpening && braceCount == 0 {
                    endIndex = html.index(after: current)
                    break
                }
                current = html.index(after: current)
            }
            
            if foundOpening && braceCount == 0 {
                return String(html[startRange.upperBound..<endIndex])
            }
        }
        
        return nil
    }
    
    private func extractFirst(_ text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }
    
    private func parseYouTubeDate(_ dateStr: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.date(from: dateStr)
    }
    
    private func downloadFile(from url: URL, to localPath: URL) async -> Bool {
        do {
            var request = URLRequest(url: url)
            request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
            let (data, _) = try await session.data(for: request)
            try data.write(to: localPath)
            return true
        } catch {
            return false
        }
    }
}
