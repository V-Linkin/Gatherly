# 拾屿 Archiver — 跨平台迁移架构设计

> **日期**: 2025-05-29（2026-06-01 更新）
> **状态**: 设计完成，待后续执行
> **策略**: 渐进式分离（方案 A）
> **当前版本**: v1.1.1

---

## 一、背景与目标

### 当前状态

拾屿 Archiver 是一个 macOS 本地跨平台内容归档器，当前版本 v1.1.1，技术栈：

- **语言**: Swift 6.0
- **UI**: SwiftUI（macOS 14.0+）
- **数据库**: GRDB 7（SQLite + FTS5）
- **构建**: XcodeGen → Xcode
- **代码规模**: 69 个 Swift 文件，约 12,676 行代码
- **支持平台**: 抖音、小红书、酷安、B站、GitHub、YouTube、X(Twitter)、微博、知乎、豆瓣（共 10 个）

### 已实现功能

| 功能模块 | 说明 |
|---------|------|
| 链接导入 | 多行粘贴框，支持含分享文案的混合文本，自动识别平台 |
| 内容归档 | 保存标题、正文、作者、封面、原图，支持 Markdown 渲染 |
| Markdown 编辑器 | 详情页支持格式化编辑正文和备注，实时预览 |
| 自定义平台 | 支持新增、重命名、删除、更换 Logo |
| 二级文件夹 | 平台下支持二级文件夹组织 |
| 媒体管理 | 添加/删除图片视频，另存为导出（按平台_作者_日期自动创建子文件夹） |
| 图片/视频查看 | 全屏查看图片，内置视频播放器 |
| 全局搜索 | 关键词搜索 + FTS5 全文检索，支持按平台/类型筛选 |
| 回收站 | 30 天自动清除，支持恢复 |
| 备份与还原 | 一键导出为 zip，可完整还原 |
| 浏览器选择 | 设置中选择 Safari/Chrome/Firefox/Edge/Arc |
| 检查更新 | 通过 GitHub Release 检测新版本 |
| 最近导入 | 首页展示最近 7 天内容，新建平台自动归类未分类内容 |
| 酷安双模式 | HTTP + WebView 双模式解析，绕过反爬 |

### 迁移目标

将拾屿从 macOS 专属应用重构为 **macOS + Windows 双平台应用**，要求：

1. 两个平台功能一致
2. macOS 使用 Sidebar 风格 UI（原生体验）
3. Windows 使用 Fluent Design 风格 UI（原生体验）
4. 共享核心业务逻辑，各平台只独立开发 UI 层
5. 通过 GitHub 同步代码，macOS 和 Windows 各自开发测试

### 迁移策略

采用**渐进式分离**：

- **阶段 1（现在）**: 继续完善 macOS Swift 版本，同时优化代码结构使其更易迁移
- **阶段 2（后续）**: 用 Tauri 重写，Rust 后端 + Web 前端，同时出 macOS 和 Windows 版本

---

## 二、目标技术架构

### 整体架构

```
┌──────────────────────────────────────────────────┐
│                Tauri 应用壳                       │
├──────────────────────┬───────────────────────────┤
│   macOS Frontend     │   Windows Frontend         │
│   Sidebar UI         │   Fluent Design UI         │
│   (Vue 3 + TypeScript)│  (Vue 3 + TypeScript)     │
│   CSS: 仿 macOS 风格  │   CSS: Fluent Design      │
├──────────────────────┴───────────────────────────┤
│              Tauri Bridge (IPC)                   │
├──────────────────────────────────────────────────┤
│              Rust 共享后端                         │
│  ┌─────────┐ ┌──────────┐ ┌─────────────────┐   │
│  │ Parsers │ │ Database │ │ File Storage    │   │
│  │ (10个)  │ │ (SQLite) │ │ (媒体文件管理)  │   │
│  └─────────┘ └──────────┘ └─────────────────┘   │
│  ┌──────────────────┐ ┌─────────────────────┐   │
│  │ Import Service   │ │ Search (FTS5)       │   │
│  └──────────────────┘ └─────────────────────┘   │
│  ┌──────────────────┐ ┌─────────────────────┐   │
│  │ Backup Service   │ │ Update Checker      │
│  └──────────────────┘ └─────────────────────┘   │
│  ┌──────────────────┐ ┌─────────────────────┐   │
│  │ Media Exporter   │ │ Browser Detector    │
│  └──────────────────┘ └─────────────────────┘   │
└──────────────────────────────────────────────────┘
```

### 技术选型

| 组件 | 选型 | 原因 |
|------|------|------|
| 应用框架 | Tauri 2.x | 体积小（5-10MB）、性能好、Rust 后端 |
| 前端框架 | Vue 3 + TypeScript | 轻量、生态成熟、AI 生成质量高 |
| UI 组件（macOS） | 自定义 CSS（仿 Sidebar 风格） | 还原 macOS 原生体验 |
| UI 组件（Windows） | Fluent UI Web Components | 微软官方 Fluent Design 组件库 |
| 数据库 | rusqlite（SQLite + FTS5） | 与当前 GRDB 完全兼容 |
| HTTP 请求 | reqwest | Rust 生态最成熟的 HTTP 客户端 |
| HTML 解析 | scraper | 类似 BeautifulSoup，用于解析网页内容 |
| WebView | wry | Tauri 内置 WebView，用于酷安等需要 JS 渲染的平台 |
| 文件操作 | std::fs + dirs | 跨平台文件系统和目录管理 |
| 异步运行时 | tokio | Rust 标准异步运行时 |

---

## 三、模块映射（Swift → Rust）

### 3.1 解析器模块

```
当前 Swift                          →  Rust
──────────────────────────────────────────────────
Parsers/ContentParser.swift         →  src/parsers/mod.rs（trait 定义）
Parsers/BaseParser.swift            →  src/parsers/base.rs（基础实现）
Parsers/PlatformRouter.swift        →  src/parsers/router.rs
Parsers/DouyinParser.swift          →  src/parsers/douyin.rs
Parsers/XiaohongshuParser.swift     →  src/parsers/xiaohongshu.rs
Parsers/CoolapkParser.swift         →  src/parsers/coolapk.rs（双模式：HTTP + WebView）
Parsers/BilibiliParser.swift        →  src/parsers/bilibili.rs
Parsers/GitHubParser.swift          →  src/parsers/github.rs
Parsers/YouTubeParser.swift         →  src/parsers/youtube.rs
Parsers/XParser.swift               →  src/parsers/twitter.rs
Parsers/WeiboParser.swift           →  src/parsers/weibo.rs
Parsers/ZhihuParser.swift           →  src/parsers/zhihu.rs
Parsers/DoubanParser.swift          →  src/parsers/douban.rs
```

**Rust trait 设计**:

```rust
// src/parsers/mod.rs
pub trait ContentParser: Send + Sync {
    /// 解析链接，返回内容
    fn parse(&self, url: &str) -> Result<ParsedContent, ParseError>;
    
    /// 检查是否支持该链接
    fn can_handle(&self, url: &str) -> bool;
    
    /// 返回平台标识
    fn platform(&self) -> Platform;
}

pub struct ParsedContent {
    pub title: Option<String>,
    pub body: Option<String>,
    pub author: Option<String>,
    pub cover_url: Option<String>,
    pub image_urls: Vec<String>,
    pub video_url: Option<String>,
    pub platform_content_id: Option<String>,
    pub publish_time: Option<String>,
}
```

### 3.2 数据库模块

```
当前 Swift                          →  Rust
──────────────────────────────────────────────────
Database/DatabaseManager.swift      →  src/db/mod.rs
Database/ItemRepository.swift       →  src/db/items.rs
Database/FolderRepository.swift     →  src/db/folders.rs
Database/MediaRepository.swift      →  src/db/media.rs
Database/SearchRepository.swift     →  src/db/search.rs
Database/TrashRepository.swift      →  src/db/trash.rs
Database/CustomPlatformRepository   →  src/db/platforms.rs
```

**关键原则**: SQLite schema 完全复用，不改表结构。

### 3.3 数据模型

```
当前 Swift                          →  Rust
──────────────────────────────────────────────────
Models/Item.swift                   →  src/models/item.rs
Models/Folder.swift                 →  src/models/folder.rs
Models/MediaAsset.swift             →  src/models/media.rs
Models/CustomPlatform.swift         →  src/models/platform.rs
Models/TrashRecord.swift            →  src/models/trash.rs
Models/ImportTask.swift             →  src/models/task.rs
Models/Enums/*.swift                →  src/models/enums.rs
```

### 3.4 服务模块

```
当前 Swift                          →  Rust
──────────────────────────────────────────────────
Services/ImportService.swift        →  src/services/import.rs
Services/BackupService.swift        →  src/services/backup.rs
Services/UpdateChecker.swift        →  src/services/update.rs
```

### 3.5 工具模块

```
当前 Swift                          →  Rust
──────────────────────────────────────────────────
Utilities/URLNormalizer.swift       →  src/utils/url.rs
Utilities/DataDirectory.swift       →  src/utils/directory.rs
Utilities/BrowserDetector.swift     →  src/utils/browser.rs
Utilities/PlatformCustomization.swift → src/utils/customization.rs
Utilities/MediaExporter.swift       →  src/utils/media_export.rs
Utilities/FilePicker.swift          →  src/utils/file_picker.rs
```

### 3.6 前端视图映射

```
当前 SwiftUI 视图                    →  Vue 组件
──────────────────────────────────────────────────
Views/Home/HomeView.swift           →  src/views/HomeView.vue
Views/Platform/PlatformView.swift   →  src/views/PlatformView.vue
Views/Platform/FolderView.swift     →  src/views/FolderView.vue
Views/Platform/CustomPlatformContentView.swift → src/views/CustomPlatformView.vue
Views/Platform/UncategorizedContentView.swift  → src/views/UncategorizedView.vue
Views/Platform/NewCustomPlatformSheet.swift    → src/views/NewPlatformSheet.vue
Views/Platform/EditCustomPlatformSheet.swift   → src/views/EditPlatformSheet.vue
Views/Platform/ChangeLogoSheet.swift           → src/views/ChangeLogoSheet.vue
Views/Item/ItemDetailView.swift     →  src/views/ItemDetailView.vue
Views/Item/EditItemView.swift       →  src/views/EditItemView.vue
Views/Item/NewItemView.swift        →  src/views/NewItemView.vue
Views/Search/SearchResultsView.swift → src/views/SearchView.vue
Views/Trash/TrashView.swift         →  src/views/TrashView.vue
Views/Settings/SettingsView.swift   →  src/views/SettingsView.vue
Views/Components/ItemCardView.swift →  src/components/ItemCard.vue
Views/Components/MarkdownView.swift →  src/components/MarkdownViewer.vue
Views/Components/MarkdownEditor.swift → src/components/MarkdownEditor.vue
Views/Components/ImageViewerView.swift → src/components/ImageViewer.vue
Views/Components/VideoPlayerView.swift → src/components/VideoPlayer.vue
Views/Components/ToastView.swift    →  src/components/Toast.vue
Views/Components/ExportPickerSheet.swift → src/components/ExportPicker.vue
Views/Components/DebounceHelper.swift    → src/utils/debounce.ts
Views/Components/PlaceholderTextEditor.swift → src/components/PlaceholderEditor.vue
```

---

## 四、数据库兼容性

### 核心原则

SQLite schema **完全保留**，Rust 端使用 `rusqlite` 读写同一份数据库文件。

### 路径处理规范

```rust
// 当前问题：Swift 代码中可能硬编码了 macOS 路径
// 迁移要求：所有路径使用相对路径或通过 dirs crate 获取

use dirs;

// 正确做法
let data_dir = dirs::data_local_dir()
    .expect("无法获取本地数据目录")
    .join("com.archiver.app");

// 媒体文件路径存储格式（数据库中）
// 使用正斜杠，运行时根据平台转换
let stored_path = "media/items/abc123/cover.jpg";  // 数据库存储
let actual_path = data_dir.join(stored_path.replace('/', std::path::MAIN_SEPARATOR_STR));
```

### FTS5 兼容性

```rust
// FTS5 虚拟表在 Rust 端的创建语句必须与 Swift 端完全一致
// 验证方法：对比 GRDB 创建的 schema 和 rusqlite 创建的 schema
```

---

## 五、前端 UI 设计

### 5.1 macOS Sidebar UI

```css
/* 模拟 macOS Finder Sidebar 风格 */
.sidebar {
    width: 220px;
    background: rgba(245, 245, 245, 0.95);
    border-right: 1px solid #d0d0d0;
    font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text";
}

.sidebar-item {
    padding: 4px 12px;
    border-radius: 6px;
    margin: 1px 8px;
}

.sidebar-item:hover {
    background: rgba(0, 0, 0, 0.05);
}

.sidebar-item.active {
    background: rgba(0, 122, 255, 0.15);
    color: #007AFF;
}
```

### 5.2 Windows Fluent Design UI

```css
/* 使用 Fluent UI Web Components */
@import '@fluentui/web-components';

/* Fluent Design 风格 */
.sidebar {
    width: 240px;
    background: var(--neutral-layer-1);
    border-right: 1px solid var(--neutral-stroke-divider);
}

.sidebar-item {
    padding: 6px 12px;
    border-radius: 4px;
    margin: 2px 8px;
}

.sidebar-item:hover {
    background: var(--neutral-layer-hover);
}

.sidebar-item.active {
    background: var(--brand-background);
    color: white;
}
```

### 5.3 共享组件

以下组件两个平台共用，只通过 CSS 变量适配风格：

- `ItemCard.vue` — 内容卡片（网格/列表视图）
- `MarkdownViewer.vue` — Markdown 渲染
- `MarkdownEditor.vue` — Markdown 编辑器
- `ImageViewer.vue` — 图片全屏查看
- `VideoPlayer.vue` — 视频播放器
- `Toast.vue` — 提示消息
- `SearchBar.vue` — 搜索框
- `EmptyState.vue` — 空状态
- `ExportPicker.vue` — 媒体导出选择
- `PlaceholderEditor.vue` — 占位文本编辑器

---

## 六、Tauri IPC 接口设计

```rust
// ===== 解析与导入 =====
#[tauri::command]
async fn import_url(url: String) -> Result<Item, String>;

#[tauri::command]
async fn import_urls(urls: Vec<String>) -> Result<Vec<Item>, String>;

#[tauri::command]
async fn create_manual_item(item: NewItemParams) -> Result<Item, String>;

// ===== 内容查询 =====
#[tauri::command]
async fn get_items(platform: String, status: Option<String>, folder_id: Option<i64>) -> Result<Vec<Item>, String>;

#[tauri::command]
async fn get_item_detail(id: i64) -> Result<ItemDetail, String>;

#[tauri::command]
async fn get_recent_items(days: i32) -> Result<Vec<Item>, String>;

// ===== 内容编辑 =====
#[tauri::command]
async fn update_item(id: i64, updates: ItemUpdate) -> Result<Item, String>;

#[tauri::command]
async fn add_media(item_id: i64, file_paths: Vec<String>) -> Result<Vec<MediaAsset>, String>;

#[tauri::command]
async fn remove_media(media_id: i64) -> Result<(), String>;

#[tauri::command]
async fn export_media(media_id: i64, save_path: String) -> Result<(), String>;

#[tauri::command]
async fn export_media_batch(item_ids: Vec<i64>, save_path: String) -> Result<(), String>;

// ===== 搜索 =====
#[tauri::command]
async fn search_items(query: String, platform: Option<String>, content_type: Option<String>) -> Result<Vec<Item>, String>;

// ===== 文件夹 =====
#[tauri::command]
async fn create_folder(name: String, parent_id: Option<i64>, platform: String) -> Result<Folder, String>;

#[tauri::command]
async fn rename_folder(id: i64, name: String) -> Result<(), String>;

#[tauri::command]
async fn delete_folder(id: i64) -> Result<(), String>;

#[tauri::command]
async fn move_to_folder(item_id: i64, folder_id: Option<i64>) -> Result<(), String>;

// ===== 自定义平台 =====
#[tauri::command]
async fn create_platform(name: String, logo_path: Option<String>) -> Result<CustomPlatform, String>;

#[tauri::command]
async fn update_platform(id: i64, name: Option<String>, logo_path: Option<String>) -> Result<(), String>;

#[tauri::command]
async fn delete_platform(id: i64) -> Result<(), String>;

#[tauri::command]
async fn move_platform(id: i64, direction: String) -> Result<(), String>;

#[tauri::command]
async fn pin_platform(id: i64) -> Result<(), String>;

// ===== 删除与回收站 =====
#[tauri::command]
async fn delete_item(id: i64) -> Result<(), String>;

#[tauri::command]
async fn restore_item(id: i64) -> Result<(), String>;

#[tauri::command]
async fn permanent_delete(id: i64) -> Result<(), String>;

#[tauri::command]
async fn get_trash_items() -> Result<Vec<TrashRecord>, String>;

// ===== 系统功能 =====
#[tauri::command]
async fn open_url_in_browser(url: String) -> Result<(), String>;

#[tauri::command]
async fn get_installed_browsers() -> Result<Vec<BrowserInfo>, String>;

#[tauri::command]
async fn set_preferred_browser(bundle_id: String) -> Result<(), String>;

#[tauri::command]
async fn backup_data() -> Result<String, String>;

#[tauri::command]
async fn restore_data(backup_path: String) -> Result<(), String>;

#[tauri::command]
async fn check_for_updates() -> Result<UpdateInfo, String>;

#[tauri::command]
async fn get_data_directory() -> Result<String, String>;

#[tauri::command]
async fn set_data_directory(path: String) -> Result<(), String>;
```

---

## 七、现阶段优化建议（不影响 macOS 功能）

在继续开发 macOS Swift 版本时，有意识地做以下优化，为将来迁移铺路：

### 7.1 解析器逻辑清晰化

- 每个 Parser 的 `parse()` 方法只做解析，不直接操作 UI
- 解析结果统一用 `ParsedContent` 结构体传递
- 网络请求和 HTML 解析逻辑与业务逻辑分离
- 酷安双模式（HTTP + WebView）的切换逻辑封装清晰

### 7.2 路径处理规范化

- `DataDirectory` 返回的路径用 `URL` 或 `String` 表示，不硬编码分隔符
- 媒体文件存储路径使用正斜杠 `/` 作为通用分隔符
- 数据库中路径字段使用相对路径

### 7.3 业务逻辑与 UI 分离

- Service 层（ImportService、BackupService）不要直接引用 SwiftUI 类型
- 搜索逻辑、去重逻辑封装在独立的方法中
- 状态管理通过 @Observable/@Published 但不依赖具体 UI 组件

### 7.4 媒体文件命名规范化

- 使用内容 ID + hash 作为文件名，避免特殊字符
- 目录结构统一：`media/{platform}/{item_id}/{type}.{ext}`
- 封面图统一命名：`cover.{ext}`

### 7.5 Markdown 处理规范化

- Markdown 解析和渲染逻辑封装在独立模块中
- 编辑器和查看器使用统一的解析器
- 图片引用使用相对路径

---

## 八、迁移阶段规划

### 阶段 1：Rust 后端搭建（预计 2-3 周）

- [ ] 初始化 Tauri 2.x 项目
- [ ] 实现 SQLite 数据库层（复用现有 schema）
- [ ] 迁移 10 个解析器到 Rust（含酷安双模式）
- [ ] 迁移导入服务（支持多链接批量导入）
- [ ] 迁移搜索服务（FTS5 + LIKE 双模式）
- [ ] 迁移备份/恢复服务
- [ ] 实现媒体导出功能
- [ ] 实现浏览器检测与选择
- [ ] 编写单元测试

### 阶段 2：macOS 前端（预计 2-3 周）

- [ ] 搭建 Vue 3 + TypeScript 项目
- [ ] 实现 Sidebar UI 组件
- [ ] 实现首页（多行粘贴导入、最近 7 天导入、平台入口）
- [ ] 实现平台分类页 + 二级文件夹
- [ ] 实现内容详情页 + Markdown 渲染 + 图片查看器 + 视频播放器
- [ ] 实现 Markdown 编辑器
- [ ] 实现搜索页（网格/列表视图切换）
- [ ] 实现回收站（30 天倒计时）
- [ ] 实现设置页（浏览器选择、数据目录、备份还原、检查更新）
- [ ] 实现媒体另存为（单个/批量导出）
- [ ] macOS 上功能测试

### 阶段 3：Windows 前端（预计 2-3 周）

- [ ] 引入 Fluent UI Web Components
- [ ] 实现 Fluent Design 风格 UI
- [ ] 共享 Vue 组件，通过 CSS 变量适配
- [ ] Windows 上功能测试
- [ ] 文件路径兼容性测试

### 阶段 4：发布与维护（持续）

- [ ] macOS 和 Windows 统一版本号
- [ ] GitHub Release 同时发两个平台的包
- [ ] 自动化构建脚本（build_release.sh 支持双平台）
- [ ] 持续功能同步

---

## 九、风险与注意事项

### 风险点

1. **FTS5 兼容性** — 需要验证 rusqlite 的 FTS5 与 GRDB 的 FTS5 行为一致
2. **视频下载** — Rust 的 reqwest 处理大文件下载需要超时和断点续传
3. **路径分隔符** — 数据库中存储的路径在 Windows 上需要转换
4. **UI 一致性** — 两个平台的功能需要保持同步，避免遗漏
5. **中文编码** — URL 中的中文字符处理需要确保跨平台一致
6. **酷安 WebView** — Tauri 的 wry WebView 需要验证酷安 JS 渲染是否正常
7. **Markdown 图片** — 本地图片引用路径在跨平台时需要统一处理

### 注意事项

1. **数据库文件位置**: macOS 在 `~/Library/Application Support/com.archiver.app/`，Windows 在 `%LOCALAPPDATA%/com.archiver.app/`
2. **文件权限**: Windows 和 macOS 的文件权限模型不同，需要注意媒体文件的读写权限
3. **应用签名**: macOS 需要开发者签名，Windows 需要代码签名证书
4. **自动更新**: Tauri 内置更新机制，但需要配置更新服务器
5. **媒体导出**: 跨平台文件选择器实现方式不同，Tauri 内置 dialog 插件可处理

---

## 十、附录

### 当前项目文件结构（v1.1.1）

```
Archiver/
├── App/                    应用入口 + 全局状态 + 导航
├── Database/               GRDB 数据库层 + Repos（7个）
├── Models/                 数据模型 + 枚举
│   └── Enums/             枚举定义（平台/状态/类型）（7个）
├── Parsers/                平台解析器（协议 + 12个实现）
├── Services/               导入/备份/更新服务（3个）
├── Utilities/              工具类（6个）
│   ├── BrowserDetector    浏览器检测与选择
│   ├── DataDirectory      数据目录管理
│   ├── FilePicker         文件选择器
│   ├── MediaExporter      媒体另存为导出
│   ├── PlatformCustomization 平台自定义配置
│   ├── URLNormalizer      URL 标准化
│   └── ZhihuWebLoader     知乎 WebView 加载器
├── Views/                  SwiftUI 视图层（19个）
│   ├── Home/              首页
│   ├── Platform/          平台分类 + 文件夹（7个）
│   ├── Item/              内容详情 + 编辑（3个）
│   ├── Search/            搜索结果
│   ├── Trash/             回收站
│   ├── Settings/          设置
│   └── Components/        通用组件（9个）
├── Tests/                  单元测试
├── Assets.xcassets/        资源文件
├── docs/                   文档
├── scripts/                构建脚本
├── project.yml             XcodeGen 配置
└── Info.plist              应用配置
```

### Tauri 项目目标结构

```
archiver-tauri/
├── src-tauri/              Rust 后端
│   ├── src/
│   │   ├── main.rs         Tauri 入口
│   │   ├── db/             数据库模块
│   │   ├── parsers/        解析器模块（含酷安双模式）
│   │   ├── services/       服务模块
│   │   ├── models/         数据模型
│   │   └── utils/          工具模块
│   ├── Cargo.toml          Rust 依赖
│   └── tauri.conf.json     Tauri 配置
├── src/                    Vue 前端
│   ├── views/              页面组件
│   ├── components/         通用组件
│   ├── styles/             样式文件
│   │   ├── macos.css       macOS Sidebar 风格
│   │   └── windows.css     Windows Fluent Design 风格
│   ├── utils/              前端工具函数
│   ├── App.vue             根组件
│   └── main.ts             前端入口
├── package.json            Node.js 依赖
└── README.md               项目说明
```
