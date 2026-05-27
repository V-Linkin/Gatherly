import SwiftUI

/// 内容卡片（网格视图）
struct ItemCardView: View {
    let item: Item
    
    private var coverImage: NSImage? {
        guard let assetID = item.coverAssetID else { return nil }
        let mediaDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Archiver/media")
        
        let repo = MediaRepository()
        guard let asset = try? repo.findByItemID(item.id).first(where: { $0.id == assetID }),
              let localPath = asset.localPath else { return nil }
        
        let fileURL = mediaDir.appendingPathComponent(localPath)
        return NSImage(contentsOf: fileURL)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topTrailing) {
                if let nsImage = coverImage {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(4/3, contentMode: .fill)
                        .clipped()
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.quaternary)
                        .aspectRatio(4/3, contentMode: .fit)
                        .overlay {
                            Image(systemName: item.platform.iconName)
                                .font(.title)
                                .foregroundStyle(.tertiary)
                        }
                }
                
                HStack(spacing: 4) {
                    if item.contentStatus == .mediaIncomplete {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                    if item.contentStatus == .parseFailed {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(.red)
                    }
                }
                .padding(4)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            
            Text(item.displayTitle)
                .font(.subheadline)
                .fontWeight(.medium)
                .lineLimit(2)
                .foregroundStyle(.primary)
            
            HStack(spacing: 4) {
                Image(systemName: item.platform.iconName)
                    .font(.caption2)
                    .foregroundStyle(item.platform.brandColor)
                Text(item.displayAuthor)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(8)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(.quaternary, lineWidth: 1)
        )
    }
}

/// 内容列表行（列表视图）
struct ItemListRow: View {
    let item: Item
    
    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 6)
                .fill(.quaternary)
                .frame(width: 60, height: 60)
                .overlay {
                    Image(systemName: item.platform.iconName)
                        .foregroundStyle(.tertiary)
                }
                .clipShape(RoundedRectangle(cornerRadius: 6))
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(item.displayTitle)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    
                    if item.contentStatus != .normal {
                        Image(systemName: item.contentStatus.iconName)
                            .font(.caption2)
                            .foregroundStyle(statusColor)
                    }
                }
                
                if let body = item.body, !body.isEmpty {
                    Text(body)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                
                HStack(spacing: 8) {
                    Label(item.displayAuthor, systemImage: "person")
                    Label(item.platform.displayName, systemImage: item.platform.iconName)
                    if let date = item.publishDate {
                        Label(date.formatted(.dateTime.month().day()), systemImage: "calendar")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
            
            Spacer()
            
            Text(item.archiveStatus.displayName)
                .font(.caption2)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.quaternary)
                .clipShape(Capsule())
        }
        .padding(.vertical, 4)
    }
    
    private var statusColor: Color {
        switch item.contentStatus {
        case .normal: return .green
        case .parseFailed: return .red
        case .mediaIncomplete: return .orange
        case .sourceDeleted: return .gray
        case .trashed: return .gray
        }
    }
}
