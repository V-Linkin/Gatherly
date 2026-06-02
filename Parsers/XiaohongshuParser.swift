import Foundation

/// 小红书解析器 - 双模式：登录用 HTTP，未登录用 WKWebView
final class XiaohongshuParser: ContentParser, @unchecked Sendable {
    
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
        return host.contains("xiaohongshu.com") || host.contains("xhslink.com")
    }
    
    func extractContentID(from url: URL) -> String? {
        URLNormalizer.extractContentID(url.absoluteString, platform: .xiaohongshu)
    }
    
    func normalizeURL(_ url: String) -> String {
        URLNormalizer.normalize(url, platform: .xiaohongshu)
    }
    
    func parse(url: URL) async throws -> ParsedContent {
        // 1. 先尝试 HTTP 快速获取（登录状态）
        if let content = try? await parseViaHTTP(url: url) {
            return content
        }
        
        // 2. HTTP 失败，使用 WKWebView 降级（未登录状态）
        let result = try await parseViaWebView(url: url)
        return result
    }
    
    // MARK: - HTTP 模式（登录状态，快速）
    
    private func parseViaHTTP(url: URL) async throws -> ParsedContent? {
        let (data, response) = try await session.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            return nil
        }
        
        guard httpResponse.statusCode == 200 else {
            return nil
        }
        
        guard let html = String(data: data, encoding: .utf8) else {
            return nil
        }
        
        let hasSSR = html.contains("__INITIAL_STATE__=")
        
        guard hasSSR else {
            return nil
        }
        
        return extractFromSSRData(html, url: url)
    }
    
    // MARK: - WKWebView 模式（未登录状态，稳定）
    
    @MainActor
    private func parseViaWebView(url: URL) async throws -> ParsedContent {
        let loader = JSWebLoader()
        guard let result = await loader.loadFullContent(from: url) else {
            throw ParserError.parseFailed(reason: "无法加载小红书页面")
        }
        
        // 解析 XIAOHONGSHU_JSON: 前缀的结果
        if result == "XHS_LOGIN_REQUIRED" {
            throw ParserError.parseFailed(reason: "小红书需要登录才能访问此内容")
        }
        
        guard result.hasPrefix("XIAOHONGSHU_JSON:") else {
            throw ParserError.parseFailed(reason: "页面解析失败")
        }
        
        let jsonStr = String(result.dropFirst("XIAOHONGSHU_JSON:".count))
        guard let jsonData = jsonStr.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            throw ParserError.parseFailed(reason: "JSON 解析失败")
        }
        
        let title = json["title"] as? String
        let author = json["author"] as? String
        let text = json["text"] as? String
        let images = json["images"] as? [String] ?? []
        let cover = json["cover"] as? String
        let videoURL = json["video"] as? String
        
        guard title != nil || text != nil else {
            throw ParserError.parseFailed(reason: "未获取到内容")
        }
        
        // 去重：如果封面是第一张图，从图片列表中移除
        var uniqueImages = images
        if let coverURL = cover, !coverURL.isEmpty, uniqueImages.first == coverURL {
            uniqueImages.removeFirst()
        }
        
        return ParsedContent(
            title: title,
            body: text,
            author: author,
            coverURL: cover,
            imageURLs: uniqueImages,
            videoURL: videoURL,
            platformContentID: extractContentID(from: url)
        )
    }
    
    // MARK: - SSR 数据解析
    
    private func extractFromSSRData(_ html: String, url: URL) -> ParsedContent? {
        guard let startRange = html.range(of: "__INITIAL_STATE__=") else {
            return nil
        }
        
        guard let endRange = html.range(of: "</script>", range: startRange.upperBound..<html.endIndex) else {
            return nil
        }
        
        var jsonStr = String(html[startRange.upperBound..<endRange.lowerBound])
        jsonStr = jsonStr.replacingOccurrences(of: "undefined", with: "null")
        
        guard let jsonData = jsonStr.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            return nil
        }
        
        // 小红书页面有两种数据结构：
        // 1. note.noteDetailMap (explore 页面)
        // 2. noteData.data.noteData (discovery/item 页面)
        var note: [String: Any]?
        
        if let noteMap = json["note"] as? [String: Any],
           let detailMap = noteMap["noteDetailMap"] as? [String: Any],
           let firstKey = detailMap.keys.first,
           let detail = detailMap[firstKey] as? [String: Any] {
            note = detail["note"] as? [String: Any]
        } else if let noteData = json["noteData"] as? [String: Any],
                  let data = noteData["data"] as? [String: Any],
                  let noteDetail = data["noteData"] as? [String: Any] {
            note = noteDetail
        }
        
        guard let note = note else { return nil }
        
        let title = note["title"] as? String
        let desc = note["desc"] as? String
        let user = note["user"] as? [String: Any]
        let author = user?["nickName"] as? String ?? user?["nickname"] as? String
        
        var imageURLs: [String] = []
        var coverURL: String?
        var videoURL: String?
        
        // 提取所有图片 - 转换为无水印 URL
        if let imageList = note["imageList"] as? [[String: Any]] {
            for img in imageList {
                // 优先用 fileId 构造无水印 URL（fileId 可能含斜杠如 notes_uhdr/xxx）
                if let fileId = img["fileId"] as? String, !fileId.isEmpty {
                    imageURLs.append("http://sns-na-i1.xhscdn.com/\(fileId)?imageView2/2/w/1080/format/jpg")
                } else if let url = img["urlDefault"] as? String {
                    imageURLs.append(url)
                } else if let url = img["url"] as? String {
                    imageURLs.append(url)
                }
            }
            for (idx, url) in imageURLs.enumerated() {
            }
        } else {
        }
        
        // 提取封面 - 优先用 normalNotePreloadData（无水印），兜底用 imageList 第一张
        if let preloadData = json["noteData"] as? [String: Any],
           let normalPreload = preloadData["normalNotePreloadData"] as? [String: Any],
           let imagesList = normalPreload["imagesList"] as? [[String: Any]],
           let firstImg = imagesList.first {
            if let urlLarge = firstImg["urlSizeLarge"] as? String, !urlLarge.isEmpty {
                coverURL = urlLarge
            } else if let url = firstImg["url"] as? String, !url.isEmpty {
                coverURL = url
            }
        }
        if coverURL == nil && !imageURLs.isEmpty {
            coverURL = imageURLs.first
        }
        // 封面和首图一定重复，直接移除首图
        if coverURL != nil && !imageURLs.isEmpty {
            imageURLs.removeFirst()
        }
        
        // 提取视频（优先 h264，兼容性最好）
        if let video = note["video"] as? [String: Any],
           let media = video["media"] as? [String: Any],
           let stream = media["stream"] as? [String: Any] {
            for codec in ["h264", "h265", "av1"] {
                if let streams = stream[codec] as? [[String: Any]] {
                    // 选择最高质量
                    let sorted = streams.sorted { ($0["width"] as? Int ?? 0) > ($1["width"] as? Int ?? 0) }
                    if let first = sorted.first,
                       let masterUrl = first["masterUrl"] as? String, !masterUrl.isEmpty {
                        videoURL = masterUrl
                        break
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

    // MARK: - Media Download
    
    func downloadMedia(content: ParsedContent, itemID: UUID, mediaDir: URL) async throws -> [MediaAsset] {
        var assets: [MediaAsset] = []
        let fileManager = FileManager.default
        let itemDir = mediaDir.appendingPathComponent(itemID.uuidString)
        try fileManager.createDirectory(at: itemDir, withIntermediateDirectories: true)
        
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
        
        for (index, imageURL) in content.imageURLs.enumerated() {
            guard let url = URL(string: imageURL) else { continue }
            let fileName = "image_\(String(format: "%03d", index + 1)).jpg"
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
        
        if let videoURL = content.videoURL, let url = URL(string: videoURL) {
            let fileName = "video.mp4"
            let localPath = itemDir.appendingPathComponent(fileName)
            if await downloadFile(from: url, to: localPath) {
                let fileSize = (try? fileManager.attributesOfItem(atPath: localPath.path)[.size] as? Int64) ?? 0
                let asset = MediaAsset(
                    itemID: itemID, type: .video,
                    localPath: "\(itemID.uuidString)/\(fileName)",
                    remoteURL: videoURL, fileName: fileName,
                    fileSize: fileSize,
                    downloadStatus: .completed
                )
                try MediaRepository().insert(asset)
                assets.append(asset)
            } else {
                let asset = MediaAsset(
                    itemID: itemID, type: .video,
                    remoteURL: videoURL, fileName: "video.mp4",
                    downloadStatus: .failed
                )
                try MediaRepository().insert(asset)
                assets.append(asset)
            }
        }
        
        return assets
    }
    
    // MARK: - Private
    
    private func extractMeta(_ html: String, property: String) -> String? {
        let patterns = [
            "<meta[^>]+property=\"\(property)\"[^>]+content=\"([^\"]+)\"",
            "<meta[^>]+content=\"([^\"]+)\"[^>]+property=\"\(property)\""
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
               let range = Range(match.range(at: 1), in: html) {
                return String(html[range])
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
