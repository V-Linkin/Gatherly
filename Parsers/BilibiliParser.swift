import Foundation

/// B站解析器
final class BilibiliParser: BaseParser {
    
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
        
        let (data, response) = try await session.data(from: resolvedURL)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw ParserError.parseFailed(reason: "HTTP 请求失败")
        }
        
        guard let html = String(data: data, encoding: .utf8) else {
            throw ParserError.parseFailed(reason: "无法解析 HTML")
        }
        
        let title = extractMeta(html, property: "og:title") ?? extractTitle(from: html) ?? "未知标题"
        let description = extractMeta(html, property: "og:description") ?? ""
        let coverURL = extractMeta(html, property: "og:image")
        let author = extractMeta(html, name: "author") ?? "未知作者"
        
        // 尝试从 HTML 中提取图片
        var imageURLs: [String] = []
        let imagePattern = "<img[^>]+src=\"([^\"]+)\""
        if let regex = try? NSRegularExpression(pattern: imagePattern, options: .caseInsensitive) {
            let matches = regex.matches(in: html, range: NSRange(html.startIndex..., in: html))
            for match in matches {
                if let range = Range(match.range(at: 1), in: html) {
                    let imageURL = String(html[range])
                    if imageURL.contains("bilibili") || imageURL.contains("http") {
                        imageURLs.append(imageURL)
                    }
                }
            }
        }
        
        return ParsedContent(
            title: title,
            body: description,
            author: author,
            coverURL: coverURL,
            imageURLs: imageURLs,
            platformContentID: extractContentID(from: url)
        )
    }
    
    private func extractTitle(from html: String) -> String? {
        let pattern = "<title[^>]*>([^<]+)</title>"
        if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
           let range = Range(match.range(at: 1), in: html) {
            return String(html[range]).trimmingCharacters(in: .whitespacesAndNewlines)
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
