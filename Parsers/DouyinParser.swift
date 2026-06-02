import Foundation

/// 抖音解析器
final class DouyinParser: ContentParser, @unchecked Sendable {
    
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Mobile/15E148 Safari/604.1",
            "Referer": "https://www.douyin.com/"
        ]
        return URLSession(configuration: config)
    }()
    
    func canParse(url: URL) -> Bool {
        let host = url.host?.lowercased() ?? ""
        return host.contains("douyin.com") || host.contains("iesdouyin.com")
    }
    
    func extractContentID(from url: URL) -> String? {
        URLNormalizer.extractContentID(url.absoluteString, platform: .douyin)
    }
    
    func normalizeURL(_ url: String) -> String {
        URLNormalizer.normalize(url, platform: .douyin)
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
        
        // 尝试从 SSR 数据中提取 JSON
        if let content = extractFromSSRData(html, url: url) {
            return content
        }
        
        // 回退：从 meta 标签提取基础信息
        return extractFromMetaTags(html, url: url)
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
                let asset = MediaAsset(
                    itemID: itemID,
                    type: .cover,
                    localPath: "\(itemID.uuidString)/\(fileName)",
                    remoteURL: coverURL,
                    fileName: fileName,
                    downloadStatus: .completed
                )
                try MediaRepository().insert(asset)
                assets.append(asset)
            }
        }
        
        // 下载图片
        for (index, imageURL) in content.imageURLs.enumerated() {
            guard let url = URL(string: imageURL) else { continue }
            let ext = url.pathExtension.lowercased() == "webp" ? "webp" : "jpg"
            let fileName = "image_\(index + 1).\(ext)"
            let localPath = itemDir.appendingPathComponent(fileName)
            if await downloadFile(from: url, to: localPath) {
                let asset = MediaAsset(
                    itemID: itemID,
                    type: .image,
                    localPath: "\(itemID.uuidString)/\(fileName)",
                    remoteURL: imageURL,
                    fileName: fileName,
                    downloadStatus: .completed
                )
                try MediaRepository().insert(asset)
                assets.append(asset)
            }
        }
        
        // 下载视频
        if let videoURL = content.videoURL, let url = URL(string: videoURL) {
            let fileName = "video.mp4"
            let localPath = itemDir.appendingPathComponent(fileName)
            if await downloadFile(from: url, to: localPath) {
                let fileSize = (try? fileManager.attributesOfItem(atPath: localPath.path)[.size] as? Int64) ?? 0
                let asset = MediaAsset(
                    itemID: itemID,
                    type: .video,
                    localPath: "\(itemID.uuidString)/\(fileName)",
                    remoteURL: videoURL,
                    fileName: fileName,
                    fileSize: fileSize,
                    downloadStatus: .completed
                )
                try MediaRepository().insert(asset)
                assets.append(asset)
            }
        }
        
        return assets
    }
    
    // MARK: - Private
    
    private func extractFromSSRData(_ html: String, url: URL) -> ParsedContent? {
        // 移动端页面使用 window._ROUTER_DATA
        if let routerRange = html.range(of: "window._ROUTER_DATA = ") {
            let startIdx = routerRange.upperBound
            guard let scriptEnd = html.range(of: "</script>", range: startIdx..<html.endIndex) else {
                return nil
            }
            
            var jsonStr = String(html[startIdx..<scriptEnd.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if jsonStr.hasSuffix(";") {
                jsonStr = String(jsonStr.dropLast())
            }
            
            guard let jsonData = jsonStr.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
                return nil
            }
            
            return parseMobileJSON(json, url: url)
        }
        
        // 桌面端：尝试 RENDER_DATA
        guard let renderRange = html.range(of: "<script id=\"RENDER_DATA\" type=\"application/json\">"),
              let endRange = html.range(of: "</script>", range: renderRange.upperBound..<html.endIndex) else {
            return nil
        }
        
        let jsonStr = String(html[renderRange.upperBound..<endRange.lowerBound])
            .removingPercentEncoding ?? ""
        
        guard let jsonData = jsonStr.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            return nil
        }
        
        return parseDesktopJSON(json, url: url)
    }
    
    private func parseMobileJSON(_ json: [String: Any], url: URL) -> ParsedContent? {
        guard let loaderData = json["loaderData"] as? [String: Any] else {
            return nil
        }
        
        // 找到 note_(id)/page 或 video_(id)/page 键
        var notePage: [String: Any]?
        for (key, value) in loaderData {
            if (key.hasPrefix("note_(") || key.hasPrefix("video_(")) && key.hasSuffix(")/page") {
                notePage = value as? [String: Any]
                break
            }
        }
        
        guard let page = notePage else {
            return nil
        }
        
        // 尝试 aweme.detail
        if let aweme = page["aweme"] as? [String: Any] {
            if let detail = aweme["detail"] as? [String: Any] {
                return parseNoteDetail(detail, url: url)
            }
        }
        
        // 尝试 videoInfoRes
        if let videoInfoRes = page["videoInfoRes"] as? [String: Any] {
            if let itemList = videoInfoRes["item_list"] as? [[String: Any]] {
                if let first = itemList.first {
                    return parseNoteDetail(first, url: url)
                }
            }
        }
        
        return nil
    }
    
    private func parseNoteDetail(_ detail: [String: Any], url: URL) -> ParsedContent? {
        let desc = detail["desc"] as? String
        
        var author: String?
        if let authorInfo = detail["author"] as? [String: Any] {
            author = authorInfo["nickname"] as? String
        }
        
        // aweme_type: 0=视频, 2=图文
        let awemeType = detail["aweme_type"] as? Int ?? 0
        let isImageNote = (awemeType == 2)
        
        // 提取封面（仅视频笔记使用）
        var coverURL: String?
        if !isImageNote {
            if let video = detail["video"] as? [String: Any],
               let cover = video["cover"] as? [String: Any],
               let urlList = cover["url_list"] as? [String],
               let firstURL = urlList.first {
                coverURL = firstURL
            }
        }
        
        // 提取视频 URL（仅视频笔记）
        var videoURL: String?
        if !isImageNote {
            if let video = detail["video"] as? [String: Any] {
                if let playAddr = video["play_addr"] as? [String: Any] {
                    if let urlList = playAddr["url_list"] as? [String] {
                        videoURL = urlList.first
                    }
                }
            }
        }
        
        // 提取图片列表
        var imageURLs: [String] = []
        if let images = detail["images"] as? [[String: Any]] {
            for image in images {
                if let urlList = image["url_list"] as? [String],
                   let firstURL = urlList.first {
                    imageURLs.append(firstURL)
                }
            }
        }
        
        // 封面去重：如果封面和首图相同，移除首图
        if let cover = coverURL, imageURLs.first == cover {
            imageURLs.removeFirst()
        }
        
        // 标题：优先用 title，没有则用 desc 去掉 #话题 后截取前50字
        let title: String
        if let t = detail["title"] as? String {
            title = t
        } else if let d = desc {
            // 去掉 #话题 格式
            let pattern = "#[^#\n\t ]+"
            let cleaned = d.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            title = String(cleaned.prefix(50))
        } else {
            title = ""
        }
        
        guard !title.isEmpty || desc != nil else { return nil }
        
        return ParsedContent(
            title: title,
            body: desc,
            author: author,
            coverURL: coverURL,
            imageURLs: imageURLs,
            videoURL: videoURL,
            platformContentID: extractContentID(from: url)
        )
    }
    
    private func parseDesktopJSON(_ json: [String: Any], url: URL) -> ParsedContent? {
        var title: String?
        var desc: String?
        var author: String?
        var coverURL: String?
        var videoURL: String?
        var imageURLs: [String] = []
        
        if let detail = findValue(in: json, key: "detail") as? [String: Any] {
            title = detail["title"] as? String
            desc = detail["desc"] as? String
            
            if let authorInfo = detail["authorInfo"] as? [String: Any] {
                author = authorInfo["nickname"] as? String
            }
            
            if let video = detail["video"] as? [String: Any],
               let playAddr = video["playAddr"] as? [[String: Any]],
               let first = playAddr.first,
               let src = first["src"] as? String {
                videoURL = src
            }
            
            if let cover = detail["video"] as? [String: Any],
               let coverAddr = cover["cover"] as? [[String: Any]],
               let first = coverAddr.first,
               let urlList = first["urlList"] as? [String],
               let firstURL = urlList.first {
                coverURL = firstURL
            }
            
            if let images = detail["images"] as? [[String: Any]] {
                for image in images {
                    if let urlList = image["url_list"] as? [String],
                       let firstURL = urlList.first {
                        imageURLs.append(firstURL)
                    }
                }
            }
        }
        
        guard title != nil || desc != nil else { return nil }
        
        return ParsedContent(
            title: title,
            body: desc,
            author: author,
            coverURL: coverURL,
            imageURLs: imageURLs,
            videoURL: videoURL,
            platformContentID: extractContentID(from: url)
        )
    }
    
    private func extractFromMetaTags(_ html: String, url: URL) -> ParsedContent {
        let title = extractMetaContent(html, property: "og:title") 
            ?? extractMetaContent(html, property: "twitter:title")
        let desc = extractMetaContent(html, property: "og:description")
            ?? extractMetaContent(html, name: "description")
        let cover = extractMetaContent(html, property: "og:image")
            ?? extractMetaContent(html, property: "twitter:image")
        
        return ParsedContent(
            title: title,
            body: desc,
            coverURL: cover,
            platformContentID: extractContentID(from: url)
        )
    }
    
    private func extractMetaContent(_ html: String, property: String) -> String? {
        let pattern = "<meta[^>]+property=\"\(property)\"[^>]+content=\"([^\"]+)\""
        return extractFirstMatch(html, pattern: pattern)
    }
    
    private func extractMetaContent(_ html: String, name: String) -> String? {
        let pattern = "<meta[^>]+name=\"\(name)\"[^>]+content=\"([^\"]+)\""
        return extractFirstMatch(html, pattern: pattern)
    }
    
    private func extractFirstMatch(_ text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[range])
    }
    
    private func findValue(in dict: [String: Any], key: String) -> Any? {
        if let value = dict[key] { return value }
        for (_, value) in dict {
            if let nested = value as? [String: Any],
               let found = findValue(in: nested, key: key) {
                return found
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
