import Foundation
import SwiftUI

/// 平台枚举
enum Platform: String, Codable, CaseIterable, Identifiable {
    case douyin
    case xiaohongshu
    case coolapk
    case bilibili
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .douyin: return "抖音"
        case .xiaohongshu: return "小红书"
        case .coolapk: return "酷安"
        case .bilibili: return "B站"
        }
    }
    
    var iconName: String {
        switch self {
        case .douyin: return "music.note"
        case .xiaohongshu: return "book.fill"
        case .coolapk: return "apps.iphone"
        case .bilibili: return "play.tv"
        }
    }
    
    var brandColor: Color {
        switch self {
        case .douyin: return .black
        case .xiaohongshu: return .red
        case .coolapk: return .green
        case .bilibili: return .cyan
        }
    }
}
