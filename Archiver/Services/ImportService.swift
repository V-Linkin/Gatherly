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
    private let trashRepo = TrashRepository()
    
    /// 当前正在处理的任务
    var activeTasks: [UUID: ImportTask] = [:]
    
    /// 最近的导入结果
    var recentResults: [ImportResult] = []
    
    private var mediaDir: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Archiver/media", isDirectory: true)
    }
    
    private init() {
        try? FileManager.default.createDirectory(at: mediaDir, withIntermediateDirectories: true)
    }
    
    // MARK: - Public API
    
    /// 导入一条链接
    @MainActor
    func importURL(_ urlString: String) async -> ImportResult {
        logger.info("开始导入: \(urlString)")
        
        // 1. 验证 URL
        guard URLNormalizer.isValidURL(urlString) else {
            logger.warning("URL 格式不合法: \(urlString)")
            let error = ParserError.invalidURL
            return .failure(error: error)
        }
        
        // 2. 识别平台
        guard let platform = URLNormalizer.recognizePlatform(urlString) else {
            logger.warning("不支持的平台: \(urlString)")
            let error = ParserError.unsupportedPlatform
            return .failure(error: error)
        }
        
        // 3. 去重检查
        let normalizedURL = URLNormalizer.normalize(urlString, platform: platform)
        if let existingItem = try? itemRepo.findByNormalizedURL(normalizedURL) {
            logger.info("内容已存在: \(existingItem.id)")
            return .duplicate(existingItem: existingItem)
        }
        
        // 如果有 contentID 也检查
        if let contentID = URLNormalizer.extractContentID(urlString, platform: platform),
           let existingItem = try? itemRepo.findByPlatformContentID(platform: platform, contentID: contentID) {
            logger.info("内容已存在(ContentID): \(existingItem.id)")
            return .duplicate(existingItem: existingItem)
        }
        
        // 4. 创建导入任务
        var task = ImportTask(originalURL: urlString, normalizedURL: normalizedURL, platform: platform)
        task.status = .recognizing
        activeTasks[task.id] = task
        
        // 5. 解析内容
        task.status = .parsing
        activeTasks[task.id] = task
        
        let parsedContent: ParsedContent
        let parser: ContentParser
        do {
            (parsedContent, parser) = try await PlatformRouter.shared.parse(urlString: urlString)
        } catch {
            logger.error("解析失败: \(error.localizedDescription)")
            task.status = .failed
            task.errorMessage = error.localizedDescription
            activeTasks[task.id] = task
            
            // 即使解析失败也保留一条记录
            let failedItem = createFailedItem(
                url: urlString, platform: platform,
                normalizedURL: normalizedURL, error: error
            )
            try? itemRepo.insert(failedItem)
            return .failure(error: error)
        }
        
        // 6. 创建 Item 记录
        let item = createItem(from: parsedContent, url: urlString, platform: platform, normalizedURL: normalizedURL)
        
        do {
            try itemRepo.insert(item)
        } catch {
            logger.error("保存失败: \(error.localizedDescription)")
            return .failure(error: error)
        }
        
        // 7. 下载媒体
        task.status = .downloading
        task.itemID = item.id
        activeTasks[task.id] = task
        
        var mediaStatus: MediaStatus = .textOnly
        do {
            let assets = try await parser.downloadMedia(
                content: parsedContent,
                itemID: item.id,
                mediaDir: mediaDir
            )
            
            if assets.contains(where: { $0.type == .image || $0.type == .cover }) {
                mediaStatus = assets.contains(where: { $0.type == .video && $0.downloadStatus == .completed })
                    ? .complete : .partial
            } else if assets.contains(where: { $0.type == .video }) {
                mediaStatus = .partial
            }
            
            // 更新封面ID
            if let coverAsset = assets.first(where: { $0.type == .cover }) {
                var updatedItem = item
                updatedItem.coverAssetID = coverAsset.id
                updatedItem.mediaStatus = mediaStatus
                try itemRepo.update(updatedItem)
                
                task.status = .completed
                task.completedAt = Date()
                activeTasks[task.id] = task
                
                logger.info("导入成功: \(item.id)")
                return .success(updatedItem)
            }
        } catch {
            logger.warning("媒体下载失败: \(error.localizedDescription)")
            mediaStatus = .failed
        }
        
        // 更新状态
        var updatedItem = item
        updatedItem.mediaStatus = mediaStatus
        if mediaStatus == .failed || mediaStatus == .partial {
            updatedItem.contentStatus = .mediaIncomplete
        }
        try? itemRepo.update(updatedItem)
        
        task.status = .completed
        task.completedAt = Date()
        activeTasks[task.id] = task
        
        logger.info("导入完成(媒体部分): \(item.id)")
        return .success(updatedItem)
    }
    
    // MARK: - Private
    
    private func createItem(from content: ParsedContent, url: String,
                            platform: Platform, normalizedURL: String) -> Item {
        Item(
            title: content.title,
            body: content.body,
            originalURL: url,
            platform: platform,
            platformContentID: content.platformContentID,
            normalizedURL: normalizedURL,
            author: content.author,
            authorID: content.authorID,
            publishDate: content.publishDate,
            archiveStatus: .pending,
            mediaStatus: .textOnly
        )
    }
    
    private func createFailedItem(url: String, platform: Platform,
                                  normalizedURL: String, error: Error) -> Item {
        Item(
            title: "解析失败",
            body: "解析此链接时出错: \(error.localizedDescription)\n您可以手动编辑标题和正文。",
            originalURL: url,
            platform: platform,
            normalizedURL: normalizedURL,
            contentStatus: .parseFailed,
            archiveStatus: .pending,
            mediaStatus: .textOnly
        )
    }
}
