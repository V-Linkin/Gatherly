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
        .defaultSize(width: 1200, height: 800)
    }
}

@MainActor
@Observable
final class AppState {
    let itemRepo = ItemRepository()
    let folderRepo = FolderRepository()
    let mediaRepo = MediaRepository()
    let trashRepo = TrashRepository()
    let searchRepo = SearchRepository()
    let importService = ImportService.shared
    let customPlatformRepo = CustomPlatformRepository()
    
    var recentItems: [Item] = []
    var customPlatformCounts: [UUID: Int] = [:]
    var recentFolders: [Folder] = []
    
    var searchQuery = ""
    var searchResults: [SearchResult] = []
    
    var showNewItem = false
    var newItemPlatform: Platform = .custom
    var newItemCustomPlatformID: UUID? = nil
    
    var editingCustomPlatform: CustomPlatform? = nil
    var changeLogoCustomPlatform: CustomPlatform? = nil
    var deletingCustomPlatform: CustomPlatform? = nil
    
    var showNewCustomPlatform = false
    
    var customPlatforms: [CustomPlatform] = []
    
    var toastMessage: String?
    var showToast = false
    
    func refreshData() {
        customPlatforms = (try? customPlatformRepo.fetchAll()) ?? []
        recentItems = (try? itemRepo.fetchRecent(limit: 10)) ?? []
        recentFolders = (try? folderRepo.fetchRecent(limit: 5)) ?? []
        try? searchRepo.rebuildIndex()
        
        let allItems = (try? itemRepo.fetchAll()) ?? []
        for cp in customPlatforms {
            customPlatformCounts[cp.id] = allItems.filter { $0.customPlatformID == cp.id }.count
        }
    }
    
    enum MoveDirection {
        case up, down, top
    }

    func movePlatform(_ platform: CustomPlatform, direction: MoveDirection) {
        guard let idx = customPlatforms.firstIndex(where: { $0.id == platform.id }) else { return }
        var platforms = customPlatforms
        
        switch direction {
        case .up:
            guard idx > 0 else { return }
            platforms.swapAt(idx, idx - 1)
        case .down:
            guard idx < platforms.count - 1 else { return }
            platforms.swapAt(idx, idx + 1)
        case .top:
            guard idx > 0 else { return }
            let item = platforms.remove(at: idx)
            platforms.insert(item, at: 0)
        }
        
        // 更新 sort_order
        for (i, var p) in platforms.enumerated() {
            p.sortOrder = i
            try? customPlatformRepo.update(p)
        }
        
        customPlatforms = platforms
    }

    func showToast(_ message: String) {
        toastMessage = message
        showToast = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.showToast = false
        }
    }
}
