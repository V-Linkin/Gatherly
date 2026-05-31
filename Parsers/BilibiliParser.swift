import Foundation

/// B站解析器 — 使用 AJAX API 获取视频数据
final class BilibiliParser: BaseParser, @unchecked Sendable {
    
    init() {
        super.init(additionalHeaders: [
            "Referer": "https://www.bilibili.com/"
        ])
    }
    
    override func canParse(url: URL) -> Bool {
        let host = url.host?.lowercased() ?? ""
        return host.contains("bilibili.com") || host.contains("b23.tv")
    }
    
    override func extractContentID(from url: URL) -> String? {
        URLNormalizer.extractContentID(url.absoluteString, platform: .bilibili)
    }
    
    override func normalizeURL(_ url: String) -> String {
        URLNormalizer.normalize(url, platform: .bilibili)
    }
    
    override func parse(url: URL) async throws -> ParsedContent {
        let resolvedURL = try await resolveShortURL(url)
        
        guard let bvid = extractBVID(from: resolvedURL) else {
            throw ParserError.parseFailed(reason: "无法提取 B站视频 ID")
        }
        
        let apiURLString = "https://api.bilibili.com/x/web-interface/view?bvid=\(bvid)"
        guard let apiURL = URL(string: apiURLString) else {
            throw ParserError.parseFailed(reason: "API URL 无效")
        }
        
        let (data, response) = try await session.data(from: apiURL)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw ParserError.parseFailed(reason: "API 请求失败")
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let responseData = json["data"] as? [String: Any] else {
            throw ParserError.parseFailed(reason: "API 返回数据格式错误")
        }
        
        let title = responseData["title"] as? String ?? "未知标题"
        let description = responseData["desc"] as? String ?? ""
        var coverURL = responseData["pic"] as? String
        
        if let cover = coverURL, cover.hasPrefix("//") {
            coverURL = "https:" + cover
        } else if let cover = coverURL, cover.hasPrefix("http://") {
            coverURL = cover.replacingOccurrences(of: "http://", with: "https://")
        }
        
        var author = "未知作者"
        if let owner = responseData["owner"] as? [String: Any],
           let name = owner["name"] as? String {
            author = name
        }
        
        var publishDate: Date?
        if let pubdate = responseData["pubdate"] as? TimeInterval {
            publishDate = Date(timeIntervalSince1970: pubdate)
        }
        
        return ParsedContent(
            title: title,
            body: description.isEmpty ? nil : description,
            author: author,
            authorID: nil,
            publishDate: publishDate,
            coverURL: coverURL,
            imageURLs: [],
            videoURL: nil,
            platformContentID: bvid
        )
    }
    
    private func extractBVID(from url: URL) -> String? {
        let urlString = url.absoluteString
        let patterns = [
            "bilibili\\.com/video/(BV[a-zA-Z0-9]+)",
            "bilibili\\.com/video/(av\\d+)"
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
    
    private func resolveShortURL(_ url: URL) async throws -> URL {
        guard url.host?.contains("b23.tv") == true else { return url }
        
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        let (_, response) = try await session.data(for: request)
        
        if let httpResponse = response as? HTTPURLResponse,
           let location = httpResponse.value(forHTTPHeaderField: "Location"),
           let redirectURL = URL(string: location) {
            return redirectURL
        }
        return url
    }
}
