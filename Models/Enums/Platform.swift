import Foundation
import SwiftUI

/// 平台枚举
enum Platform: String, Codable, CaseIterable, Identifiable {
    case douyin
    case xiaohongshu
    case coolapk
    case bilibili
    case github
    case custom
    
    var id: String { rawValue }
    
    var defaultDisplayName: String {
        switch self {
        case .douyin: return "抖音"
        case .xiaohongshu: return "小红书"
        case .coolapk: return "酷安"
        case .bilibili: return "B站"
        case .github: return "GitHub"
        case .custom: return "自定义"
        }
    }
    
    var displayName: String {
        PlatformCustomization.displayName(for: self)
    }
    
    var iconName: String {
        switch self {
        case .douyin: return "music.note"
        case .xiaohongshu: return "book.fill"
        case .coolapk: return "apps.iphone"
        case .bilibili: return "play.tv"
        case .github: return "chevron.left.forwardslash.chevron.right"
        case .custom: return "star.fill"
        }
    }
    
    var brandColor: Color {
        switch self {
        case .douyin: return .black
        case .xiaohongshu: return .red
        case .coolapk: return .green
        case .bilibili: return .cyan
        case .github: return .primary
        case .custom: return .purple
        }
    }
}
