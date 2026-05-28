import SwiftUI

struct TrashView: View {
    @Environment(AppState.self) private var appState
    @State private var trashedItems: [Item] = []
    @State private var showClearAllConfirm = false
    
    var body: some View {
        Group {
            if trashedItems.isEmpty {
                ContentUnavailableView("回收站是空的", systemImage: "trash")
            } else {
                List {
                    Section {
                        HStack(spacing: 8) {
                            Image(systemName: "clock.badge.exclamationmark")
                                .foregroundStyle(.orange)
                            Text("回收站中的内容将在30天后自动清除")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .listRowBackground(Color.orange.opacity(0.08))
                    }
                    
                    ForEach(trashedItems) { item in
                        TrashItemRow(item: item, onRestore: { restoreItem(item) },
                                     onPermanentDelete: { permanentDeleteItem(item) })
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("回收站")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("清空回收站", role: .destructive) {
                    showClearAllConfirm = true
                }
                .disabled(trashedItems.isEmpty)
            }
        }
        .alert("清空回收站", isPresented: $showClearAllConfirm) {
            Button("取消", role: .cancel) {}
            Button("彻底删除全部", role: .destructive) {
                clearAll()
            }
        } message: {
            Text("此操作不可恢复，所有内容将被永久删除。")
        }
        .onAppear { loadData() }
    }
    
    private func loadData() {
        trashedItems = (try? appState.itemRepo.fetchTrashed()) ?? []
    }
    
    private func restoreItem(_ item: Item) {
        guard let record = try? appState.trashRepo.findByItemID(item.id) else { return }
        
        var updated = item
        updated.deletedAt = nil
        updated.contentStatus = .normal
        updated.archiveStatus = record.originalArchiveStatus
        updated.folderID = record.originalFolderID
        try? appState.itemRepo.update(updated)
        try? appState.trashRepo.deleteByItemID(item.id)
        
        loadData()
        appState.refreshData()
    }
    
    private func permanentDeleteItem(_ item: Item) {
        let mediaDir = DataDirectory.media
        // 删除媒体文件
        if let record = try? appState.trashRepo.findByItemID(item.id) {
            for path in record.mediaPaths {
                try? FileManager.default.removeItem(at: mediaDir.appendingPathComponent(path))
            }
        }
        // 删除整个 item 目录
        let itemDir = mediaDir.appendingPathComponent(item.id.uuidString)
        try? FileManager.default.removeItem(at: itemDir)
        
        try? appState.itemRepo.permanentDelete(id: item.id)
        try? appState.trashRepo.deleteByItemID(item.id)
        
        loadData()
        appState.refreshData()
    }
    
    private func clearAll() {
        for item in trashedItems {
            permanentDeleteItem(item)
        }
    }
}

struct TrashItemRow: View {
    let item: Item
    let onRestore: () -> Void
    let onPermanentDelete: () -> Void
    
    @State private var showDeleteConfirm = false
    @State private var showRestoreConfirm = false
    
    private let autoDeleteDays = 30
    
    private var daysRemaining: Int {
        guard let deletedAt = item.deletedAt else { return autoDeleteDays }
        let elapsed = Calendar.current.dateComponents([.day], from: deletedAt, to: Date()).day ?? 0
        return max(0, autoDeleteDays - elapsed)
    }
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.platform.iconName)
                .font(.title3)
                .foregroundStyle(item.platform.brandColor)
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(item.displayTitle)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .strikethrough()
                    .foregroundStyle(.secondary)
                
                HStack(spacing: 8) {
                    Text(item.platform.displayName)
                        .font(.caption2)
                    if let deletedAt = item.deletedAt {
                        Text("删除于 \(deletedAt.formatted(.dateTime.month().day().hour().minute()))")
                            .font(.caption2)
                    }
                }
                .foregroundStyle(.tertiary)
            }
            
            Spacer()
            
            Text("剩余 \(daysRemaining) 天")
                .font(.caption)
                .foregroundStyle(daysRemaining <= 7 ? .red : .secondary)
                .fontWeight(daysRemaining <= 7 ? .medium : .regular)
            
            Button("恢复") { showRestoreConfirm = true }
                .buttonStyle(.bordered)
                .controlSize(.small)
            
            Button("彻底删除", role: .destructive) {
                showDeleteConfirm = true
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.vertical, 4)
        .alert("彻底删除", isPresented: $showDeleteConfirm) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) { onPermanentDelete() }
        } message: {
            Text("此操作不可恢复，内容及所有媒体文件将被永久删除。")
        }
        .alert("恢复内容", isPresented: $showRestoreConfirm) {
            Button("取消", role: .cancel) {}
            Button("恢复") { onRestore() }
        } message: {
            Text("确定要将此内容恢复到原来的位置吗？")
        }
    }
}
