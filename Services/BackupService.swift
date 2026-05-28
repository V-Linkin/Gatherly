import Foundation
import OSLog

/// 备份服务 - 支持导出和导入数据
final class BackupService: @unchecked Sendable {
    static let shared = BackupService()
    
    private let logger = Logger(subsystem: "com.archiver.app", category: "Backup")
    private let fileManager = FileManager.default
    
    private init() {}
    
    // MARK: - 备份
    
    /// 备份所有数据到用户选择的目录
    /// 返回导出的 zip 文件路径
    func backup(to destinationURL: URL) async throws -> URL {
        let baseDir = DataDirectory.base
        let dbPath = DataDirectory.database
        let mediaDir = DataDirectory.media
        let platformLogosDir = DataDirectory.platformLogos
        
        // 创建临时工作目录
        let tempDir = fileManager.temporaryDirectory.appendingPathComponent("archiver_backup_\(UUID().uuidString)")
        try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        defer {
            try? fileManager.removeItem(at: tempDir)
        }
        
        // 1. 复制数据库
        if fileManager.fileExists(atPath: dbPath.path) {
            let dbBackup = tempDir.appendingPathComponent("archiver.db")
            try fileManager.copyItem(at: dbPath, to: dbBackup)
            logger.info("数据库已复制")
        }
        
        // 2. 复制媒体文件
        if fileManager.fileExists(atPath: mediaDir.path) {
            let mediaBackup = tempDir.appendingPathComponent("media")
            try fileManager.copyItem(at: mediaDir, to: mediaBackup)
            logger.info("媒体文件已复制")
        }
        
        // 3. 复制平台 Logo
        if fileManager.fileExists(atPath: platformLogosDir.path) {
            let logosBackup = tempDir.appendingPathComponent("platform_logos")
            try fileManager.copyItem(at: platformLogosDir, to: logosBackup)
            logger.info("平台 Logo 已复制")
        }
        
        // 4. 写入备份元信息
        let metadata: [String: Any] = [
            "version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0",
            "backupDate": ISO8601DateFormatter().string(from: Date()),
            "hasDatabase": fileManager.fileExists(atPath: dbPath.path),
            "hasMedia": fileManager.fileExists(atPath: mediaDir.path),
            "hasLogos": fileManager.fileExists(atPath: platformLogosDir.path)
        ]
        let metadataData = try JSONSerialization.data(withJSONObject: metadata)
        try metadataData.write(to: tempDir.appendingPathComponent("backup_info.json"))
        
        // 5. 打包为 zip
        let zipPath = destinationURL.appendingPathComponent("Archiver备份_\(formatDateForFilename(Date())).zip")
        try await createZip(from: tempDir, to: zipPath)
        
        logger.info("备份完成: \(zipPath.path, privacy: .public)")
        return zipPath
    }
    
    // MARK: - 还原
    
    /// 从备份 zip 还原数据
    func restore(from backupURL: URL) async throws {
        let baseDir = DataDirectory.base
        
        // 1. 解压 zip 到临时目录
        let tempDir = fileManager.temporaryDirectory.appendingPathComponent("archiver_restore_\(UUID().uuidString)")
        try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        defer {
            try? fileManager.removeItem(at: tempDir)
        }
        
        try await extractZip(from: backupURL, to: tempDir)
        
        // 2. 验证备份内容
        let dbFile = tempDir.appendingPathComponent("archiver.db")
        guard fileManager.fileExists(atPath: dbFile.path) else {
            throw BackupError.invalidBackup("备份中缺少数据库文件")
        }
        
        // 3. 替换数据库
        let currentDB = DataDirectory.database
        if fileManager.fileExists(atPath: currentDB.path) {
            // 备份当前数据库
            let safetyBackup = currentDB.deletingLastPathComponent().appendingPathComponent("archiver_backup_before_restore_\(formatDateForFilename(Date())).db")
            try? fileManager.copyItem(at: currentDB, to: safetyBackup)
            try fileManager.removeItem(at: currentDB)
        }
        try fileManager.copyItem(at: dbFile, to: currentDB)
        
        // 4. 替换媒体文件
        let mediaBackup = tempDir.appendingPathComponent("media")
        if fileManager.fileExists(atPath: mediaBackup.path) {
            let currentMedia = DataDirectory.media
            if fileManager.fileExists(atPath: currentMedia.path) {
                try fileManager.removeItem(at: currentMedia)
            }
            try fileManager.copyItem(at: mediaBackup, to: currentMedia)
        }
        
        // 5. 替换平台 Logo
        let logosBackup = tempDir.appendingPathComponent("platform_logos")
        if fileManager.fileExists(atPath: logosBackup.path) {
            let currentLogos = DataDirectory.platformLogos
            if fileManager.fileExists(atPath: currentLogos.path) {
                try fileManager.removeItem(at: currentLogos)
            }
            try fileManager.copyItem(at: logosBackup, to: currentLogos)
        }
        
        logger.info("还原完成")
    }
    
    /// 获取备份中的元信息
    func readBackupMetadata(from backupURL: URL) async -> BackupMetadata? {
        let tempDir = fileManager.temporaryDirectory.appendingPathComponent("archiver_meta_\(UUID().uuidString)")
        defer { try? fileManager.removeItem(at: tempDir) }
        
        do {
            try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
            try await extractZip(from: backupURL, to: tempDir)
            
            let metaFile = tempDir.appendingPathComponent("backup_info.json")
            let data = try Data(contentsOf: metaFile)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            
            return BackupMetadata(
                version: json?["version"] as? String ?? "未知",
                backupDate: json?["backupDate"] as? String ?? "未知",
                hasDatabase: json?["hasDatabase"] as? Bool ?? false,
                hasMedia: json?["hasMedia"] as? Bool ?? false,
                hasLogos: json?["hasLogos"] as? Bool ?? false
            )
        } catch {
            logger.error("读取备份信息失败: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
    
    // MARK: - 私有方法
    
    private func createZip(from sourceDir: URL, to destination: URL) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin ditto")
        process.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent", sourceDir.path, destination.path]
        process.standardOutput = nil
        process.standardError = nil
        try process.run()
        process.waitUntilExit()
        
        guard process.terminationStatus == 0 else {
            throw BackupError.zipFailed("ditto 返回错误码 \(process.terminationStatus)")
        }
    }
    
    private func extractZip(from zipURL: URL, to destination: URL) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin ditto")
        process.arguments = ["-x", "-k", zipURL.path, destination.path]
        process.standardOutput = nil
        process.standardError = nil
        try process.run()
        process.waitUntilExit()
        
        guard process.terminationStatus == 0 else {
            throw BackupError.zipFailed("解压失败，错误码 \(process.terminationStatus)")
        }
    }
    
    private func formatDateForFilename(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmm"
        return formatter.string(from: date)
    }
}

// MARK: - 类型定义

enum BackupError: LocalizedError {
    case invalidBackup(String)
    case zipFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidBackup(let reason): return "备份文件无效: \(reason)"
        case .zipFailed(let reason): return "压缩/解压失败: \(reason)"
        }
    }
}

struct BackupMetadata {
    let version: String
    let backupDate: String
    let hasDatabase: Bool
    let hasMedia: Bool
    let hasLogos: Bool
}
