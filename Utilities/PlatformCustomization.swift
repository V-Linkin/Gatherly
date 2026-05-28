import Foundation

/// 内置平台自定义管理（显示名、Logo、隐藏状态）
struct PlatformCustomization {
    private static let prefix = "platform_custom_"
    
    static func displayName(for platform: Platform) -> String {
        guard platform != .custom else { return platform.rawValue }
        let key = "\(prefix)name_\(platform.rawValue)"
        return UserDefaults.standard.string(forKey: key) ?? platform.defaultDisplayName
    }
    
    static func setDisplayName(_ name: String, for platform: Platform) {
        let key = "\(prefix)name_\(platform.rawValue)"
        UserDefaults.standard.set(name, forKey: key)
    }
    
    static func logoPath(for platform: Platform) -> String? {
        guard platform != .custom else { return nil }
        let key = "\(prefix)logo_\(platform.rawValue)"
        return UserDefaults.standard.string(forKey: key)
    }
    
    static func setLogoPath(_ path: String?, for platform: Platform) {
        let key = "\(prefix)logo_\(platform.rawValue)"
        if let path = path {
            UserDefaults.standard.set(path, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
    
    static func isHidden(_ platform: Platform) -> Bool {
        guard platform != .custom else { return false }
        let key = "\(prefix)hidden_\(platform.rawValue)"
        return UserDefaults.standard.bool(forKey: key)
    }
    
    static func setHidden(_ hidden: Bool, _ platform: Platform) {
        let key = "\(prefix)hidden_\(platform.rawValue)"
        UserDefaults.standard.set(hidden, forKey: key)
    }
}
