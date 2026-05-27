import SwiftUI

struct PlatformView: View {
    let platform: Platform
    @Binding var selectedNav: NavigationTarget?
    @Binding var previousNav: NavigationTarget?
    @Environment(AppState.self) private var appState
    @State private var items: [Item] = []
    @State private var folders: [Folder] = []
    @State private var viewMode: ViewMode = .grid
    @State private var showNewFolderSheet = false
    @State private var moveTargetItemID: UUID?
    @State private var showMoveOverlay = false
        
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
            if !folders.isEmpty { folderSection }
            
            if items.isEmpty { emptyState }
            else if viewMode == .grid { mediaGridView }
            else { textListView }
        }
        .navigationTitle(platform.displayName)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 8) {
                    Button(action: { showNewFolderSheet = true }) {
                        Image(systemName: "folder.badge.plus")
                    }
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
        .sheet(isPresented: $showNewFolderSheet) {
            NewFolderSheet(platform: platform, isPresented: $showNewFolderSheet) { loadData() }
        }
        .overlay {
            if showMoveOverlay, let itemID = moveTargetItemID {
                Color.black.opacity(0.3).ignoresSafeArea()
                    .onTapGesture { showMoveOverlay = false }
                MoveToFolderOverlay(itemID: itemID, isPresented: $showMoveOverlay)
            }
        }
        .onAppear { loadData() }
    }
    
    private var folderSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(folders) { folder in
                    Button { selectedNav = .folder(folder.id) } label: {
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
    
    private var mediaGridView: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180, maximum: 220), spacing: 16)], spacing: 16) {
                ForEach(items) { item in
                    Button { previousNav = .platform(platform); selectedNav = .item(item.id) } label: {
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
            Button { previousNav = .platform(platform); selectedNav = .item(item.id) } label: {
                ItemListRow(item: item)
            }
            .buttonStyle(.plain)
            .contextMenu { itemContextMenu(item) }
        }
        .listStyle(.plain)
    }
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: platform.iconName)
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("\(platform.displayName)暂无内容")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("回到首页粘贴一条链接导入")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    @ViewBuilder
    private func itemContextMenu(_ item: Item) -> some View {
        Button {
            moveTargetItemID = item.id; showMoveOverlay = true
        } label: {
            Label(folders.isEmpty ? "暂无文件夹" : "移动到文件夹", systemImage: "folder")
        }
        .disabled(folders.isEmpty)
        Divider()
        Button("删除", role: .destructive) { deleteItem(item) }
    }
    
    private func loadData() {
        let repo = appState.itemRepo
        let folderRepo = appState.folderRepo
        let platform = platform
        DispatchQueue.global(qos: .userInitiated).async {
            let loadedItems = (try? repo.fetchAll(platform: platform)) ?? []
            let loadedFolders = (try? folderRepo.fetchAll(platform: platform)) ?? []
            DispatchQueue.main.async {
                self.items = loadedItems
                self.folders = loadedFolders
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

struct StatusTab: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundStyle(isSelected ? .primary : .secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(isSelected ? Color.primary.opacity(0.1) : Color.clear)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct PlatformStatusView: View {
    let platform: Platform
    let status: ArchiveStatus
    @Environment(AppState.self) private var appState
    @State private var items: [Item] = []
    var body: some View {
        Group {
            if items.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: status.iconName).font(.system(size: 48)).foregroundStyle(.tertiary)
                    Text("暂无\(status.displayName)内容").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(items) { item in ItemListRow(item: item) }.listStyle(.plain)
            }
        }
        .navigationTitle("\(platform.displayName) · \(status.displayName)")
        .onAppear { items = (try? appState.itemRepo.fetchAll(platform: platform, archiveStatus: status)) ?? [] }
    }
}

struct NewFolderSheet: View {
    let platform: Platform
    @Binding var isPresented: Bool
    var onCreate: (() -> Void)?
    @Environment(AppState.self) private var appState
    @State private var folderName = ""
    var body: some View {
        VStack(spacing: 20) {
            Text("新建文件夹").font(.headline)
            TextField("文件夹名称", text: $folderName).textFieldStyle(.roundedBorder)
            HStack {
                Button("取消") { isPresented = false }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("创建") {
                    let folder = Folder(name: folderName, platform: platform)
                    try? appState.folderRepo.insert(folder)
                    isPresented = false
                    appState.refreshData()
                    onCreate?()
                }
                .buttonStyle(.borderedProminent)
                .disabled(folderName.trimmingCharacters(in: .whitespaces).isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 350)
    }
}
