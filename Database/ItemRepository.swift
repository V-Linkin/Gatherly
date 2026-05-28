import Foundation
import GRDB

/// Item 数据访问层
final class ItemRepository: @unchecked Sendable {
    private let db: DatabaseQueue
    
    init(db: DatabaseQueue = DatabaseManager.shared.db) {
        self.db = db
    }
    
    // MARK: - CRUD
    
    /// 插入新内容
    func insert(_ item: Item) throws {
        try db.write { db in
            try insertRecord(item, db: db)
        }
    }
    
    private func insertRecord(_ item: Item, db: Database) throws {
        // 获取当前 last_insert_rowid 用于 FTS
        
        try db.execute(
            sql: """
            INSERT INTO items (id, title, body, original_url, platform, platform_content_id,
                normalized_url, author, author_id, publish_date, import_date, modify_date,
                content_status, archive_status, media_status, cover_asset_id, folder_id,
                remark, is_starred, version, deleted_at, custom_platform_id)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            arguments: [
                item.id.uuidString, item.title, item.body, item.originalURL,
                item.platform.rawValue, item.platformContentID, item.normalizedURL,
                item.author, item.authorID,
                item.publishDate?.timeIntervalSince1970,
                item.importDate.timeIntervalSince1970,
                item.modifyDate.timeIntervalSince1970,
                item.contentStatus.rawValue, item.archiveStatus.rawValue,
                item.mediaStatus.rawValue,
                item.coverAssetID?.uuidString, item.folderID?.uuidString,
                item.remark, item.isStarred, item.version,
                item.deletedAt?.timeIntervalSince1970,
                item.customPlatformID?.uuidString
            ]
        )
        
        // 使用显式 rowid 查询来同步 FTS 索引
        if let rowid = try? Int.fetchOne(
            db,
            sql: "SELECT rowid FROM items WHERE id=?",
            arguments: [item.id.uuidString]
        ) {
            try? db.execute(
                sql: "INSERT INTO items_fts (rowid, title, body) VALUES (?, ?, ?)",
                arguments: [rowid, item.title ?? "", item.body ?? ""]
            )
        }
    }
    
    /// 更新内容
    func update(_ item: Item) throws {
        try db.write { db in
            try db.execute(
                sql: """
                UPDATE items SET title=?, body=?, original_url=?, platform=?,
                    platform_content_id=?, normalized_url=?, author=?, author_id=?,
                    publish_date=?, import_date=?, modify_date=?, content_status=?,
                    archive_status=?, media_status=?, cover_asset_id=?, folder_id=?,
                    remark=?, is_starred=?, version=?, deleted_at=?,
                    custom_platform_id=?
                WHERE id=?
                """,
                arguments: [
                    item.title, item.body, item.originalURL, item.platform.rawValue,
                    item.platformContentID, item.normalizedURL, item.author, item.authorID,
                    item.publishDate?.timeIntervalSince1970,
                    item.importDate.timeIntervalSince1970,
                    item.modifyDate.timeIntervalSince1970,
                    item.contentStatus.rawValue, item.archiveStatus.rawValue,
                    item.mediaStatus.rawValue,
                    item.coverAssetID?.uuidString, item.folderID?.uuidString,
                    item.remark, item.isStarred, item.version,
                    item.deletedAt?.timeIntervalSince1970,
                    item.customPlatformID?.uuidString,
                    item.id.uuidString
                ]
            )
            
            // 更新 FTS 索引
            guard let rowid = try Int.fetchOne(
                db,
                sql: "SELECT rowid FROM items WHERE id=?",
                arguments: [item.id.uuidString]
            ) else { return }
            
            // 先删除旧 FTS 记录，再插入新记录
            try? db.execute(
                sql: "DELETE FROM items_fts WHERE rowid=?",
                arguments: [rowid]
            )
            try? db.execute(
                sql: "INSERT INTO items_fts (rowid, title, body) VALUES (?, ?, ?)",
                arguments: [rowid, item.title ?? "", item.body ?? ""]
            )
        }
    }
    
    /// 根据ID查找
    func find(id: UUID) throws -> Item? {
        try db.read { db in
            try fetchOne(db, sql: "SELECT * FROM items WHERE id=?", arguments: [id.uuidString])
        }
    }
    
    /// 根据平台和内容ID查找（用于去重）
    func findByPlatformContentID(platform: Platform, contentID: String) throws -> Item? {
        try db.read { db in
            try fetchOne(
                db,
                sql: "SELECT * FROM items WHERE platform=? AND platform_content_id=? AND deleted_at IS NULL",
                arguments: [platform.rawValue, contentID]
            )
        }
    }
    
    /// 根据标准化链接查找（用于去重）
    func findByNormalizedURL(_ url: String) throws -> Item? {
        try db.read { db in
            try fetchOne(
                db,
                sql: "SELECT * FROM items WHERE normalized_url=? AND deleted_at IS NULL",
                arguments: [url]
            )
        }
    }
    
    /// 查询所有未删除的内容
    func fetchAll(platform: Platform? = nil, archiveStatus: ArchiveStatus? = nil,
                  folderID: UUID? = nil, limit: Int = 100, offset: Int = 0) throws -> [Item] {
        try db.read { db in
            var sql = "SELECT * FROM items WHERE deleted_at IS NULL"
            var args: [DatabaseValueConvertible] = []
            
            if let platform = platform {
                sql += " AND platform=?"
                args.append(platform.rawValue)
            }
            if let status = archiveStatus {
                sql += " AND archive_status=?"
                args.append(status.rawValue)
            }
            if let folderID = folderID {
                sql += " AND folder_id=?"
                args.append(folderID.uuidString)
            }
            
            sql += " ORDER BY import_date DESC LIMIT ? OFFSET ?"
            args.append(limit)
            args.append(offset)
            
            return try fetchAll(db, sql: sql, arguments: StatementArguments(args))
        }
    }
    
    /// 获取最近导入的内容
    func fetchRecent(limit: Int = 10) throws -> [Item] {
        try db.read { db in
            try fetchAll(
                db,
                sql: "SELECT * FROM items WHERE deleted_at IS NULL ORDER BY import_date DESC LIMIT ?",
                arguments: [limit]
            )
        }
    }
    
    /// 软删除
    func softDelete(id: UUID) throws {
        try db.write { db in
            try db.execute(
                sql: "UPDATE items SET deleted_at=?, content_status='trashed' WHERE id=?",
                arguments: [Date().timeIntervalSince1970, id.uuidString]
            )
        }
    }
    
    /// 恢复
    func restore(id: UUID) throws {
        try db.write { db in
            try db.execute(
                sql: "UPDATE items SET deleted_at=NULL, content_status='normal' WHERE id=?",
                arguments: [id.uuidString]
            )
        }
    }
    
    /// 彻底删除
    func permanentDelete(id: UUID) throws {
        try db.write { db in
            try db.execute(sql: "DELETE FROM items WHERE id=?", arguments: [id.uuidString])
        }
    }
    
    /// 获取回收站内容
    func fetchTrashed() throws -> [Item] {
        try db.read { db in
            try fetchAll(
                db,
                sql: "SELECT * FROM items WHERE deleted_at IS NOT NULL ORDER BY deleted_at DESC"
            )
        }
    }
    
    /// 统计数量
    func count(platform: Platform? = nil, archiveStatus: ArchiveStatus? = nil) throws -> Int {
        try db.read { db in
            var sql = "SELECT COUNT(*) FROM items WHERE deleted_at IS NULL"
            var args: [DatabaseValueConvertible] = []
            
            if let platform = platform {
                sql += " AND platform=?"
                args.append(platform.rawValue)
            }
            if let status = archiveStatus {
                sql += " AND archive_status=?"
                args.append(status.rawValue)
            }
            
            return try Int.fetchOne(db, sql: sql, arguments: StatementArguments(args)) ?? 0
        }
    }
    
    // MARK: - Private
    
    private func fetchOne(_ db: Database, sql: String, arguments: StatementArguments) throws -> Item? {
        guard let row = try Row.fetchOne(db, sql: sql, arguments: arguments) else { return nil }
        return try rowToItem(row)
    }
    
    private func fetchAll(_ db: Database, sql: String, arguments: StatementArguments = StatementArguments()) throws -> [Item] {
        let rows = try Row.fetchAll(db, sql: sql, arguments: arguments)
        return try rows.map { try rowToItem($0) }
    }
    
    private func rowToItem(_ row: Row) throws -> Item {
        Item(
            id: UUID(uuidString: row["id"])!,
            title: row["title"],
            body: row["body"],
            originalURL: row["original_url"],
            platform: Platform(rawValue: row["platform"])!,
            platformContentID: row["platform_content_id"],
            normalizedURL: row["normalized_url"],
            author: row["author"],
            authorID: row["author_id"],
            publishDate: (row["publish_date"] as Double?).flatMap { Date(timeIntervalSince1970: $0) },
            importDate: Date(timeIntervalSince1970: row["import_date"]),
            contentStatus: ContentStatus(rawValue: row["content_status"])!,
            archiveStatus: ArchiveStatus(rawValue: row["archive_status"])!,
            mediaStatus: MediaStatus(rawValue: row["media_status"])!,
            coverAssetID: (row["cover_asset_id"] as String?).flatMap(UUID.init),
            folderID: (row["folder_id"] as String?).flatMap(UUID.init),
            remark: row["remark"],
            isStarred: row["is_starred"],
            version: row["version"],
            deletedAt: (row["deleted_at"] as Double?).flatMap { Date(timeIntervalSince1970: $0) },
            customPlatformID: (row["custom_platform_id"] as String?).flatMap(UUID.init)
        )
    }
}
