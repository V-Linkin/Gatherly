import SwiftUI

/// 设置页
struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var totalItems = 0
    @State private var dbSize: String = "计算中..."
    
    var body: some View {
        Form {
            Section("存储管理") {
                HStack {
                    Text("总内容数")
                    Spacer()
                    Text("\(totalItems) 条")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("数据库大小")
                    Spacer()
                    Text(dbSize)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("数据目录")
                    Spacer()
                    Text(dataDirectory)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            
            Section("关于") {
                HStack {
                    Text("版本")
                    Spacer()
                    Text("1.0.0 (MVP)")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("应用名称")
                    Spacer()
                    Text("Archiver")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("设置")
        .onAppear { loadStats() }
    }
    
    private var dataDirectory: String {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Archiver").path
    }
    
    private func loadStats() {
        totalItems = (try? appState.itemRepo.count()) ?? 0
        
        let dbPath = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Archiver/archiver.db").path ?? ""
        if let attrs = try? FileManager.default.attributesOfItem(atPath: dbPath),
           let size = attrs[.size] as? Int64 {
            dbSize = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
        } else {
            dbSize = "未知"
        }
    }
}
