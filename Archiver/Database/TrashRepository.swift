import Foundation
import GRDB

/// 回收站数据访问层
final class TrashRepository: @unchecked Sendable {
    private let db: DatabaseQueue
    
    init(db: DatabaseQueue = DatabaseManager.shared.db) {
        self.db = db
    }
    
    func insert(_ record: TrashRecord) throws {
        try db.write { db in
            try db.execute(
                sql: """
                INSERT INTO trash_records (id, item_id, deleted_at, auto_delete_at,
                    original_folder_id, original_archive_status, media_paths)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    record.id.uuidString, record.itemID.uuidString,
                    record.deletedAt.timeIntervalSince1970,
                    record.autoDeleteAt.timeIntervalSince1970,
                    record.originalFolderID?.uuidString,
                    record.originalArchiveStatus.rawValue,
                    try toJSON(record.mediaPaths)
                ]
            )
        }
    }
    
    func findByItemID(_ itemID: UUID) throws -> TrashRecord? {
        try db.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: "SELECT * FROM trash_records WHERE item_id=?",
                arguments: [itemID.uuidString]
            ) else { return nil }
            return rowToRecord(row)
        }
    }
    
    func deleteByItemID(_ itemID: UUID) throws {
        try db.write { db in
            try db.execute(
                sql: "DELETE FROM trash_records WHERE item_id=?",
                arguments: [itemID.uuidString]
            )
        }
    }
    
    func fetchExpired() throws -> [TrashRecord] {
        try db.read { db in
            let now = Date().timeIntervalSince1970
            return try Row.fetchAll(
                db,
                sql: "SELECT * FROM trash_records WHERE auto_delete_at <= ?",
                arguments: [now]
            ).map(rowToRecord)
        }
    }
    
    func fetchAll() throws -> [TrashRecord] {
        try db.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT * FROM trash_records ORDER BY deleted_at DESC"
            ).map(rowToRecord)
        }
    }
    
    private func rowToRecord(_ row: Row) -> TrashRecord {
        let mediaPathsStr: String? = row["media_paths"]
        let paths: [String] = mediaPathsStr.flatMap { try? fromJSON($0) } ?? []
        
        return TrashRecord(
            id: UUID(uuidString: row["id"])!,
            itemID: UUID(uuidString: row["item_id"])!,
            deletedAt: Date(timeIntervalSince1970: row["deleted_at"]),
            autoDeleteAt: Date(timeIntervalSince1970: row["auto_delete_at"]),
            originalFolderID: (row["original_folder_id"] as String?).flatMap(UUID.init),
            originalArchiveStatus: ArchiveStatus(rawValue: row["original_archive_status"]) ?? .pending,
            mediaPaths: paths
        )
    }
    
    private func toJSON<T: Encodable>(_ value: T) throws -> String {
        let data = try JSONEncoder().encode(value)
        return String(data: data, encoding: .utf8) ?? "[]"
    }
    
    private func fromJSON<T: Decodable>(_ json: String) throws -> T {
        guard let data = json.data(using: .utf8) else { throw NSError(domain: "JSON", code: 0) }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
