import Foundation

/// 平台路由器 - 将 URL 路由到对应的解析器
@MainActor
final class PlatformRouter {
    static let shared = PlatformRouter()
    
    private let parsers: [ContentParser]
    
    private init() {
        parsers = [
            DouyinParser(),
            XiaohongshuParser(),
            CoolapkParser(),
            BilibiliParser(),
            GitHubParser(),
            YouTubeParser(),
            XParser(),
            WeiboParser(),
            ZhihuParser(),
            DoubanParser()
        ]
    }
    
    /// 识别 URL 所属平台
    func recognizePlatform(_ urlString: String) -> Platform? {
        URLNormalizer.recognizePlatform(urlString)
    }
    
    /// 获取对应的解析器
    func parser(for url: URL) -> ContentParser? {
        parsers.first { $0.canParse(url: url) }
    }
    
    /// 解析 URL
    func parse(urlString: String) async throws -> (ParsedContent, ContentParser) {
        guard URLNormalizer.isValidURL(urlString) else {
            throw ParserError.invalidURL
        }
        
        guard let url = URL(string: urlString) else {
            throw ParserError.invalidURL
        }
        
        guard let parser = parser(for: url) else {
            throw ParserError.unsupportedPlatform
        }
        
        let content = try await parser.parse(url: url)
        return (content, parser)
    }
}

/// 解析器错误
enum ParserError: LocalizedError {
    case invalidURL
    case unsupportedPlatform
    case parseFailed(reason: String)
    case mediaDownloadFailed(reason: String)
    case networkError(underlying: Error)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "链接格式不正确"
        case .unsupportedPlatform:
            return "暂不支持该平台"
        case .parseFailed(let reason):
            return "解析失败: \(reason)"
        case .mediaDownloadFailed(let reason):
            return "媒体下载失败: \(reason)"
        case .networkError(let error):
            return "网络错误: \(error.localizedDescription)"
        }
    }
}
