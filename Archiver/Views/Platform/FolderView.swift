import SwiftUI

/// 文件夹页
struct FolderView: View {
    let folderID: UUID
    @Binding var selectedNav: NavigationTarget?
    @Binding var previousNav: NavigationTarget?
    @Environment(AppState.self) private var appState
    @State private var folder: Folder? = nil
    @State private var items: [Item] = []
    @State private var subfolders: [Folder] = []
    @State private var viewMode: PlatformView.ViewMode = .grid
    @State private var showRenameSheet = false
    @State private var renameText = ""
    @State private var showDeleteConfirm = false
    
    var body: some View {
        Group {
            if let currentFolder = folder {
                folderContent(currentFolder)
            } else {
                ContentUnavailableView("文件夹未找到", systemImage: "folder.badge.questionmark")
            }
        }
        .onAppear { loadData() }
    }
    
    private func folderContent(_ folder: Folder) -> some View {
        VStack(spacing: 0) {
            if !subfolders.isEmpty {
                subfolderBar
            }
            
            if items.isEmpty {
                emptyView
            } else if viewMode == .grid {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 180, maximum: 220), spacing: 16)], spacing: 16) {
                        ForEach(items) { item in
                            Button { previousNav = .folder(folderID)
                        selectedNav = .item(item.id) } label: {
                                ItemCardView(item: item)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(16)
                }
            } else {
                List(items) { item in
                    Button { previousNav = .folder(folderID)
                        selectedNav = .item(item.id) } label: {
                        ItemListRow(item: item)
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(folder.name)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Menu {
                    Button("重命名", systemImage: "pencil") {
                        renameText = folder.name
                        showRenameSheet = true
                    }
                    Button("删除", systemImage: "trash", role: .destructive) {
                        showDeleteConfirm = true
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                Picker("视图", selection: $viewMode) {
                    ForEach(PlatformView.ViewMode.allCases, id: \.self) { mode in
                        Image(systemName: mode.icon).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 80)
            }
        }
        .alert("重命名文件夹", isPresented: $showRenameSheet) {
            TextField("名称", text: $renameText)
            Button("取消", role: .cancel) {}
            Button("保存") { renameFolder() }
        }
        .alert("删除文件夹", isPresented: $showDeleteConfirm) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) { deleteFolder() }
        } message: {
            Text("确定删除文件夹？内容不会被删除。")
        }
    }
    
    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "folder")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("文件夹是空的")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var subfolderBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(subfolders) { sub in
                    Button { selectedNav = .folder(sub.id) } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "folder.fill").foregroundStyle(.blue)
                            Text(sub.name)
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
    
    private func loadData() {
        folder = try? appState.folderRepo.find(id: folderID)
        items = (try? appState.itemRepo.fetchAll(folderID: folderID)) ?? []
        subfolders = (try? appState.folderRepo.fetchAll(parentID: folderID)) ?? []
    }
    
    private func renameFolder() {
        guard var f = folder, !renameText.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        f.name = renameText
        try? appState.folderRepo.update(f)
        self.folder = f
        appState.refreshData()
    }
    
    private func deleteFolder() {
        guard let f = folder else { return }
        let itemsInFolder = (try? appState.itemRepo.fetchAll(folderID: f.id)) ?? []
        for var item in itemsInFolder {
            item.folderID = nil
            try? appState.itemRepo.update(item)
        }
        try? appState.folderRepo.delete(id: f.id)
        appState.refreshData()
        selectedNav = nil
    }
}
