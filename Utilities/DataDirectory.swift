import Foundation

/// 统一管理数据存储目录
struct DataDirectory {
    private static let userDefaultsKey = "customDataDirectory"
    
    /// 获取基础目录（支持自定义）
    static var base: URL {
        if let customPath = UserDefaults.standard.string(forKey: userDefaultsKey) {
            let url = URL(fileURLWithPath: customPath)
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Archiver", isDirectory: true)
    }
    
    /// 媒体文件目录
    static var media: URL {
        base.appendingPathComponent("media", isDirectory: true)
    }
    
    /// 平台 Logo 目录
    static var platformLogos: URL {
        base.appendingPathComponent("platform_logos", isDirectory: true)
    }
    
    /// 数据库文件路径
    static var database: URL {
        base.appendingPathComponent("archiver.db")
    }
    
    /// 当前使用的目录路径
    static var currentPath: String {
        base.path
    }
    
    /// 是否使用自定义目录
    static var isCustom: Bool {
        UserDefaults.standard.string(forKey: userDefaultsKey) != nil
    }
    
    /// 设置自定义目录
    static func setCustom(_ path: String) {
        UserDefaults.standard.set(path, forKey: userDefaultsKey)
    }
    
    /// 恢复默认目录
    static func resetToDefault() {
        UserDefaults.standard.removeObject(forKey: userDefaultsKey)
    }
}
