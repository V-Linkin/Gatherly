import Foundation
import GRDB

/// 搜索结果
struct SearchResult: Identifiable {
    let id: UUID
    let item: Item
    let titleHighlighted: String?
    let bodyHighlighted: String?
    let rank: Double
}

/// 全文搜索数据访问层
final class SearchRepository: @unchecked Sendable {
    private let db: DatabaseQueue
    
    init(db: DatabaseQueue = DatabaseManager.shared.db) {
        self.db = db
    }
    
    /// 全文搜索
    func search(
        query: String,
        platform: Platform? = nil,
        archiveStatus: ArchiveStatus? = nil,
        limit: Int = 50
    ) throws -> [SearchResult] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        
        // FTS5 查询语法：对关键词加引号并用 OR 连接
        let keywords = query
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .map { "\"\($0)\"" }
            .joined(separator: " OR ")
        
        guard !keywords.isEmpty else { return [] }
        
        return try db.read { db in
            var sql = """
            SELECT items.id, items.title, items.body, items.original_url, items.platform,
                items.platform_content_id, items.normalized_url, items.author, items.author_id,
                items.publish_date, items.import_date, items.modify_date, items.content_status,
                items.archive_status, items.media_status, items.cover_asset_id, items.folder_id,
                items.remark, items.is_starred, items.version, items.deleted_at,
                snippet(items_fts, 0, '<mark>', '</mark>', '...', 64) AS title_hl,
                snippet(items_fts, 1, '<mark>', '</mark>', '...', 64) AS body_hl,
                items_fts.rank
            FROM items_fts
            JOIN items ON items.rowid = items_fts.rowid
            WHERE items_fts MATCH ?
              AND items.deleted_at IS NULL
            """
            
            var args: [DatabaseValueConvertible] = [keywords]
            
            if let platform = platform {
                sql += " AND items.platform=?"
                args.append(platform.rawValue)
            }
            if let status = archiveStatus {
                sql += " AND items.archive_status=?"
                args.append(status.rawValue)
            }
            
            sql += " ORDER BY items_fts.rank LIMIT ?"
            args.append(limit)
            
            let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(args))
            
            return rows.compactMap { row in
                guard let idStr: String = row["id"],
                      let id = UUID(uuidString: idStr) else { return nil }
                
                let item = self.rowToItem(row)
                return SearchResult(
                    id: id,
                    item: item,
                    titleHighlighted: row["title_hl"],
                    bodyHighlighted: row["body_hl"],
                    rank: row["rank"] ?? 0
                )
            }
        }
    }
    
    /// 更新 FTS 索引（插入后调用）
    func updateIndex(item: Item) throws {
        try db.write { db in
            guard let rowid = try Int.fetchOne(
                db,
                sql: "SELECT rowid FROM items WHERE id=?",
                arguments: [item.id.uuidString]
            ) else { return }
            
            try db.execute(
                sql: "UPDATE items_fts SET title=?, body=? WHERE rowid=?",
                arguments: [item.title ?? "", item.body ?? "", rowid]
            )
        }
    }
    
    private func rowToItem(_ row: Row) -> Item {
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
            deletedAt: (row["deleted_at"] as Double?).flatMap { Date(timeIntervalSince1970: $0) }
        )
    }
}
