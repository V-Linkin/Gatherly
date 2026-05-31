import Foundation
import AppKit
import OSLog

/// 媒体另存为导出器
@MainActor
struct MediaExporter {
    private static let logger = Logger(subsystem: "com.archiver.app", category: "MediaExporter")
    
    // MARK: - 命名生成
    
    /// 生成单个导出文件名
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
    
    /// 生成批量导出文件名（简化版）
    /// 格式: {自定义平台名}_{作者}_{日期}.{扩展名}
    static func generateBatchExportName(
        platformName: String?,
        author: String?,
        date: Date = Date(),
        index: Int,
        fileExtension: String
    ) -> String {
        var parts: [String] = []
        
        if let platform = platformName, !platform.isEmpty {
            parts.append(sanitizeFileName(platform))
        }
        if let author = author, !author.isEmpty {
            parts.append(sanitizeFileName(author))
        }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        parts.append(formatter.string(from: date))
        
        parts.append("\(index)")
        
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
        
        guard let destDir = FilePicker.pickExportFolder() else {
            logger.info("用户取消选择文件夹")
            return false
        }
        
        let platformName = getPlatformName(for: item, appState: appState)
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
        
        guard let destDir = FilePicker.pickExportFolder() else {
            logger.info("用户取消选择文件夹")
            return 0
        }
        
        let platformName = getPlatformName(for: item, appState: appState)
        let folderName = getFolderName(for: item, appState: appState)
        
        // 先按类型排序：图片在前，视频在后
        var sortedAssets: [MediaAsset] = []
        var videoAssets: [MediaAsset] = []
        
        for asset in assets {
            if asset.type == .image || asset.type == .cover {
                sortedAssets.append(asset)
            } else {
                videoAssets.append(asset)
            }
        }
        sortedAssets.append(contentsOf: videoAssets)
        
        var successCount = 0
        var index = 1
        
        for asset in sortedAssets {
            guard let localPath = asset.localPath else { continue }
            
            let sourceURL = DataDirectory.media.appendingPathComponent(localPath)
            guard FileManager.default.fileExists(atPath: sourceURL.path) else { continue }
            
            let ext = sourceURL.pathExtension.isEmpty ? "bin" : sourceURL.pathExtension
            let fileName = generateBatchExportName(
                platformName: platformName,
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
        
        guard let destDir = FilePicker.pickExportFolder() else {
            logger.info("用户取消选择文件夹")
            return 0
        }
        
        let platformName = getPlatformName(for: item, appState: appState)
        let folderName = getFolderName(for: item, appState: appState)
        
        var successCount = 0
        var index = 1
        
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
    
    /// 获取自定义平台名
    private static func getPlatformName(for item: Item, appState: AppState) -> String? {
        if let cpID = item.customPlatformID,
           let cp = appState.customPlatforms.first(where: { $0.id == cpID }) {
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
        return "jpg"
    }
}
