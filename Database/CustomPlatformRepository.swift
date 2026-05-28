import Foundation
import GRDB

class CustomPlatformRepository: @unchecked Sendable {
    private let db: DatabaseQueue
    
    init() {
        self.db = DatabaseManager.shared.db
        try? setupTable()
    }
    
    private func setupTable() throws {
        try db.write { db in
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS custom_platforms (
                    id TEXT PRIMARY KEY,
                    name TEXT NOT NULL,
                    logo_path TEXT,
                    created_at REAL NOT NULL,
                    sort_order INTEGER NOT NULL DEFAULT 0
                )
            """)
        }
    }
    
    func insert(_ platform: CustomPlatform) throws {
        try db.write { db in
            try db.execute(sql: """
                INSERT INTO custom_platforms (id, name, logo_path, created_at, sort_order)
                VALUES (?, ?, ?, ?, ?)
            """, arguments: [
                platform.id.uuidString,
                platform.name,
                platform.logoPath,
                platform.createdAt.timeIntervalSince1970,
                platform.sortOrder
            ])
        }
    }
    
    func update(_ platform: CustomPlatform) throws {
        try db.write { db in
            try db.execute(sql: """
                UPDATE custom_platforms SET name=?, logo_path=?, sort_order=? WHERE id=?
            """, arguments: [
                platform.name,
                platform.logoPath,
                platform.sortOrder,
                platform.id.uuidString
            ])
        }
    }
    
    func delete(id: UUID) throws {
        try db.write { db in
            try db.execute(sql: "DELETE FROM custom_platforms WHERE id=?", arguments: [id.uuidString])
        }
    }
    
    func fetchAll() throws -> [CustomPlatform] {
        try db.read { db in
            let sql = "SELECT * FROM custom_platforms ORDER BY sort_order, created_at"
            let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments())
            return rows.map { rowToCustomPlatform($0) }
        }
    }
    
    private func rowToCustomPlatform(_ row: Row) -> CustomPlatform {
        CustomPlatform(
            id: UUID(uuidString: row["id"] as? String ?? "") ?? UUID(),
            name: row["name"] as? String ?? "",
            logoPath: row["logo_path"] as? String,
            createdAt: Date(timeIntervalSince1970: row["created_at"] as? Double ?? 0),
            sortOrder: row["sort_order"] as? Int ?? 0
        )
    }
    
    func find(id: UUID) throws -> CustomPlatform? {
        try db.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT * FROM custom_platforms WHERE id=?",
                arguments: [id.uuidString]
            )
            guard let row = rows.first else { return nil }
            return rowToCustomPlatform(row)
        }
    }
}
