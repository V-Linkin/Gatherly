import SwiftUI

/// 批量导出时的媒体类型选择弹窗
struct ExportPickerSheet: View {
    let hasBodyImages: Bool
    let mediaAssetCount: Int
    let bodyImageCount: Int
    @Binding var isPresented: Bool
    let onExport: (ExportSelection) -> Void
    
    enum ExportSelection {
        case mediaOnly
        case bodyImagesOnly
        case all
    }
    
    @State private var selection: ExportSelection = .all
    
    var body: some View {
        VStack(spacing: 0) {
            Text("选择导出内容")
                .font(.headline)
                .padding()
            
            Divider()
            
            VStack(spacing: 12) {
                if mediaAssetCount > 0 {
                    radioOption(
                        title: "媒体区域",
                        detail: "\(mediaAssetCount) 个文件（图片/视频）",
                        tag: .mediaOnly
                    )
                }
                
                if hasBodyImages && bodyImageCount > 0 {
                    radioOption(
                        title: "正文图片",
                        detail: "\(bodyImageCount) 个文件",
                        tag: .bodyImagesOnly
                    )
                }
                
                if mediaAssetCount > 0 && hasBodyImages && bodyImageCount > 0 {
                    radioOption(
                        title: "全部导出",
                        detail: "\(mediaAssetCount + bodyImageCount) 个文件",
                        tag: .all
                    )
                }
            }
            .padding(16)
            
            Divider()
            
            HStack {
                Button("取消") {
                    isPresented = false
                }
                Spacer()
                Button("导出") {
                    onExport(selection)
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(width: 320, height: 260)
    }
    
    @ViewBuilder
    private func radioOption(title: String, detail: String, tag: ExportSelection) -> some View {
        Button {
            selection = tag
        } label: {
            HStack {
                Image(systemName: selection == tag ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selection == tag ? .blue : .secondary)
                VStack(alignment: .leading) {
                    Text(title).font(.body)
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 6).fill(selection == tag ? Color.blue.opacity(0.1) : Color.clear))
        }
        .buttonStyle(.plain)
    }
}
