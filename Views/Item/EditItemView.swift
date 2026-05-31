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
    
    // Image viewer
    @State private var editImages: [NSImage] = []
    @State private var editImageIndex: Int = 0
    @State private var showEditViewer: Bool = false
    
    init(item: Item, isPresented: Binding<Bool>) {
        self.item = item
        self._isPresented = isPresented
        _title = State(initialValue: item.title ?? "")
        _bodyText = State(initialValue: item.body ?? "")
        _author = State(initialValue: item.author ?? "")
        _remark = State(initialValue: item.remark ?? "")
        _remark = State(initialValue: item.remark ?? "")
        _remark = State(initialValue: item.remark ?? "")
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("编辑内容").font(.headline)
                Spacer()
                Button("取消") { isPresented = false }.keyboardShortcut(.cancelAction)
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
                        
                        let images = mediaAssets.filter { $0.type == .image || $0.type == .cover }
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
                                                ZStack(alignment: .topTrailing) {
                                                    Image(nsImage: nsImage)
                                                        .resizable()
                                                        .aspectRatio(contentMode: .fill)
                                                        .frame(width: 80, height: 80)
                                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                                    Button { removeAsset(asset) } label: {
                                                        Image(systemName: "xmark.circle.fill").font(.caption).foregroundStyle(.red)
                                                    }.buttonStyle(.plain)
                                                }
                                                .onTapGesture {
                                                    openEditViewer(from: index, isExisting: true)
                                                }
                                            }
                                        }
                                    }
                                    ForEach(Array(newImageURLs.enumerated()), id: \.offset) { index, url in
                                        if let nsImage = NSImage(contentsOf: url) {
                                            let existingCount = mediaAssets.filter { $0.type == .image || $0.type == .cover }.count
                                            ZStack(alignment: .topTrailing) {
                                                Image(nsImage: nsImage)
                                                    .resizable()
                                                    .aspectRatio(contentMode: .fill)
                                                    .frame(width: 80, height: 80)
                                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                                Button { newImageURLs.remove(at: index) } label: {
                                                    Image(systemName: "xmark.circle.fill").font(.caption).foregroundStyle(.red)
                                                }.buttonStyle(.plain)
                                            }
                                            .onTapGesture {
                                                openEditViewer(from: existingCount + index, isExisting: false)
                                            }
                                        }
                                    }
                                }
                            }
                            .frame(height: 96)
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
                        
                        let videos = mediaAssets.filter { $0.type == .video }
                        if videos.isEmpty && newVideoURLs.isEmpty {
                            Text("暂无视频").font(.caption).foregroundStyle(.tertiary)
                                .frame(maxWidth: .infinity, minHeight: 40)
                        } else {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(videos) { asset in
                                        if let path = asset.localPath {
                                            let url = DataDirectory.media.appendingPathComponent(path)
                                            ZStack(alignment: .topTrailing) {
                                                RoundedRectangle(cornerRadius: 6)
                                                    .fill(.quaternary)
                                                    .frame(width: 120, height: 80)
                                                    .overlay {
                                                        Image(systemName: "play.fill")
                                                            .foregroundStyle(.secondary)
                                                    }
                                                Button { removeAsset(asset) } label: {
                                                    Image(systemName: "xmark.circle.fill").font(.caption).foregroundStyle(.red)
                                                }.buttonStyle(.plain)
                                            }
                                        }
                                    }
                                    ForEach(Array(newVideoURLs.enumerated()), id: \.offset) { index, url in
                                        ZStack(alignment: .topTrailing) {
                                            RoundedRectangle(cornerRadius: 6)
                                                .fill(.quaternary)
                                                .frame(width: 120, height: 80)
                                                .overlay {
                                                    Image(systemName: "play.fill")
                                                        .foregroundStyle(.secondary)
                                                }
                                            Button { newVideoURLs.remove(at: index) } label: {
                                                Image(systemName: "xmark.circle.fill").font(.caption).foregroundStyle(.red)
                                            }.buttonStyle(.plain)
                                        }
                                    }
                                }
                            }
                            .frame(height: 96)
                        }
                    }
                    
                }
                .padding()
            }
        }
        .frame(width: 620, height: 680)
        .overlay {
            if showEditViewer && !editImages.isEmpty {
                ImageViewerView(
                    images: editImages,
                    currentIndex: $editImageIndex,
                    isPresented: $showEditViewer
                )
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.2), value: showEditViewer)
            }
        }
        .onAppear { loadMedia() }
    }
    
    private func openEditViewer(from tappedIndex: Int, isExisting: Bool) {
        var images: [NSImage] = []
        
        // Existing images from media assets
        let existingImages = mediaAssets.filter { $0.type == .image || $0.type == .cover }
        for asset in existingImages {
            if let path = asset.localPath {
                let url = DataDirectory.media.appendingPathComponent(path)
                if let nsImage = NSImage(contentsOf: url) {
                    images.append(nsImage)
                }
            }
        }
        
        // New images from file picker
        for url in newImageURLs {
            if let nsImage = NSImage(contentsOf: url) {
                images.append(nsImage)
            }
        }
        
        guard !images.isEmpty else { return }
        editImages = images
        editImageIndex = tappedIndex
        showEditViewer = true
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
        updated.remark = remark.isEmpty ? nil : remark
        updated.remark = remark.isEmpty ? nil : remark
        updated.modifyDate = Date()
        try? appState.itemRepo.update(updated)
        
        let itemDir = DataDirectory.media.appendingPathComponent(item.id.uuidString)
        try? FileManager.default.createDirectory(at: itemDir, withIntermediateDirectories: true)
        
        let existingImageCount = mediaAssets.filter { $0.type == .image || $0.type == .cover }.count
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
        
        let existingVideoCount = mediaAssets.filter { $0.type == .video }.count
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
