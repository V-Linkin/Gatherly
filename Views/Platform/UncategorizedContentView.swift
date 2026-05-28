import SwiftUI

struct UncategorizedContentView: View {
    @Binding var selectedNav: NavigationTarget?
    @Binding var previousNav: NavigationTarget?
    @Environment(AppState.self) private var appState
    
    @State private var items: [Item] = []
    @State private var folders: [Folder] = []
    @State private var viewMode: ViewMode = .grid
    @State private var sortNewestFirst = true
    @State private var moveTargetItemID: UUID?
    @State private var showMoveOverlay = false
    @State private var showMoveToPlatform = false
    
    enum ViewMode: String, CaseIterable {
        case grid = "网格"
        case list = "列表"
        var icon: String {
            switch self {
            case .grid: return "square.grid.2x2"
            case .list: return "list.bullet"
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            if !folders.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(folders) { folder in
                            Button {
                                previousNav = .uncategorized
                                selectedNav = .folder(folder.id)
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "folder.fill").foregroundStyle(.blue)
                                    Text(folder.name).font(.subheadline)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(.background)
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(.quaternary))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
            }
            
            if items.isEmpty { emptyState }
            else if viewMode == .grid { mediaGridView }
            else { textListView }
        }
        .navigationTitle("未分类内容")
        .onChange(of: viewMode) { _, newValue in
            UserDefaults.standard.set(newValue.rawValue, forKey: "viewMode_uncategorized")
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 8) {
                    Button(action: { sortNewestFirst.toggle(); loadData() }) {
                        Image(systemName: sortNewestFirst ? "arrow.down" : "arrow.up")
                    }
                    .help(sortNewestFirst ? "最新优先" : "最早优先")
                    Picker("视图", selection: $viewMode) {
                        ForEach(ViewMode.allCases, id: \.self) { mode in
                            Image(systemName: mode.icon).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 80)
                }
            }
        }
        .overlay {
            if showMoveOverlay, let itemID = moveTargetItemID {
                Color.black.opacity(0.3).ignoresSafeArea()
                    .onTapGesture { showMoveOverlay = false }
                MoveToFolderOverlay(itemID: itemID, isPresented: $showMoveOverlay)
            }
        }
        .sheet(isPresented: $showMoveToPlatform) {
            if let itemID = moveTargetItemID {
                MoveToPlatformSheet(itemID: itemID, isPresented: $showMoveToPlatform)
            }
        }
        .onAppear {
            if let saved = UserDefaults.standard.string(forKey: "viewMode_uncategorized"),
               let mode = ViewMode(rawValue: saved) {
                viewMode = mode
            }
            loadData()
        }
    }
    
    private var mediaGridView: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180, maximum: 220), spacing: 16)], spacing: 16) {
                ForEach(items) { item in
                    Button {
                        previousNav = .uncategorized
                        selectedNav = .item(item.id)
                    } label: {
                        ItemCardView(item: item)
                    }
                    .buttonStyle(.plain)
                    .contextMenu { itemContextMenu(item) }
                }
            }
            .padding(16)
        }
    }
    
    private var textListView: some View {
        List(items) { item in
            Button {
                previousNav = .uncategorized
                selectedNav = .item(item.id)
            } label: {
                ItemListRow(item: item)
            }
            .buttonStyle(.plain)
            .contextMenu { itemContextMenu(item) }
        }
        .listStyle(.plain)
    }
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "tray")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("没有未分类内容")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("自定义平台被删除后，内容会自动移到这里")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    @ViewBuilder
    private func itemContextMenu(_ item: Item) -> some View {
        Button {
            moveTargetItemID = item.id
            showMoveOverlay = true
        } label: {
            Label("移动到文件夹", systemImage: "folder")
        }
        Button {
            moveTargetItemID = item.id
            showMoveToPlatform = true
        } label: {
            Label("移动到平台", systemImage: "arrow.right.circle")
        }
        .disabled(appState.customPlatforms.isEmpty)
        Divider()
        Button("删除", role: .destructive) { deleteItem(item) }
    }
    
    private func loadData() {
        let newest = sortNewestFirst
        let itemRepo = appState.itemRepo
        let folderRepo = appState.folderRepo
        DispatchQueue.global(qos: .userInitiated).async {
            let allItems = (try? itemRepo.fetchAll()) ?? []
            // 未分类内容: customPlatformID 为 nil 且 platform 为 .custom
            // 也包含通过链接导入但没有匹配到自定义平台的项目
            let filtered = allItems.filter { $0.customPlatformID == nil }
            let sorted = filtered.sorted {
                newest ? $0.importDate > $1.importDate : $0.importDate < $1.importDate
            }
            let allFolders = (try? folderRepo.fetchAll(platform: .custom)) ?? []
            let filteredFolders = allFolders.filter { $0.customPlatformID == nil }
            DispatchQueue.main.async {
                self.items = sorted
                self.folders = filteredFolders
            }
        }
    }
    
    private func deleteItem(_ item: Item) {
        var updated = item
        updated.deletedAt = Date()
        updated.contentStatus = .trashed
        try? appState.itemRepo.update(updated)
        let record = TrashRecord(itemID: item.id, originalFolderID: item.folderID, originalArchiveStatus: item.archiveStatus)
        try? appState.trashRepo.insert(record)
        loadData()
    }
}
