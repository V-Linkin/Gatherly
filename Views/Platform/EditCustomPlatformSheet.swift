import SwiftUI

struct EditCustomPlatformSheet: View {
    let platform: CustomPlatform
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    
    @State private var platformName: String
    
    init(platform: CustomPlatform) {
        self.platform = platform
        _platformName = State(initialValue: platform.name)
    }
    
    var body: some View {
        VStack(spacing: 20) {
            Text("重命名平台").font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("平台名称").font(.subheadline).foregroundStyle(.secondary)
                TextField("输入平台名称", text: $platformName)
                    .textFieldStyle(.roundedBorder)
            }
            
            HStack {
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("保存") {
                    var updated = platform
                    updated.name = platformName.trimmingCharacters(in: .whitespaces)
                    try? appState.customPlatformRepo.update(updated)
                    appState.refreshData()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(platformName.trimmingCharacters(in: .whitespaces).isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 380)
    }
}
