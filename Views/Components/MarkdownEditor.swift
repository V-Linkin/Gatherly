import SwiftUI

// MARK: - Markdown 编辑器 (工具栏 + TextEditor + 预览切换)

struct MarkdownEditor: View {
    @Binding var text: String
    var placeholder: String = ""
    var minHeight: CGFloat = 120
    
    @State private var isPreview = false
    @FocusState private var isFocused: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 工具栏 + 预览切换
            HStack(spacing: 4) {
                MarkdownToolbarButton(icon: "bold", tooltip: "加粗") { insertMarkdown("**", "**") }
                MarkdownToolbarButton(icon: "italic", tooltip: "斜体") { insertMarkdown("*", "*") }
                MarkdownToolbarButton(icon: "heading", tooltip: "标题") { insertLinePrefix("## ") }
                MarkdownToolbarButton(icon: "list.bullet", tooltip: "无序列表") { insertLinePrefix("- ") }
                MarkdownToolbarButton(icon: "list.number", tooltip: "有序列表") { insertLinePrefix("1. ") }
                MarkdownToolbarButton(icon: "link", tooltip: "链接") { insertMarkdown("[", "](url)") }
                MarkdownToolbarButton(icon: "chevron.left.forwardslash.chevron.right", tooltip: "代码") { insertMarkdown("`", "`") }
                
                Spacer()
                
                // 编辑/预览切换
                Picker("", selection: $isPreview) {
                    Text("编辑").tag(false)
                    Text("预览").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 120)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(.quaternary.opacity(0.5))
            
            Divider()
            
            // 编辑/预览区域
            if isPreview {
                // 预览模式
                ScrollView {
                    if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("暂无内容")
                            .foregroundStyle(.tertiary)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        MarkdownView(text: text)
                            .padding(8)
                    }
                }
                .frame(minHeight: minHeight)
            } else {
                // 编辑模式
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $text)
                        .font(.system(size: 14))
                        .scrollContentBackground(.visible)
                        .scrollIndicators(.hidden)
                        .focused($isFocused)
                    
                    if text.isEmpty {
                        Text(placeholder)
                            .font(.system(size: 14))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .allowsHitTesting(false)
                    }
                }
                .frame(minHeight: minHeight)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary, lineWidth: 1))
    }
    
    // MARK: - Markdown 插入方法
    
    private func insertMarkdown(_ prefix: String, _ suffix: String) {
        text += "\(prefix)\(suffix)"
    }
    
    private func insertLinePrefix(_ prefix: String) {
        text += prefix
    }
}

// MARK: - 工具栏按钮

struct MarkdownToolbarButton: View {
    let icon: String
    let tooltip: String
    let action: () -> Void
    
    @State private var isHovering = false
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .frame(width: 28, height: 24)
        }
        .buttonStyle(.plain)
        .tooltip(tooltip)
        .onHover { hovering in isHovering = hovering }
        .background(isHovering ? Color.secondary.opacity(0.1) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

// MARK: - Tooltip 修饰符

struct TooltipModifier: ViewModifier {
    let text: String
    @State private var showTooltip = false
    
    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                showTooltip = hovering
            }
            .overlay {
                if showTooltip {
                    Text(text)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.black.opacity(0.8))
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .offset(y: -30)
                        .transition(.opacity)
                        .zIndex(100)
                }
            }
            .animation(.easeInOut(duration: 0.15), value: showTooltip)
    }
}

extension View {
    func tooltip(_ text: String) -> some View {
        modifier(TooltipModifier(text: text))
    }
}
