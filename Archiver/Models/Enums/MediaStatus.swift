import Foundation

/// 媒体保存状态
enum MediaStatus: String, Codable {
    case complete     // 完整保存
    case partial      // 部分保存（图片完整，视频可能缺失）
    case failed       // 全部失败
    case textOnly     // 纯文本（无媒体）
    
    var displayName: String {
        switch self {
        case .complete: return "完整"
        case .partial: return "部分保存"
        case .failed: return "保存失败"
        case .textOnly: return "纯文本"
        }
    }
}
