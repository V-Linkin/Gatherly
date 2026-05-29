import Foundation
import SwiftUI

/// 平台枚举
enum Platform: String, Codable, CaseIterable, Identifiable {
    case douyin
    case xiaohongshu
    case coolapk
    case bilibili
    case github
    case youtube
    case x
    case weibo
    case zhihu
    case douban
    case custom
    
    var id: String { rawValue }
    
    var defaultDisplayName: String {
        switch self {
        case .douyin: return "抖音"
        case .xiaohongshu: return "小红书"
        case .coolapk: return "酷安"
        case .bilibili: return "B站"
        case .github: return "GitHub"
        case .youtube: return "YouTube"
        case .x: return "X"
        case .weibo: return "微博"
        case .zhihu: return "知乎"
        case .douban: return "豆瓣"
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
        case .youtube: return "play.rectangle.fill"
        case .x: return "bubble.left.and.bubble.right.fill"
        case .weibo: return "bubble.left.and.bubble.right.fill"
        case .zhihu: return "text.bubble.fill"
        case .douban: return "book.closed.fill"
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
        case .youtube: return .red
        case .x: return .black
        case .weibo: return Color(red: 255/255, green: 96/255, blue: 0/255)
        case .zhihu: return Color(red: 0/255, green: 102/255, blue: 255/255)
        case .douban: return Color(red: 0/255, green: 150/255, blue: 0/255)
        case .custom: return .purple
        }
    }
}
