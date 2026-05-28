import SwiftUI

struct SearchResultsView: View {
    @Environment(AppState.self) private var appState
    @Binding var selectedNav: NavigationTarget?
    @Binding var previousNav: NavigationTarget?
    @State private var filterPlatform: String? = nil
    @State private var filterStatus: ArchiveStatus? = nil
    
    var body: some View {
        VStack(spacing: 0) {
            filterBar
            
            Divider()
            
            if filteredResults.isEmpty {
                VStack {
                    Spacer()
                    ContentUnavailableView(
                        "没有找到相关内容",
                        systemImage: "magnifyingglass",
                        description: Text("尝试修改搜索关键词")
                    )
                    Spacer()
                }
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 180, maximum: 220), spacing: 16)], spacing: 16) {
                        ForEach(filteredResults) { result in
                            Button {
                                previousNav = .search
                                selectedNav = .item(result.item.id)
                            } label: {
                                ItemCardView(item: result.item)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(16)
                }
            }
        }
        .navigationTitle("搜索: \(appState.searchQuery)")
    }
    
    private var filterBar: some View {
        HStack(spacing: 12) {
            Picker("分类", selection: $filterPlatform) {
                Text("全部").tag(nil as String?)
                ForEach(appState.customPlatforms) { cp in
                    Text(cp.name).tag(cp.id.uuidString as String?)
                }
                Text("未分类").tag("__uncategorized__" as String?)
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
            if let filterPlatform = filterPlatform {
                if filterPlatform == "__uncategorized__" {
                    if result.item.customPlatformID != nil { return false }
                } else if result.item.customPlatformID?.uuidString != filterPlatform {
                    return false
                }
            }
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
                Text(result.item.displayTitle)
                        .font(.subheadline)
                        .fontWeight(.medium)
                
                if let body = result.item.body, !body.isEmpty {
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
