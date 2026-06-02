import SwiftUI

enum NavigationTarget: Hashable, Identifiable {
    case home
    case platform(Platform)
    case platformStatus(Platform, ArchiveStatus)
    case folder(UUID)
    case item(UUID)
    case search
    case trash
    case settings
    case customPlatform(UUID)
    case uncategorized
    
    var id: String {
        switch self {
        case .home: return "home"
        case .platform(let p): return "platform_\(p.rawValue)"
        case .platformStatus(let p, let s): return "status_\(p.rawValue)_\(s.rawValue)"
        case .folder(let id): return "folder_\(id.uuidString)"
        case .item(let id): return "item_\(id.uuidString)"
        case .search: return "search"
        case .trash: return "trash"
        case .settings: return "settings"
        case .customPlatform(let id): return "custom_\(id.uuidString)"
        case .uncategorized: return "uncategorized"
        }
    }
}

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedNav: NavigationTarget? = .home
    @State private var previousNav: NavigationTarget? = .home
    
    // Image viewer state (lifted to cover entire window including sidebar)
    @State private var coverImages: [NSImage] = []
    @State private var coverImageIndex: Int = 0
    @State private var showCoverViewer: Bool = false
    
    var body: some View {
        @Bindable var state = appState
        
        NavigationSplitView {
            SidebarView(selectedNav: $selectedNav, previousNav: $previousNav)
        } detail: {
            VStack(spacing: 0) {
                if case .item = selectedNav {
                    backButton
                }
                if case .folder = selectedNav {
                    backButton
                }
                detailView
                    .id(selectedNav)
            }
        }
        .searchable(text: $state.searchQuery, prompt: "搜索标题和正文...")
        .onSubmit(of: .search) {
            if !appState.searchQuery.isEmpty {
                previousNav = selectedNav
                selectedNav = .search
                performSearch()
            }
        }
        .onChange(of: appState.searchQuery) { _, newValue in
            if newValue.isEmpty && selectedNav == .search {
                selectedNav = previousNav ?? .home
            }
        }
        .onChange(of: selectedNav) { oldValue, newValue in
            if oldValue == .search && newValue != .search {
                appState.searchQuery = ""
                appState.searchResults = []
            }
            if let old = oldValue, old != newValue {
                if oldValue != .search {
                    previousNav = oldValue
                }
            }
        }
        .overlay {
            // Image viewer overlays at top level to cover sidebar
            if showCoverViewer && !coverImages.isEmpty {
                ImageViewerView(
                    images: coverImages,
                    currentIndex: $coverImageIndex,
                    isPresented: $showCoverViewer
                )
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.2), value: showCoverViewer)
            }

        }
        .overlay(alignment: .top) {
            if appState.showToast, let message = appState.toastMessage {
                ToastView(message: message)
                    .padding(.top, 20)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .animation(.easeInOut(duration: 0.3), value: appState.showToast)
            }
        }
        .onAppear { appState.refreshData() }
        .sheet(isPresented: $state.showNewItem) {
            NewItemView(isPresented: $state.showNewItem, selectedNav: $selectedNav)
        }
        .sheet(isPresented: $state.showNewCustomPlatform) {
            NewCustomPlatformSheet(isPresented: $state.showNewCustomPlatform)
        }
        .sheet(item: $state.editingCustomPlatform) { cp in
            EditCustomPlatformSheet(platform: cp)
        }
        .sheet(item: $state.changeLogoCustomPlatform) { cp in
            ChangeLogoSheet(platform: cp)
        }
        .alert("删除平台", isPresented: .init(
            get: { state.deletingCustomPlatform != nil },
            set: { if !$0 { state.deletingCustomPlatform = nil } }
        )) {
            Button("取消", role: .cancel) { state.deletingCustomPlatform = nil }
            Button("删除", role: .destructive) {
                if let cp = state.deletingCustomPlatform {
                    try? state.customPlatformRepo.delete(id: cp.id)
                    let items = (try? state.itemRepo.fetchAll()) ?? []
                    for var item in items where item.customPlatformID == cp.id {
                        item.customPlatformID = nil
                        item.platform = .custom
                        try? state.itemRepo.update(item)
                    }
                    let folders = (try? state.folderRepo.fetchAll(platform: .custom)) ?? []
                    for var folder in folders where folder.customPlatformID == cp.id {
                        folder.customPlatformID = nil
                        try? state.folderRepo.update(folder)
                    }
                    state.refreshData()
                    state.deletingCustomPlatform = nil
                }
            }
        } message: {
            Text("确定删除平台「\(state.deletingCustomPlatform?.name ?? "")」？平台下的内容不会被删除，但会失去平台分类。")
        }
    }
    
    private var backButton: some View {
        Button {
            let target = previousNav ?? .home
            previousNav = nil
            selectedNav = target
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "chevron.left")
                Text("返回")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    @ViewBuilder
    private var detailView: some View {
        switch selectedNav {
        case .home:
            HomeView(selectedNav: $selectedNav, previousNav: $previousNav)
        case .platform(let p):
            PlatformView(platform: p, selectedNav: $selectedNav, previousNav: $previousNav)
        case .platformStatus(let p, let s):
            PlatformStatusView(platform: p, status: s)
        case .folder(let id):
            FolderView(folderID: id, selectedNav: $selectedNav, previousNav: $previousNav)
        case .item(let id):
            ItemDetailView(
                itemID: id,
                selectedNav: $selectedNav,
                previousNav: $previousNav,
                coverImages: $coverImages,
                coverImageIndex: $coverImageIndex,
                showCoverViewer: $showCoverViewer,

            )
        case .search:
            SearchResultsView(selectedNav: $selectedNav, previousNav: $previousNav)
        case .trash:
            TrashView()
        case .settings:
            SettingsView()
        case .customPlatform(let id):
            CustomPlatformContentView(customPlatformID: id, selectedNav: $selectedNav, previousNav: $previousNav)
        case .uncategorized:
            UncategorizedContentView(selectedNav: $selectedNav, previousNav: $previousNav)
        case .none:
            HomeView(selectedNav: $selectedNav, previousNav: $previousNav)
        }
    }
    
    private func performSearch() {
        let repo = appState.searchRepo
        let query = appState.searchQuery
        DispatchQueue.global(qos: .userInitiated).async {
            let results = (try? repo.search(query: query)) ?? []
            DispatchQueue.main.async { appState.searchResults = results }
        }
    }
}

// MARK: - Sidebar

struct SidebarView: View {
    @Binding var selectedNav: NavigationTarget?
    @Binding var previousNav: NavigationTarget?
    @Environment(AppState.self) private var appState
    
    var body: some View {
        List(selection: $selectedNav) {
            Section {
                Label("首页", systemImage: "house.fill")
                    .tag(NavigationTarget.home)
            }
            
            Section("平台") {
                ForEach(appState.customPlatforms) { cp in
                    NavigationLink(value: NavigationTarget.customPlatform(cp.id)) {
                        Label {
                            Text(cp.name)
                        } icon: {
                            if let logoPath = cp.logoPath {
                                let url = DataDirectory.platformLogos.appendingPathComponent(logoPath)
                                if let nsImage = NSImage(contentsOf: url) {
                                    Image(nsImage: nsImage)
                                        .resizable()
                                        .frame(width: 16, height: 16)
                                        .clipShape(RoundedRectangle(cornerRadius: 3))
                                } else {
                                    Image(systemName: "star.fill").foregroundStyle(.purple)
                                }
                            } else {
                                Image(systemName: "star.fill").foregroundStyle(.purple)
                            }
                        }
                    }
                    .contextMenu {
                        Button("重命名") { appState.editingCustomPlatform = cp }
                        Button("更换 Logo") { appState.changeLogoCustomPlatform = cp }
                        Divider()
                        if let idx = appState.customPlatforms.firstIndex(where: { $0.id == cp.id }) {
                            if idx > 0 {
                                Button("上移") { appState.movePlatform(cp, direction: .up) }
                            }
                            if idx < appState.customPlatforms.count - 1 {
                                Button("下移") { appState.movePlatform(cp, direction: .down) }
                            }
                            Button("置顶") { appState.movePlatform(cp, direction: .top) }
                                .disabled(idx == 0)
                        }
                        Divider()
                        Button("删除平台", role: .destructive) { appState.deletingCustomPlatform = cp }
                    }
                }
                NavigationLink(value: NavigationTarget.uncategorized) {
                    Label {
                        Text("未分类内容")
                    } icon: {
                        Image(systemName: "tray")
                            .foregroundStyle(.gray)
                    }
                }
                Button {
                    appState.showNewCustomPlatform = true
                } label: {
                    Label("新增平台", systemImage: "plus.circle")
                        .font(.subheadline)
                }
            }
            
            Divider()
            
            Section {
                Label("回收站", systemImage: "trash.fill")
                    .tag(NavigationTarget.trash)
                Label("设置", systemImage: "gearshape.fill")
                    .tag(NavigationTarget.settings)
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 250)
    }
}
