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
                
                if !appState.recentItems.isEmpty {
                    RecentItemsSection(items: appState.recentItems, selectedNav: $selectedNav, previousNav: $previousNav)
                    Divider()
                }
                
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
            }
        }
    }
}

// MARK: - 最近导入

struct RecentItemsSection: View {
    let items: [Item]
    @Binding var selectedNav: NavigationTarget?
    @Binding var previousNav: NavigationTarget?
    
    private let cardWidth: CGFloat = 200
    private let cardHeight: CGFloat = 240
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("最近导入")
                .font(.headline)
            
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(items) { item in
                        Button {
                            previousNav = .home
                            selectedNav = .item(item.id)
                        } label: {
                            ItemCardView(item: item)
                        }
                        .buttonStyle(.plain)
                        .frame(width: cardWidth)
                    }
                }
            }
            .frame(height: cardHeight)
        }
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
