import SwiftUI

struct HelpView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    quickStartSection
                    platformsSection
                    organizeSection
                    mediaSection
                    backupSection
                    faqSection
                }
                .padding()
            }
            .navigationTitle("使用帮助")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .frame(width: 600, height: 500)
    }
    
    // MARK: - Quick Start
    
    private var quickStartSection: some View {
        HelpSection(title: "快速入门") {
            HelpItem(
                title: "归档第一个链接",
                content: """
                1. 复制任意平台的分享链接（支持抖音、小红书、B站等）
                2. 打开拾屿，粘贴到首页的输入框
                3. 点击「一键归档」
                4. 等待解析完成，内容自动保存到本地
                """
            )
            HelpItem(
                title: "批量归档",
                content: "支持一次粘贴多个链接，用换行或空格分隔，系统会自动识别并批量解析。"
            )
        }
    }
    
    // MARK: - Platforms
    
    private var platformsSection: some View {
        HelpSection(title: "支持平台") {
            HelpItem(
                title: "短视频平台",
                content: """
                • 抖音 — 支持视频、图文笔记
                • B站 — 支持视频信息、封面、简介
                • 小红书 — 支持图文笔记、视频笔记
                """
            )
            HelpItem(
                title: "社交媒体",
                content: """
                • 微博 — 支持微博正文、图片
                • X (Twitter) — 支持推文、图片、视频
                • YouTube — 支持视频信息、封面、简介
                """
            )
            HelpItem(
                title: "内容社区",
                content: """
                • 知乎 — 支持问答、文章
                • 豆瓣 — 支持影评、书评、小组帖子
                • 酷安 — 支持应用动态、数码帖子
                • GitHub — 支持仓库 README、Issue、PR
                """
            )
        }
    }
    
    // MARK: - Organize
    
    private var organizeSection: some View {
        HelpSection(title: "内容整理") {
            HelpItem(
                title: "编辑内容",
                content: "点击内容卡片进入详情，可编辑标题、正文、作者、备注。支持 Markdown 格式。"
            )
            HelpItem(
                title: "状态管理",
                content: "内容会自动保存到对应平台分类下，可通过文件夹进行分类整理。"
            )
            HelpItem(
                title: "文件夹分类",
                content: "在平台分类下创建文件夹，右键内容卡片可移动到指定文件夹。支持多选批量移动。"
            )
            HelpItem(
                title: "搜索",
                content: "顶部搜索框支持全文搜索，可按平台、状态、类型筛选结果。"
            )
        }
    }
    
    // MARK: - Media
    
    private var mediaSection: some View {
        HelpSection(title: "媒体导出") {
            HelpItem(
                title: "查看媒体",
                content: "内容详情页顶部显示图片/视频，点击可全屏预览。支持 Shift+滚轮横向滚动浏览多图。"
            )
            HelpItem(
                title: "导出文件",
                content: """
                • 右键图片/视频 → 选择「另存为」导出单个文件
                • 工具栏「导出」按钮可批量导出所有媒体
                • 导出文件名格式：平台_文件夹_作者_序号_日期
                """
            )
            HelpItem(
                title: "复制图片",
                content: "右键图片选择「复制图片」，可直接粘贴到其他应用。"
            )
        }
    }
    
    // MARK: - Backup
    
    private var backupSection: some View {
        HelpSection(title: "备份还原") {
            HelpItem(
                title: "备份数据",
                content: "设置 → 备份与还原 → 导出备份，将数据库、媒体文件打包为 zip 文件。"
            )
            HelpItem(
                title: "还原数据",
                content: "选择之前备份的 zip 文件，可完整还原所有内容。还原后需要重启应用。"
            )
            HelpItem(
                title: "更换存储位置",
                content: "设置 → 存储管理 → 修改目录，可将数据迁移到其他磁盘。"
            )
        }
    }
    
    // MARK: - FAQ
    
    private var faqSection: some View {
        HelpSection(title: "常见问题") {
            HelpItem(
                title: "Q: 为什么有些链接无法解析？",
                content: "可能是链接格式不正确，或平台暂时限制访问。请确认链接来自平台的「分享」功能。"
            )
            HelpItem(
                title: "Q: 解析后的图片有水印吗？",
                content: "小红书、微博等平台的图片已自动去除水印，保存为高清原图。"
            )
            HelpItem(
                title: "Q: 数据存储在哪里？",
                content: "默认存储在 ~/Library/Application Support/Archiver，可在设置中查看和修改。"
            )
            HelpItem(
                title: "Q: 支持自动更新吗？",
                content: "设置 → 关于 → 检查更新，有新版本可直接下载安装。"
            )
        }
    }
}

// MARK: - Components

struct HelpSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.title3.bold())
                .foregroundStyle(.primary)
            VStack(alignment: .leading, spacing: 4) {
                content()
            }
        }
    }
}

struct HelpItem: View {
    let title: String
    let content: String
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(title)
                        .font(.body)
                        .foregroundStyle(.primary)
                    Spacer()
                }
            }
            .buttonStyle(.plain)
            
            if isExpanded {
                Text(content)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 16)
                    .padding(.top, 2)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.vertical, 4)
    }
}
