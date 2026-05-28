import SwiftUI

/// 首页
struct HomeView: View {
    @Binding var selectedNav: NavigationTarget?
    @Binding var previousNav: NavigationTarget?
    @Environment(AppState.self) private var appState
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // 粘贴并保存输入区
                PasteInputView()
                
                // 新建内容按钮
                HStack {
                    Button {
                        appState.showNewItem = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "plus.circle.fill")
                            Text("新建内容")
                        }
                        .font(.subheadline)
                        .fontWeight(.medium)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    Spacer()
                }
                
                Divider()
                
                // 最近导入
                if !appState.recentItems.isEmpty {
                    RecentItemsSection(items: appState.recentItems, selectedNav: $selectedNav, previousNav: $previousNav)
                    
                    Divider()
                }
                
                // 平台快捷入口
                PlatformGridSection()
                
                Divider()
                
                // 最近文件夹
                if !appState.recentFolders.isEmpty {
                    RecentFoldersSection(folders: appState.recentFolders)
                }
            }
            .padding(24)
        }
        .navigationTitle("Archiver")
        .onAppear {
            appState.refreshData()
        }
    }
}

// MARK: - 粘贴输入区

struct PasteInputView: View {
    @Environment(AppState.self) private var appState
    @State private var inputURL = ""
    @State private var recognizedPlatform: Platform?
    @State private var isImporting = false
    @FocusState private var isInputFocused: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("粘贴并保存")
                .font(.headline)
            
            HStack(spacing: 12) {
                TextField("粘贴链接到这里...", text: $inputURL)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 16))
                    .focused($isInputFocused)
                    .onChange(of: inputURL) { _, newValue in
                        recognizedPlatform = URLNormalizer.recognizePlatform(newValue)
                    }
                    .onSubmit {
                        if !inputURL.isEmpty {
                            importURL()
                        }
                    }
                
                Button(action: importURL) {
                    if isImporting {
                        ProgressView()
                            .scaleEffect(0.8)
                            .frame(width: 60)
                    } else {
                        Text("保存")
                            .frame(width: 60)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(inputURL.isEmpty || isImporting)
                .keyboardShortcut(.return, modifiers: [])
            }
            
            // 识别到的平台
            if let platform = recognizedPlatform {
                HStack(spacing: 6) {
                    Image(systemName: platform.iconName)
                        .foregroundStyle(platform.brandColor)
                    Text("识别到: \(platform.displayName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.15), value: recognizedPlatform)
    }
    
    private func importURL() {
        guard !inputURL.isEmpty, !isImporting else { return }
        isImporting = true
        let url = inputURL
        inputURL = ""
        recognizedPlatform = nil
        
        Task {
            let result = await appState.importService.importURL(url)
            
            await MainActor.run {
                isImporting = false
                
                switch result {
                case .success(let item):
                    appState.showToast("已归档到 \(item.platform.displayName) > \(item.archiveStatus.displayName)")
                    appState.refreshData()
                case .duplicate(let existing):
                    appState.showToast("该内容已存在于 \(existing.platform.displayName) > \(existing.archiveStatus.displayName)")
                case .failure(let error):
                    if let parserError = error as? ParserError {
                        appState.showToast(parserError.errorDescription ?? "导入失败")
                    } else {
                        appState.showToast("导入失败: \(error.localizedDescription)")
                    }
                    appState.refreshData() // 失败记录也需要刷新
                }
            }
        }
    }
}

// MARK: - 最近导入区

struct RecentItemsSection: View {
    let items: [Item]
    @Binding var selectedNav: NavigationTarget?
    @Binding var previousNav: NavigationTarget?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("最近导入")
                .font(.headline)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(items) { item in
                        Button { previousNav = .home
                        selectedNav = .item(item.id) } label: {
                            ItemCardView(item: item)
                            .frame(width: 180)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

// MARK: - 平台快捷入口

struct PlatformGridSection: View {
    @Environment(AppState.self) private var appState
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("平台入口")
                .font(.headline)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                ForEach(Platform.allCases) { platform in
                    NavigationLink(value: NavigationTarget.platform(platform)) {
                        PlatformCard(platform: platform, count: appState.platformCounts[platform] ?? 0)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

struct PlatformCard: View {
    let platform: Platform
    let count: Int
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: platform.iconName)
                .font(.title2)
                .foregroundStyle(platform.brandColor)
                .frame(width: 36)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(platform.displayName)
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
