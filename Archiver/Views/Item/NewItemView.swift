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

    @State private var selectedPlatform: Platform = .xiaohongshu
    @State private var selectedFolderID: UUID? = nil

    @State private var imageURLs: [URL] = []
    @State private var videoURLs: [URL] = []

    @State private var availableFolders: [Folder] = []
    @State private var isSaving = false

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
        .onAppear { loadFolders() }
        .onChange(of: selectedPlatform) { _, _ in loadFolders() }
    }

    // MARK: - Header

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

    // MARK: - Platform

    private var platformSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("平台分类").font(.headline)
            Picker("平台", selection: $selectedPlatform) {
                ForEach(Platform.allCases) { p in
                    HStack {
                        Image(systemName: p.iconName).foregroundStyle(p.brandColor)
                        Text(p.displayName)
                    }
                    .tag(p)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    // MARK: - Folder

    private var folderSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("文件夹（可选）").font(.headline)
            if availableFolders.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle").foregroundStyle(.tertiary)
                    Text("该平台下暂无文件夹，可在平台页面新建")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            } else {
                Picker("文件夹", selection: $selectedFolderID) {
                    Text("无").tag(nil as UUID?)
                    ForEach(availableFolders) { folder in
                        Text(folder.name).tag(folder.id as UUID?)
                    }
                }
            }
        }
    }

    // MARK: - Metadata

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("内容信息").font(.headline)

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("标题 *").font(.subheadline).foregroundStyle(.secondary)
                    TextField("输入标题", text: $title)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("作者").font(.subheadline).foregroundStyle(.secondary)
                    TextField("输入作者名", text: $author)
                        .textFieldStyle(.roundedBorder)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("正文").font(.subheadline).foregroundStyle(.secondary)
                TextEditor(text: $bodyText)
                    .frame(height: 140)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(.quaternary)
                    )
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("原始链接（可选）").font(.subheadline).foregroundStyle(.secondary)
                TextField("https://...", text: $originalURL)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    // MARK: - Media

    private var mediaSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("媒体文件").font(.headline)

            HStack(spacing: 12) {
                Button {
                    let urls = FilePicker.pickImages()
                    imageURLs.append(contentsOf: urls)
                } label: {
                    Label("添加图片", systemImage: "photo.on.rectangle")
                }
                .buttonStyle(.bordered)

                Button {
                    let urls = FilePicker.pickVideos()
                    videoURLs.append(contentsOf: urls)
                } label: {
                    Label("添加视频", systemImage: "video.badge.plus")
                }
                .buttonStyle(.bordered)
            }

            if !imageURLs.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("已选图片（\(imageURLs.count)张）")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Array(imageURLs.enumerated()), id: \.offset) { index, url in
                                imageThumbnail(url: url, index: index)
                            }
                        }
                    }
                }
            }

            if !videoURLs.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("已选视频（\(videoURLs.count)个）")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(Array(videoURLs.enumerated()), id: \.offset) { index, url in
                        HStack(spacing: 8) {
                            Image(systemName: "film").foregroundStyle(.secondary)
                            Text(url.lastPathComponent)
                                .font(.caption)
                                .lineLimit(1)
                            Spacer()
                            Button {
                                videoURLs.remove(at: index)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.tertiary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.quaternary.opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
            }

            if imageURLs.isEmpty && videoURLs.isEmpty {
                HStack {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.title2)
                        .foregroundStyle(.tertiary)
                    Text("点击上方按钮添加图片或视频")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .background(.quaternary.opacity(0.3))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private func imageThumbnail(url: URL, index: Int) -> some View {
        Group {
            if let nsImage = NSImage(contentsOf: url) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle()
                    .fill(.quaternary)
                    .overlay {
                        Image(systemName: "photo").foregroundStyle(.tertiary)
                    }
            }
        }
        .frame(width: 80, height: 80)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(alignment: .topTrailing) {
            Button {
                imageURLs.remove(at: index)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.white, .black.opacity(0.6))
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .offset(x: 4, y: -4)
        }
    }

    // MARK: - Remark

    private var remarkSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("备注（可选）").font(.headline)
            TextEditor(text: $remark)
                .frame(height: 60)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(.quaternary)
                )
        }
    }

    // MARK: - Actions

    private func loadFolders() {
        availableFolders = (try? appState.folderRepo.fetchAll(platform: selectedPlatform)) ?? []
    }

    private func save() {
        guard !title.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isSaving = true

        let now = Date()
        let normalizedURL = originalURL.isEmpty
            ? "custom://\(UUID().uuidString)"
            : URLNormalizer.normalize(originalURL, platform: selectedPlatform)
        let contentID = originalURL.isEmpty
            ? nil
            : URLNormalizer.extractContentID(originalURL, platform: selectedPlatform)

        var item = Item(
            title: title.isEmpty ? nil : title,
            body: bodyText.isEmpty ? nil : bodyText,
            originalURL: originalURL.isEmpty ? "custom://\(UUID().uuidString)" : originalURL,
            platform: selectedPlatform,
            platformContentID: contentID,
            normalizedURL: normalizedURL,
            author: author.isEmpty ? nil : author,
            publishDate: now,
            archiveStatus: .pending,
            mediaStatus: .textOnly
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

        let mediaDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Archiver/media", isDirectory: true)
        let itemDir = mediaDir.appendingPathComponent(item.id.uuidString)

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

        // Update media status
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
        appState.showToast("内容已保存到 \(selectedPlatform.displayName)")
    }
}
