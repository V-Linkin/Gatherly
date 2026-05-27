import SwiftUI

struct ItemDetailView: View {
    let itemID: UUID
    @Binding var selectedNav: NavigationTarget?
    @Binding var zoomedImage: NSImage?
    @Environment(AppState.self) private var appState
    
    @State private var item: Item?
    @State private var mediaAssets: [MediaAsset] = []
    @State private var isEditing = false
    @State private var editTitle = ""
    @State private var editBody = ""
    @State private var editRemark = ""
    @State private var showMoveSheet = false
    @State private var showDeleteConfirm = false
    
    
    var body: some View {
        Group {
            if let item = item {
                detailContent(item)
            } else {
                ContentUnavailableView("内容未找到", systemImage: "doc.questionmark")
            }
        }
        .navigationTitle(item?.displayTitle ?? "详情")
        .sheet(isPresented: $isEditing) { editSheet }
        .sheet(isPresented: $showMoveSheet) {
            MoveToFolderSheet(itemID: itemID, isPresented: $showMoveSheet)
        }
        .alert("移入回收站", isPresented: $showDeleteConfirm) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) { deleteItem() }
        } message: {
            Text("确定将此内容移入回收站？")
        }
        .onAppear { loadItem() }
    }
    
    private func detailContent(_ item: Item) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                mediaSection(item)
                Divider()
                metadataSection(item)
                Divider()
                bodySection(item)
                Divider()
                remarkSection(item)
            }
            .padding(24)
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Menu {
                    Button("编辑", systemImage: "pencil") {
                        editTitle = item.title ?? ""
                        editBody = item.body ?? ""
                        editRemark = item.remark ?? ""
                        isEditing = true
                    }
                    Button("移动到文件夹", systemImage: "folder") { showMoveSheet = true }
                    Divider()
                    Button("删除", systemImage: "trash", role: .destructive) { showDeleteConfirm = true }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
    }
    

    
    // MARK: - Sections
    
    private func mediaSection(_ item: Item) -> some View {
        let imageAssets = mediaAssets.filter { $0.type == .image || $0.type == .cover }
        
        return Group {
            if imageAssets.isEmpty {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.quaternary)
                    .frame(height: 200)
                    .overlay {
                        VStack(spacing: 8) {
                            Image(systemName: item.platform.iconName)
                                .font(.largeTitle)
                                .foregroundStyle(.tertiary)
                            Text("无媒体内容")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(imageAssets) { asset in
                            if let path = asset.localPath {
                                let url = mediaRootDir().appendingPathComponent(path)
                                if let nsImage = NSImage(contentsOf: url) {
                                    Image(nsImage: nsImage)
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(height: 280)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                        .onTapGesture { zoomedImage = nsImage }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 4)
                }
                .frame(height: 300)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }
    
    private func metadataSection(_ item: Item) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            InfoRow(label: "平台", value: item.platform.displayName, icon: item.platform.iconName)
            InfoRow(label: "作者", value: item.displayAuthor, icon: "person")
            if let date = item.publishDate {
                InfoRow(label: "发布时间", value: date.formatted(.dateTime.year().month().day()), icon: "calendar")
            }
            InfoRow(label: "导入时间", value: item.importDate.formatted(.dateTime.year().month().day().hour().minute()), icon: "clock")
            InfoRow(label: "状态", value: "\(item.archiveStatus.displayName) · \(item.contentStatus.displayName)", icon: "tag")
            Link(destination: URL(string: item.originalURL) ?? URL(string: "about:blank")!) {
                HStack(spacing: 6) {
                    Image(systemName: "link").font(.caption)
                    Text("查看原文").font(.caption)
                }
                .foregroundStyle(.blue)
            }
        }
    }
    
    private func bodySection(_ item: Item) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("正文").font(.headline)
            if let body = item.body, !body.isEmpty {
                Text(body).font(.body).textSelection(.enabled)
            } else {
                Text("无正文内容").font(.subheadline).foregroundStyle(.tertiary)
            }
        }
    }
    
    private func remarkSection(_ item: Item) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("备注").font(.headline)
            if let remark = item.remark, !remark.isEmpty {
                Text(remark).font(.body).foregroundStyle(.secondary)
            } else {
                Text("点击工具栏编辑按钮添加备注").font(.subheadline).foregroundStyle(.tertiary)
            }
        }
    }
    
    // MARK: - Edit Sheet
    
    private var editSheet: some View {
        VStack(spacing: 16) {
            Text("编辑内容").font(.headline)
            Form {
                TextField("标题", text: $editTitle)
                TextEditor(text: $editBody).frame(height: 150)
                TextEditor(text: $editRemark).frame(height: 80)
            }
            HStack {
                Button("取消") { isEditing = false }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("保存") { saveEdits() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 500, height: 400)
    }
    
    // MARK: - Actions
    
    private func loadItem() {
        item = try? appState.itemRepo.find(id: itemID)
        mediaAssets = (try? appState.mediaRepo.findByItemID(itemID)) ?? []
    }
    
    private func saveEdits() {
        guard var item = item else { return }
        item.title = editTitle.isEmpty ? nil : editTitle
        item.body = editBody.isEmpty ? nil : editBody
        item.remark = editRemark.isEmpty ? nil : editRemark
        item.modifyDate = Date()
        try? appState.itemRepo.update(item)
        self.item = item
        isEditing = false
        appState.refreshData()
    }
    

    private func deleteItem() {
        guard let item = item else { return }
        var updated = item
        updated.deletedAt = Date()
        updated.contentStatus = .trashed
        try? appState.itemRepo.update(updated)
        let record = TrashRecord(itemID: item.id, originalFolderID: item.folderID, originalArchiveStatus: item.archiveStatus)
        try? appState.trashRepo.insert(record)
        appState.refreshData()
        selectedNav = nil
    }
    
    private func mediaRootDir() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Archiver/media", isDirectory: true)
    }
}

// MARK: - InfoRow

struct InfoRow: View {
    let label: String
    let value: String
    var icon: String? = nil
    
    var body: some View {
        HStack(spacing: 8) {
            if let icon = icon {
                Image(systemName: icon).font(.caption).foregroundStyle(.secondary).frame(width: 16)
            }
            Text(label).font(.subheadline).foregroundStyle(.secondary).frame(width: 70, alignment: .trailing)
            Text(value).font(.subheadline)
        }
    }
}

// MARK: - MoveToFolderSheet

struct MoveToFolderSheet: View {
    let itemID: UUID
    @Binding var isPresented: Bool
    @Environment(AppState.self) private var appState
    @State private var folders: [Folder] = []
    @State private var selectedID: UUID? = nil
    @State private var item: Item?
    
    var body: some View {
        VStack(spacing: 0) {
            Text("移动到文件夹")
                .font(.headline)
                .padding()
            
            Divider()
            
            if folders.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "folder").font(.largeTitle).foregroundStyle(.tertiary)
                    Text("暂无文件夹").foregroundStyle(.secondary)
                    Text("请先在平台页面新建文件夹").font(.caption).foregroundStyle(.tertiary)
                    Spacer()
                }
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(folders) { folder in
                            Button {
                                selectedID = folder.id
                            } label: {
                                HStack {
                                    Image(systemName: selectedID == folder.id ? "folder.fill" : "folder")
                                        .foregroundStyle(.blue)
                                    Text(folder.name)
                                    Spacer()
                                    if selectedID == folder.id {
                                        Image(systemName: "checkmark").foregroundStyle(.blue)
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                            }
                            .buttonStyle(.plain)
                            
                            if folder.id != folders.last?.id {
                                Divider().padding(.leading, 40)
                            }
                        }
                    }
                }
            }
            
            Divider()
            
            HStack {
                Button("取消") { isPresented = false }
                Spacer()
                if item?.folderID != nil {
                    Button("移出文件夹") { moveItem(folderID: nil) }
                        .foregroundStyle(.secondary)
                }
                Button("移动") { moveItem(folderID: selectedID) }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedID == nil)
            }
            .padding()
        }
        .frame(width: 360, height: 320)
        .onAppear {
            folders = (try? appState.folderRepo.fetchAll()) ?? []
            item = try? appState.itemRepo.find(id: itemID)
            if let fid = item?.folderID { selectedID = fid }
        }
    }
    
    private func moveItem(folderID: UUID?) {
        guard var item = try? appState.itemRepo.find(id: itemID) else { return }
        item.folderID = folderID
        try? appState.itemRepo.update(item)
        isPresented = false
        appState.refreshData()
    }
}

// MARK: - MoveToFolderOverlay

struct MoveToFolderOverlay: View {
    let itemID: UUID
    @Binding var isPresented: Bool
    @Environment(AppState.self) private var appState
    @State private var folders: [Folder] = []
    @State private var selectedFolderID: UUID? = nil
    
    var body: some View {
        VStack(spacing: 0) {
            Text("移动到文件夹")
                .font(.headline)
                .padding()
            
            Divider()
            
            if folders.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "folder").font(.largeTitle).foregroundStyle(.tertiary)
                    Text("暂无文件夹").foregroundStyle(.secondary)
                    Spacer()
                }
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(folders) { folder in
                            Button {
                                selectedFolderID = folder.id
                            } label: {
                                HStack {
                                    Image(systemName: selectedFolderID == folder.id ? "folder.fill" : "folder")
                                        .foregroundStyle(.blue)
                                    Text(folder.name)
                                    Spacer()
                                    if selectedFolderID == folder.id {
                                        Image(systemName: "checkmark").foregroundStyle(.blue)
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                            }
                            .buttonStyle(.plain)
                            Divider().padding(.leading, 40)
                        }
                    }
                }
            }
            
            Divider()
            
            HStack {
                Button("取消") { isPresented = false }
                Spacer()
                Button("移动") {
                    guard let folderID = selectedFolderID else { return }
                    guard var item = try? appState.itemRepo.find(id: itemID) else { return }
                    item.folderID = folderID
                    try? appState.itemRepo.update(item)
                    isPresented = false
                    appState.refreshData()
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedFolderID == nil)
            }
            .padding()
        }
        .frame(width: 320, height: 300)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(radius: 20)
        .onAppear {
            folders = (try? appState.folderRepo.fetchAll()) ?? []
            if let item = try? appState.itemRepo.find(id: itemID) {
                selectedFolderID = item.folderID
            }
        }
    }
}
