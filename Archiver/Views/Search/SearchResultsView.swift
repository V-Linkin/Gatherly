import SwiftUI

/// 搜索结果页
struct SearchResultsView: View {
    @Environment(AppState.self) private var appState
    @State private var filterPlatform: Platform? = nil
    @State private var filterStatus: ArchiveStatus? = nil
    
    var body: some View {
        VStack(spacing: 0) {
            // 筛选栏
            filterBar
            
            // 结果
            if appState.searchResults.isEmpty {
                ContentUnavailableView(
                    "没有找到相关内容",
                    systemImage: "magnifyingglass",
                    description: Text("尝试修改搜索关键词")
                )
            } else {
                List(filteredResults) { result in
                    SearchResultRow(result: result)
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("搜索: \(appState.searchQuery)")
    }
    
    private var filterBar: some View {
        HStack(spacing: 12) {
            Picker("平台", selection: $filterPlatform) {
                Text("全部平台").tag(nil as Platform?)
                ForEach(Platform.allCases) { p in
                    Text(p.displayName).tag(p as Platform?)
                }
            }
            .frame(width: 120)
            
            Picker("状态", selection: $filterStatus) {
                Text("全部状态").tag(nil as ArchiveStatus?)
                ForEach(ArchiveStatus.allCases, id: \.self) { s in
                    Text(s.displayName).tag(s as ArchiveStatus?)
                }
            }
            .frame(width: 120)
            
            Spacer()
            
            Text("\(filteredResults.count) 条结果")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
    }
    
    private var filteredResults: [SearchResult] {
        appState.searchResults.filter { result in
            if let platform = filterPlatform, result.item.platform != platform { return false }
            if let status = filterStatus, result.item.archiveStatus != status { return false }
            return true
        }
    }
}

struct SearchResultRow: View {
    let result: SearchResult
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: result.item.platform.iconName)
                .font(.title3)
                .foregroundStyle(result.item.platform.brandColor)
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(result.item.displayTitle)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text(result.item.platform.displayName)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(result.item.platform.brandColor.opacity(0.1))
                        .clipShape(Capsule())
                    Text(result.item.archiveStatus.displayName)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary)
                        .clipShape(Capsule())
                }
                
                if let body = result.item.body {
                    Text(body)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                
                Text(result.item.importDate.formatted(.dateTime.month().day().hour().minute()))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }
}
