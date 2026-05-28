import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var totalItems = 0
    @State private var dbSize: String = "计算中..."
    @State private var currentPath: String = DataDirectory.currentPath
    @State private var showResetConfirm = false
    @State private var updateChecker = UpdateChecker.shared
    
    @State private var isBackingUp = false
    @State private var isRestoring = false
    @State private var showRestoreConfirm = false
    @State private var showRestoreComplete = false
    @State private var backupStatus: String?
    @State private var restoreMetadata: BackupMetadata?
    @State private var selectedBackupURL: URL?
    
    var body: some View {
        Form {
            storageSection
            backupSection
            aboutSection
        }
        .formStyle(.grouped)
        .navigationTitle("设置")
        .onAppear { loadStats() }
        .onDisappear { updateChecker.status = .idle; updateChecker.isChecking = false }
        .alert("恢复默认目录", isPresented: $showResetConfirm) {
            Button("取消", role: .cancel) {}
            Button("恢复") {
                DataDirectory.resetToDefault()
                currentPath = DataDirectory.currentPath
                loadStats()
            }
        } message: {
            Text("将恢复到默认的 Application Support 目录。自定义目录中的数据不会被删除。")
        }
        .alert("确认还原", isPresented: $showRestoreConfirm) {
            Button("取消", role: .cancel) { showRestoreConfirm = false }
            Button("还原", role: .destructive) { performRestore() }
        } message: {
            Text("还原将覆盖当前所有数据。\n\n建议先导出当前数据作为备份。\n\n还原后需要重新启动应用。")
        }
        .alert("还原完成", isPresented: $showRestoreComplete) {
            Button("确定") {}
        } message: {
            Text("数据已还原成功。请重新启动应用以加载新数据。")
        }
    }
    
    // MARK: - Storage
    
    private var storageSection: some View {
        Section("存储管理") {
            HStack { Text("总内容数"); Spacer(); Text("\(totalItems) 条").foregroundStyle(.secondary) }
            HStack { Text("数据库大小"); Spacer(); Text(dbSize).foregroundStyle(.secondary) }
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("数据目录")
                    Spacer()
                    if DataDirectory.isCustom { Text("自定义").font(.caption).foregroundStyle(.orange) }
                }
                Text(currentPath).font(.caption).foregroundStyle(.secondary).textSelection(.enabled).lineLimit(2)
                HStack(spacing: 8) {
                    Button { chooseDirectory() } label: { Label("修改目录", systemImage: "folder") }
                        .buttonStyle(.bordered).controlSize(.small)
                    if DataDirectory.isCustom {
                        Button { showResetConfirm = true } label: { Label("恢复默认", systemImage: "arrow.counterclockwise") }
                            .buttonStyle(.bordered).controlSize(.small)
                    }
                }
            }
        }
    }
    
    // MARK: - Backup
    
    private var backupSection: some View {
        Section("备份与还原") {
            VStack(alignment: .leading, spacing: 8) {
                HStack { Label("备份数据", systemImage: "externaldrive.badge.checkmark"); Spacer(); if isBackingUp { ProgressView().scaleEffect(0.6) } }
                Text("将数据库、媒体文件和平台 Logo 打包为 zip 文件").font(.caption).foregroundStyle(.secondary)
                Button { performBackup() } label: { Label("导出备份", systemImage: "square.and.arrow.up") }
                    .buttonStyle(.bordered).controlSize(.small).disabled(isBackingUp || isRestoring)
                if let s = backupStatus { Text(s).font(.caption).foregroundStyle(.green) }
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack { Label("还原数据", systemImage: "externaldrive.badge.xmark"); Spacer(); if isRestoring { ProgressView().scaleEffect(0.6) } }
                Text("从备份 zip 文件还原数据，当前数据将被覆盖").font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Button { chooseBackupFile() } label: { Label("选择备份文件", systemImage: "doc.badge.plus") }
                        .buttonStyle(.bordered).controlSize(.small).disabled(isBackingUp || isRestoring)
                    if selectedBackupURL != nil {
                        Button { showRestoreConfirm = true } label: { Label("开始还原", systemImage: "arrow.counterclockwise") }
                            .buttonStyle(.borderedProminent).controlSize(.small).tint(.orange).disabled(isBackingUp || isRestoring)
                    }
                }
                if let meta = restoreMetadata {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("备份信息").font(.caption).fontWeight(.medium)
                        Text("版本: \(meta.version)").font(.caption2).foregroundStyle(.secondary)
                        Text("时间: \(meta.backupDate)").font(.caption2).foregroundStyle(.secondary)
                        HStack(spacing: 12) {
                            Label("数据库", systemImage: meta.hasDatabase ? "checkmark.circle.fill" : "xmark.circle").font(.caption2).foregroundStyle(meta.hasDatabase ? .green : .red)
                            Label("媒体", systemImage: meta.hasMedia ? "checkmark.circle.fill" : "xmark.circle").font(.caption2).foregroundStyle(meta.hasMedia ? .green : .red)
                            Label("Logo", systemImage: meta.hasLogos ? "checkmark.circle.fill" : "xmark.circle").font(.caption2).foregroundStyle(meta.hasLogos ? .green : .red)
                        }
                    }.padding(8).background(.quaternary).clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
        }
    }
    
    // MARK: - About (含更新)
    
    private var aboutSection: some View {
        Section("关于") {
            HStack { Text("版本"); Spacer(); Text(appVersion).foregroundStyle(.secondary) }
            HStack { Text("应用名称"); Spacer(); Text("拾屿 (Archiver)").foregroundStyle(.secondary) }
            HStack { Text("作者"); Spacer(); Text("LinKin").foregroundStyle(.secondary) }
            
            HStack {
                Text("检查更新")
                Spacer()
                if updateChecker.isChecking {
                    ProgressView().scaleEffect(0.6)
                } else {
                    switch updateChecker.status {
                    case .upToDate:
                        Button { resetUpdateStatus() } label: {
                            Label("已是最新", systemImage: "arrow.clockwise")
                        }
                        .foregroundStyle(.green)
                    case .updateAvailable(let version, _):
                        Button { updateChecker.openReleasePage() } label: {
                            Label("v\(version) · 前往下载", systemImage: "arrow.clockwise")
                        }
                    case .error:
                        Button { resetUpdateStatus() } label: {
                            Label("检查失败", systemImage: "arrow.clockwise")
                        }
                        .foregroundStyle(.red)
                    default:
                        Button { startCheckForUpdates() } label: {
                            Label("检查", systemImage: "arrow.clockwise")
                        }
                    }
                }
            }
            
            Link(destination: URL(string: "https://github.com/V-Linkin/Archiver")!) {
                HStack {
                    Label("GitHub 项目地址", systemImage: "link")
                    Spacer()
                    Image(systemName: "arrow.up.right.square").foregroundStyle(.secondary)
                }
            }
        }
    }
    
    // MARK: - Actions
    
    private func resetUpdateStatus() {
        updateChecker.status = .idle
    }
    
    private func startCheckForUpdates() {
        Task { await updateChecker.checkForUpdates() }
    }
    
    private func performBackup() {
        let panel = NSSavePanel()
        panel.title = "导出备份"
        panel.nameFieldStringValue = "Archiver备份_\(formatDate(Date())).zip"
        panel.allowedContentTypes = [.zip]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        
        isBackingUp = true
        backupStatus = nil
        Task {
            do {
                let zipPath = try await BackupService.shared.backup(to: url.deletingLastPathComponent())
                if zipPath != url {
                    try? FileManager.default.removeItem(at: url)
                    try FileManager.default.moveItem(at: zipPath, to: url)
                }
                await MainActor.run {
                    isBackingUp = false
                    backupStatus = "备份成功: \(url.lastPathComponent)"
                    appState.showToast("备份已完成")
                }
            } catch {
                await MainActor.run {
                    isBackingUp = false
                    appState.showToast("备份失败: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func chooseBackupFile() {
        let panel = NSOpenPanel()
        panel.title = "选择备份文件"
        panel.allowedContentTypes = [.zip]
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        guard panel.runModal() == .OK, let url = panel.urls.first else { return }
        selectedBackupURL = url
        restoreMetadata = nil
        Task {
            let meta = await BackupService.shared.readBackupMetadata(from: url)
            await MainActor.run { restoreMetadata = meta }
        }
    }
    
    private func performRestore() {
        guard let backupURL = selectedBackupURL else { return }
        isRestoring = true
        Task {
            do {
                try await BackupService.shared.restore(from: backupURL)
                await MainActor.run {
                    isRestoring = false
                    showRestoreComplete = true
                    loadStats()
                }
            } catch {
                await MainActor.run {
                    isRestoring = false
                    appState.showToast("还原失败: \(error.localizedDescription)")
                }
            }
        }
    }
    
    // MARK: - Helpers
    
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }
    
    private func loadStats() {
        totalItems = (try? appState.itemRepo.count()) ?? 0
        currentPath = DataDirectory.currentPath
        let dbPath = DataDirectory.database.path
        if let attrs = try? FileManager.default.attributesOfItem(atPath: dbPath),
           let size = attrs[.size] as? Int64 {
            dbSize = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
        } else {
            dbSize = "未知"
        }
    }
    
    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.title = "选择数据存储目录"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        if let u = URL(string: "file://" + currentPath) { panel.directoryURL = u }
        guard panel.runModal() == .OK, let url = panel.urls.first else { return }
        DataDirectory.setCustom(url.path)
        currentPath = DataDirectory.currentPath
        loadStats()
        appState.showToast("数据目录已切换到 \(url.lastPathComponent)")
    }
    
    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyyMMdd_HHmm"; return f.string(from: date)
    }
}
