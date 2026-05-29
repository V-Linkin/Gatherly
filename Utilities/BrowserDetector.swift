import Foundation
import AppKit

@MainActor
class BrowserDetector {
    static let shared = BrowserDetector()
    
    private let selectedBrowserKey = "selectedBrowserBundleIdentifier"
    
    private let knownBrowsers: [String: String] = [
        "com.apple.Safari": "Safari",
        "com.google.Chrome": "Google Chrome",
        "org.mozilla.firefox": "Firefox",
        "com.microsoft.edgemac": "Microsoft Edge",
        "company.thebrowser.Browser": "Arc"
    ]
    
    private init() {}
    
    // MARK: - Public Methods
    
    func getAvailableBrowsers() -> [BrowserInfo] {
        var browsers: [BrowserInfo] = []
        
        for (bundleIdentifier, name) in knownBrowsers {
            if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
                let version = getAppVersion(at: appURL)
                let icon = NSWorkspace.shared.icon(forFile: appURL.path)
                
                let browser = BrowserInfo(
                    bundleIdentifier: bundleIdentifier,
                    name: name,
                    version: version,
                    icon: icon
                )
                browsers.append(browser)
            }
        }
        
        return browsers.sorted { $0.name < $1.name }
    }
    
    func getSelectedBrowserBundleIdentifier() -> String {
        return UserDefaults.standard.string(forKey: selectedBrowserKey) ?? ""
    }
    
    func setSelectedBrowser(_ bundleIdentifier: String) {
        UserDefaults.standard.set(bundleIdentifier, forKey: selectedBrowserKey)
    }
    
    func openURL(_ url: URL) {
        let bundleIdentifier = getSelectedBrowserBundleIdentifier()
        
        if bundleIdentifier.isEmpty {
            // 使用系统默认浏览器
            NSWorkspace.shared.open(url)
        } else {
            // 根据 bundle identifier 查找浏览器应用
            guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
                // 浏览器不存在，回退到默认浏览器
                NSWorkspace.shared.open(url)
                return
            }
            
            // 指定浏览器打开
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            
            NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: configuration)
        }
    }
    
    func getSelectedBrowserName() -> String {
        let bundleIdentifier = getSelectedBrowserBundleIdentifier()
        if bundleIdentifier.isEmpty {
            return "系统默认"
        }
        return knownBrowsers[bundleIdentifier] ?? "未知浏览器"
    }
    
    func isBrowserAvailable(_ bundleIdentifier: String) -> Bool {
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) != nil
    }
    
    // MARK: - Private Methods
    
    private func getAppVersion(at appURL: URL) -> String {
        guard let infoPlist = NSDictionary(contentsOfFile: appURL.appendingPathComponent("Contents/Info.plist").path),
              let version = infoPlist["CFBundleShortVersionString"] as? String else {
            return "未知"
        }
        return version
    }
}

struct BrowserInfo: Identifiable {
    let id = UUID()
    let bundleIdentifier: String
    let name: String
    let version: String
    let icon: NSImage?
}
