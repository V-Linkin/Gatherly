import Foundation

/// 归档状态（分类）
enum ArchiveStatus: String, Codable, CaseIterable {
    case favorite     // 收藏
    case inspiration  // 灵感
    case pending      // 待整理（默认）
    case archived     // 已归档
    
    var displayName: String {
        switch self {
        case .favorite: return "收藏"
        case .inspiration: return "灵感"
        case .pending: return "待整理"
        case .archived: return "已归档"
        }
    }
    
    var iconName: String {
        switch self {
        case .favorite: return "star.fill"
        case .inspiration: return "lightbulb.fill"
        case .pending: return "tray.full.fill"
        case .archived: return "archivebox.fill"
        }
    }
}
