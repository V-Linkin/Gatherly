import Foundation

/// 内容状态
enum ContentStatus: String, Codable, CaseIterable {
    case normal          // 正常
    case parseFailed     // 解析失败
    case mediaIncomplete // 媒体未完整保存
    case sourceDeleted   // 原始内容已被删除
    case trashed         // 回收站中
    
    var displayName: String {
        switch self {
        case .normal: return "正常"
        case .parseFailed: return "解析失败"
        case .mediaIncomplete: return "媒体未完整保存"
        case .sourceDeleted: return "原始内容已删除"
        case .trashed: return "回收站中"
        }
    }
    
    var iconName: String {
        switch self {
        case .normal: return "checkmark.circle.fill"
        case .parseFailed: return "exclamationmark.triangle.fill"
        case .mediaIncomplete: return "photo.on.rectangle.angled"
        case .sourceDeleted: return "trash.slash"
        case .trashed: return "trash.fill"
        }
    }
}
