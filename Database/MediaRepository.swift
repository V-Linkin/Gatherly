import Foundation
import GRDB

/// 媒体资产数据访问层
final class MediaRepository: @unchecked Sendable {
    private let db: DatabaseQueue
    
    init(db: DatabaseQueue = DatabaseManager.shared.db) {
        self.db = db
    }
    
    func insert(_ asset: MediaAsset) throws {
        try db.write { db in
            try db.execute(
                sql: """
                INSERT INTO media_assets (id, item_id, type, local_path, remote_url, file_name,
                    file_size, mime_type, width, height, duration, checksum, download_status,
                    thumbnail_path, created_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    asset.id.uuidString, asset.itemID.uuidString, asset.type.rawValue,
                    asset.localPath, asset.remoteURL, asset.fileName,
                    asset.fileSize, asset.mimeType, asset.width, asset.height,
                    asset.duration, asset.checksum, asset.downloadStatus.rawValue,
                    asset.thumbnailPath, asset.createdAt.timeIntervalSince1970
                ]
            )
        }
    }
    
    func update(_ asset: MediaAsset) throws {
        try db.write { db in
            try db.execute(
                sql: """
                UPDATE media_assets SET local_path=?, file_size=?, width=?, height=?,
                    duration=?, checksum=?, download_status=?, thumbnail_path=?
                WHERE id=?
                """,
                arguments: [
                    asset.localPath, asset.fileSize, asset.width, asset.height,
                    asset.duration, asset.checksum, asset.downloadStatus.rawValue,
                    asset.thumbnailPath, asset.id.uuidString
                ]
            )
        }
    }
    
    func findByItemID(_ itemID: UUID) throws -> [MediaAsset] {
        try db.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT * FROM media_assets WHERE item_id=? ORDER BY created_at",
                arguments: [itemID.uuidString]
            ).map(rowToAsset)
        }
    }
    
    func findByItemType(itemID: UUID, type: MediaType) throws -> [MediaAsset] {
        try db.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT * FROM media_assets WHERE item_id=? AND type=?",
                arguments: [itemID.uuidString, type.rawValue]
            ).map(rowToAsset)
        }
    }
    
    func deleteByID(_ id: UUID) throws {
        try db.write { db in
            try db.execute(sql: "DELETE FROM media_assets WHERE id=?", arguments: [id.uuidString])
        }
    }

    func deleteByItemID(_ itemID: UUID) throws {
        try db.write { db in
            try db.execute(sql: "DELETE FROM media_assets WHERE item_id=?", arguments: [itemID.uuidString])
        }
    }
    
    func fetchPending() throws -> [MediaAsset] {
        try db.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT * FROM media_assets WHERE download_status IN ('pending', 'failed')"
            ).map(rowToAsset)
        }
    }
    
    private func rowToAsset(_ row: Row) -> MediaAsset {
        MediaAsset(
            id: UUID(uuidString: row["id"])!,
            itemID: UUID(uuidString: row["item_id"])!,
            type: MediaType(rawValue: row["type"])!,
            localPath: row["local_path"],
            remoteURL: row["remote_url"],
            fileName: row["file_name"],
            fileSize: row["file_size"],
            mimeType: row["mime_type"],
            width: row["width"],
            height: row["height"],
            duration: row["duration"],
            checksum: row["checksum"],
            downloadStatus: DownloadStatus(rawValue: row["download_status"])!,
            thumbnailPath: row["thumbnail_path"],
            createdAt: Date(timeIntervalSince1970: row["created_at"])
        )
    }
}
