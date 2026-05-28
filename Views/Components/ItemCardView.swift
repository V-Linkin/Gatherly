import SwiftUI

struct ItemCardView: View {
    let item: Item
    
    private static let cardWidth: CGFloat = 200
    private static let imageHeight: CGFloat = 160
    private static let innerWidth: CGFloat = 184 // 200 - 8*2
    
    private var coverImage: NSImage? {
        guard let assetID = item.coverAssetID else { return nil }
        let mediaDir = DataDirectory.media
        let repo = MediaRepository()
        guard let asset = try? repo.findByItemID(item.id).first(where: { $0.id == assetID }),
              let localPath = asset.localPath else { return nil }
        return NSImage(contentsOf: mediaDir.appendingPathComponent(localPath))
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 封面图：宽度填满，高度固定，超出裁切
            Group {
                if let nsImage = coverImage {
                    let w = nsImage.size.width
                    let h = nsImage.size.height
                    let scaledH = h * (Self.innerWidth / w)
                    let offset = scaledH > Self.imageHeight ? (scaledH - Self.imageHeight) / 2 : 0
                    Image(nsImage: nsImage)
                        .resizable()
                        .frame(width: Self.innerWidth, height: scaledH)
                        .offset(y: -offset)
                        .frame(width: Self.innerWidth, height: Self.imageHeight)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(.quaternary)
                        .frame(width: Self.innerWidth, height: Self.imageHeight)
                        .overlay {
                            Image(systemName: item.platform.iconName)
                                .font(.title)
                                .foregroundStyle(.tertiary)
                        }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            
            // 文字区域：固定高度，超出截断
            VStack(alignment: .leading, spacing: 4) {
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
                
                Text(item.importDate.formatted(.dateTime.month().day().hour().minute()))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.top, 6)
            .frame(width: Self.innerWidth, height: 52, alignment: .topLeading)
        }
        .padding(8)
        .background(.background)
        .frame(width: Self.cardWidth)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(.quaternary, lineWidth: 1)
        )
    }
}

struct ItemListRow: View {
    let item: Item
    
    private var coverImage: NSImage? {
        guard let assetID = item.coverAssetID else { return nil }
        let mediaDir = DataDirectory.media
        let repo = MediaRepository()
        guard let asset = try? repo.findByItemID(item.id).first(where: { $0.id == assetID }),
              let localPath = asset.localPath else { return nil }
        return NSImage(contentsOf: mediaDir.appendingPathComponent(localPath))
    }
    
    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let nsImage = coverImage {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.quaternary)
                        .overlay {
                            Image(systemName: item.platform.iconName)
                                .foregroundStyle(.tertiary)
                        }
                }
            }
            .frame(width: 60, height: 60)
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
