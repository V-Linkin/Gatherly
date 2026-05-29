# 浏览器选择功能实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在拾屿应用的设置页面中添加浏览器选择功能，让用户可以选择使用哪个浏览器打开内容的原始链接。

**Architecture:** 
1. 创建 `BrowserDetector` 工具类，负责浏览器检测、版本获取、图标获取和选择管理
2. 修改 `SettingsView`，添加浏览器设置Section，使用下拉菜单让用户选择浏览器
3. 修改内容详情页的链接打开逻辑，使用选中的浏览器打开链接

**Tech Stack:** Swift, SwiftUI, NSWorkspace, UserDefaults

---

### Task 1: 创建 BrowserDetector 工具类

**Files:**
- Create: `Utilities/BrowserDetector.swift`

- [ ] **Step 1: 创建 BrowserDetector 类框架**

```swift
import Foundation
import AppKit

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
```

- [ ] **Step 2: 运行测试验证**

运行：`swift build` 预期：编译成功，无错误

- [ ] **Step 3: 提交**

```bash
git add Utilities/BrowserDetector.swift
git commit -m "feat: add BrowserDetector utility class"
```

---

### Task 2: 修改 SettingsView 添加浏览器设置Section

**Files:**
- Modify: `Views/Settings/SettingsView.swift`

- [ ] **Step 1: 添加浏览器设置Section**

```swift
// MARK: - Browser Settings

private var browserSection: some View {
    Section("浏览器设置") {
        VStack(alignment: .leading, spacing: 8) {
            HStack { 
                Label("默认浏览器", systemImage: "globe"); 
                Spacer()
                Picker("", selection: Binding(
                    get: { BrowserDetector.shared.getSelectedBrowserBundleIdentifier() },
                    set: { BrowserDetector.shared.setSelectedBrowser($0) }
                )) {
                    Text("系统默认").tag("")
                    ForEach(BrowserDetector.shared.getAvailableBrowsers()) { browser in
                        HStack {
                            if let icon = browser.icon {
                                Image(nsImage: icon)
                                    .resizable()
                                    .frame(width: 16, height: 16)
                            }
                            Text("\(browser.name) (\(browser.version))")
                        }
                        .tag(browser.bundleIdentifier)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 250)
            }
        }
        Text("选择用于打开内容原始链接的浏览器").font(.caption).foregroundStyle(.secondary)
    }
}
```

- [ ] **Step 2: 修改 body 属性，添加新的Section**

```swift
var body: some View {
    Form {
        storageSection
        backupSection
        browserSection  // 新增
        aboutSection
    }
    .formStyle(.grouped)
    .navigationTitle("设置")
    .onAppear { loadStats() }
    .onDisappear { updateChecker.status = .idle; updateChecker.isChecking = false }
    // ... 其他修饰符保持不变
}
```

- [ ] **Step 3: 优化所有Section标题样式**

```swift
// 在 body 属性中添加统一的Section标题样式
Form {
    storageSection
    backupSection
    browserSection
    aboutSection
}
.formStyle(.grouped)
.sectionHeaderFont(.body.weight(.semibold))  // 统一Section标题样式
```

- [ ] **Step 4: 运行测试验证**

运行：`swift build` 预期：编译成功，设置页面显示新的浏览器设置Section

- [ ] **Step 5: 提交**

```bash
git add Views/Settings/SettingsView.swift
git commit -m "feat: add browser settings section to SettingsView"
```

---

### Task 3: 修改内容详情页的链接打开逻辑

**Files:**
- Modify: `Views/Item/ItemDetailView.swift`

- [ ] **Step 1: 找到链接打开代码位置**

```swift
// 在 ItemDetailView 中找到类似这样的代码
Link(destination: URL(string: item.originalURL)!) {
    Label("查看原始内容", systemImage: "link")
}
```

- [ ] **Step 2: 修改为使用 BrowserDetector**

```swift
Button {
    if let url = URL(string: item.originalURL) {
        BrowserDetector.shared.openURL(url)
    }
} label: {
    Label("查看原始内容", systemImage: "link")
}
```

- [ ] **Step 3: 运行测试验证**

运行：`swift build` 预期：编译成功，点击链接使用选中的浏览器打开

- [ ] **Step 4: 提交**

```bash
git add Views/Item/ItemDetailView.swift
git commit -m "feat: use selected browser to open links"
```

---

### Task 4: 创建单元测试

**Files:**
- Create: `Tests/Utilities/BrowserDetectorTests.swift`

- [ ] **Step 1: 创建测试文件框架**

```swift
import XCTest
@testable import Archiver

final class BrowserDetectorTests: XCTestCase {
    var browserDetector: BrowserDetector!
    
    override func setUp() {
        super.setUp()
        browserDetector = BrowserDetector.shared
    }
    
    override func tearDown() {
        // 清理测试数据
        UserDefaults.standard.removeObject(forKey: "selectedBrowserBundleIdentifier")
        super.tearDown()
    }
    
    func testGetAvailableBrowsers() {
        // Given
        // When
        let browsers = browserDetector.getAvailableBrowsers()
        
        // Then
        XCTAssertFalse(browsers.isEmpty, "应该检测到至少一个浏览器")
        
        // 验证每个浏览器都有有效的信息
        for browser in browsers {
            XCTAssertFalse(browser.bundleIdentifier.isEmpty)
            XCTAssertFalse(browser.name.isEmpty)
            XCTAssertFalse(browser.version.isEmpty)
        }
    }
    
    func testGetSelectedBrowserBundleIdentifier() {
        // Given
        let testBundleId = "com.apple.Safari"
        
        // When
        browserDetector.setSelectedBrowser(testBundleId)
        let retrievedBundleId = browserDetector.getSelectedBrowserBundleIdentifier()
        
        // Then
        XCTAssertEqual(retrievedBundleId, testBundleId)
    }
    
    func testSetSelectedBrowserWithEmptyString() {
        // Given
        let emptyBundleId = ""
        
        // When
        browserDetector.setSelectedBrowser(emptyBundleId)
        let retrievedBundleId = browserDetector.getSelectedBrowserBundleIdentifier()
        
        // Then
        XCTAssertEqual(retrievedBundleId, emptyBundleId)
    }
    
    func testGetSelectedBrowserName() {
        // Given
        // 测试默认情况
        browserDetector.setSelectedBrowser("")
        
        // When
        let name = browserDetector.getSelectedBrowserName()
        
        // Then
        XCTAssertEqual(name, "系统默认")
    }
    
    func testIsBrowserAvailable() {
        // Given
        let safariBundleId = "com.apple.Safari"
        let invalidBundleId = "com.nonexistent.browser"
        
        // When
        let safariAvailable = browserDetector.isBrowserAvailable(safariBundleId)
        let invalidAvailable = browserDetector.isBrowserAvailable(invalidBundleId)
        
        // Then
        XCTAssertTrue(safariAvailable, "Safari应该可用")
        XCTAssertFalse(invalidAvailable, "不存在的浏览器应该不可用")
    }
}
```

- [ ] **Step 2: 运行测试验证**

运行：`swift test` 预期：所有测试通过

- [ ] **Step 3: 提交**

```bash
git add Tests/Utilities/BrowserDetectorTests.swift
git commit -m "test: add unit tests for BrowserDetector"
```

---

### Task 5: 集成测试和验收

**Files:**
- No new files, manual testing

- [ ] **Step 1: 运行完整测试套件**

运行：`swift test` 预期：所有测试通过

- [ ] **Step 2: 手动测试设置页面**

1. 打开设置页面
2. 验证显示"浏览器设置"Section
3. 验证下拉菜单显示检测到的浏览器
4. 选择不同浏览器，验证选择立即保存
5. 验证所有Section标题高度一致

- [ ] **Step 3: 手动测试链接打开**

1. 打开一个内容详情页
2. 点击原始链接
3. 验证使用选中的浏览器打开
4. 切换浏览器设置，再次点击链接验证使用新浏览器

- [ ] **Step 4: 提交最终版本**

```bash
git add .
git commit -m "feat: complete browser selection feature"
```

---

## 验收标准检查清单

- [ ] 设置页面显示新的"浏览器设置"部分
- [ ] 下拉菜单显示检测到的浏览器列表
- [ ] 选择浏览器后立即保存，无需重启
- [ ] 内容详情页点击链接时使用选中的浏览器打开
- [ ] 所有Section标题和内容行高度一致
- [ ] 错误情况下静默回退到默认浏览器
- [ ] 所有单元测试通过
- [ ] 手动测试通过
