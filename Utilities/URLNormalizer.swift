import Foundation

/// URL 标准化器 - 用于去重
struct URLNormalizer {
    
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
    
    // MARK: - Helper
    
    private static func extractFirstMatch(_ text: String, patterns: [String]) -> String? {
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
