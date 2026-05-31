import Foundation

/// URL 标准化器 - 用于去重
struct URLNormalizer {
    
    /// 从混合文本中提取所有支持平台的 URL
    static func extractURLs(from text: String) -> [String] {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let range = NSRange(text.startIndex..., in: text)
        let matches = detector?.matches(in: text, options: [], range: range) ?? []
        
        var results: [String] = []
        for match in matches {
            guard let urlRange = Range(match.range, in: text) else { continue }
            let urlString = String(text[urlRange])
            if recognizePlatform(urlString) != nil {
                results.append(urlString)
            }
        }
        return results
    }
    
    /// 从混合文本中提取第一个支持的 URL
    static func extractFirstURL(from text: String) -> String? {
        return extractURLs(from: text).first
    }
    
    /// 从 URL 中识别平台
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
        if lower.contains("x.com") || lower.contains("twitter.com") {
            return .x
        }
        if lower.contains("weibo.com") || lower.contains("m.weibo.cn") {
            return .weibo
        }
        if lower.contains("zhihu.com") {
            return .zhihu
        }
        if lower.contains("douban.com") {
            return .douban
        }
        
        return nil
    }
    
    /// 标准化 URL（去除追踪参数，提取内容 ID）
    static func normalize(_ urlString: String, platform: Platform) -> String {
        switch platform {
        case .douyin:
            return normalizeDouyin(urlString)
        case .xiaohongshu:
            return normalizeXiaohongshu(urlString)
        case .coolapk:
            return normalizeCoolapk(urlString)
        case .bilibili:
            return normalizeBilibili(urlString)
        case .github:
            return normalizeGitHub(urlString)
        case .youtube:
            return normalizeYouTube(urlString)
        case .x:
            return normalizeX(urlString)
        case .weibo:
            return normalizeWeibo(urlString)
        case .zhihu:
            return normalizeZhihu(urlString)
        case .douban:
            return normalizeDouban(urlString)
        case .custom:
            return urlString
        }
    }
    
    /// 提取平台内容 ID
    static func extractContentID(_ urlString: String, platform: Platform) -> String? {
        switch platform {
        case .douyin:
            return extractDouyinID(urlString)
        case .xiaohongshu:
            return extractXiaohongshuID(urlString)
        case .coolapk:
            return extractCoolapkID(urlString)
        case .bilibili:
            return extractBilibiliID(urlString)
        case .github:
            return extractGitHubID(urlString)
        case .youtube:
            return extractYouTubeID(urlString)
        case .x:
            return extractXID(urlString)
        case .weibo:
            return extractWeiboID(urlString)
        case .zhihu:
            return extractZhihuID(urlString)
        case .douban:
            return extractDoubanID(urlString)
        case .custom:
            return nil
        }
    }
    
    // MARK: - 抖音
    
    private static func normalizeDouyin(_ url: String) -> String {
        if let id = extractDouyinID(url) {
            return "douyin://video/\(id)"
        }
        return url
    }
    
    private static func extractDouyinID(_ url: String) -> String? {
        let patterns = [
            "douyin\\.com/video/(\\d+)",
            "iesdouyin\\.com/share/video/(\\d+)"
        ]
        return extractFirstMatch(url, patterns: patterns)
    }
    
    // MARK: - 小红书
    
    private static func normalizeXiaohongshu(_ url: String) -> String {
        if let id = extractXiaohongshuID(url) {
            return "xiaohongshu://explore/\(id)"
        }
        return url
    }
    
    private static func extractXiaohongshuID(_ url: String) -> String? {
        let patterns = [
            "xiaohongshu\\.com/explore/([a-f0-9]+)",
            "xiaohongshu\\.com/discovery/item/([a-f0-9]+)"
        ]
        return extractFirstMatch(url, patterns: patterns)
    }
    
    // MARK: - 酷安
    
    private static func normalizeCoolapk(_ url: String) -> String {
        if let id = extractCoolapkID(url) {
            return "coolapk://feed/\(id)"
        }
        return url
    }
    
    private static func extractCoolapkID(_ url: String) -> String? {
        let patterns = [
            "coolapk\\.com/feed/(\\d+)",
            "coolapk1s\\.com/feed/(\\d+)"
        ]
        return extractFirstMatch(url, patterns: patterns)
    }
    
    // MARK: - B站
    
    private static func normalizeBilibili(_ url: String) -> String {
        if let id = extractBilibiliID(url) {
            return "bilibili://video/\(id)"
        }
        return url
    }
    
    private static func extractBilibiliID(_ url: String) -> String? {
        let patterns = [
            "bilibili\\.com/video/(BV[a-zA-Z0-9]+)",
            "bilibili\\.com/video/(av\\d+)"
        ]
        return extractFirstMatch(url, patterns: patterns)
    }
    
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
    
    // MARK: - YouTube
    
    private static func normalizeYouTube(_ url: String) -> String {
        if let id = extractYouTubeID(url) {
            return "youtube://video/\(id)"
        }
        return url
    }
    
    static func extractYouTubeID(_ url: String) -> String? {
        let patterns = [
            "youtube\\.com/watch\\?v=([a-zA-Z0-9_-]{11})",
            "youtu\\.be/([a-zA-Z0-9_-]{11})",
            "youtube\\.com/embed/([a-zA-Z0-9_-]{11})",
            "youtube\\.com/shorts/([a-zA-Z0-9_-]{11})",
            "youtube\\.com/channel/([a-zA-Z0-9_-]+)",
            "youtube\\.com/@([a-zA-Z0-9._-]+)"
        ]
        return extractFirstMatch(url, patterns: patterns)
    }
    
    // MARK: - X (Twitter)
    
    private static func normalizeX(_ url: String) -> String {
        if let id = extractXID(url) {
            return "x://tweet/\(id)"
        }
        return url
    }
    
    static func extractXID(_ url: String) -> String? {
        let patterns = [
            "(?:x|twitter)\\.com/[^/]+/status/(\\d+)",
            "(?:x|twitter)\\.com/i/status/(\\d+)"
        ]
        return extractFirstMatch(url, patterns: patterns)
    }
    
    static func extractXUsername(_ url: String) -> String? {
        let patterns = [
            "(?:x|twitter)\\.com/([a-zA-Z0-9_]+)/status/",
            "(?:x|twitter)\\.com/([a-zA-Z0-9_]+)$"
        ]
        return extractFirstMatch(url, patterns: patterns)
    }
    
    // MARK: - 微博
    
    private static func normalizeWeibo(_ url: String) -> String {
        if let id = extractWeiboID(url) {
            return "weibo://status/\(id)"
        }
        return url
    }
    
    static func extractWeiboID(_ url: String) -> String? {
        let patterns = [
            "weibo\\.com/status/(\\d+)",
            "weibo\\.com/\\d+/([a-zA-Z0-9]+)",
            "m\\.weibo\\.cn/detail/(\\d+)",
            "m\\.weibo\\.cn/status/(\\d+)"
        ]
        return extractFirstMatch(url, patterns: patterns)
    }
    
    // MARK: - 知乎
    
    private static func normalizeZhihu(_ url: String) -> String {
        if let id = extractZhihuID(url) {
            return "zhihu://content/\(id)"
        }
        return url
    }
    
    static func extractZhihuID(_ url: String) -> String? {
        let patterns = [
            "zhihu\\.com/question/\\d+/answer/(\\d+)",
            "zhihu\\.com/p/(\\d+)",
            "zhihu\\.com/column/([a-zA-Z0-9_-]+)"
        ]
        return extractFirstMatch(url, patterns: patterns)
    }
    
    // MARK: - 豆瓣
    
    private static func normalizeDouban(_ url: String) -> String {
        if let id = extractDoubanID(url) {
            return "douban://subject/\(id)"
        }
        return url
    }
    
    static func extractDoubanID(_ url: String) -> String? {
        let patterns = [
            "douban\\.com/subject/(\\d+)"
        ]
        return extractFirstMatch(url, patterns: patterns)
    }
    
    // MARK: - Helper
    
    static func extractFirstMatch(_ text: String, patterns: [String]) -> String? {
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               let range = Range(match.range(at: 1), in: text) {
                return String(text[range])
            }
        }
        return nil
    }
    
    /// 验证 URL 是否合法
    static func isValidURL(_ urlString: String) -> Bool {
        guard let url = URL(string: urlString),
              let scheme = url.scheme,
              ["http", "https"].contains(scheme.lowercased()) else {
            return false
        }
        return true
    }
}
