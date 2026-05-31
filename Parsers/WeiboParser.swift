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

        let mobileURL = URL(string: "https://m.weibo.cn/detail/\(statusID)")!
        if let content = try? await parseMobilePage(mobileURL, statusID: statusID) {
            return content
        }

        let desktopURL = URL(string: "https://weibo.com/status/\(statusID)")!
        return try await parseDesktopPage(desktopURL, statusID: statusID)
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

    // MARK: - JSON 解析（AJAX API 共用）

    private func parseWeiboJSON(_ status: [String: Any], statusID: String) -> ParsedContent {
        let rawText = status["text"] as? String ?? ""
        let text = Self.stripHTML(rawText)

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

        var author: String?
        var authorID: String?
        if let user = status["user"] as? [String: Any] {
            author = user["screen_name"] as? String
            authorID = user["id_str"] as? String ?? (user["id"] as? Int).map { String($0) }
        }

        var publishDate: Date?
        if let createdAt = status["created_at"] as? String {
            publishDate = parseWeiboDate(createdAt)
        }

        let title = text.isEmpty ? "微博 \(statusID)" : String(text.prefix(80))

        // 首张图作为封面，从正文图片列表中移除避免重复下载
        let cover = imageURLs.first
        let bodyImages = Array(imageURLs.dropFirst())

        return ParsedContent(
            title: title,
            body: text,
            author: author,
            authorID: authorID,
            publishDate: publishDate,
            coverURL: cover,
            imageURLs: bodyImages,
            videoURL: nil,
            platformContentID: statusID,
            rawMetadata: ["type": "status"]
        )
    }

    // MARK: - Mobile Page (m.weibo.cn)

    private func parseMobilePage(_ url: URL, statusID: String) async throws -> ParsedContent? {
        // 优先用 AJAX API（带 X-Requested-With 头绕过反爬）
        let apiURL = URL(string: "https://m.weibo.cn/statuses/show?id=\(statusID)")!
        var apiRequest = URLRequest(url: apiURL)
        apiRequest.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
        apiRequest.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        apiRequest.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        apiRequest.setValue("https://m.weibo.cn/detail/\(statusID)", forHTTPHeaderField: "Referer")

        let (apiData, apiResponse) = try await URLSession.shared.data(for: apiRequest)
        guard let apiHttpResponse = apiResponse as? HTTPURLResponse,
              apiHttpResponse.statusCode == 200 else { return nil }

        if let apiJSON = try? JSONSerialization.jsonObject(with: apiData) as? [String: Any],
           apiJSON["ok"] as? Int == 1,
           let dataDict = apiJSON["data"] as? [String: Any] {
            return parseWeiboJSON(dataDict, statusID: statusID)
        }

        // 兜底：尝试原始 HTML 解析
        let (data, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else { return nil }
        guard let html = String(data: data, encoding: .utf8) else { return nil }

        guard let renderDataStr = extractRenderData(from: html),
              let renderData = renderDataStr.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: renderData) as? [String: Any],
              let dataDict = json["data"] as? [String: Any],
              let status = dataDict["status"] as? [String: Any] else {
            return nil
        }

        let rawText = status["text"] as? String ?? ""
        let text = Self.stripHTML(rawText)

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

        var author: String?
        var authorID: String?
        if let user = status["user"] as? [String: Any] {
            author = user["screen_name"] as? String
            authorID = user["id_str"] as? String ?? (user["id"] as? Int).map { String($0) }
        }

        var publishDate: Date?
        if let createdAt = status["created_at"] as? String {
            publishDate = parseWeiboDate(createdAt)
        }

        let title = text.isEmpty ? "微博 \(statusID)" : String(text.prefix(80))

        // 首张图作为封面，从正文图片列表中移除避免重复下载
        let cover = imageURLs.first
        let bodyImages = Array(imageURLs.dropFirst())

        return ParsedContent(
            title: title,
            body: text,
            author: author,
            authorID: authorID,
            publishDate: publishDate,
            coverURL: cover,
            imageURLs: bodyImages,
            videoURL: nil,
            platformContentID: statusID,
            rawMetadata: ["type": "status"]
        )
    }

    // MARK: - Desktop Page (weibo.com)

    private func parseDesktopPage(_ url: URL, statusID: String) async throws -> ParsedContent {
        let (data, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw ParserError.parseFailed(reason: "HTTP 请求失败")
        }
        guard let html = String(data: data, encoding: .utf8) else {
            throw ParserError.parseFailed(reason: "无法解码页面内容")
        }

        let title = extractMeta(html, property: "og:title") ?? "微博 \(statusID)"
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
        URLNormalizer.extractWeiboID(url.absoluteString)
    }

    private func extractRenderData(from html: String) -> String? {
        if let startRange = html.range(of: "var $render_data = ") {
            let afterEquals = html[startRange.upperBound...]
            if let bracketStart = afterEquals.firstIndex(of: "["),
               let bracketEnd = afterEquals.firstIndex(of: "]") {
                let arrayStr = String(afterEquals[bracketStart...afterEquals.index(after: bracketEnd)])
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
        for (old, new) in [("orj360", "large"), ("orj480", "large"), ("thumb", "large"), ("thumbnail", "large")] {
            result = result.replacingOccurrences(of: old, with: new)
        }
        return result
    }

    private func parseWeiboDate(_ dateStr: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE MMM dd HH:mm:ss Z yyyy"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.date(from: dateStr)
    }

    private func extractMeta(_ html: String, property: String) -> String? {
        let pattern = "\(property)\"\\s+content=\"([^\"]*)\""
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let range = Range(match.range(at: 1), in: html) else { return nil }
        return String(html[range])
    }

    private func downloadFile(from url: URL, to localURL: URL) async -> Bool {
        do {
            let (data, _) = try await session.data(from: url)
            try data.write(to: localURL)
            return true
        } catch { return false }
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
