import SwiftUI

struct EditItemView: View {
    let item: Item
    @Binding var isPresented: Bool
    @Environment(AppState.self) private var appState
    
    @State private var title: String
    @State private var bodyText: String
    @State private var author: String
    @State private var remark: String
    @State private var mediaAssets: [MediaAsset] = []
    @State private var newImageURLs: [URL] = []
    @State private var newVideoURLs: [URL] = []
    
    // 初始值，用于检测是否有变更
    @State private var initialTitle: String
    @State private var initialBodyText: String
    @State private var initialAuthor: String
    @State private var initialRemark: String
    @State private var removedAssetIDs: Set<UUID> = []
    
    // 退出确认
    @State private var showDiscardConfirm = false
    
    // Image viewer
    // 图片查看器已使用 ViewerWindowManager
    
    init(item: Item, isPresented: Binding<Bool>) {
        self.item = item
        self._isPresented = isPresented
        let t = item.title ?? ""
        let b = item.body ?? ""
        let a = item.author ?? ""
        let r = item.remark ?? ""
        _title = State(initialValue: t)
        _bodyText = State(initialValue: b)
        _author = State(initialValue: a)
        _remark = State(initialValue: r)
        _initialTitle = State(initialValue: t)
        _initialBodyText = State(initialValue: b)
        _initialAuthor = State(initialValue: a)
        _initialRemark = State(initialValue: r)
    }
    
    private var hasChanges: Bool {
        title != initialTitle ||
        bodyText != initialBodyText ||
        author != initialAuthor ||
        remark != initialRemark ||
        !newImageURLs.isEmpty ||
        !newVideoURLs.isEmpty ||
        !removedAssetIDs.isEmpty
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("编辑内容").font(.headline)
                Spacer()
                Button("取消") {
                    if hasChanges {
                        showDiscardConfirm = true
                    } else {
                        isPresented = false
                    }
                }
                .keyboardShortcut(.cancelAction)
                Button("保存") { save() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("标题").font(.subheadline).foregroundStyle(.secondary)
                            TextField("输入标题", text: $title)
                                .textFieldStyle(.roundedBorder)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("作者").font(.subheadline).foregroundStyle(.secondary)
                            TextField("输入作者", text: $author)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("正文").font(.subheadline).foregroundStyle(.secondary)
                        MarkdownEditor(text: $bodyText, placeholder: "输入正文内容，支持 Markdown 格式", minHeight: 150)
                    }
                    
                    // Images
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("图片").font(.subheadline).foregroundStyle(.secondary)
                            Spacer()
                            Button {
                                let urls = FilePicker.pickImages()
                                newImageURLs.append(contentsOf: urls)
                            } label: {
                                Label("添加图片", systemImage: "photo.badge.plus")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                        
                        let images = mediaAssets.filter { ($0.type == .image || $0.type == .cover) && !removedAssetIDs.contains($0.id) }
                        if images.isEmpty && newImageURLs.isEmpty {
                            Text("暂无图片").font(.caption).foregroundStyle(.tertiary)
                                .frame(maxWidth: .infinity, minHeight: 40)
                        } else {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(Array(images.enumerated()), id: \.element.id) { index, asset in
                                        if let path = asset.localPath {
                                            let url = DataDirectory.media.appendingPathComponent(path)
                                            if let nsImage = NSImage(contentsOf: url) {
                                                Image(nsImage: nsImage)
                                                    .resizable()
                                                    .scaledToFill()
                                                    .frame(width: 100, height: 100)
                                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                                    .onTapGesture { openImageViewer(images: images, tappedIndex: index) }
                                                    .overlay(alignment: .topTrailing) {
                                                        Button {
                                                            removedAssetIDs.insert(asset.id)
                                                        } label: {
                                                            Image(systemName: "xmark.circle.fill")
                                                                .foregroundStyle(.white, .red)
                                                                .font(.caption)
                                                        }
                                                        .offset(x: 4, y: -4)
                                                    }
                                            }
                                        }
                                    }
                                    ForEach(Array(newImageURLs.enumerated()), id: \.offset) { index, url in
                                        if let nsImage = NSImage(contentsOf: url) {
                                            Image(nsImage: nsImage)
                                                .resizable()
                                                .scaledToFill()
                                                .frame(width: 100, height: 100)
                                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                                .overlay(alignment: .topTrailing) {
                                                    Button {
                                                        newImageURLs.remove(at: index)
                                                    } label: {
                                                        Image(systemName: "xmark.circle.fill")
                                                            .foregroundStyle(.white, .red)
                                                            .font(.caption)
                                                    }
                                                    .offset(x: 4, y: -4)
                                                }
                                        }
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                    
                    // Videos
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("视频").font(.subheadline).foregroundStyle(.secondary)
                            Spacer()
                            Button {
                                let urls = FilePicker.pickVideos()
                                newVideoURLs.append(contentsOf: urls)
                            } label: {
                                Label("添加视频", systemImage: "video.badge.plus")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                        
                        let videos = mediaAssets.filter { $0.type == .video && !removedAssetIDs.contains($0.id) }
                        if videos.isEmpty && newVideoURLs.isEmpty {
                            Text("暂无视频").font(.caption).foregroundStyle(.tertiary)
                                .frame(maxWidth: .infinity, minHeight: 40)
                        } else {
                            VStack(spacing: 6) {
                                ForEach(videos, id: \.id) { asset in
                                    HStack {
                                        Image(systemName: "film")
                                            .foregroundStyle(.secondary)
                                        Text(asset.fileName ?? "视频")
                                            .font(.subheadline)
                                        Spacer()
                                        Button {
                                            removedAssetIDs.insert(asset.id)
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundStyle(.red)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(8)
                                    .background(Color.secondary.opacity(0.05))
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                    .onTapGesture {
                                        if let path = asset.localPath {
                                            let url = DataDirectory.media.appendingPathComponent(path)
                                            ViewerWindowManager.shared.openVideoViewer(url: url)
                                        }
                                    }
                                }
                                ForEach(Array(newVideoURLs.enumerated()), id: \.offset) { index, url in
                                    HStack {
                                        Image(systemName: "film")
                                            .foregroundStyle(.secondary)
                                        Text(url.lastPathComponent)
                                            .font(.subheadline)
                                        Spacer()
                                        Button {
                                            newVideoURLs.remove(at: index)
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundStyle(.red)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(8)
                                    .background(Color.secondary.opacity(0.05))
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                }
                            }
                        }
                    }
                    
                    // Remark
                    VStack(alignment: .leading, spacing: 4) {
                        Text("备注").font(.subheadline).foregroundStyle(.secondary)
                        PlaceholderTextEditor(text: $remark, placeholder: "点击即可开始输入")
                            .frame(minHeight: 80)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.secondary.opacity(0.2))
                            )
                    }
                }
                .padding()
            }
        }
        .frame(width: 600, height: 500)
        .onAppear { loadMedia() }
        // 使用独立窗口查看器，与详情页一致
        .alert("放弃修改？", isPresented: $showDiscardConfirm) {
            Button("继续编辑", role: .cancel) {}
            Button("放弃修改", role: .destructive) {
                isPresented = false
            }
        } message: {
            Text("当前内容有未保存的修改，放弃后将丢失这些更改。")
        }
    }
    
    private func openImageViewer(images: [MediaAsset], tappedIndex: Int) {
        var loadedImages: [NSImage] = []
        for asset in images {
            if let path = asset.localPath {
                let url = DataDirectory.media.appendingPathComponent(path)
                if let nsImage = NSImage(contentsOf: url) {
                    loadedImages.append(nsImage)
                }
            }
        }
        
        for url in newImageURLs {
            if let nsImage = NSImage(contentsOf: url) {
                loadedImages.append(nsImage)
            }
        }
        
        guard !loadedImages.isEmpty else { return }
        ViewerWindowManager.shared.openImageViewer(images: loadedImages, startIndex: tappedIndex)
    }
    
    private func loadMedia() {
        mediaAssets = (try? appState.mediaRepo.findByItemID(item.id)) ?? []
    }
    
    private func save() {
        guard var updated = try? appState.itemRepo.find(id: item.id) else { return }
        updated.title = title.isEmpty ? nil : title
        updated.body = bodyText.isEmpty ? nil : bodyText
        updated.author = author.isEmpty ? nil : author
        updated.remark = remark.isEmpty ? nil : remark
        updated.modifyDate = Date()
        try? appState.itemRepo.update(updated)
        
        let itemDir = DataDirectory.media.appendingPathComponent(item.id.uuidString)
        try? FileManager.default.createDirectory(at: itemDir, withIntermediateDirectories: true)
        
        let existingImageCount = mediaAssets.filter { ($0.type == .image || $0.type == .cover) && !removedAssetIDs.contains($0.id) }.count
        for (index, url) in newImageURLs.enumerated() {
            let fileName = "image_\(String(format: "%03d", existingImageCount + index + 1)).jpg"
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
            } catch {
                print("图片保存失败: \(error)")
            }
        }
        
        let existingVideoCount = mediaAssets.filter { $0.type == .video && !removedAssetIDs.contains($0.id) }.count
        for (index, url) in newVideoURLs.enumerated() {
            let ext = url.pathExtension.isEmpty ? "mp4" : url.pathExtension
            let fileName = "video_\(existingVideoCount + index + 1).\(ext)"
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
            } catch {
                print("视频保存失败: \(error)")
            }
        }
        
        // 处理删除的媒体文件
        for assetID in removedAssetIDs {
            if let asset = mediaAssets.first(where: { $0.id == assetID }) {
                if let path = asset.localPath {
                    try? FileManager.default.removeItem(at: DataDirectory.media.appendingPathComponent(path))
                }
                try? appState.mediaRepo.deleteByID(assetID)
            }
        }
        
        if let firstImage = try? appState.mediaRepo.findByItemID(item.id).first(where: { $0.type == .image }) {
            var final = updated
            final.coverAssetID = firstImage.id
            try? appState.itemRepo.update(final)
        }
        
        try? appState.searchRepo.updateIndex(item: updated)
        
        appState.refreshData()
        isPresented = false
    }
    
    private func removeAsset(_ asset: MediaAsset) {
        if let path = asset.localPath {
            try? FileManager.default.removeItem(at: DataDirectory.media.appendingPathComponent(path))
        }
        try? appState.mediaRepo.deleteByID(asset.id)
        mediaAssets.removeAll { $0.id == asset.id }
    }
}
