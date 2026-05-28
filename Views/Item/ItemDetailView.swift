import SwiftUI

struct ItemDetailView: View {
    let itemID: UUID
    @Binding var selectedNav: NavigationTarget?
    @Binding var previousNav: NavigationTarget?
    @Binding var zoomedImage: NSImage?
    @Environment(AppState.self) private var appState
    
    @State private var item: Item?
    @State private var mediaAssets: [MediaAsset] = []
    @State private var isEditing = false
    @State private var showMoveSheet = false
    @State private var showDeleteConfirm = false
    
    var body: some View {
        return Group {
            if let item = item {
                detailContent(item)
            } else {
                ContentUnavailableView("内容未找到", systemImage: "doc.questionmark")
            }
        }
        .navigationTitle(item?.displayTitle ?? "详情")
        .sheet(isPresented: $isEditing) {
            if let item = item {
                EditItemView(item: item, isPresented: $isEditing)
            }
        }
        .sheet(isPresented: $showMoveSheet) {
            MoveToFolderSheet(itemID: itemID, itemPlatform: item?.customPlatformID, isPresented: $showMoveSheet)
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
        return ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                mediaSection(item)
                Divider()
                metadataSection(item)
                Divider()
                bodySection(item)
                if let remark = item.remark, !remark.isEmpty {
                    Divider()
                    remarkSection(item)
                }
            }
            .padding(24)
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    isEditing = true
                } label: {
                    Label("编辑", systemImage: "pencil")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                
                Button { showMoveSheet = true } label: {
                    Label("移动", systemImage: "folder")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                
                Button { showDeleteConfirm = true } label: {
                    Label("删除", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .foregroundStyle(.red)
            }
        }
    }
    
    private func mediaSection(_ item: Item) -> some View {
        Group {
            if mediaAssets.isEmpty {
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
                        ForEach(Array(mediaAssets), id: \.id) { asset in
                            if let path = asset.localPath {
                                let url = DataDirectory.media.appendingPathComponent(path)
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
            if let cp = item.customPlatformID, let platform = appState.customPlatforms.first(where: { $0.id == cp }) {
                InfoRow(label: "平台", value: platform.name, icon: "star.fill")
            } else {
                InfoRow(label: "平台", value: item.platform.displayName, icon: item.platform.iconName)
            }
            InfoRow(label: "作者", value: item.displayAuthor, icon: "person")
            if let date = item.publishDate {
                InfoRow(label: "发布时间", value: date.formatted(.dateTime.year().month().day().hour().minute()), icon: "calendar")
            }
            InfoRow(label: "导入时间", value: item.importDate.formatted(.dateTime.year().month().day().hour().minute()), icon: "clock")
            if !item.originalURL.hasPrefix("custom://") {
                HStack(spacing: 6) {
                    Image(systemName: "link")
                        .foregroundStyle(.blue)
                    Text(item.originalURL)
                        .font(.caption)
                        .foregroundStyle(.blue)
                        .lineLimit(1)
                        .textSelection(.enabled)
                }
            }
            if let folderID = item.folderID, let folder = try? appState.folderRepo.find(id: folderID) {
                InfoRow(label: "文件夹", value: folder.name, icon: "folder.fill")
            }
        }
    }
    
    private func bodySection(_ item: Item) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("正文").font(.headline)
            if let body = item.body, !body.isEmpty {
                Text(stripHTML(body))
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineSpacing(4)
                    .textSelection(.enabled)
            } else {
                Text("暂无正文内容")
                    .font(.body)
                    .foregroundStyle(.tertiary)
            }
        }
    }
    
    private func remarkSection(_ item: Item) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("备注").font(.headline)
            Text(item.remark ?? "")
                .font(.body)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
        }
    }
    
    private func stripHTML(_ html: String) -> String {
        var result = html
        // 块级标签先转为换行
        result = result.replacingOccurrences(of: "<br[^>]*>", with: "\n", options: .regularExpression)
        result = result.replacingOccurrences(of: "</p>", with: "\n", options: .regularExpression)
        result = result.replacingOccurrences(of: "</div>", with: "\n", options: .regularExpression)
        result = result.replacingOccurrences(of: "</li>", with: "\n", options: .regularExpression)
        result = result.replacingOccurrences(of: "<p[^>]*>", with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: "<div[^>]*>", with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: "<li[^>]*>", with: "", options: .regularExpression)
        // 去除剩余 HTML 标签
        result = result.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        // 解码 HTML 实体
        result = result.replacingOccurrences(of: "&amp;", with: "&")
        result = result.replacingOccurrences(of: "&lt;", with: "<")
        result = result.replacingOccurrences(of: "&gt;", with: ">")
        result = result.replacingOccurrences(of: "&nbsp;", with: " ")
        result = result.replacingOccurrences(of: "&quot;", with: "\"")
        result = result.replacingOccurrences(of: "&#39;", with: "'")
        // 合并连续空格（但保留换行）
        result = result.replacingOccurrences(of: " +", with: " ", options: .regularExpression)
        result = result.replacingOccurrences(of: "\n +", with: "\n", options: .regularExpression)
        result = result.replacingOccurrences(of: " +\n", with: "\n", options: .regularExpression)
        // 合并连续空行为一个
        result = result.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func loadItem() {
        item = try? appState.itemRepo.find(id: itemID)
        mediaAssets = (try? appState.mediaRepo.findByItemID(itemID)) ?? []

    }
    
    private func deleteItem() {
        guard let item = item else { return }
        var updated = item
        updated.deletedAt = Date()
        updated.contentStatus = .trashed
        try? appState.itemRepo.update(updated)
        
        let mediaPaths = mediaAssets.compactMap { $0.localPath }
        let record = TrashRecord(
            itemID: item.id,
            originalFolderID: item.folderID,
            originalArchiveStatus: item.archiveStatus,
            mediaPaths: mediaPaths
        )
        try? appState.trashRepo.insert(record)
        
        appState.refreshData()
        let target = previousNav ?? .home
        previousNav = nil
        selectedNav = target
    }
}

struct InfoRow: View {
    let label: String
    let value: String
    let icon: String
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .leading)
            Text(value)
                .font(.subheadline)
        }
    }
}

// MARK: - MoveToFolderSheet

struct MoveToFolderSheet: View {
    let itemID: UUID
    var itemPlatform: UUID? = nil
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
                    Text("暂无文件夹，请先创建文件夹").foregroundStyle(.secondary)
                        .font(.subheadline)
                    Spacer()
                }
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(folders), id: \.id) { folder in
                            Button {
                                selectedID = folder.id
                            } label: {
                                HStack {
                                    Image(systemName: selectedID == folder.id ? "folder.fill" : "folder")
                                        .foregroundStyle(.blue)
                                    Text(folderPlatformName(folder))
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
            if let cpID = itemPlatform {
                folders = (try? appState.folderRepo.fetchAll(platform: .custom, customPlatformID: cpID)) ?? []
            } else {
                folders = (try? appState.folderRepo.fetchAll(platform: .custom)) ?? []
            }
            item = try? appState.itemRepo.find(id: itemID)
            if let fid = item?.folderID { selectedID = fid }
        }
    }
    
    private func folderPlatformName(_ folder: Folder) -> String {
        if let cpID = folder.customPlatformID,
           let cp = try? appState.customPlatformRepo.find(id: cpID) {
            return "\(cp.name) - \(folder.name)"
        }
        return folder.name
    }
    
    private func moveItem(folderID: UUID?) {
        guard var item = try? appState.itemRepo.find(id: itemID) else { return }
        item.folderID = folderID
        // 自动移动到文件夹所属平台
        if let folderID = folderID,
           let folder = folders.first(where: { $0.id == folderID }),
           let cpID = folder.customPlatformID {
            item.customPlatformID = cpID
            item.platform = .custom
        } else if folderID == nil {
            item.customPlatformID = nil
        }
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
                        .font(.subheadline)
                    Spacer()
                }
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(folders), id: \.id) { folder in
                            Button {
                                selectedFolderID = folder.id
                            } label: {
                                HStack {
                                    Image(systemName: selectedFolderID == folder.id ? "folder.fill" : "folder")
                                        .foregroundStyle(.blue)
                                    Text(folderPlatformName(folder))
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
                    // 自动移动到文件夹所属平台
                    if let folder = folders.first(where: { $0.id == folderID }),
                       let cpID = folder.customPlatformID {
                        item.customPlatformID = cpID
                        item.platform = .custom
                    }
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
            folders = (try? appState.folderRepo.fetchAll(platform: .custom)) ?? []
            if let item = try? appState.itemRepo.find(id: itemID) {
                selectedFolderID = item.folderID
            }
        }
    }
    
    private func folderPlatformName(_ folder: Folder) -> String {
        if let cpID = folder.customPlatformID,
           let cp = try? appState.customPlatformRepo.find(id: cpID) {
            return "\(cp.name) - \(folder.name)"
        }
        return folder.name
    }
}

// MARK: - MoveToPlatformSheet

struct MoveToPlatformSheet: View {
    let itemID: UUID
    @Binding var isPresented: Bool
    @Environment(AppState.self) private var appState
    @State private var selectedPlatformID: UUID? = nil
    @State private var item: Item?
    
    var body: some View {
        VStack(spacing: 0) {
            Text("移动到平台")
                .font(.headline)
                .padding()
            
            Divider()
            
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(appState.customPlatforms) { cp in
                        Button {
                            selectedPlatformID = cp.id
                        } label: {
                            HStack {
                                if let logoPath = cp.logoPath {
                                    let url = DataDirectory.platformLogos.appendingPathComponent(logoPath)
                                    if let nsImage = NSImage(contentsOf: url) {
                                        Image(nsImage: nsImage)
                                            .resizable()
                                            .frame(width: 20, height: 20)
                                            .clipShape(RoundedRectangle(cornerRadius: 4))
                                    } else {
                                        Image(systemName: "star.fill").foregroundStyle(.purple)
                                    }
                                } else {
                                    Image(systemName: "star.fill").foregroundStyle(.purple)
                                }
                                Text(cp.name)
                                Spacer()
                                if selectedPlatformID == cp.id {
                                    Image(systemName: "checkmark").foregroundStyle(.blue)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)
                        if cp.id != appState.customPlatforms.last?.id {
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
                    guard let platformID = selectedPlatformID else { return }
                    guard var item = try? appState.itemRepo.find(id: itemID) else { return }
                    item.customPlatformID = platformID
                    item.platform = .custom
                    item.folderID = nil
                    try? appState.itemRepo.update(item)
                    isPresented = false
                    appState.refreshData()
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedPlatformID == nil)
            }
            .padding()
        }
        .frame(width: 320, height: 340)
        .onAppear {
            item = try? appState.itemRepo.find(id: itemID)
            selectedPlatformID = item?.customPlatformID
        }
    }
}
