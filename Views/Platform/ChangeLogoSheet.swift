import SwiftUI

struct ChangeLogoSheet: View {
    let platform: CustomPlatform
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    
    @State private var logoURL: URL?
    @State private var logoImage: NSImage?
    
    var body: some View {
        VStack(spacing: 20) {
            Text("更换 Logo").font(.headline)
            Text(platform.name).font(.subheadline).foregroundStyle(.secondary)
            
            HStack(spacing: 16) {
                if let img = logoImage {
                    Image(nsImage: img)
                        .resizable()
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                } else if let logoPath = platform.logoPath {
                    let url = DataDirectory.platformLogos.appendingPathComponent(logoPath)
                    if let nsImage = NSImage(contentsOf: url) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .frame(width: 64, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    } else {
                        placeholder
                    }
                } else {
                    placeholder
                }
                
                VStack(spacing: 8) {
                    Button {
                        let panel = NSOpenPanel()
                        panel.title = "选择 Logo"
                        panel.allowsMultipleSelection = false
                        panel.canChooseDirectories = false
                        panel.canChooseFiles = true
                        panel.allowedContentTypes = [.image]
                        if panel.runModal() == .OK, let url = panel.urls.first {
                            logoURL = url
                            logoImage = NSImage(contentsOf: url)
                        }
                    } label: {
                        Label("选择图片", systemImage: "photo.badge.plus")
                    }
                    .buttonStyle(.bordered)
                    
                    if platform.logoPath != nil || logoURL != nil {
                        Button("移除 Logo") {
                            logoURL = nil
                            logoImage = nil
                            var updated = platform
                            updated.logoPath = nil
                            if let oldPath = platform.logoPath {
                                try? FileManager.default.removeItem(at: DataDirectory.platformLogos.appendingPathComponent(oldPath))
                            }
                            try? appState.customPlatformRepo.update(updated)
                            appState.refreshData()
                            dismiss()
                        }
                        .foregroundStyle(.red)
                        .controlSize(.small)
                    }
                }
            }
            
            HStack {
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("保存") { saveLogo() }
                    .buttonStyle(.borderedProminent)
                    .disabled(logoURL == nil)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 420)
    }
    
    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(.quaternary)
            .frame(width: 64, height: 64)
            .overlay {
                Image(systemName: "photo")
                    .font(.title2)
                    .foregroundStyle(.tertiary)
            }
    }
    
    private func saveLogo() {
        guard let logoURL = logoURL else { return }
        
        let logosDir = DataDirectory.platformLogos
        try? FileManager.default.createDirectory(at: logosDir, withIntermediateDirectories: true)
        
        let ext = logoURL.pathExtension.isEmpty ? "png" : logoURL.pathExtension
        let fileName = "\(platform.id.uuidString).\(ext)"
        let dest = logosDir.appendingPathComponent(fileName)
        
        do {
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.copyItem(at: logoURL, to: dest)
            
            if let oldPath = platform.logoPath, oldPath != fileName {
                try? FileManager.default.removeItem(at: logosDir.appendingPathComponent(oldPath))
            }
            
            var updated = platform
            updated.logoPath = fileName
            try? appState.customPlatformRepo.update(updated)
            appState.refreshData()
            dismiss()
        } catch {
            print("Logo 保存失败: \(error)")
        }
    }
}
