import SwiftUI
import AppKit

struct NewItemView: View {
    @Binding var isPresented: Bool
    @Binding var selectedNav: NavigationTarget?
    @Environment(AppState.self) private var appState

    @State private var title = ""
    @State private var bodyText = ""
    @State private var author = ""
    @State private var originalURL = ""
    @State private var remark = ""

    @State private var selectedCustomPlatformID: UUID? = nil
    @State private var selectedFolderID: UUID? = nil

    @State private var imageURLs: [URL] = []
    @State private var videoURLs: [URL] = []

    @State private var availableFolders: [Folder] = []
    @State private var isSaving = false
    @State private var newFolderName = ""
    @State private var isCreatingFolder = false

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    platformSection
                    folderSection
                    metadataSection
                    mediaSection
                    remarkSection
                }
                .padding(24)
            }
        }
        .frame(width: 620, height: 680)
        .onAppear {
            selectedCustomPlatformID = appState.newItemCustomPlatformID
            loadFolders()
        }
        .onChange(of: selectedCustomPlatformID) { _, _ in loadFolders() }
    }

    private var headerBar: some View {
        HStack {
            Text("新建内容").font(.headline)
            Spacer()
            Button("取消") { isPresented = false }
                .keyboardShortcut(.cancelAction)
            Button("保存") { save() }
                .buttonStyle(.borderedProminent)
                .disabled(isSaving || title.trimmingCharacters(in: .whitespaces).isEmpty)
                .keyboardShortcut(.defaultAction)
        }
        .padding()
    }

    private var platformSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("平台分类").font(.headline)
            if appState.customPlatforms.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle").foregroundStyle(.tertiary)
                    Text("请先在侧边栏「新增平台」创建平台")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            } else {
                Picker("平台", selection: $selectedCustomPlatformID) {
                    Text("选择平台").tag(nil as UUID?)
                    ForEach(appState.customPlatforms) { cp in
                        Text(cp.name).tag(cp.id as UUID?)
                    }
                }
            }
        }
    }

    private var folderSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("文件夹（可选）").font(.headline)
                Spacer()
                Button {
                    isCreatingFolder = true
                } label: {
                    Label("新建文件夹", systemImage: "plus")
                        .font(.subheadline)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(selectedCustomPlatformID == nil)
            }
            
            if isCreatingFolder {
                HStack(spacing: 8) {
                    TextField("文件夹名称", text: $newFolderName)
                        .textFieldStyle(.roundedBorder)
                    Button("创建") {
                        createFolder()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(newFolderName.trimmingCharacters(in: .whitespaces).isEmpty)
                    Button("取消") {
                        isCreatingFolder = false
                        newFolderName = ""
                    }
                    .foregroundStyle(.secondary)
                }
            }
            
            if !availableFolders.isEmpty {
                Picker("选择文件夹", selection: $selectedFolderID) {
                    Text("无").tag(nil as UUID?)
                    ForEach(availableFolders) { folder in
                        Text(folder.name).tag(folder.id as UUID?)
                    }
                }
            } else if !isCreatingFolder {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle").foregroundStyle(.tertiary)
                    Text("该平台下暂无文件夹")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("内容信息").font(.headline)
            
            TextField("标题（必填）", text: $title)
                .textFieldStyle(.roundedBorder)
            
            TextField("作者", text: $author)
                .textFieldStyle(.roundedBorder)
            
            TextField("原始链接（可选）", text: $originalURL)
                .textFieldStyle(.roundedBorder)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("正文").font(.subheadline).foregroundStyle(.secondary)
                TextEditor(text: $bodyText)
                    .font(.body)
                    .scrollContentBackground(.visible)
                    .frame(minHeight: 100, idealHeight: 150, maxHeight: 250)
                    .padding(4)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
            }
        }
    }

    private var mediaSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("媒体文件").font(.headline)
            
            HStack(spacing: 12) {
                Button {
                    let urls = FilePicker.pickImages()
                    imageURLs.append(contentsOf: urls)
                } label: {
                    Label("添加图片", systemImage: "photo.badge.plus")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                
                Button {
                    let urls = FilePicker.pickVideos()
                    videoURLs.append(contentsOf: urls)
                } label: {
                    Label("添加视频", systemImage: "video.badge.plus")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            
            if !imageURLs.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("已选图片 (\(imageURLs.count))").font(.caption).foregroundStyle(.secondary)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Array(imageURLs.enumerated()), id: \.offset) { index, url in
                                if let nsImage = NSImage(contentsOf: url) {
                                    ZStack(alignment: .topTrailing) {
                                        Image(nsImage: nsImage)
                                            .resizable()
                                            .aspectRatio(contentMode: .fill)
                                            .frame(width: 80, height: 80)
                                            .clipShape(RoundedRectangle(cornerRadius: 6))
                                        Button { imageURLs.remove(at: index) } label: {
                                            Image(systemName: "xmark.circle.fill").font(.caption).foregroundStyle(.red)
                                        }.buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            
            if !videoURLs.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("已选视频 (\(videoURLs.count))").font(.caption).foregroundStyle(.secondary)
                    ForEach(Array(videoURLs.enumerated()), id: \.offset) { index, url in
                        HStack(spacing: 8) {
                            Image(systemName: "video")
                                .foregroundStyle(.blue)
                            Text(url.lastPathComponent)
                                .font(.caption)
                                .lineLimit(1)
                            Spacer()
                            Button { videoURLs.remove(at: index) } label: {
                                Image(systemName: "xmark.circle.fill").font(.caption).foregroundStyle(.red)
                            }.buttonStyle(.plain)
                        }
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(.quaternary).clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
        }
    }

    private var remarkSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("备注").font(.headline)
            TextEditor(text: $remark)
                .font(.body)
                .scrollContentBackground(.visible)
                .frame(minHeight: 60, idealHeight: 80)
                .padding(4)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
        }
    }

    private func loadFolders() {
        guard let cpID = selectedCustomPlatformID else {
            availableFolders = []
            return
        }
        availableFolders = (try? appState.folderRepo.fetchAll(platform: .custom, customPlatformID: cpID)) ?? []
    }

    private func createFolder() {
        guard let cpID = selectedCustomPlatformID else { return }
        let name = newFolderName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        
        let folder = Folder(name: name, platform: .custom, customPlatformID: cpID)
        try? appState.folderRepo.insert(folder)
        newFolderName = ""
        isCreatingFolder = false
        loadFolders()
        appState.refreshData()
        
        // 自动选中新创建的文件夹
        selectedFolderID = folder.id
    }

    private func save() {
        guard !title.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isSaving = true

        let now = Date()
        let normalizedURL = originalURL.isEmpty
            ? "custom://\(UUID().uuidString)"
            : URLNormalizer.normalize(originalURL, platform: .custom)
        let contentID = originalURL.isEmpty
            ? nil
            : URLNormalizer.extractContentID(originalURL, platform: .custom)

        var item = Item(
            title: title.isEmpty ? nil : title,
            body: bodyText.isEmpty ? nil : bodyText,
            originalURL: originalURL.isEmpty ? "custom://\(UUID().uuidString)" : originalURL,
            platform: .custom,
            platformContentID: contentID,
            normalizedURL: normalizedURL,
            author: author.isEmpty ? nil : author,
            publishDate: now,
            archiveStatus: .pending,
            mediaStatus: .textOnly,
            customPlatformID: selectedCustomPlatformID
        )
        item.folderID = selectedFolderID
        item.remark = remark.isEmpty ? nil : remark

        do {
            try appState.itemRepo.insert(item)
        } catch {
            isSaving = false
            appState.showToast("保存失败: \(error.localizedDescription)")
            return
        }

        let itemDir = DataDirectory.media.appendingPathComponent(item.id.uuidString)
        do {
            try FileManager.default.createDirectory(at: itemDir, withIntermediateDirectories: true)
        } catch {
            isSaving = false
            appState.showToast("创建目录失败")
            return
        }

        var mediaStatus: MediaStatus = .textOnly

        // Save images
        var savedImageCount = 0
        for (index, url) in imageURLs.enumerated() {
            let fileName = "image_\(String(format: "%03d", index + 1)).jpg"
            let dest = itemDir.appendingPathComponent(fileName)
            do {
                if FileManager.default.fileExists(atPath: dest.path) {
                    try FileManager.default.removeItem(at: dest)
                }
                try FileManager.default.copyItem(at: url, to: dest)
                let fileSize = (try? FileManager.default.attributesOfItem(atPath: dest.path)[.size] as? Int64) ?? 0
                let asset = MediaAsset(
                    itemID: item.id, type: .image,
                    localPath: "\(item.id.uuidString)/\(fileName)",
                    remoteURL: nil, fileName: fileName,
                    fileSize: fileSize, downloadStatus: .completed
                )
                try appState.mediaRepo.insert(asset)
                savedImageCount += 1
            } catch {
                print("图片保存失败: \(error)")
            }
        }

        // Use first image as cover
        if savedImageCount > 0 {
            if let firstAsset = try? appState.mediaRepo.findByItemID(item.id).first(where: { $0.type == .image }) {
                var updated = item
                updated.coverAssetID = firstAsset.id
                try? appState.itemRepo.update(updated)
            }
        }

        // Save videos
        var savedVideoCount = 0
        for (index, url) in videoURLs.enumerated() {
            let ext = url.pathExtension.isEmpty ? "mp4" : url.pathExtension
            let fileName = "video_\(index + 1).\(ext)"
            let dest = itemDir.appendingPathComponent(fileName)
            do {
                if FileManager.default.fileExists(atPath: dest.path) {
                    try FileManager.default.removeItem(at: dest)
                }
                try FileManager.default.copyItem(at: url, to: dest)
                let fileSize = (try? FileManager.default.attributesOfItem(atPath: dest.path)[.size] as? Int64) ?? 0
                let asset = MediaAsset(
                    itemID: item.id, type: .video,
                    localPath: "\(item.id.uuidString)/\(fileName)",
                    remoteURL: nil, fileName: fileName,
                    fileSize: fileSize, downloadStatus: .completed
                )
                try appState.mediaRepo.insert(asset)
                savedVideoCount += 1
            } catch {
                print("视频保存失败: \(error)")
            }
        }

        if savedImageCount > 0 && savedVideoCount > 0 {
            mediaStatus = .complete
        } else if savedImageCount > 0 || savedVideoCount > 0 {
            mediaStatus = .partial
        }

        var finalItem = item
        finalItem.mediaStatus = mediaStatus
        try? appState.itemRepo.update(finalItem)

        appState.refreshData()
        isSaving = false
        isPresented = false
        selectedNav = .item(item.id)
        
        let platformName = appState.customPlatforms.first(where: { $0.id == selectedCustomPlatformID })?.name ?? "未分类"
        appState.showToast("内容已保存到 \(platformName)")
    }
}
