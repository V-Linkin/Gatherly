import Foundation
import GRDB

struct SearchResult: Identifiable {
    let id: UUID
    let item: Item
    let titleHighlighted: String?
    let bodyHighlighted: String?
    let rank: Double
}

final class SearchRepository: @unchecked Sendable {
    private let db: DatabaseQueue
    
    init(db: DatabaseQueue = DatabaseManager.shared.db) {
        self.db = db
    }
    
    func search(
        query: String,
        limit: Int = 50
    ) throws -> [SearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }
        
        // 先尝试 FTS5 搜索
        let ftsResults = try searchFTS(query: trimmed, limit: limit)
        if !ftsResults.isEmpty {
            return ftsResults
        }
        
        // FTS 无结果时，使用 LIKE 兜底搜索（支持中文）
        return try searchLike(query: trimmed, limit: limit)
    }
    
    private func searchFTS(query: String, limit: Int) throws -> [SearchResult] {
        let keywords = query
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .map { "\"\($0)\"" }
            .joined(separator: " OR ")
        
        guard !keywords.isEmpty else { return [] }
        
        return try db.read { db in
            let sql = """
            SELECT items.id, items.title, items.body, items.original_url, items.platform,
                items.platform_content_id, items.normalized_url, items.author, items.author_id,
                items.publish_date, items.import_date, items.modify_date, items.content_status,
                items.archive_status, items.media_status, items.cover_asset_id, items.folder_id,
                items.remark, items.is_starred, items.version, items.deleted_at,
                items.custom_platform_id,
                snippet(items_fts, 0, '<mark>', '</mark>', '...', 64) AS title_hl,
                snippet(items_fts, 1, '<mark>', '</mark>', '...', 64) AS body_hl,
                items_fts.rank
            FROM items_fts
            JOIN items ON items.rowid = items_fts.rowid
            WHERE items_fts MATCH ?
              AND items.deleted_at IS NULL
            ORDER BY items_fts.rank
            LIMIT ?
            """
            
            let rows = try Row.fetchAll(db, sql: sql, arguments: [keywords, limit])
            
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
    
    private func searchLike(query: String, limit: Int) throws -> [SearchResult] {
        let pattern = "%\(query)%"
        
        return try db.read { db in
            let sql = """
            SELECT id, title, body, original_url, platform,
                platform_content_id, normalized_url, author, author_id,
                publish_date, import_date, modify_date, content_status,
                archive_status, media_status, cover_asset_id, folder_id,
                remark, is_starred, version, deleted_at,
                custom_platform_id
            FROM items
            WHERE deleted_at IS NULL
              AND (title LIKE ? OR body LIKE ?)
            ORDER BY import_date DESC
            LIMIT ?
            """
            
            let rows = try Row.fetchAll(db, sql: sql, arguments: [pattern, pattern, limit])
            
            return rows.compactMap { row in
                guard let idStr: String = row["id"],
                      let id = UUID(uuidString: idStr) else { return nil }
                let item = self.rowToItem(row)
                return SearchResult(
                    id: id,
                    item: item,
                    titleHighlighted: nil,
                    bodyHighlighted: nil,
                    rank: 0
                )
            }
        }
    }
    
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
    
    func rebuildIndex() throws {
        try db.write { db in
            try db.execute(sql: "INSERT INTO items_fts(items_fts) VALUES('rebuild')")
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
            deletedAt: (row["deleted_at"] as Double?).flatMap { Date(timeIntervalSince1970: $0) },
            customPlatformID: (row["custom_platform_id"] as String?).flatMap(UUID.init)
        )
    }
}
