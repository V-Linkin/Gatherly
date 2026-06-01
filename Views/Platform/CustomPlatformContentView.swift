import SwiftUI

struct CustomPlatformContentView: View {
    let customPlatformID: UUID
    @Binding var selectedNav: NavigationTarget?
    @Binding var previousNav: NavigationTarget?
    @Environment(AppState.self) private var appState
    
    @State private var items: [Item] = []
    @State private var folders: [Folder] = []
    @State private var customPlatform: CustomPlatform?
    @State private var viewMode: ViewMode = .grid
    @State private var sortNewestFirst = true
    @State private var moveTargetItemID: UUID?
    @State private var showMoveOverlay = false
    @State private var showMoveToPlatform = false
    private struct MoveTarget: Identifiable { let id: UUID }
    @State private var moveTarget: MoveTarget?
    @State private var showNewFolderSheet = false
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
            if !folders.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(folders) { folder in
                            Button {
                                previousNav = .customPlatform(customPlatformID)
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
        .navigationTitle(customPlatform?.name ?? "自定义平台")
        .onChange(of: viewMode) { _, newValue in
            UserDefaults.standard.set(newValue.rawValue, forKey: "viewMode_custom_\(customPlatformID.uuidString)")
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
                        Button(action: { appState.newItemPlatform = .custom; appState.newItemCustomPlatformID = customPlatformID; appState.showNewItem = true }) {
                            Image(systemName: "plus.circle")
                        }
                        Button(action: { showNewFolderSheet = true }) {
                            Image(systemName: "folder.badge.plus")
                        }
                        Button(action: { sortNewestFirst.toggle(); loadData() }) {
                            Image(systemName: sortNewestFirst ? "arrow.down" : "arrow.up")
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
        }
        .sheet(isPresented: $showNewFolderSheet) {
            NewFolderSheet(platform: .custom, customPlatformID: customPlatformID, isPresented: $showNewFolderSheet) { loadData() }
        }
        .overlay {
            if showMoveOverlay, let itemID = moveTargetItemID {
                Color.black.opacity(0.3).ignoresSafeArea()
                    .onTapGesture { showMoveOverlay = false }
                MoveToFolderOverlay(itemID: itemID, isPresented: $showMoveOverlay)
            }
        }
        .sheet(item: $moveTarget) { target in
            MoveToPlatformSheet(itemID: target.id, isPresented: Binding(
                get: { moveTarget != nil },
                set: { if !$0 { moveTarget = nil } }
            )) { loadData() }
        }
        .sheet(isPresented: $showMoveToPlatform) {
            MoveToPlatformSheet(itemID: nil, itemIDs: Array(selectedItemIDs), isPresented: $showMoveToPlatform) {
                isMultiSelectMode = false
                selectedItemIDs.removeAll()
                loadData()
            }
        }
        .onAppear {
            // 加载上次保存的视图模式
            if let saved = UserDefaults.standard.string(forKey: "viewMode_custom_\(customPlatformID.uuidString)"),
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
                            previousNav = .customPlatform(customPlatformID)
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
                    previousNav = .customPlatform(customPlatformID)
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
            Image(systemName: "star.fill")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("\(customPlatform?.name ?? "自定义平台")暂无内容")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("回到首页粘贴一条链接导入，或新建内容")
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
            Label("移动到文件夹", systemImage: "folder")
        }
        .disabled(folders.isEmpty)
        Button {
            moveTarget = MoveTarget(id: item.id)
        } label: {
            Label("移动到平台", systemImage: "arrow.right.circle")
        }
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
        customPlatform = try? appState.customPlatformRepo.find(id: customPlatformID)
        let newest = sortNewestFirst
        let itemRepo = appState.itemRepo
        let folderRepo = appState.folderRepo
        DispatchQueue.global(qos: .userInitiated).async {
            let allItems = (try? itemRepo.fetchAll()) ?? []
            // 显示 customPlatformID 匹配的项目
            let filtered = allItems.filter { $0.customPlatformID == customPlatformID }
            let sorted = filtered.sorted {
                newest ? $0.importDate > $1.importDate : $0.importDate < $1.importDate
            }
            let loadedFolders = (try? folderRepo.fetchAll(platform: .custom, customPlatformID: customPlatformID)) ?? []
            DispatchQueue.main.async {
                self.items = sorted
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
