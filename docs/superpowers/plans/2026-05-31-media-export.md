# 媒体另存为功能实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 内容详情页的图片和视频支持另存为到本地路径，提供右键单个导出和工具栏批量导出两种方式。

**Architecture:** 新增 `MediaExporter` 工具类负责命名生成和文件导出逻辑，新增 `ExportPickerSheet` 弹窗组件用于批量导出时的媒体类型选择，在 `ItemDetailView` 中集成右键菜单和工具栏按钮。

**Tech Stack:** Swift 6.0, SwiftUI, AppKit (NSOpenPanel, NSMenu), FileManager

---

### Task 1: 创建 MediaExporter 工具类

**Files:**
- Create: `Utilities/MediaExporter.swift`

- [ ] **Step 1: 创建 MediaExporter.swift 文件**

```swift
import Foundation
import AppKit
import OSLog

/// 媒体另存为导出器
@MainActor
struct MediaExporter {
    private static let logger = Logger(subsystem: "com.archiver.app", category: "MediaExporter")
    
    // MARK: - 命名生成
    
    /// 生成导出文件名
    /// 格式: {平台名}_{文件夹}_{作者}_{序号}_{日期}.{扩展名}
    static func generateExportName(
        platformName: String?,
        folderName: String?,
        author: String?,
        index: Int,
        date: Date = Date(),
        fileExtension: String
    ) -> String {
        var parts: [String] = []
        
        if let platform = platformName, !platform.isEmpty {
            parts.append(sanitizeFileName(platform))
        }
        if let folder = folderName, !folder.isEmpty {
            parts.append(sanitizeFileName(folder))
        }
        if let author = author, !author.isEmpty {
            parts.append(sanitizeFileName(author))
        }
        
        parts.append("\(index)")
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        parts.append(formatter.string(from: date))
        
        let baseName = parts.joined(separator: "_")
        return "\(baseName).\(fileExtension)"
    }
    
    /// 替换文件名中的非法字符为下划线
    static func sanitizeFileName(_ name: String) -> String {
        let illegalCharacters = CharacterSet(charactersIn: "/:\\?*\"<>|")
        return name.components(separatedBy: illegalCharacters)
            .joined(separator: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // MARK: - 文件覆盖处理
    
    /// 获取不重复的文件URL，如果已存在同名文件则追加后缀
    static func uniqueFileURL(in directory: URL, fileName: String) -> URL {
        let ext = (fileName as NSString).pathExtension
        let base = (fileName as NSString).deletingPathExtension
        
        var candidate = directory.appendingPathComponent(fileName)
        var counter = 1
        
        while FileManager.default.fileExists(atPath: candidate.path) {
            let newName = "\(base)_\(counter).\(ext)"
            candidate = directory.appendingPathComponent(newName)
            counter += 1
        }
        
        return candidate
    }
    
    // MARK: - 单个导出
    
    /// 导出单个媒体资产到用户选择的文件夹
    static func exportSingle(
        asset: MediaAsset,
        item: Item,
        from appState: AppState
    ) -> Bool {
        guard let localPath = asset.localPath else {
            logger.warning("资产本地路径为空，跳过导出")
            return false
        }
        
        let sourceURL = DataDirectory.media.appendingPathComponent(localPath)
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            logger.warning("源文件不存在: \(sourceURL.path, privacy: .public)")
            return false
        }
        
        guard let destDir = pickExportFolder() else {
            logger.info("用户取消选择文件夹")
            return false
        }
        
        let platformName = getPlatformName(for: item)
        let folderName = getFolderName(for: item, appState: appState)
        let ext = sourceURL.pathExtension.isEmpty ? "bin" : sourceURL.pathExtension
        
        // 单个导出序号固定为 1
        let fileName = generateExportName(
            platformName: platformName,
            folderName: folderName,
            author: item.author,
            index: 1,
            fileExtension: ext
        )
        
        let destURL = uniqueFileURL(in: destDir, fileName: fileName)
        
        do {
            try FileManager.default.copyItem(at: sourceURL, to: destURL)
            logger.info("导出成功: \(destURL.lastPathComponent, privacy: .public)")
            return true
        } catch {
            logger.error("导出失败: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
    
    // MARK: - 批量导出
    
    /// 导出媒体资产列表到用户选择的文件夹
    static func exportBatch(
        assets: [MediaAsset],
        item: Item,
        from appState: AppState
    ) -> Int {
        guard !assets.isEmpty else { return 0 }
        
        guard let destDir = pickExportFolder() else {
            logger.info("用户取消选择文件夹")
            return 0
        }
        
        let platformName = getPlatformName(for: item)
        let folderName = getFolderName(for: item, appState: appState)
        
        // 先按类型排序：图片在前，视频在后
        let sortedAssets = assets.sorted { a, b in
            let aIsImage = a.type == .image || a.type == .cover
            let bIsImage = b.type == .image || b.type == .cover
            if aIsImage != bIsImage {
                return aIsImage  // 图片排前面
            }
            return assets.firstIndex(of: a)! < assets.firstIndex(of: b)!
        }
        
        var successCount = 0
        var index = 1
        
        for asset in sortedAssets {
            guard let localPath = asset.localPath else { continue }
            
            let sourceURL = DataDirectory.media.appendingPathComponent(localPath)
            guard FileManager.default.fileExists(atPath: sourceURL.path) else { continue }
            
            let ext = sourceURL.pathExtension.isEmpty ? "bin" : sourceURL.pathExtension
            let fileName = generateExportName(
                platformName: platformName,
                folderName: folderName,
                author: item.author,
                index: index,
                fileExtension: ext
            )
            
            let destURL = uniqueFileURL(in: destDir, fileName: fileName)
            
            do {
                try FileManager.default.copyItem(at: sourceURL, to: destURL)
                successCount += 1
                index += 1
            } catch {
                logger.error("导出失败 [\(asset.fileName, privacy: .public)]: \(error.localizedDescription, privacy: .public)")
            }
        }
        
        logger.info("批量导出完成: \(successCount)/\(sortedAssets.count) 个文件")
        return successCount
    }
    
    // MARK: - 批量导出正文图片
    
    /// 导出正文图片（从缓存或远程URL）
    static func exportBodyImages(
        imageURLs: [String],
        imageCache: ImageCache,
        item: Item,
        from appState: AppState
    ) -> Int {
        guard !imageURLs.isEmpty else { return 0 }
        
        guard let destDir = pickExportFolder() else {
            logger.info("用户取消选择文件夹")
            return 0
        }
        
        let platformName = getPlatformName(for: item)
        let folderName = getFolderName(for: item, appState: appState)
        
        var successCount = 0
        var index = 1
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd"
        let dateStr = dateFormatter.string(from: Date())
        
        for remoteURL in imageURLs {
            var nsImage: NSImage?
            
            // 优先从缓存读取
            if let cached = imageCache.get(remoteURL) {
                nsImage = cached
            } else {
                // 尝试从本地文件读取
                if let url = URL(string: remoteURL),
                   let imageData = try? Data(contentsOf: url),
                   let image = NSImage(data: imageData) {
                    nsImage = image
                }
            }
            
            guard let image = nsImage else {
                logger.warning("无法加载正文图片: \(remoteURL, privacy: .public)")
                continue
            }
            
            // 从 URL 推断扩展名
            let ext = inferExtension(from: remoteURL, image: image)
            let fileName = generateExportName(
                platformName: platformName,
                folderName: folderName,
                author: item.author,
                index: index,
                fileExtension: ext
            )
            
            let destURL = uniqueFileURL(in: destDir, fileName: fileName)
            
            // 保存图片
            guard let tiffData = image.tiffRepresentation,
                  let bitmapRep = NSBitmapImageRep(data: tiffData) else { continue }
            
            let data: Data?
            switch ext {
            case "png":
                data = bitmapRep.representation(using: .png, properties: [:])
            case "jpeg", "jpg":
                data = bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: 0.9])
            case "webp":
                // macOS 不原生支持 webp 导出，降级为 png
                data = bitmapRep.representation(using: .png, properties: [:])
            default:
                data = bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: 0.9])
            }
            
            guard let outputData = data else { continue }
            
            do {
                try outputData.write(to: destURL)
                successCount += 1
                index += 1
            } catch {
                logger.error("导出正文图片失败: \(error.localizedDescription, privacy: .public)")
            }
        }
        
        logger.info("正文图片导出完成: \(successCount)/\(imageURLs.count) 个文件")
        return successCount
    }
    
    // MARK: - 辅助方法
    
    /// 弹出系统文件夹选择器
    private static func pickExportFolder() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "选择保存位置"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
        
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }
    
    /// 获取自定义平台名
    private static func getPlatformName(for item: Item) -> String? {
        if let cpID = item.customPlatformID,
           let cp = try? DatabaseManager.shared.db.read({ db in
               try CustomPlatform.fetchOne(db, sql: "SELECT * FROM custom_platforms WHERE id=?", arguments: [cpID.uuidString])
           }) {
            return cp.name
        }
        return item.platform.defaultDisplayName
    }
    
    /// 获取文件夹名
    private static func getFolderName(for item: Item, appState: AppState) -> String? {
        guard let folderID = item.folderID else { return nil }
        return try? appState.folderRepo.find(id: folderID)?.name
    }
    
    /// 从远程 URL 推断文件扩展名
    private static func inferExtension(from urlString: String, image: NSImage) -> String {
        if let url = URL(string: urlString) {
            let pathExt = url.pathExtension.lowercased()
            switch pathExt {
            case "png": return "png"
            case "jpg", "jpeg": return "jpg"
            case "webp": return "webp"
            case "gif": return "gif"
            default: break
            }
        }
        // 从 image properties 推断
        if let tiffData = image.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiffData) {
            switch rep.bitsPerSample {
            case 8 where rep.samplesPerPixel == 4: return "png"
            default: return "jpg"
            }
        }
        return "jpg"
    }
}
```

- [ ] **Step 2: 验证编译**

Run:
```bash
DEVELOPER_DIR=/Volumes/APFS_Data/Applications/Xcode.app/Contents/Developer xcodebuild build -project Archiver.xcodeproj -scheme Archiver -destination 'platform=macOS' CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20
```
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add Utilities/MediaExporter.swift
git commit -m "feat: add MediaExporter utility for media export"
```

---

### Task 2: 添加 FilePicker 导出文件夹选择方法

**Files:**
- Modify: `Utilities/FilePicker.swift`

- [ ] **Step 1: 添加 pickExportFolder 方法**

在 `FilePicker.swift` 的 `pickMedia()` 方法后面添加：

```swift
static func pickExportFolder() -> URL? {
    let panel = NSOpenPanel()
    panel.title = "选择保存位置"
    panel.allowsMultipleSelection = false
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.canCreateDirectories = true
    panel.directoryURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first

    guard panel.runModal() == .OK else { return nil }
    return panel.url
}
```

- [ ] **Step 2: 验证编译**

Run:
```bash
DEVELOPER_DIR=/Volumes/APFS_Data/Applications/Xcode.app/Contents/Developer xcodebuild build -project Archiver.xcodeproj -scheme Archiver -destination 'platform=macOS' CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20
```
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add Utilities/FilePicker.swift
git commit -m "feat: add pickExportFolder to FilePicker"
```

---

### Task 3: 创建 ExportPickerSheet 弹窗组件

**Files:**
- Create: `Views/Components/ExportPickerSheet.swift`

- [ ] **Step 1: 创建 ExportPickerSheet.swift**

```swift
import SwiftUI

/// 批量导出时的媒体类型选择弹窗
struct ExportPickerSheet: View {
    let hasBodyImages: Bool
    let mediaAssetCount: Int
    let bodyImageCount: Int
    @Binding var isPresented: Bool
    let onExport: (ExportSelection) -> Void
    
    enum ExportSelection {
        case mediaOnly
        case bodyImagesOnly
        case all
    }
    
    @State private var selection: ExportSelection = .all
    
    var body: some View {
        VStack(spacing: 0) {
            Text("选择导出内容")
                .font(.headline)
                .padding()
            
            Divider()
            
            VStack(spacing: 12) {
                if mediaAssetCount > 0 {
                    radioOption(
                        title: "媒体区域",
                        detail: "\(mediaAssetCount) 个文件（图片/视频）",
                        tag: .mediaOnly
                    )
                }
                
                if hasBodyImages && bodyImageCount > 0 {
                    radioOption(
                        title: "正文图片",
                        detail: "\(bodyImageCount) 个文件",
                        tag: .bodyImagesOnly
                    )
                }
                
                if mediaAssetCount > 0 && hasBodyImages && bodyImageCount > 0 {
                    radioOption(
                        title: "全部导出",
                        detail: "\(mediaAssetCount + bodyImageCount) 个文件",
                        tag: .all
                    )
                }
            }
            .padding(16)
            
            Divider()
            
            HStack {
                Button("取消") {
                    isPresented = false
                }
                Spacer()
                Button("导出") {
                    onExport(selection)
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(width: 320, height: 260)
    }
    
    @ViewBuilder
    private func radioOption(title: String, detail: String, tag: ExportSelection) -> some View {
        Button {
            selection = tag
        } label: {
            HStack {
                Image(systemName: selection == tag ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selection == tag ? .blue : .secondary)
                VStack(alignment: .leading) {
                    Text(title).font(.body)
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 6).fill(selection == tag ? Color.blue.opacity(0.1) : Color.clear))
        }
        .buttonStyle(.plain)
    }
}
```

- [ ] **Step 2: 验证编译**

Run:
```bash
DEVELOPER_DIR=/Volumes/APFS_Data/Applications/Xcode.app/Contents/Developer xcodebuild build -project Archiver.xcodeproj -scheme Archiver -destination 'platform=macOS' CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20
```
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add Views/Components/ExportPickerSheet.swift
git commit -m "feat: add ExportPickerSheet for batch export selection"
```

---

### Task 4: 在 ItemDetailView 中集成右键菜单和工具栏导出按钮

**Files:**
- Modify: `Views/Item/ItemDetailView.swift`

- [ ] **Step 1: 添加导出相关状态变量**

在 `ItemDetailView` 的 `@State` 属性中添加：

```swift
@State private var showExportPicker = false
@State private var showExportSuccess = false
@State private var exportSuccessCount = 0
```

- [ ] **Step 2: 在 mediaSection 中添加右键菜单**

找到 `mediaSection` 方法中 `ForEach` 内的图片/视频视图，在 `.onTapGesture` 之后添加 `.contextMenu`：

```swift
.contextMenu {
    Button {
        if let asset = mediaAssets.first(where: { $0.id == asset.id }) {
            let success = MediaExporter.exportSingle(asset: asset, item: item, from: appState)
            if success {
                appState.showToast("导出成功")
            }
        }
    } label: {
        Label("另存为", systemImage: "square.and.arrow.down")
    }
    .disabled(asset.localPath == nil)
}
```

注意：需要将 `ForEach` 中的 `asset` 变量传递给 `.contextMenu`。

- [ ] **Step 3: 在工具栏添加导出按钮**

找到 `toolbar` 中的 `ToolbarItemGroup`，在最后一个 Button 之前添加：

```swift
Button {
    if bodyImageURLs.isEmpty {
        // 没有正文图片，直接导出媒体区域
        let count = MediaExporter.exportBatch(
            assets: mediaAssets,
            item: item,
            from: appState
        )
        if count > 0 {
            appState.showToast("成功导出 \(count) 个文件")
        }
    } else {
        // 有正文图片，弹出选择框
        showExportPicker = true
    }
} label: {
    Label("导出", systemImage: "square.and.arrow.down")
}
.buttonStyle(.bordered)
.controlSize(.small)
.disabled(mediaAssets.isEmpty && bodyImageURLs.isEmpty)
```

- [ ] **Step 4: 添加 ExportPickerSheet 的 sheet**

在 `ItemDetailView` 的 `body` 修饰符链中（在其他 `.sheet` 之后）添加：

```swift
.sheet(isPresented: $showExportPicker) {
    ExportPickerSheet(
        hasBodyImages: !bodyImageURLs.isEmpty,
        mediaAssetCount: mediaAssets.count,
        bodyImageCount: bodyImageURLs.count,
        isPresented: $showExportPicker
    ) { selection in
        switch selection {
        case .mediaOnly:
            let count = MediaExporter.exportBatch(assets: mediaAssets, item: item, from: appState)
            if count > 0 {
                appState.showToast("成功导出 \(count) 个文件")
            }
        case .bodyImagesOnly:
            let count = MediaExporter.exportBodyImages(
                imageURLs: bodyImageURLs,
                imageCache: bodyImageCache,
                item: item,
                from: appState
            )
            if count > 0 {
                appState.showToast("成功导出 \(count) 个文件")
            }
        case .all:
            let mediaCount = MediaExporter.exportBatch(assets: mediaAssets, item: item, from: appState)
            let bodyCount = MediaExporter.exportBodyImages(
                imageURLs: bodyImageURLs,
                imageCache: bodyImageCache,
                item: item,
                from: appState
            )
            let total = mediaCount + bodyCount
            if total > 0 {
                appState.showToast("成功导出 \(total) 个文件")
            }
        }
    }
}
```

- [ ] **Step 5: 验证编译**

Run:
```bash
DEVELOPER_DIR=/Volumes/APFS_Data/Applications/Xcode.app/Contents/Developer xcodebuild build -project Archiver.xcodeproj -scheme Archiver -destination 'platform=macOS' CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20
```
Expected: BUILD SUCCEEDED

- [ ] **Step 6: Commit**

```bash
git add Views/Item/ItemDetailView.swift
git commit -m "feat: integrate media export into ItemDetailView with right-click menu and toolbar button"
```

---

### Task 5: 更新文档

**Files:**
- Modify: `AGENTS.md`
- Modify: `docs/superpowers/specs/2026-05-31-media-export-design.md`

- [ ] **Step 1: 更新 AGENTS.md 中的已知问题**

找到 AGENTS.md 中的「已知问题」部分，将第 3 条「豆瓣影评正文图片未提取」的描述更新为：

```
3. **豆瓣影评正文图片未提取** — `DoubanParser` 影评正文的 `<img>` 标签被 `innerText` 忽略，正文只保留文字。暂不支持豆瓣正文插图导出。封面已修复（review 页面始终从 subject 页面获取电影海报，兜底 `og:image`）。正文区域已恢复为完整显示（移除了固定高度滚动框），备注框移至正文上方并支持实时编辑保存。
```

- [ ] **Step 2: Commit**

```bash
git add AGENTS.md docs/superpowers/specs/2026-05-31-media-export-design.md
git commit -m "docs: update AGENTS.md with media export info"
```

---

### Task 6: 最终集成测试

- [ ] **Step 1: 完整构建**

Run:
```bash
DEVELOPER_DIR=/Volumes/APFS_Data/Applications/Xcode.app/Contents/Developer xcodebuild build -project Archiver.xcodeproj -scheme Archiver -destination 'platform=macOS' CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20
```
Expected: BUILD SUCCEEDED

- [ ] **Step 2: 功能验证清单**

手动验证以下场景：
- 右键点击媒体图片 → 弹出「另存为」→ 选择文件夹 → 文件正确保存，命名符合规则
- 右键点击视频 → 同上
- 工具栏点击「导出」→ 无正文图片时直接弹出文件夹选择器
- 有正文图片时弹出勾选框 → 选择不同选项导出
- 导出的文件命名格式正确：`平台_文件夹_作者_序号_日期.格式`
- 无文件夹时跳过文件夹段
- 同名文件自动追加后缀

- [ ] **Step 3: Final Commit**

```bash
git add -A
git commit -m "feat: media export feature complete"
```
