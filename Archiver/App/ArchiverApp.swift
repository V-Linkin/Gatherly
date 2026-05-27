import SwiftUI

@main
struct ArchiverApp: App {
    @State private var appState = AppState()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1200, height: 800)
    }
}

/// 全局应用状态
@MainActor
@Observable
final class AppState {
    let itemRepo = ItemRepository()
    let folderRepo = FolderRepository()
    let mediaRepo = MediaRepository()
    let trashRepo = TrashRepository()
    let searchRepo = SearchRepository()
    let importService = ImportService.shared
    
    /// 最近导入的内容
    var recentItems: [Item] = []
    
    /// 各平台内容数量
    var platformCounts: [Platform: Int] = [:]
    
    /// 最近使用的文件夹
    var recentFolders: [Folder] = []
    
    /// 搜索关键词
    var searchQuery = ""
    
    /// 搜索结果
    var searchResults: [SearchResult] = []
    
    /// Toast 消息
    var toastMessage: String?
    var showToast = false
    
    func refreshData() {
        recentItems = (try? itemRepo.fetchRecent(limit: 10)) ?? []
        recentFolders = (try? folderRepo.fetchRecent(limit: 5)) ?? []
        
        for platform in Platform.allCases {
            platformCounts[platform] = (try? itemRepo.count(platform: platform)) ?? 0
        }
    }
    
    func showToast(_ message: String) {
        toastMessage = message
        showToast = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.showToast = false
        }
    }
}
