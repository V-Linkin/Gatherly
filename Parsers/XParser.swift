import Foundation

/// X (Twitter) 解析器 - 通过 fxtwitter API 获取推文数据
final class XParser: BaseParser, @unchecked Sendable {
    
    override func canParse(url: URL) -> Bool {
        let host = url.host?.lowercased() ?? ""
        return host.contains("x.com") || host.contains("twitter.com")
    }
    
    override func extractContentID(from url: URL) -> String? {
        URLNormalizer.extractXID(url.absoluteString)
    }
    
    override func normalizeURL(_ url: String) -> String {
        URLNormalizer.normalize(url, platform: .x)
    }
    
    override func parse(url: URL) async throws -> ParsedContent {
        guard let tweetID = URLNormalizer.extractXID(url.absoluteString) else {
            throw ParserError.parseFailed(reason: "无法从链接提取推文ID")
        }
        
        guard let username = URLNormalizer.extractXUsername(url.absoluteString) else {
            throw ParserError.parseFailed(reason: "无法从链接提取用户名，请确保链接包含完整的用户名")
        }
        
        // 使用 fxtwitter API 获取推文数据
        let apiURL = URL(string: "https://api.fxtwitter.com/\(username)/status/\(tweetID)")!
        
        let (data, response) = try await session.data(from: apiURL)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw ParserError.parseFailed(reason: "无法获取推文数据 (HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0))")
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tweet = json["tweet"] as? [String: Any] else {
            throw ParserError.parseFailed(reason: "推文数据格式错误")
        }
        
        return parseTweetJSON(tweet, tweetID: tweetID)
    }
    
    override func downloadMedia(content: ParsedContent, itemID: UUID, mediaDir: URL) async throws -> [MediaAsset] {
        var assets: [MediaAsset] = []
        let fileManager = FileManager.default
        let itemDir = mediaDir.appendingPathComponent(itemID.uuidString)
        try fileManager.createDirectory(at: itemDir, withIntermediateDirectories: true)
        
        
        // 下载封面图
        if let coverURL = content.coverURL, let url = URL(string: coverURL) {
            let ext = url.pathExtension.isEmpty ? "jpg" : url.pathExtension
            let fileName = "cover.\(ext)"
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
        
        // 下载图片列表
        for (index, imageURL) in content.imageURLs.enumerated() {
            guard let url = URL(string: imageURL) else { continue }
            let ext = url.pathExtension.isEmpty ? "jpg" : url.pathExtension
            let fileName = "image_\(String(format: "%03d", index + 1)).\(ext)"
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
        
        // 下载视频
        if let videoURL = content.videoURL, let url = URL(string: videoURL) {
            let fileName = "video.mp4"
            let localPath = itemDir.appendingPathComponent(fileName)
            if await downloadFile(from: url, to: localPath) {
                let fileSize = (try? fileManager.attributesOfItem(atPath: localPath.path)[.size] as? Int64) ?? 0
                let asset = MediaAsset(
                    itemID: itemID, type: .video,
                    localPath: "\(itemID.uuidString)/\(fileName)",
                    remoteURL: videoURL, fileName: fileName,
                    fileSize: fileSize, downloadStatus: .completed
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
        
        // 如果没有图片也没有视频，下载作者头像作为封面
        if content.coverURL == nil, content.imageURLs.isEmpty, content.videoURL == nil,
           let avatarURL = content.rawMetadata["avatarURL"],
           let url = URL(string: avatarURL) {
            let fileName = "avatar.jpg"
            let localPath = itemDir.appendingPathComponent(fileName)
            if await downloadFile(from: url, to: localPath) {
                let fileSize = (try? fileManager.attributesOfItem(atPath: localPath.path)[.size] as? Int64) ?? 0
                let asset = MediaAsset(
                    itemID: itemID, type: .cover,
                    localPath: "\(itemID.uuidString)/\(fileName)",
                    remoteURL: avatarURL, fileName: fileName,
                    fileSize: fileSize, downloadStatus: .completed
                )
                try MediaRepository().insert(asset)
                assets.append(asset)
            }
        }
        
        return assets
    }
    
    // MARK: - Private
    
    /// 解析 fxtwitter API 返回的推文 JSON
    private func parseTweetJSON(_ tweet: [String: Any], tweetID: String) -> ParsedContent {
        // 正文
        let fullText = tweet["text"] as? String
        
        // 作者信息
        var author: String?
        var authorID: String?
        var avatarURL: String?
        if let authorData = tweet["author"] as? [String: Any] {
            author = authorData["name"] as? String
            authorID = authorData["screen_name"] as? String
            avatarURL = authorData["avatar_url"] as? String
        }
        
        // 发布时间
        var publishDate: Date?
        if let createdAt = tweet["created_at"] as? String {
            publishDate = parseXDate(createdAt)
        } else if let timestamp = tweet["created_timestamp"] as? TimeInterval {
            publishDate = Date(timeIntervalSince1970: timestamp)
        }
        
        // 媒体
        var imageURLs: [String] = []
        var coverURL: String?
        var videoURL: String?
        
        if let media = tweet["media"] as? [String: Any] {
            // 图片
            if let photos = media["photos"] as? [[String: Any]] {
                for photo in photos {
                    if let url = photo["url"] as? String {
                        imageURLs.append(url)
                    }
                }
            }
            
            // 视频
            if let videos = media["videos"] as? [[String: Any]],
               let firstVideo = videos.first {
                if let url = firstVideo["url"] as? String {
                    videoURL = url
                } else if let preview = firstVideo["preview"] as? String {
                    videoURL = preview
                }
                // 视频缩略图作为封面
                if let thumb = firstVideo["thumbnail_url"] as? String {
                    coverURL = thumb
                }
            }
            
            // GIF
            if let gifs = media["gifs"] as? [[String: Any]],
               let firstGif = gifs.first {
                if let url = firstGif["url"] as? String {
                    videoURL = url
                }
                if let thumb = firstGif["thumbnail_url"] as? String {
                    coverURL = thumb
                }
            }
        }
        
        if let videos = (tweet["media"] as? [String: Any])?["videos"] as? [[String: Any]],
           let first = videos.first {
                }
        
        // 如果没有图片，检查 quote 中的媒体
        if imageURLs.isEmpty, let quote = tweet["quote"] as? [String: Any],
           let quoteMedia = quote["media"] as? [String: Any],
           let photos = quoteMedia["photos"] as? [[String: Any]] {
            for photo in photos {
                if let url = photo["url"] as? String {
                    imageURLs.append(url)
                }
            }
        }
        
        if coverURL == nil {
            coverURL = imageURLs.first ?? avatarURL
        }
        
        // 互动数据
        let likes = tweet["likes"] as? Int ?? 0
        let retweets = tweet["retweets"] as? Int ?? 0
        let replies = tweet["replies"] as? Int ?? 0
        let bookmarks = tweet["bookmarks"] as? Int ?? 0
        let views = tweet["views"] as? Int ?? 0
        
        var metadata: [String: String] = [
            "likes": "\(likes)",
            "retweets": "\(retweets)",
            "replies": "\(replies)",
            "bookmarks": "\(bookmarks)",
            "views": "\(views)"
        ]
        if let avatarURL = avatarURL {
            metadata["avatarURL"] = avatarURL
        }
        if let authorID = authorID {
            metadata["screenName"] = authorID
        }
        
        
        // 封面去重：如果封面等于首张图片，从图片列表中移除首张
        if let cover = coverURL, cover == imageURLs.first {
                imageURLs.removeFirst()
        } else {
            }
        
        
        // 标题取正文前 50 字
        let title = fullText.map { String($0.prefix(50)) }
        
        return ParsedContent(
            title: title,
            body: fullText,
            author: author,
            authorID: authorID,
            publishDate: publishDate,
            coverURL: coverURL,
            imageURLs: imageURLs,
            videoURL: videoURL,
            platformContentID: tweetID,
            rawMetadata: metadata
        )
    }
    
    /// 解析 X 的日期格式: "Tue May 26 15:44:05 +0000 2026"
    private func parseXDate(_ dateString: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE MMM dd HH:mm:ss Z yyyy"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.date(from: dateString)
    }
}
