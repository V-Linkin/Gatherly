import SwiftUI

/// 首页
struct HomeView: View {
    @Binding var selectedNav: NavigationTarget?
    @Binding var previousNav: NavigationTarget?
    @Environment(AppState.self) private var appState
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PasteInputView()
                
                HStack {
                    Button {
                        appState.showNewItem = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "plus.circle.fill")
                            Text("自定义导入内容")
                        }
                        .font(.subheadline)
                        .fontWeight(.medium)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    Spacer()
                }
                
                Divider()
                
                RecentItemsSection(items: appState.recentItems, selectedNav: $selectedNav, previousNav: $previousNav)
                Divider()
                
                PlatformGridSection(selectedNav: $selectedNav, previousNav: $previousNav)
                

            }
            .padding(24)
        }
        .navigationTitle("拾屿 · 跨平台的私人内容岛")
        .onAppear {
            appState.refreshData()
        }
    }
}

// MARK: - 粘贴输入区

struct PasteInputView: View {
    @Environment(AppState.self) private var appState
    @State private var inputText = ""
    @State private var recognizedPlatform: Platform?
    @State private var detectedURL: String?
    @State private var isImporting = false
    @FocusState private var isInputFocused: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("一键归档")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                ZStack(alignment: .topLeading) {
                    NoScrollTextEditor(text: $inputText)
                        .frame(minHeight: 80, maxHeight: 160)
                        .focused($isInputFocused)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                        )
                        .onChange(of: inputText) { _, newValue in
                            autoDetectAndImport(newValue)
                        }
                    
                    if inputText.isEmpty {
                        Text("粘贴到此处以完成导入")
                            .font(.system(size: 14))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .allowsHitTesting(false)
                    }
                }
                
                if isImporting {
                    HStack(spacing: 6) {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("正在导入...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if let url = detectedURL, let platform = recognizedPlatform {
                    HStack(spacing: 6) {
                        Image(systemName: platform.iconName)
                            .foregroundStyle(platform.brandColor)
                        Text("识别到 \(platform.displayName): \(url)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .animation(.easeInOut(duration: 0.15), value: recognizedPlatform)
    }
    
    private func autoDetectAndImport(_ text: String) {
        guard !isImporting else { return }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            recognizedPlatform = nil
            detectedURL = nil
            return
        }
        
        // 从文本中提取 URL
        if let url = URLNormalizer.extractFirstURL(from: text) {
            let platform = URLNormalizer.recognizePlatform(url)
            // 避免重复触发：URL 和平台都没变时跳过
            if url == detectedURL && platform == recognizedPlatform { return }
            
            detectedURL = url
            recognizedPlatform = platform
            
            // 粘贴后自动开始导入
            if platform != nil {
                autoImport(url: url)
            }
        } else {
            recognizedPlatform = nil
            detectedURL = nil
        }
    }
    
    private func autoImport(url: String) {
        guard !isImporting else { return }
        isImporting = true
        
        Task {
            let result = await appState.importService.importURL(url)
            
            await MainActor.run {
                isImporting = false
                
                switch result {
                case .success(let item):
                    let platformName = appState.customPlatforms.first(where: { $0.id == item.customPlatformID })?.name ?? item.platform.displayName
                    appState.showToast("已归档到 \(platformName)")
                    appState.refreshData()
                case .duplicate(_):
                    appState.showToast("该内容已存在")
                case .failure(let error):
                    appState.refreshData()
                    if let parserError = error as? ParserError {
                        appState.showToast(parserError.localizedDescription)
                    } else {
                        appState.showToast("导入失败: \(error.localizedDescription)")
                    }
                }
                
                // 导入完成后清空输入框
                inputText = ""
                detectedURL = nil
                recognizedPlatform = nil
            }
        }
    }
}

// MARK: - 最近导入

struct RecentItemsSection: View {
    let items: [Item]
    @Binding var selectedNav: NavigationTarget?
    @Binding var previousNav: NavigationTarget?
    @Environment(AppState.self) private var appState
    
    private let cardWidth: CGFloat = 200
    private let cardHeight: CGFloat = 240
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("最近导入")
                .font(.headline)
            
            if items.isEmpty {
                Text("最近7日暂无内容导入")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, minHeight: 60)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        ForEach(items) { item in
                            Button {
                                previousNav = .home
                                if NavDebounce.shared.canNavigate() { selectedNav = .item(item.id) }
                            } label: {
                                ItemCardView(item: item)
                            }
                            .buttonStyle(.plain)
                            .frame(width: cardWidth)
                            .contextMenu {
                                Button {
                                    appState.hideItem(item)
                                } label: {
                                    Label("不显示该内容", systemImage: "eye.slash")
                                }
                                Divider()
                                Button("删除", role: .destructive) {
                                    deleteRecentItem(item)
                                }
                            }
                        }
                    }
                }
                .frame(height: cardHeight)
            }
        }
    }
    
    private func deleteRecentItem(_ item: Item) {
        var updated = item
        updated.deletedAt = Date()
        updated.contentStatus = .trashed
        try? appState.itemRepo.update(updated)
        let record = TrashRecord(itemID: item.id, originalFolderID: item.folderID, originalArchiveStatus: item.archiveStatus)
        try? appState.trashRepo.insert(record)
        appState.refreshData()
    }
}

// MARK: - 平台快捷入口

struct PlatformGridSection: View {
    @Environment(AppState.self) private var appState
    @Binding var selectedNav: NavigationTarget?
    @Binding var previousNav: NavigationTarget?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("平台入口")
                .font(.headline)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                ForEach(appState.customPlatforms) { cp in
                    Button {
                        previousNav = selectedNav
                        selectedNav = .customPlatform(cp.id)
                    } label: {
                        CustomPlatformCard(platform: cp, count: appState.customPlatformCounts[cp.id] ?? 0)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

struct CustomPlatformCard: View {
    let platform: CustomPlatform
    let count: Int
    
    var body: some View {
        HStack(spacing: 12) {
            if let logoPath = platform.logoPath {
                let url = DataDirectory.platformLogos.appendingPathComponent(logoPath)
                if let nsImage = NSImage(contentsOf: url) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .frame(width: 36, height: 36)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    Image(systemName: "star.fill")
                        .font(.title2)
                        .foregroundStyle(.purple)
                        .frame(width: 36)
                }
            } else {
                Image(systemName: "star.fill")
                    .font(.title2)
                    .foregroundStyle(.purple)
                    .frame(width: 36)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(platform.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text("\(count) 条内容")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(.quaternary, lineWidth: 1)
        )
    }
}

// MARK: - 最近文件夹

struct RecentFoldersSection: View {
    let folders: [Folder]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("最近文件夹")
                .font(.headline)
            
            HStack(spacing: 12) {
                ForEach(folders) { folder in
                    NavigationLink(value: NavigationTarget.folder(folder.id)) {
                        HStack {
                            Image(systemName: "folder.fill")
                                .foregroundStyle(.blue)
                            Text(folder.name)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.background)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule().stroke(.quaternary, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}


// MARK: - 无滚动条的 TextEditor (NSViewRepresentable)

struct NoScrollTextEditor: NSViewRepresentable {
    @Binding var text: String
    var font: NSFont = .systemFont(ofSize: 14)
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let textView = scrollView.documentView as! NSTextView
        
        textView.font = font
        textView.isRichText = false
        textView.allowsUndo = true
        textView.delegate = context.coordinator
        textView.textContainerInset = NSSize(width: 5, height: 8)
        
        // 隐藏滚动条
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        
        // 背景透明
        scrollView.drawsBackground = false
        textView.backgroundColor = .clear
        
        textView.string = text
        
        return scrollView
    }
    
    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let textView = scrollView.documentView as! NSTextView
        if textView.string != text {
            textView.string = text
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NoScrollTextEditor
        init(_ parent: NoScrollTextEditor) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
        }
    }
}
