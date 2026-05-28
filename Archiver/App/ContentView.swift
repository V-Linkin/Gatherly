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
        }
    }
}

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedNav: NavigationTarget? = .home
    @State private var previousNav: NavigationTarget? = .home
    @State private var zoomedImage: NSImage?

    
    var body: some View {
        @Bindable var state = appState
        
        NavigationSplitView {
            SidebarView(selectedNav: $selectedNav)
        } detail: {
            VStack(spacing: 0) {
                if case .item = selectedNav {
                    backButton
                }
                detailView
                    .id(selectedNav)
            }
        }
        .searchable(text: $state.searchQuery, prompt: "搜索标题和正文...")
        .onSubmit(of: .search) {
            if !appState.searchQuery.isEmpty {
                selectedNav = .search
                performSearch()
            }
        }
        .onChange(of: appState.searchQuery) { _, newValue in
            if newValue.isEmpty && selectedNav == .search {
                selectedNav = .home
            }
        }
        .onChange(of: selectedNav) { _, newValue in
            if newValue != .search { appState.searchQuery = "" }
        }
        .overlay {
            imageZoomOverlay
        }
        .onAppear { appState.refreshData() }
        .sheet(isPresented: $state.showNewItem) {
            NewItemView(isPresented: $state.showNewItem, selectedNav: $selectedNav)
        }
    }
    
    private var backButton: some View {
        Button {
            selectedNav = previousNav
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
    
    private var imageZoomOverlay: some View {
        Group {
            if let img = zoomedImage {
                Color.black.opacity(0.95)
                    .ignoresSafeArea()
                    .onTapGesture { zoomedImage = nil }
                    .overlay {
                        Image(nsImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .padding(60)
                            .onTapGesture { zoomedImage = nil }
                    }
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.2), value: zoomedImage != nil)
            }
        }
    }
    
    @ViewBuilder
    private var detailView: some View {
        switch selectedNav {
        case .home, .none:
            HomeView(selectedNav: $selectedNav, previousNav: $previousNav)
        case .platform(let platform):
            PlatformView(platform: platform, selectedNav: $selectedNav, previousNav: $previousNav)
        case .platformStatus(let platform, let status):
            PlatformStatusView(platform: platform, status: status)
        case .folder(let folderID):
            FolderView(folderID: folderID, selectedNav: $selectedNav, previousNav: $previousNav)
        case .item(let id):
            ItemDetailView(itemID: id, selectedNav: $selectedNav, zoomedImage: $zoomedImage)
        case .search:
            SearchResultsView()
        case .trash:
            TrashView()
        case .settings:
            SettingsView()
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
    @Environment(AppState.self) private var appState

    var body: some View {
        List(selection: $selectedNav) {
            Section {
                Label("首页", systemImage: "house.fill")
                    .tag(NavigationTarget.home)
            }
            
            Section("平台") {
                ForEach(Platform.allCases) { platform in
                    NavigationLink(value: NavigationTarget.platform(platform)) {
                        Label {
                            Text(platform.displayName)
                        } icon: {
                            Image(systemName: platform.iconName)
                                .foregroundStyle(platform.brandColor)
                        }
                    }
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
