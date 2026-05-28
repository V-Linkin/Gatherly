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
    
    init(item: Item, isPresented: Binding<Bool>) {
        self.item = item
        self._isPresented = isPresented
        _title = State(initialValue: item.title ?? "")
        _bodyText = State(initialValue: item.body ?? "")
        _author = State(initialValue: item.author ?? "")
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
                    // Title & Author
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
                    
                    // Body
                    VStack(alignment: .leading, spacing: 4) {
                        Text("正文").font(.subheadline).foregroundStyle(.secondary)
                        TextEditor(text: $bodyText)
                            .font(.body)
                            .scrollContentBackground(.visible)
                            .frame(minHeight: 120, idealHeight: 180, maxHeight: 300)
                            .padding(4)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
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
                                    ForEach(images) { asset in
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
                                            }
                                        }
                                    }
                                    ForEach(Array(newImageURLs.enumerated()), id: \.offset) { index, url in
                                        if let nsImage = NSImage(contentsOf: url) {
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
                                        }
                                    }
                                }
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
                        
                        let videos = mediaAssets.filter { $0.type == .video }
                        if videos.isEmpty && newVideoURLs.isEmpty {
                            Text("暂无视频").font(.caption).foregroundStyle(.tertiary)
                                .frame(maxWidth: .infinity, minHeight: 40)
                        } else {
                            VStack(spacing: 4) {
                                ForEach(videos) { asset in
                                    HStack(spacing: 8) {
                                        Image(systemName: "video")
                                            .foregroundStyle(.blue)
                                        Text(asset.fileName)
                                            .font(.caption)
                                            .lineLimit(1)
                                        Spacer()
                                        Button { removeAsset(asset) } label: {
                                            Image(systemName: "xmark.circle.fill").font(.caption).foregroundStyle(.red)
                                        }.buttonStyle(.plain)
                                    }
                                    .padding(.horizontal, 8).padding(.vertical, 4)
                                    .background(.quaternary).clipShape(RoundedRectangle(cornerRadius: 6))
                                }
                                ForEach(Array(newVideoURLs.enumerated()), id: \.offset) { index, url in
                                    HStack(spacing: 8) {
                                        Image(systemName: "video")
                                            .foregroundStyle(.green)
                                        Text(url.lastPathComponent)
                                            .font(.caption)
                                            .lineLimit(1)
                                        Spacer()
                                        Button { newVideoURLs.remove(at: index) } label: {
                                            Image(systemName: "xmark.circle.fill").font(.caption).foregroundStyle(.red)
                                        }.buttonStyle(.plain)
                                    }
                                    .padding(.horizontal, 8).padding(.vertical, 4)
                                    .background(.quaternary).clipShape(RoundedRectangle(cornerRadius: 6))
                                }
                            }
                        }
                    }
                    
                    // Remark
                    VStack(alignment: .leading, spacing: 4) {
                        Text("备注").font(.subheadline).foregroundStyle(.secondary)
                        TextEditor(text: $remark)
                            .font(.body)
                            .scrollContentBackground(.visible)
                            .frame(minHeight: 60, idealHeight: 80)
                            .padding(4)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
                    }
                }
                .padding()
            }
        }
        .frame(width: 620, height: 680)
        .onAppear { loadMedia() }
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
        
        // Save new images
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
        
        // Save new videos
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
        
        // Update cover
        if let firstImage = try? appState.mediaRepo.findByItemID(item.id).first(where: { $0.type == .image }) {
            var final = updated
            final.coverAssetID = firstImage.id
            try? appState.itemRepo.update(final)
        }
        
        // Update FTS index
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
