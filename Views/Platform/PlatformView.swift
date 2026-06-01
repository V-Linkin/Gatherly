import SwiftUI

struct PlatformView: View {
    let platform: Platform
    @Binding var selectedNav: NavigationTarget?
    @Binding var previousNav: NavigationTarget?
    @Environment(AppState.self) private var appState
    @State private var items: [Item] = []
    @State private var folders: [Folder] = []
    @State private var viewMode: ViewMode = .grid
    @State private var sortNewestFirst = true
    @State private var showNewFolderSheet = false
    @State private var moveTargetItemID: UUID?
    @State private var showMoveOverlay = false
    @State private var showMoveToPlatform = false
    @State private var isMultiSelectMode = false
    @State private var selectedItemIDs: Set<UUID> = []
    @State private var showBatchDeleteConfirm = false
    
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
        .onChange(of: viewMode) { _, newValue in
            UserDefaults.standard.set(newValue.rawValue, forKey: "viewMode_\(platform.rawValue)")
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if isMultiSelectMode {
                    HStack(spacing: 8) {
                        Text("已选 \(selectedItemIDs.count) 项")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Button("移动") { showMoveToPlatform = true }
                            .disabled(selectedItemIDs.isEmpty)
                        Button("删除", role: .destructive) { showBatchDeleteConfirm = true }
                            .disabled(selectedItemIDs.isEmpty)
                        Button("取消") { isMultiSelectMode = false; selectedItemIDs.removeAll() }
                    }
                } else {
                    HStack(spacing: 8) {
                        Button(action: { appState.newItemPlatform = platform; appState.newItemCustomPlatformID = nil; appState.showNewItem = true }) {
                            Image(systemName: "plus.circle")
                        }
                        Button(action: { showNewFolderSheet = true }) {
                            Image(systemName: "folder.badge.plus")
                        }
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
        .sheet(isPresented: $showMoveToPlatform) {
            if isMultiSelectMode {
                MoveToPlatformSheet(itemID: nil, itemIDs: Array(selectedItemIDs), isPresented: $showMoveToPlatform) {
                    isMultiSelectMode = false
                    selectedItemIDs.removeAll()
                    loadData()
                }
            } else if let itemID = moveTargetItemID {
                MoveToPlatformSheet(itemID: itemID, isPresented: $showMoveToPlatform) { loadData() }
            }
        }
        .onAppear {
            if let saved = UserDefaults.standard.string(forKey: "viewMode_\(platform.rawValue)"),
               let mode = ViewMode(rawValue: saved) {
                viewMode = mode
            }
            loadData()
        }
        .alert("确认删除", isPresented: $showBatchDeleteConfirm) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) { batchDeleteItems() }
        } message: {
            Text("确定要删除选中的 \(selectedItemIDs.count) 条内容吗？删除后可在回收站恢复。")
        }
    }
    
    private var folderSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(folders) { folder in
                    Button {
                        previousNav = .platform(platform)
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
    
    private var mediaGridView: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180, maximum: 220), spacing: 16)], spacing: 16) {
                ForEach(items) { item in
                    Button {
                        if isMultiSelectMode {
                            if selectedItemIDs.contains(item.id) {
                                selectedItemIDs.remove(item.id)
                                if selectedItemIDs.isEmpty { isMultiSelectMode = false }
                            } else {
                                selectedItemIDs.insert(item.id)
                            }
                        } else {
                            previousNav = .platform(platform)
                            if NavDebounce.shared.canNavigate() { selectedNav = .item(item.id) }
                        }
                    } label: {
                        ZStack(alignment: .topTrailing) {
                            ItemCardView(item: item)
                            if isMultiSelectMode {
                                Color.black.opacity(selectedItemIDs.contains(item.id) ? 0.15 : 0)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                Image(systemName: selectedItemIDs.contains(item.id) ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 28))
                                    .foregroundStyle(selectedItemIDs.contains(item.id) ? .blue : .white)
                                    .padding(8)
                            }
                        }
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
                if isMultiSelectMode {
                    if selectedItemIDs.contains(item.id) {
                        selectedItemIDs.remove(item.id)
                        if selectedItemIDs.isEmpty { isMultiSelectMode = false }
                    } else {
                        selectedItemIDs.insert(item.id)
                    }
                } else {
                    previousNav = .platform(platform)
                    if NavDebounce.shared.canNavigate() { selectedNav = .item(item.id) }
                }
            } label: {
                HStack {
                    if isMultiSelectMode {
                        Image(systemName: selectedItemIDs.contains(item.id) ? "checkmark.circle.fill" : "circle")
                            .font(.title2)
                            .foregroundStyle(selectedItemIDs.contains(item.id) ? .blue : .secondary)
                            .frame(width: 28)
                    }
                    ItemListRow(item: item)
                }
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
            isMultiSelectMode = true
            selectedItemIDs.insert(item.id)
        } label: {
            Label("多选", systemImage: "checkmark.circle")
        }
        Button {
            moveTargetItemID = item.id
            showMoveOverlay = true
        } label: {
            Label(folders.isEmpty ? "暂无文件夹" : "移动到文件夹", systemImage: "folder")
        }
        .disabled(folders.isEmpty)
        Divider()
        Button("删除", role: .destructive) { deleteItem(item) }
    }
    
    private func batchDeleteItems() {
        for id in selectedItemIDs {
            if let item = items.first(where: { $0.id == id }) {
                var updated = item
                updated.deletedAt = Date()
                updated.contentStatus = .trashed
                try? appState.itemRepo.update(updated)
                let record = TrashRecord(itemID: item.id, originalFolderID: item.folderID, originalArchiveStatus: item.archiveStatus)
                try? appState.trashRepo.insert(record)
            }
        }
        selectedItemIDs.removeAll()
        isMultiSelectMode = false
        loadData()
    }
    
    private func loadData() {
        let newest = sortNewestFirst
        let itemRepo = appState.itemRepo
        let folderRepo = appState.folderRepo
        DispatchQueue.global(qos: .userInitiated).async {
            let loadedItems = (try? itemRepo.fetchAll(platform: platform)) ?? []
            let sortedItems = loadedItems.sorted {
                newest ? $0.importDate > $1.importDate : $0.importDate < $1.importDate
            }
            let loadedFolders = (try? folderRepo.fetchAll(platform: platform)) ?? []
            DispatchQueue.main.async {
                self.items = sortedItems
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
    var customPlatformID: UUID? = nil
    var parentID: UUID? = nil
    @Binding var isPresented: Bool
    var onCreate: (() -> Void)?
    @Environment(AppState.self) private var appState
    @State private var folderName = ""
    
    var body: some View {
        VStack(spacing: 20) {
            Text(parentID != nil ? "新建子文件夹" : "新建文件夹").font(.headline)
            TextField("文件夹名称", text: $folderName).textFieldStyle(.roundedBorder)
            HStack {
                Button("取消") { isPresented = false }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("创建") {
                    let folder = Folder(
                        name: folderName,
                        parentID: parentID,
                        platform: platform,
                        customPlatformID: customPlatformID
                    )
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
