import Foundation
import OSLog

/// 导入结果
enum ImportResult {
    case success(Item)
    case duplicate(existingItem: Item)
    case failure(error: Error)
}

/// 导入服务 - 编排整个导入流程
@MainActor
@Observable
final class ImportService {
    static let shared = ImportService()
    
    private let logger = Logger(subsystem: "com.archiver.app", category: "Import")
    private let itemRepo = ItemRepository()
    private let mediaRepo = MediaRepository()
    private let customPlatformRepo = CustomPlatformRepository()
    
    var activeTasks: [UUID: ImportTask] = [:]
    var recentResults: [ImportResult] = []
    
    private var mediaDir: URL {
        DataDirectory.media
    }
    
    private init() {
        try? FileManager.default.createDirectory(at: mediaDir, withIntermediateDirectories: true)
    }
    
    // MARK: - Public API
    
    @MainActor
    func importURL(_ urlString: String) async -> ImportResult {
        logger.info("=== 开始导入: \(urlString, privacy: .public) ===")
        
        guard URLNormalizer.isValidURL(urlString) else {
            logger.error("URL 无效: \(urlString, privacy: .public)")
            return .failure(error: ParserError.invalidURL)
        }
        
        guard let detectedPlatform = URLNormalizer.recognizePlatform(urlString) else {
            logger.error("无法识别平台: \(urlString, privacy: .public)")
            return .failure(error: ParserError.unsupportedPlatform)
        }
        logger.info("识别到平台: \(detectedPlatform.rawValue, privacy: .public)")
        
        // 去重检查
        let normalizedURL = URLNormalizer.normalize(urlString, platform: detectedPlatform)
        logger.info("标准化URL: \(normalizedURL, privacy: .public)")
        
        if let existingItem = try? itemRepo.findByNormalizedURL(normalizedURL) {
            logger.info("去重命中(标准化URL): 已存在 item \(existingItem.id.uuidString, privacy: .public)")
            return .duplicate(existingItem: existingItem)
        }
        
        if let contentID = URLNormalizer.extractContentID(urlString, platform: detectedPlatform),
           let existingItem = try? itemRepo.findByPlatformContentID(platform: detectedPlatform, contentID: contentID) {
            logger.info("去重命中(内容ID): 已存在 item \(existingItem.id.uuidString, privacy: .public)")
            return .duplicate(existingItem: existingItem)
        }
        
        logger.info("未发现重复，继续导入")
        
        // 查找匹配的自定义平台
        let customPlatformID = findMatchingCustomPlatform(for: detectedPlatform)
        if let cpID = customPlatformID {
            logger.info("匹配到自定义平台: \(cpID.uuidString, privacy: .public)")
        } else {
            logger.info("未匹配到自定义平台")
        }
        
        // 创建导入任务
        var task = ImportTask(originalURL: urlString, normalizedURL: normalizedURL, platform: detectedPlatform)
        task.status = .parsing
        activeTasks[task.id] = task
        
        // 解析内容
        logger.info("开始解析内容...")
        let parsedContent: ParsedContent
        let parser: ContentParser
        do {
            (parsedContent, parser) = try await PlatformRouter.shared.parse(urlString: urlString)
            logger.info("解析成功 - 标题: \(parsedContent.title ?? "nil", privacy: .public), 图片数: \(parsedContent.imageURLs.count), 有视频: \(parsedContent.videoURL != nil)")
        } catch {
            logger.error("解析失败: \(error.localizedDescription, privacy: .public)")
            task.status = .failed
            task.errorMessage = error.localizedDescription
            activeTasks[task.id] = task
            
            let failedItem = createFailedItem(
                url: urlString, platform: detectedPlatform,
                normalizedURL: normalizedURL, error: error
            )
            do {
                try itemRepo.insert(failedItem)
                logger.info("已保存失败记录: \(failedItem.id.uuidString, privacy: .public)")
            } catch {
                logger.error("保存失败记录也失败了: \(error.localizedDescription, privacy: .public)")
            }
            return .failure(error: error)
        }
        
        // 创建 Item 记录
        let item = createItem(
            from: parsedContent, url: urlString,
            platform: detectedPlatform, normalizedURL: normalizedURL,
            customPlatformID: customPlatformID
        )
        logger.info("准备插入 item: \(item.id.uuidString, privacy: .public), platform: \(item.platform.rawValue, privacy: .public), customPlatformID: \(item.customPlatformID?.uuidString ?? "nil", privacy: .public)")
        
        do {
            try itemRepo.insert(item)
            logger.info("item 插入成功")
        } catch {
            logger.error("item 插入失败: \(error.localizedDescription, privacy: .public)")
            return .failure(error: error)
        }
        
        // 下载媒体
        task.status = .downloading
        task.itemID = item.id
        activeTasks[task.id] = task
        
        var mediaStatus: MediaStatus = .textOnly
        do {
            logger.info("开始下载媒体...")
            let assets = try await parser.downloadMedia(
                content: parsedContent,
                itemID: item.id,
                mediaDir: mediaDir
            )
            logger.info("媒体下载完成: \(assets.count, privacy: .public) 个资产")
            
            if assets.contains(where: { $0.type == .image || $0.type == .cover }) {
                mediaStatus = assets.contains(where: { $0.type == .video && $0.downloadStatus == .completed })
                    ? .complete : .partial
            } else if assets.contains(where: { $0.type == .video }) {
                mediaStatus = .partial
            }
            
            if let coverAsset = assets.first(where: { $0.type == .cover || $0.type == .image }) {
                var updatedItem = item
                updatedItem.coverAssetID = coverAsset.id
                updatedItem.mediaStatus = mediaStatus
                try itemRepo.update(updatedItem)
                
                task.status = .completed
                task.completedAt = Date()
                activeTasks[task.id] = task
                
                logger.info("导入完成(有封面): mediaStatus=\(mediaStatus.rawValue, privacy: .public)")
                return .success(updatedItem)
            }
        } catch {
            logger.warning("媒体下载失败: \(error.localizedDescription, privacy: .public)")
            mediaStatus = .failed
        }
        
        var updatedItem = item
        updatedItem.mediaStatus = mediaStatus
        if mediaStatus == .failed || mediaStatus == .partial {
            updatedItem.contentStatus = .mediaIncomplete
        }
        try? itemRepo.update(updatedItem)
        
        task.status = .completed
        task.completedAt = Date()
        activeTasks[task.id] = task
        
        logger.info("导入完成(无封面): mediaStatus=\(mediaStatus.rawValue, privacy: .public)")
        return .success(updatedItem)
    }
    
    // MARK: - Private
    
    /// 查找与平台枚举匹配的自定义平台
    private func findMatchingCustomPlatform(for platform: Platform) -> UUID? {
        let allPlatforms = (try? customPlatformRepo.fetchAll()) ?? []
        logger.info("所有自定义平台: \(allPlatforms.map { $0.name }.joined(separator: ", "), privacy: .public)")
        let targetName = platform.defaultDisplayName
        logger.info("查找目标平台名: \(targetName, privacy: .public)")
        let match = allPlatforms.first { $0.name == targetName }
        if let match {
            logger.info("找到匹配平台: \(match.name, privacy: .public) id=\(match.id.uuidString, privacy: .public)")
        } else {
            logger.info("未找到匹配平台 '\(targetName, privacy: .public)'")
        }
        return match?.id
    }
    
    private func createItem(from content: ParsedContent, url: String,
                            platform: Platform, normalizedURL: String,
                            customPlatformID: UUID?) -> Item {
        let item = Item(
            title: content.title,
            body: content.body,
            originalURL: url,
            platform: customPlatformID != nil ? .custom : platform,
            platformContentID: content.platformContentID,
            normalizedURL: normalizedURL,
            author: content.author,
            authorID: content.authorID,
            publishDate: content.publishDate,
            archiveStatus: .pending,
            mediaStatus: .textOnly,
            customPlatformID: customPlatformID
        )
        return item
    }
    
    private func createFailedItem(url: String, platform: Platform,
                                  normalizedURL: String, error: Error) -> Item {
        let customPlatformID = findMatchingCustomPlatform(for: platform)
        return Item(
            title: "解析失败",
            body: "解析此链接时出错: \(error.localizedDescription)\n您可以手动编辑标题和正文。",
            originalURL: url,
            platform: customPlatformID != nil ? .custom : platform,
            normalizedURL: normalizedURL,
            contentStatus: .parseFailed,
            archiveStatus: .pending,
            mediaStatus: .textOnly,
            customPlatformID: customPlatformID
        )
    }
}
