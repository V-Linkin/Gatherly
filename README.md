# Archiver

**macOS 本地跨平台内容归档器** — 把你喜欢的内容，永久留在本地。

> 跨平台内容归档器 + 搜索库。主动粘贴各平台链接，解析后保存为本地可长期查看、可搜索、可整理的私人资料库。即使原平台内容被删除，已归档内容仍可本地查看。

---

## 截图

| 首页 | 平台分类 | 内容详情 |
|------|---------|---------|
| 粘贴链接即归档 | 按平台自动分类 | 图片放大、正文浏览 |

---

## 核心功能

### 🔗 粘贴即归档
- 粘贴任意平台链接，自动识别平台
- 解析标题、正文、作者、发布时间、封面图
- 下载图片原图到本地
- 自动去重，重复导入会提示

### 📱 四平台支持
| 平台 | 图文 | 视频 | 解析方式 |
|------|------|------|---------|
| 抖音 | ✅ | ⚠️ 尽量保存 | SSR 数据 + Meta 标签 |
| 小红书 | ✅ | ⚠️ 尽量保存 | SSR 数据 + Meta 标签 |
| 酷安 | ✅ | — | JSON-LD + Meta 标签 |
| B站 | ✅ | ⚠️ 尽量保存 | SSR 数据 + Meta 标签 |

> ⚠️ 视频保存受限于平台反爬策略，失败时仍保留元数据和图文信息。

### 🔎 全局搜索
- 基于 SQLite FTS5 全文搜索引擎
- 搜索范围：标题 + 正文
- 支持中文分词（unicode61）
- 搜索结果关键词高亮

### 🗂️ 文件夹管理
- 每个平台下可创建二级文件夹
- 右键菜单快速移动内容到文件夹
- 新建、重命名、删除文件夹
- 删除文件夹时内容自动移出

### 🗑️ 回收站
- 删除的内容进入回收站，30 天内可恢复
- 彻底删除同时清理本地媒体文件
- 恢复时自动回到原文件夹和原状态

### 🖼️ 图片查看
- 点击图片全屏放大查看
- 纯黑背景，不影响浏览
- 水平滚动浏览多图

---

## 技术架构

```
Archiver/
├── App/                    # 应用入口 + 全局状态 + 导航
├── Models/                 # 数据模型
│   └── Enums/              # 枚举定义（平台/状态/类型）
├── Database/               # 数据库层（GRDB + FTS5）
├── Parsers/                # 平台解析器（协议 + 4个实现）
├── Services/               # 导入服务（编排解析流程）
├── Utilities/              # URL 标准化等工具
└── Views/                  # UI 层
    ├── Home/               # 首页（粘贴输入 + 最近导入）
    ├── Platform/           # 平台分类 + 文件夹
    ├── Item/               # 内容详情 + 图片放大
    ├── Search/             # 搜索结果
    ├── Trash/              # 回收站
    ├── Settings/           # 设置
    └── Components/         # 卡片、Toast 等通用组件
```

### 技术栈

| 层级 | 技术 | 说明 |
|------|------|------|
| UI 框架 | SwiftUI + AppKit | 原生 macOS 体验 |
| 语言 | Swift 5.9+ | 类型安全，async/await |
| 数据库 | SQLite + GRDB.swift | 轻量、成熟、支持 FTS5 |
| 全文搜索 | SQLite FTS5 | 与数据库同引擎，毫秒级响应 |
| 网络 | URLSession + async/await | 原生网络库 |
| 日志 | OSLog | 原生日志系统 |

### 数据存储

```
~/Library/Application Support/Archiver/
├── data/
│   └── archiver.db          # SQLite 数据库
└── media/
    └── {item-uuid}/          # 按内容 ID 分目录
        ├── cover.jpg         # 封面图
        ├── image_001.jpg     # 内容图片
        └── video.mp4         # 视频文件
```

### 核心数据模型

- **Item** — 内容主体（标题/正文/链接/平台/状态）
- **MediaAsset** — 媒体资产（图片/视频/封面，含本地路径和下载状态）
- **Folder** — 文件夹（二级结构，按平台分组）
- **TrashRecord** — 回收站记录（保留恢复信息）
- **ImportTask** — 导入任务（跟踪解析进度）

---

## 快速开始

### 环境要求

- macOS 14.0+
- Xcode 16.0+
- Swift 5.9+

### 安装步骤

```bash
# 1. 克隆仓库
git clone https://github.com/V-Linkin/Archiver.git
cd Archiver

# 2. 安装 XcodeGen（如果没有）
brew install xcodegen

# 3. 生成 Xcode 项目
xcodegen generate

# 4. 打开项目
open Archiver.xcodeproj
```

Xcode 打开后会自动下载 GRDB 依赖，等右上角进度条走完，按 `Cmd+R` 运行。

### 手动设置（不用 XcodeGen）

```bash
# 直接用生成好的项目文件
open Archiver/Archiver.xcodeproj
```

---

## 已实现的功能

- [x] 首页粘贴链接输入框，实时识别平台
- [x] 四平台解析器（抖音/小红书/酷安/B站）
- [x] 内容自动归档到对应平台分类
- [x] 封面图、内容图片本地下载保存
- [x] SQLite 数据库 + FTS5 全文搜索
- [x] 全局搜索（标题+正文）+ 关键词高亮
- [x] 平台分类浏览（网格/列表双视图）
- [x] 二级文件夹管理（新建/重命名/删除）
- [x] 右键菜单移动内容到文件夹
- [x] 内容详情页（元信息/正文/备注）
- [x] 图片点击全屏放大查看
- [x] 编辑标题、正文、备注
- [x] 删除 → 回收站 → 恢复/彻底删除
- [x] 去重检查（基于平台内容 ID + 标准化链接）
- [x] 导入失败兜底（保留原始记录，支持手动编辑）
- [x] 侧边栏导航 + 返回按钮（记住来源页面）
- [x] 搜索结果按平台/状态筛选
- [x] 设置页（存储统计、版本信息）

## 未实现 / 待优化

- [ ] **视频完整保存** — 目前尽量保存，失败时保留元数据
- [ ] **图片原图保存** — 目前保存中等质量，可升级为原图
- [ ] **视频播放器** — 内置本地视频播放
- [ ] **批量操作** — 批量移动、批量删除
- [ ] **标签系统** — 自定义标签分类
- [ ] **导入历史** — 查看所有导入任务状态
- [ ] **快捷键支持** — Cmd+N 新建、Cmd+D 删除等
- [ ] **Spotlight 搜索集成** — 系统级搜索
- [ ] **Shortcuts 快捷指令** — 自动化导入
- [ ] **本地备份与恢复** — 导出/导入整个资料库
- [ ] **更多平台** — 微博、知乎、Twitter/X 等
- [ ] **云同步** — 跨设备同步（架构已预留 version 字段）

---

## 平台解析机制

每个平台实现 `ContentParser` 协议：

```swift
protocol ContentParser: Sendable {
    func canParse(url: URL) -> Bool
    func extractContentID(from url: URL) -> String?
    func normalizeURL(_ url: String) -> String
    func parse(url: URL) async throws -> ParsedContent
    func downloadMedia(content: ParsedContent, itemID: UUID, mediaDir: URL) async throws -> [MediaAsset]
}
```

新增平台只需：
1. 在 `Platform` 枚举中添加新值
2. 实现 `ContentParser` 协议
3. 在 `PlatformRouter` 中注册

---

## 搜索实现

基于 SQLite FTS5，支持中文分词：

```sql
CREATE VIRTUAL TABLE items_fts USING fts5(
    title,
    body,
    tokenize='unicode61'
);

-- 搜索示例
SELECT items.*, snippet(items_fts, 0, '<mark>', '</mark>', '...', 64) AS title_hl
FROM items_fts
JOIN items ON items.rowid = items_fts.rowid
WHERE items_fts MATCH '关键词'
ORDER BY items_fts.rank;
```

---

## 项目结构

```
37 个 Swift 源文件
约 4,400 行代码
```

| 模块 | 文件数 | 说明 |
|------|--------|------|
| Models | 12 | 数据模型 + 枚举 |
| Database | 7 | 数据库管理 + 5个 Repository |
| Parsers | 6 | 4个平台解析器 + 路由 + 协议 |
| Services | 1 | 导入编排服务 |
| Views | 8 | 7个页面 + 通用组件 |
| App | 2 | 入口 + 导航 |
| Utilities | 1 | URL 工具 |

---

## License

MIT

---

## Author

[@V-Linkin](https://github.com/V-Linkin)
