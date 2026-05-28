import SwiftUI

struct NewCustomPlatformSheet: View {
    @Binding var isPresented: Bool
    @Environment(AppState.self) private var appState
    
    @State private var platformName = ""
    @State private var logoURL: URL?
    @State private var logoImage: NSImage?
    
    var body: some View {
        VStack(spacing: 20) {
            Text("新增平台").font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("平台名称").font(.subheadline).foregroundStyle(.secondary)
                TextField("输入平台名称", text: $platformName)
                    .textFieldStyle(.roundedBorder)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("平台 Logo（可选）").font(.subheadline).foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    if let img = logoImage {
                        Image(nsImage: img)
                            .resizable()
                            .frame(width: 48, height: 48)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    } else {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.quaternary)
                            .frame(width: 48, height: 48)
                            .overlay {
                                Image(systemName: "photo")
                                    .foregroundStyle(.tertiary)
                            }
                    }
                    
                    Button {
                        let panel = NSOpenPanel()
                        panel.title = "选择平台 Logo"
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
                    .controlSize(.small)
                    
                    if logoURL != nil {
                        Button {
                            logoURL = nil
                            logoImage = nil
                        } label: {
                            Text("移除")
                        }
                        .controlSize(.small)
                        .foregroundStyle(.secondary)
                    }
                }
            }
            
            HStack {
                Button("取消") { isPresented = false }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("创建") { createPlatform() }
                    .buttonStyle(.borderedProminent)
                    .disabled(platformName.trimmingCharacters(in: .whitespaces).isEmpty)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 420)
    }
    
    private func createPlatform() {
        let name = platformName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        
        var cp = CustomPlatform(name: name)
        
        // Save logo
        if let logoURL = logoURL {
            let logosDir = DataDirectory.platformLogos
            try? FileManager.default.createDirectory(at: logosDir, withIntermediateDirectories: true)
            
            let fileName = "\(cp.id.uuidString).\(logoURL.pathExtension.isEmpty ? "png" : logoURL.pathExtension)"
            let dest = logosDir.appendingPathComponent(fileName)
            do {
                if FileManager.default.fileExists(atPath: dest.path) {
                    try FileManager.default.removeItem(at: dest)
                }
                try FileManager.default.copyItem(at: logoURL, to: dest)
                cp.logoPath = fileName
            } catch {
                print("Logo 保存失败: \(error)")
            }
        }
        
        try? appState.customPlatformRepo.insert(cp)
        appState.refreshData()
        isPresented = false
        appState.showToast("平台「\(name)」已创建")
    }
}
