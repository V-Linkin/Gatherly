# 浏览器选择功能设计文档

## 概述

在拾屿应用的设置页面中添加浏览器选择功能，让用户可以选择使用哪个浏览器打开内容的原始链接。

## 设计目标

1. **简洁易用**：用户可以通过下拉菜单快速选择浏览器
2. **立即生效**：选择后无需重启应用，立即生效
3. **自动检测**：自动检测系统中安装的常见浏览器
4. **视觉一致**：与现有设置页面的UI风格保持一致

## 功能设计

### 1. 功能位置

在设置页面创建新的"浏览器设置"部分，位于"备份与还原"之后，"关于"之前。

**设置页面结构：**
- 存储管理
- 备份与还原
- **浏览器设置**（新增）
- 关于

### 2. UI设计

#### Section标题样式
- 字体大小：16px
- 字重：加粗
- 颜色：#2c3e50（深色）
- 高度：固定40px，垂直居中
- 底部边框：1px solid #eee

#### 内容行样式
- 字体大小：14px
- 字重：中等粗细
- 高度：固定36px，垂直居中
- 底部边框：1px solid #f5f5f5

#### 说明文字样式
- 字体大小：12px
- 颜色：#666（浅色）
- 底部内边距：8px

### 3. 浏览器选择控件

**控件类型**：下拉菜单（Picker）

**下拉菜单内容：**
- 默认选项："系统默认浏览器"
- 浏览器选项：显示浏览器图标 + 名称 + 版本号
- 示例：`🦊 Safari (17.4)`、`🌐 Google Chrome (124.0.6367.91)`

**支持的浏览器：**
1. Safari
2. Google Chrome
3. Mozilla Firefox
4. Microsoft Edge
5. Arc

### 4. 交互流程

1. 用户打开设置页面
2. 看到"浏览器设置"部分，显示当前选中的浏览器
3. 点击下拉菜单，展开浏览器选项列表
4. 选择想要使用的浏览器
5. 选择后立即保存并生效
6. 在内容详情页点击链接时，使用选中的浏览器打开

## 技术设计

### 1. 浏览器检测

**检测逻辑：**
- 扫描 `/Applications/` 目录下的浏览器应用
- 识别已知浏览器的 bundle identifier
- 读取应用 `Info.plist` 获取版本号
- 使用 `NSWorkspace.shared.icon(forFile:)` 获取浏览器图标

**浏览器 Bundle Identifier：**
```swift
let knownBrowsers: [String: String] = [
    "com.apple.Safari": "Safari",
    "com.google.Chrome": "Google Chrome",
    "org.mozilla.firefox": "Firefox",
    "com.microsoft.edgemac": "Microsoft Edge",
    "company.thebrowser.Browser": "Arc"
]
```

### 2. 数据存储

**存储位置：** UserDefaults

**存储键：**
```swift
let kSelectedBrowserKey = "selectedBrowserBundleIdentifier"
```

**存储值：**
- 浏览器的 bundle identifier（如 "com.apple.Safari"）
- 空字符串表示使用系统默认浏览器

**读写操作：**
- 写入：用户在下拉菜单中选择浏览器时立即保存
- 读取：点击链接时读取设置，确定使用哪个浏览器
- 重置：选择"系统默认"时，存储空字符串

### 3. 链接打开逻辑

**触发场景：** 内容详情页点击原始链接

**实现方式：**
```swift
func openURLInBrowser(_ url: URL) {
    let bundleIdentifier = UserDefaults.standard.string(forKey: kSelectedBrowserKey) ?? ""
    
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
```

**关键点：**
1. 使用 `NSWorkspace.shared.urlForApplication(withBundleIdentifier:)` 动态查找浏览器路径
2. 如果浏览器不存在，自动回退到系统默认浏览器
3. 不硬编码浏览器路径，支持浏览器安装在不同位置

### 4. 错误处理

**边界情况处理：**

1. **浏览器不存在**
   - 用户选择了某个浏览器，但后来卸载了该浏览器
   - 处理：自动回退到系统默认浏览器，不提示错误

2. **浏览器检测失败**
   - 某些浏览器安装在非标准位置
   - 处理：只检测 `/Applications/` 目录，不检测其他位置

3. **版本号获取失败**
   - 某些浏览器的 `Info.plist` 格式不标准
   - 处理：版本号显示为"未知"，不影响选择

4. **UserDefaults 读取失败**
   - 存储的数据损坏或被清除
   - 处理：使用默认值（系统默认浏览器）

5. **首次使用**
   - 用户从未设置过浏览器
   - 处理：默认选择"系统默认浏览器"

**用户反馈：**
- 选择浏览器后不显示提示，立即生效
- 如果浏览器不可用，静默回退到默认浏览器
- 不需要额外的成功或错误提示

## 文件结构

需要创建或修改的文件：

1. **Views/Settings/SettingsView.swift**
   - 添加 `browserSection` 计算属性
   - 添加浏览器检测和选择逻辑
   - 修改 `body` 属性，添加新的Section

2. **Utilities/BrowserDetector.swift**（新文件）
   - 浏览器检测逻辑
   - 获取浏览器图标和版本
   - 管理浏览器选择

## 验收标准

1. ✅ 设置页面显示新的"浏览器设置"部分
2. ✅ 下拉菜单显示检测到的浏览器列表
3. ✅ 选择浏览器后立即保存，无需重启
4. ✅ 内容详情页点击链接时使用选中的浏览器打开
5. ✅ 所有Section标题和内容行高度一致
6. ✅ 错误情况下静默回退到默认浏览器
