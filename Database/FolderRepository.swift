import Foundation
import GRDB

/// 文件夹数据访问层
final class FolderRepository: @unchecked Sendable {
    private let db: DatabaseQueue
    
    init(db: DatabaseQueue = DatabaseManager.shared.db) {
        self.db = db
    }
    
    func insert(_ folder: Folder) throws {
        try db.write { db in
            try db.execute(
                sql: """
                INSERT INTO folders (id, name, parent_id, platform, created_at, sort_order, custom_platform_id)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    folder.id.uuidString, folder.name,
                    folder.parentID?.uuidString, folder.platform.rawValue,
                    folder.createdAt.timeIntervalSince1970, folder.sortOrder,
                    folder.customPlatformID?.uuidString
                ]
            )
        }
    }
    
    func update(_ folder: Folder) throws {
        try db.write { db in
            try db.execute(
                sql: "UPDATE folders SET name=?, parent_id=?, sort_order=? WHERE id=?",
                arguments: [folder.name, folder.parentID?.uuidString, folder.sortOrder, folder.id.uuidString]
            )
        }
    }
    
    func delete(id: UUID) throws {
        try db.write { db in
            try db.execute(sql: "DELETE FROM folders WHERE id=?", arguments: [id.uuidString])
        }
    }
    
    func find(id: UUID) throws -> Folder? {
        try db.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: "SELECT * FROM folders WHERE id=?",
                arguments: [id.uuidString]
            ) else { return nil }
            return rowToFolder(row)
        }
    }
    
    func fetchAll(platform: Platform? = nil, parentID: UUID? = nil, customPlatformID: UUID? = nil) throws -> [Folder] {
        try db.read { db in
            var sql = "SELECT * FROM folders WHERE 1=1"
            var args: [DatabaseValueConvertible] = []
            
            if let platform = platform {
                sql += " AND platform=?"
                args.append(platform.rawValue)
            }
            if let parentID = parentID {
                sql += " AND parent_id=?"
                args.append(parentID.uuidString)
            } else {
                sql += " AND parent_id IS NULL"
            }
            if let cpID = customPlatformID {
                sql += " AND custom_platform_id=?"
                args.append(cpID.uuidString)
            }
            
            sql += " ORDER BY sort_order, name"
            return try Row.fetchAll(db, sql: sql, arguments: StatementArguments(args)).map(rowToFolder)
        }
    }
    
    func fetchRecent(limit: Int = 5) throws -> [Folder] {
        try db.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT * FROM folders ORDER BY created_at DESC LIMIT ?",
                arguments: [limit]
            ).map(rowToFolder)
        }
    }
    
    func countItems(folderID: UUID) throws -> Int {
        try db.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM items WHERE folder_id=? AND deleted_at IS NULL",
                arguments: [folderID.uuidString]
            ) ?? 0
        }
    }
    
    private func rowToFolder(_ row: Row) -> Folder {
        Folder(
            id: UUID(uuidString: row["id"])!,
            name: row["name"],
            parentID: (row["parent_id"] as String?).flatMap(UUID.init),
            platform: Platform(rawValue: row["platform"])!,
            customPlatformID: (row["custom_platform_id"] as String?).flatMap(UUID.init),
            createdAt: Date(timeIntervalSince1970: row["created_at"]),
            sortOrder: row["sort_order"]
        )
    }
}
