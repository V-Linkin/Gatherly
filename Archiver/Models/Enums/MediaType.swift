import Foundation

/// 媒体类型
enum MediaType: String, Codable {
    case image       // 内容图片
    case cover       // 封面图
    case video       // 视频
    case thumbnail   // 缩略图
}
