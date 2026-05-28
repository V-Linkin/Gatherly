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
        // https://www.douyin.com/video/7351234567890
        // https://v.douyin.com/xxxxx/
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
        // https://www.xiaohongshu.com/explore/64a1b2c3d4e5f6789
        // https://www.xiaohongshu.com/discovery/item/64a1b2c3d4e5f6789
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
        // https://www.coolapk.com/feed/12345678
        // https://www.coolapk.com/feed?url=xxx
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
        // https://www.bilibili.com/video/BV1xx411c7mD
        // https://b23.tv/xxxxx
        let patterns = [
            "bilibili\\.com/video/(BV[a-zA-Z0-9]+)",
            "bilibili\\.com/video/(av\\d+)"
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
