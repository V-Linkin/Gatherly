# Archiver — macOS 本地跨平台内容归档器

## 产品方案 + 信息架构 + 技术架构 + 数据模型 + MVP 规划

---

# 一、产品定位

**一句话定位**：面向个人用户的 macOS 本地跨平台内容归档器 + 搜索库。

**核心价值**：
- 用户主动粘贴各平台内容链接，App 自动解析并保存为本地可长期查看、可搜索、可整理的私人资料库。
- 即使原平台内容被删除，已归档内容仍可本地查看。

**不做什么**：
- 不做社交账号同步（不登录、不OAuth、不抓取用户主页）
- 不做多人协作、权限系统
- 不做云端同步（架构预留）
- 不做自动备份（架构预留）

---

# 二、用户流程

## 核心流程：粘贴并保存

```
用户打开 App
    ↓
首页显示「粘贴并保存」输入框
    ↓
用户粘贴一条链接 → 点击「保存」
    ↓
系统识别平台（抖音/小红书/酷安/B站）
    ↓
┌─ 识别成功 → 启动后台解析任务 → 显示进度条
│     ↓
│   解析成功 → 显示成功提示 → 内容进入对应平台 + 「待整理」状态
│   解析失败 → 显示失败提示 → 保留原始记录（链接+平台+时间）
│
└─ 未识别平台 → 显示「暂不支持该平台」提示
```

**每步反馈**：
1. 粘贴链接后，输入框下方实时显示识别到的平台图标
2. 点击保存后，显示轻量 toast 提示「正在解析…」
3. 解析完成后，toast 切换为「已归档到 抖音 > 待整理」或具体错误信息
4. 解析过程中首页「最近导入」区域出现占位卡片，解析完成后填充内容

## 整理流程

```
用户在任意分类/文件夹中浏览内容
    ↓
长按/右键内容卡片 → 弹出操作菜单
    ├─ 修改标题
    ├─ 修改备注
    ├─ 修改状态（收藏/灵感/待整理/已归档）
    ├─ 移动到文件夹
    ├─ 删除 → 进入回收站
    └─ 彻底删除
```

---

# 三、信息架构

```
Archiver
├── 首页
│   ├── 全局搜索框
│   ├── 粘贴并保存输入框
│   ├── 最近导入（最近10条）
│   ├── 平台快捷入口（抖音/小红书/酷安/B站）
│   └── 文件夹入口（最近使用的文件夹）
│
├── 平台分类（侧边栏/Tab）
│   ├── 抖音
│   │   ├── 收藏
│   │   ├── 灵感
│   │   ├── 待整理（默认入口）
│   │   ├── 已归档
│   │   └── 文件夹（二级结构）
│   ├── 小红书
│   │   └── （同上）
│   ├── 酷安
│   │   └── （同上）
│   └── B站
│       └── （同上）
│
├── 搜索结果页
│   ├── 搜索框 + 筛选器
│   ├── 结果列表（标题+正文高亮）
│   └── 按平台/状态/类型筛选
│
├── 内容详情页
│   ├── 媒体展示区
│   ├── 元信息区（标题/作者/平台/时间/链接）
│   ├── 正文区
│   ├── 备注区
│   └── 操作按钮（编辑/移动/删除）
│
├── 回收站
│   ├── 已删除内容列表
│   ├── 恢复操作
│   └── 彻底删除操作
│
└── 设置页
    ├── 存储管理（已用空间）
    ├── 默认导入平台设置
    └── 关于/版本信息
```

---

# 四、页面设计

## 4.1 首页

**页面目标**：核心导入入口 + 快速浏览最近内容

**布局**：
```
┌─────────────────────────────────────────────────┐
│  🔍 全局搜索框                                    │
├─────────────────────────────────────────────────┤
│  ┌───────────────────────────────────┐ [保存]    │
│  │ 粘贴链接到这里...                     │           │
│  └───────────────────────────────────┘           │
│  📱 识别到: 小红书                                │
├─────────────────────────────────────────────────┤
│  最近导入                                         │
│  ┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐           │
│  │封面图 │ │封面图 │ │封面图 │ │封面图 │           │
│  │标题   │ │标题   │ │标题   │ │标题   │           │
│  │抖音   │ │小红书 │ │B站   │ │酷安   │           │
│  └──────┘ └──────┘ └──────┘ └──────┘           │
├─────────────────────────────────────────────────┤
│  平台入口                                         │
│  [抖音 🎵] [小红书 📕] [酷安 📱] [B站 📺]       │
├─────────────────────────────────────────────────┤
│  我的文件夹                                       │
│  📂 科技数码  📂 设计灵感  📂 旅行攻略            │
└─────────────────────────────────────────────────┘
```

**核心交互**：
- 输入框支持 `Cmd+V` 粘贴自动填充
- 粘贴后实时显示识别到的平台图标（100ms内响应）
- 点击保存后，输入框清空，内容出现在「最近导入」第一位
- 点击平台图标进入对应平台分类页

**空状态**：「还没有内容，粘贴一条链接开始归档吧」

---

## 4.2 平台分类页

**页面目标**：浏览某个平台下所有已归档内容

**布局**：
```
┌─────────────────────────────────────────────────┐
│  ← 抖音                           [列表|网格]    │
├─────────────────────────────────────────────────┤
│  [收藏] [灵感] [待整理(3)] [已归档] [全部]        │
├─────────────────────────────────────────────────┤
│  📂 科技数码(5)  📂 生活技巧(3)  [+ 新建文件夹]   │
├─────────────────────────────────────────────────┤
│  状态栏: 共 42 条内容 · 3 张图片 · 2 个视频       │
├─────────────────────────────────────────────────┤
│  ┌──────────┐ ┌──────────┐ ┌──────────┐        │
│  │ 封面图    │ │ 封面图    │ │ 封面图    │        │
│  │ 标题      │ │ 标题      │ │ 标题      │        │
│  │ 作者·时间 │ │ 作者·时间 │ │ 作者·时间 │        │
│  │ ⚠️媒体未完整│ │          │ │ 🎬视频    │        │
│  └──────────┘ └──────────┘ └──────────┘        │
│  ┌──────────┐ ┌──────────┐                      │
│  │ ...       │ │ ...       │                      │
│  └──────────┘ └──────────┘                      │
└─────────────────────────────────────────────────┘
```

**核心交互**：
- 顶部 Tab 切换状态分类
- 文件夹区域可折叠展开
- 支持列表/网格视图切换
- 右键/长按内容卡片弹出操作菜单

**空状态**：「抖音暂无内容，回到首页粘贴一条链接导入」

---

## 4.3 状态分类页（独立视图）

**页面目标**：跨平台查看某个状态下的所有内容

**与平台分类页的区别**：此处按状态聚合所有平台的内容，侧边栏显示平台来源。

---

## 4.4 文件夹页

**页面目标**：浏览某个具体文件夹下的内容

**布局**：
```
┌─────────────────────────────────────────────────┐
│  ← 抖音 > 待整理 > 📂 科技数码    [移动] [设置]  │
├─────────────────────────────────────────────────┤
│  📱 小红书/已归档 > 📂 旧笔记      ← 子文件夹    │
├─────────────────────────────────────────────────┤
│  共 5 条内容                                     │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐        │
│  │ ...       │ │ ...       │ │ ...       │        │
│  └──────────┘ └──────────┘ └──────────┘        │
└─────────────────────────────────────────────────┘
```

**核心交互**：
- 面包屑导航显示完整路径
- 支持拖拽内容到文件夹
- 支持新建/重命名/删除文件夹
- 支持移动文件夹到其他位置

---

## 4.5 内容详情页

**页面目标**：完整查看单条归档内容的所有信息

**布局**：
```
┌─────────────────────────────────────────────────┐
│  ← 返回                    [编辑] [移动] [删除]  │
├─────────────────────────────────────────────────┤
│                                                 │
│         ┌─────────────────────┐                 │
│         │                     │                 │
│         │    媒体内容区        │                 │
│         │   (图片轮播/视频)    │                 │
│         │                     │                 │
│         └─────────────────────┘                 │
│                                                 │
│  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ │
│                                                 │
│  标题: Flutter 开发完全指南                       │
│  作者: @科技小王子                               │
│  平台: 小红书  📕                                │
│  发布时间: 2025-03-15                           │
│  导入时间: 2025-05-27 14:30                     │
│  状态: 待整理                                    │
│  文件夹: /                                     │
│  原始链接: [查看原文](https://...)              │
│                                                 │
│  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ │
│                                                 │
│  正文:                                           │
│  今天分享一个 Flutter 开发的小技巧...              │
│                                                 │
│  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ │
│                                                 │
│  📝 备注:                                        │
│  [点击添加备注...]                               │
│                                                 │
└─────────────────────────────────────────────────┘
```

**核心交互**：
- 图片区域支持点击放大、左右滑动切换
- 视频区域支持播放/暂停/进度条
- 标题、正文、备注支持 inline 编辑（点击即编辑）
- 媒体未完整保存时显示 ⚠️ 标记和提示

---

## 4.6 搜索结果页

**页面目标**：全局搜索并展示匹配内容

**布局**：
```
┌─────────────────────────────────────────────────┐
│  🔍 Flutter                              [清除]  │
├─────────────────────────────────────────────────┤
│  筛选: [抖音▾] [状态▾] [类型▾] [排序: 最近▾]    │
├─────────────────────────────────────────────────┤
│  找到 12 条结果                                  │
├─────────────────────────────────────────────────┤
│  📕 小红书 · 待整理                              │
│  **Flutter** 开发完全指南                         │
│  今天分享一个 **Flutter** 开发的小技巧...          │
│  2025-05-27 导入                                │
│  ─────────────────────────────────────           │
│  🎵 抖音 · 收藏                                  │
│  **Flutter** 入门教程 #3                         │
│  新手必看的 **Flutter** 教程...                    │
│  2025-05-26 导入                                │
└─────────────────────────────────────────────────┘
```

**核心交互**：
- 搜索框支持实时输入搜索（debounce 300ms）
- 搜索结果标题和正文中的关键词高亮显示
- 筛选器支持多选组合
- 点击结果项进入详情页
- 支持按平台、状态、内容类型筛选
- 支持按导入时间或修改时间排序

---

## 4.7 回收站

**页面目标**：管理已删除内容，支持恢复或彻底删除

**布局**：
```
┌─────────────────────────────────────────────────┐
│  🗑️ 回收站                  [清空回收站]          │
├─────────────────────────────────────────────────┤
│  共 3 条内容 · 占用 15.2 MB                       │
│                                                 │
│  ┌──────────────────────────────────────────┐   │
│  │ 🎵 抖音 · 删除于 2025-05-27              │   │
│  │ 某条已删除的视频标题                       │   │
│  │                    [恢复] [彻底删除]       │   │
│  └──────────────────────────────────────────┘   │
│  ┌──────────────────────────────────────────┐   │
│  │ 📕 小红书 · 删除于 2025-05-26            │   │
│  │ 某条已删除的笔记标题                       │   │
│  │                    [恢复] [彻底删除]       │   │
│  └──────────────────────────────────────────┘   │
└─────────────────────────────────────────────────┘
```

**核心交互**：
- 恢复操作：将内容状态改回删除前的状态，恢复到原文件夹
- 彻底删除：删除数据库记录 + 删除本地媒体文件，不可恢复
- 清空回收站：批量彻底删除所有内容
- 30天自动清理（可配置）

---

## 4.8 设置页

**页面目标**：应用配置与存储管理

**布局**：
```
┌─────────────────────────────────────────────────┐
│  ⚙️ 设置                                        │
├─────────────────────────────────────────────────┤
│  存储管理                                        │
│  ├─ 已用空间: 2.3 GB                            │
│  ├─ 数据库: 15 MB                               │
│  ├─ 媒体文件: 2.28 GB                           │
│  └─ [清理缓存]                                  │
│                                                 │
│  导入设置                                        │
│  ├─ 默认状态: [待整理 ▾]                         │
│  └─ 自动保存视频: [开启]                         │
│                                                 │
│  回收站                                          │
│  ├─ 自动清理: [30天 ▾]                           │
│  └─ [立即清空]                                  │
│                                                 │
│  关于                                            │
│  ├─ 版本: 1.0.0                                 │
│  └─ 数据目录: ~/Documents/Archiver/              │
└─────────────────────────────────────────────────┘
```

---

# 五、功能模块

## 5.1 核心模块划分

```
Archiver
├── 📥 导入模块 (ImportModule)
│   ├── 链接识别器 (LinkRecognizer)
│   ├── 平台路由器 (PlatformRouter)
│   ├── 去重检查器 (Deduplicator)
│   └── 导入任务管理器 (ImportTaskManager)
│
├── 🔍 解析模块 (ParserModule)
│   ├── 抖音解析器 (DouyinParser)
│   ├── 小红书解析器 (XiaohongshuParser)
│   ├── 酷安解析器 (CoolapkParser)
│   ├── B站解析器 (BilibiliParser)
│   └── 媒体下载器 (MediaDownloader)
│
├── 💾 存储模块 (StorageModule)
│   ├── 数据库管理器 (DatabaseManager)
│   ├── 媒体文件管理器 (MediaFileManager)
│   └── 导出管理器 (ExportManager) [预留]
│
├── 🔎 搜索模块 (SearchModule)
│   ├── 全文搜索引擎 (FullTextSearchEngine)
│   └── 筛选器 (FilterEngine)
│
├── 🗂️ 整理模块 (OrganizeModule)
│   ├── 文件夹管理器 (FolderManager)
│   ├── 状态管理器 (StatusManager)
│   └── 回收站管理器 (TrashManager)
│
├── 🖼️ 展示模块 (DisplayModule)
│   ├── 媒体流视图 (MediaGridView)
│   ├── 文案列表视图 (TextListView)
│   └── 详情页 (DetailView)
│
└── ⚙️ 设置模块 (SettingsModule)
    └── 应用配置管理 (AppConfig)
```

## 5.2 模块依赖关系

```
UI层 (SwiftUI Views)
    ↓
ViewModel层 (@Observable)
    ↓
Service层 (各模块)
    ↓
Data层 (Database + FileSystem)
```

---

# 六、数据模型

## 6.1 核心实体

### Item（内容主体）

```swift
struct Item: Identifiable, Codable {
    let id: UUID                          // 全局唯一ID
    var title: String?                    // 标题
    var body: String?                     // 正文内容（纯文本或Markdown）
    var originalURL: String               // 原始链接
    var platform: Platform                // 平台枚举
    var platformContentID: String?        // 平台内内容ID（用于去重）
    var normalizedURL: String             // 标准化链接（用于去重）
    
    var author: String?                   // 作者
    var authorID: String?                 // 作者ID
    var publishDate: Date?                // 发布时间
    var importDate: Date                  // 导入时间
    var modifyDate: Date                  // 最后修改时间
    
    var contentStatus: ContentStatus      // 内容状态
    var archiveStatus: ArchiveStatus      // 归档状态（收藏/灵感/待整理/已归档）
    var mediaStatus: MediaStatus          // 媒体保存状态
    
    var coverAssetID: UUID?              // 封面图资产ID
    var folderID: UUID?                  // 所属文件夹ID
    
    var remark: String?                  // 用户备注
    var tags: [String]?                  // 标签（预留）
    
    // 扩展预留
    var isStarred: Bool                  // 是否收藏
    var metadata: [String: String]?      // 扩展元数据（JSON）
    var version: Int                     // 数据版本号（用于同步冲突检测）
    var deletedAt: Date?                 // 软删除时间
}
```

### Platform（平台）

```swift
enum Platform: String, Codable, CaseIterable {
    case douyin = "douyin"               // 抖音
    case xiaohongshu = "xiaohongshu"     // 小红书
    case coolapk = "coolapk"            // 酷安
    case bilibili = "bilibili"          // B站
    
    var displayName: String { ... }
    var icon: String { ... }             // SF Symbol名
    var color: Color { ... }             // 品牌色
}
```

### Folder（文件夹）

```swift
struct Folder: Identifiable, Codable {
    let id: UUID
    var name: String                      // 文件夹名称
    var parentID: UUID?                   // 父文件夹ID（nil=根目录）
    var platform: Platform                // 所属平台
    var createdAt: Date
    var sortOrder: Int                    // 排序权重
    
    // 最多二级：parentID 的 parentID 必须为 nil
}
```

### MediaAsset（媒体资产）

```swift
struct MediaAsset: Identifiable, Codable {
    let id: UUID
    var itemID: UUID                      // 所属内容ID
    var type: MediaType                   // 图片/视频/封面
    var localPath: String                 // 本地文件路径（相对于媒体根目录）
    var remoteURL: String?                // 原始远程URL
    var fileName: String                  // 本地文件名
    var fileSize: Int64                   // 文件大小（字节）
    var mimeType: String?                 // MIME类型
    var width: Int?                       // 图片/视频宽度
    var height: Int?                      // 图片/视频高度
    var duration: Double?                 // 视频时长（秒）
    var checksum: String?                 // 文件hash（SHA-256）
    var downloadStatus: DownloadStatus    // 下载状态
    var createdAt: Date
    
    // 扩展预留
    var thumbnailPath: String?            // 缩略图路径
    var metadata: [String: String]?       // 扩展元数据
}

enum MediaType: String, Codable {
    case image       // 内容图片
    case cover       // 封面图
    case video       // 视频
    case thumbnail   // 缩略图（自动生成）
}

enum DownloadStatus: String, Codable {
    case pending     // 等待下载
    case downloading // 下载中
    case completed   // 下载完成
    case failed      // 下载失败
    case skipped     // 已跳过（如视频太大）
}
```

### ContentStatus（内容状态）

```swift
enum ContentStatus: String, Codable {
    case normal          // 正常
    case parseFailed     // 解析失败
    case mediaIncomplete // 媒体未完整保存
    case sourceDeleted   // 原始内容已被删除
    case trashed         // 回收站中
}
```

### ArchiveStatus（归档状态）

```swift
enum ArchiveStatus: String, Codable {
    case favorite   // 收藏
    case inspiration // 灵感
    case pending    // 待整理（默认）
    case archived   // 已归档
}
```

### MediaStatus（媒体保存状态）

```swift
enum MediaStatus: String, Codable {
    case complete        // 完整保存（所有媒体都已下载）
    case partial         // 部分保存（图片完整，视频可能缺失）
    case failed          // 全部失败
    case textOnly        // 纯文本（无媒体）
}
```

### ImportTask（导入任务）

```swift
struct ImportTask: Identifiable, Codable {
    let id: UUID
    var originalURL: String
    var normalizedURL: String
    var platform: Platform?
    var status: TaskStatus
    var progress: Double                   // 0.0 ~ 1.0
    var errorMessage: String?
    var itemID: UUID?                      // 创建的Item ID
    var createdAt: Date
    var completedAt: Date?
    var retryCount: Int                    // 重试次数
}

enum TaskStatus: String, Codable {
    case pending       // 等待处理
    case recognizing   // 识别平台中
    case parsing       // 解析内容中
    case downloading   // 下载媒体中
    case completed     // 完成
    case failed        // 失败
}
```

### TrashRecord（回收站记录）

```swift
struct TrashRecord: Identifiable, Codable {
    let id: UUID
    var itemID: UUID                       // 关联的内容ID
    var deletedAt: Date                    // 删除时间
    var autoDeleteAt: Date                 // 自动彻底删除时间
    var originalFolderPath: UUID?          // 原文件夹ID（用于恢复）
    var originalArchiveStatus: ArchiveStatus // 原归档状态（用于恢复）
    var mediaPaths: [String]               // 关联的媒体文件路径（用于彻底删除）
}
```

## 6.2 数据关系图

```
Item (1) ──── (N) MediaAsset
  │                    │
  │                    └── type: cover/image/video
  │
  ├── folderID → Folder.id
  │
  ├── platform → Platform
  │
  ├── archiveStatus → ArchiveStatus
  │
  └── TrashRecord.itemID → Item.id (可选)
```

---

# 七、技术架构

## 7.1 技术选型

| 层级 | 技术方案 | 理由 |
|------|---------|------|
| 客户端框架 | **SwiftUI + AppKit** | 原生macOS体验，SwiftUI负责UI，AppKit补充高级控件 |
| 语言 | **Swift 5.9+** | 原生开发首选，类型安全，性能优秀 |
| 本地数据库 | **SQLite + GRDB.swift** | 轻量、成熟、支持FTS5全文搜索，无需额外依赖 |
| 全文搜索 | **SQLite FTS5** | 与数据库同引擎，无需额外索引，支持中文分词（via ICU） |
| 媒体下载 | **URLSession + async/await** | 原生网络库，支持并发下载，断点续传 |
| 图片处理 | **Kingfisher** | 图片下载+缓存+压缩，社区成熟 |
| 视频播放 | **AVKit (AVPlayerViewController)** | 原生视频播放，支持本地文件 |
| 异步任务 | **Swift Concurrency (async/await)** | 原生异步方案，结构化并发 |
| 日志 | **OSLog (os.log)** | 原生日志系统，性能好，Console.app可查看 |
| 配置管理 | **Codable + UserDefaults** | 轻量配置持久化 |

### 为什么选 GRDB + SQLite FTS5

- **GRDB.swift**：Swift 生态最成熟的 SQLite 封装，支持 Codable 自动映射、迁移、FTS5
- **FTS5**：SQLite 内置全文搜索引擎，支持中文（通过 ICU tokenizer），无需引入额外搜索引擎
- **单文件数据库**：便于未来的导出/备份/迁移
- **性能**：FTS5 对 10万条以内的数据搜索在毫秒级

## 7.2 存储方案

### 目录结构

```
~/Documents/Archiver/                    // 应用数据根目录
├── data/
│   └── archiver.db                      // SQLite 数据库文件
├── media/
│   ├── {item-uuid}/                     // 按内容ID分目录
│   │   ├── cover.jpg                    // 封面图
│   │   ├── image_001.jpg               // 内容图片
│   │   ├── image_002.jpg
│   │   ├── video.mp4                    // 视频文件
│   │   └── thumb_cover.jpg             // 缩略图
│   ├── {item-uuid-2}/
│   │   └── ...
│   └── ...
├── cache/                               // 临时缓存（可清理）
│   └── downloads/                       // 下载中的临时文件
└── exports/                             // 导出文件（预留）
```

### 数据库中媒体路径设计

```sql
-- MediaAsset 表中的路径均为相对路径
-- 相对于 ~/Documents/Archiver/media/
-- 例如: "a1b2c3d4-e5f6-7890-abcd-ef1234567890/cover.jpg"
```

### 数据库与文件联动规则

| 操作 | 数据库行为 | 文件系统行为 |
|------|-----------|-------------|
| 新增内容 | INSERT Item + MediaAsset | 创建目录，下载媒体文件 |
| 软删除 | 设置 Item.deletedAt + 创建 TrashRecord | **不删除文件** |
| 恢复 | 清除 Item.deletedAt + 删除 TrashRecord | **不操作文件** |
| 彻底删除 | DELETE Item + MediaAsset + TrashRecord | 删除整个 item 目录 |
| 清空回收站 | 批量彻底删除 | 批量删除目录 |
| 媒体重下载 | 更新 MediaAsset 的 downloadStatus | 重新下载覆盖 |

## 7.3 数据库设计

```sql
-- 内容表
CREATE TABLE items (
    id TEXT PRIMARY KEY,                  -- UUID
    title TEXT,
    body TEXT,
    original_url TEXT NOT NULL,
    platform TEXT NOT NULL,
    platform_content_id TEXT,
    normalized_url TEXT NOT NULL,
    author TEXT,
    author_id TEXT,
    publish_date REAL,                    -- Unix timestamp
    import_date REAL NOT NULL,
    modify_date REAL NOT NULL,
    content_status TEXT NOT NULL DEFAULT 'normal',
    archive_status TEXT NOT NULL DEFAULT 'pending',
    media_status TEXT NOT NULL DEFAULT 'textOnly',
    cover_asset_id TEXT,
    folder_id TEXT,
    remark TEXT,
    is_starred INTEGER NOT NULL DEFAULT 0,
    metadata TEXT,                        -- JSON
    version INTEGER NOT NULL DEFAULT 1,
    deleted_at REAL
);

CREATE INDEX idx_items_platform ON items(platform);
CREATE INDEX idx_items_archive_status ON items(archive_status);
CREATE INDEX idx_items_folder ON items(folder_id);
CREATE INDEX idx_items_normalized_url ON items(normalized_url);
CREATE INDEX idx_items_import_date ON items(import_date DESC);
CREATE INDEX idx_items_deleted_at ON items(deleted_at);

-- FTS5 全文搜索表
CREATE VIRTUAL TABLE items_fts USING fts5(
    title,
    body,
    content=items,
    content_rowid=rowid,
    tokenize='unicode61'                  -- 基础分词，后续可切换为ICU
);

-- 媒体资产表
CREATE TABLE media_assets (
    id TEXT PRIMARY KEY,
    item_id TEXT NOT NULL REFERENCES items(id) ON DELETE CASCADE,
    type TEXT NOT NULL,
    local_path TEXT,
    remote_url TEXT,
    file_name TEXT NOT NULL,
    file_size INTEGER DEFAULT 0,
    mime_type TEXT,
    width INTEGER,
    height INTEGER,
    duration REAL,
    checksum TEXT,
    download_status TEXT NOT NULL DEFAULT 'pending',
    thumbnail_path TEXT,
    metadata TEXT,
    created_at REAL NOT NULL
);

CREATE INDEX idx_media_item ON media_assets(item_id);
CREATE INDEX idx_media_type ON media_assets(type);

-- 文件夹表
CREATE TABLE folders (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    parent_id TEXT REFERENCES folders(id) ON DELETE CASCADE,
    platform TEXT NOT NULL,
    created_at REAL NOT NULL,
    sort_order INTEGER NOT NULL DEFAULT 0
);

CREATE INDEX idx_folders_platform ON folders(platform);
CREATE INDEX idx_folders_parent ON folders(parent_id);

-- 回收站表
CREATE TABLE trash_records (
    id TEXT PRIMARY KEY,
    item_id TEXT NOT NULL REFERENCES items(id) ON DELETE CASCADE,
    deleted_at REAL NOT NULL,
    auto_delete_at REAL NOT NULL,
    original_folder_id TEXT,
    original_archive_status TEXT NOT NULL,
    media_paths TEXT                      -- JSON array of paths
);

CREATE INDEX idx_trash_deleted_at ON trash_records(deleted_at);

-- 导入任务表
CREATE TABLE import_tasks (
    id TEXT PRIMARY KEY,
    original_url TEXT NOT NULL,
    normalized_url TEXT NOT NULL,
    platform TEXT,
    status TEXT NOT NULL DEFAULT 'pending',
    progress REAL NOT NULL DEFAULT 0,
    error_message TEXT,
    item_id TEXT REFERENCES items(id),
    created_at REAL NOT NULL,
    completed_at REAL,
    retry_count INTEGER NOT NULL DEFAULT 0
);

CREATE INDEX idx_tasks_status ON import_tasks(status);
CREATE INDEX idx_tasks_created ON import_tasks(created_at DESC);
```

## 7.4 全文搜索实现

```sql
-- 搜索示例：搜索包含 "Flutter" 的内容
SELECT items.*, 
       snippet(items_fts, 0, '<mark>', '</mark>', '...', 64) as title_highlighted,
       snippet(items_fts, 1, '<mark>', '</mark>', '...', 64) as body_highlighted,
       rank
FROM items_fts
JOIN items ON items.rowid = items_fts.rowid
WHERE items_fts MATCH 'Flutter'
  AND items.deleted_at IS NULL
ORDER BY rank
LIMIT 50;
```

**搜索特性**：
- 支持关键词高亮（`snippet()` 函数）
- 支持按平台/状态筛选（WHERE 条件）
- 支持按相关性/时间排序
- 搜索结果在 10万条数据内 < 50ms

## 7.5 平台解析模块架构

```
ParserModule
├── protocol ContentParser {
│     func canParse(url: URL) -> Bool
│     func extractContentID(from url: URL) -> String?
│     func normalizeURL(_ url: String) -> String
│     func parse(url: URL) async throws -> ParsedContent
│     func downloadMedia(content: ParsedContent) async throws -> [MediaAsset]
│ }
│
├── struct ParsedContent {
│     let title: String?
│     let body: String?
│     let author: String?
│     let publishDate: Date?
│     let coverURL: String?
│     let imageURLs: [String]
│     let videoURL: String?
│     let platformContentID: String?
│     let rawMetadata: [String: Any]
│ }
│
├── DouyinParser: ContentParser
├── XiaohongshuParser: ContentParser
├── CoolapkParser: ContentParser
└── BilibiliParser: ContentParser
```

**扩展新平台的步骤**：
1. 新增 `Platform` 枚举值
2. 实现 `ContentParser` 协议
3. 在 `PlatformRouter` 中注册
4. 完成

## 7.6 去重机制

### 标准化链接处理

```
原始链接: https://www.xiaohongshu.com/explore/abc123?xsec_token=xxx&xsec_source=pc_search
    ↓ 提取平台 + 内容ID
标准化: xiaohongshu://explore/abc123
```

**各平台标准化规则**：
- **抖音**：提取视频ID → `douyin://video/{video_id}`
- **小红书**：提取笔记ID → `xiaohongshu://explore/{note_id}`
- **酷安**：提取动态ID → `coolapk://feed/{feed_id}`
- **B站**：提取视频ID → `bilibili://video/{bvid}`

### 去重流程

```
输入链接
    ↓
识别平台 → 提取内容ID
    ↓
查询: SELECT id FROM items 
      WHERE platform = ? AND platform_content_id = ?
    ↓
┌─ 找到匹配 → 返回「该内容已存在于 [平台/状态/文件夹]」
│             提供操作选项: [查看已有] [更新媒体] [取消]
│
└─ 未找到 → 继续解析流程
```

### 去重提示文案

- **已存在**：「这条内容已经归档过了，保存在 抖音 > 待整理 中。」
- **操作选项**：「查看已有内容 / 更新媒体文件 / 取消」

## 7.7 异步任务设计

```swift
actor ImportTaskManager {
    // 任务队列（最多3个并发解析任务）
    private let maxConcurrentTasks = 3
    private var runningTasks: [UUID: Task<Void, Never>] = [:]
    
    func startImport(url: String) async {
        // 1. 创建 ImportTask 记录
        // 2. 识别平台
        // 3. 去重检查
        // 4. 启动解析任务（并发限制）
        // 5. 下载媒体文件（并发限制）
        // 6. 创建 Item 记录
        // 7. 更新 ImportTask 状态
    }
    
    func cancelTask(id: UUID) { ... }
    func retryTask(id: UUID) { ... }
}
```

**任务状态流转**：
```
pending → recognizing → parsing → downloading → completed
                                    ↓
                                  failed (可重试)
```

## 7.8 日志与错误追踪

```swift
// 使用 OSLog
import os

let logger = Logger(subsystem: "com.archiver.app", category: "Import")

// 日志级别
logger.info("开始解析: \(url)")           // info
logger.warning("视频下载失败: \(error)")   // warning
logger.error("解析完全失败: \(error)")     // error

// 错误追踪
enum AppError: LocalizedError {
    case unsupportedPlatform(url: String)
    case parseFailed(url: String, reason: String)
    case mediaDownloadFailed(assetID: UUID, reason: String)
    case databaseError(underlying: Error)
    case duplicateContent(existingItemID: UUID)
}
```

---

# 八、内容展示

## 8.1 两种视图

### 媒体流视图（网格视图）
- **适合场景**：浏览图片内容、封面、视频预览
- **布局**：3列瀑布流网格
- **列表项显示**：封面图 + 平台图标 + 标题（单行截断）+ 媒体类型标记
- **切换方式**：工具栏网格/列表切换按钮

### 文案列表视图（列表视图）
- **适合场景**：浏览文字内容、搜索结果、批量整理
- **布局**：单列列表
- **列表项显示**：平台图标 + 标题 + 正文摘要（2行）+ 作者 + 时间 + 状态标签
- **切换方式**：同上

## 8.2 内容详情页布局

**顶部**：返回按钮 + 操作菜单（编辑/移动/删除）
**媒体区**：图片轮播（支持手势缩放）或视频播放器
**元信息区**：标题、作者、平台、时间、链接
**正文区**：完整正文内容
**备注区**：用户备注（可编辑）
**底部**：状态标签 + 文件夹路径

---

# 九、二次整理

## 9.1 删除交互

| 操作 | 交互 | 结果 |
|------|------|------|
| **删除** | 点击删除 → 确认弹窗「移入回收站？」→ 确认 | 软删除，进入回收站，可恢复 |
| **彻底删除** | 回收站中 → 点击彻底删除 → 确认弹窗「永久删除且不可恢复」→ 确认 | 硬删除，数据库记录+本地文件全部删除 |
| **恢复** | 回收站中 → 点击恢复 | 恢复到原文件夹和原状态 |

## 9.2 回收站数据结构

```swift
// 回收站保留完整的 Item 记录 + TrashRecord
// TrashRecord 记录：
// - 删除时间
// - 自动清理时间（默认30天后）
// - 原文件夹ID（恢复时用）
// - 原归档状态（恢复时用）
// - 关联媒体路径列表（彻底删除时清理文件）

// 回收站中的媒体文件不删除，保持原位
// 彻底删除时，读取 TrashRecord.mediaPaths，删除文件，再删数据库记录
```

## 9.3 避免层级迷失

- **面包屑导航**：始终显示完整路径（如 `抖音 > 待整理 > 科技数码`）
- **侧边栏高亮**：当前所在位置在侧边栏高亮显示
- **快速跳转**：面包屑每个层级可点击跳转
- **移动操作**：移动时弹出树状选择器，显示完整文件夹结构

---

# 十、异常处理

## 10.1 异常场景与处理

| 场景 | 处理方式 | 用户反馈 |
|------|---------|---------|
| 链接格式不合法 | 拒绝导入 | 「链接格式不正确，请检查后重试」 |
| 平台暂不支持 | 拒绝导入 | 「暂不支持该平台，目前支持：抖音、小红书、酷安、B站」 |
| 识别成功但解析失败 | 创建失败记录 | 「解析失败，已保存链接，可稍后重试」 |
| 图文成功但视频失败 | 创建记录，标记partial | 「内容已保存，但视频未能完整下载」 |
| 媒体下载中断 | 保留已下载部分，标记状态 | 「下载中断，已保存部分内容」 |
| 原始内容被删除 | 创建记录，标记sourceDeleted | 「原始内容可能已被删除，已保存元信息」 |
| 网络连接失败 | 排队等待重试 | 「网络连接失败，将在恢复网络后重试」 |
| 数据库写入失败 | 记录错误日志 | 「保存失败，请检查存储空间」 |

## 10.2 兜底策略

即使解析完全失败，也必须创建一条记录，最少保留：
- 原始链接
- 识别到的平台（或"未知平台"）
- 导入时间
- 失败状态
- 失败原因

用户可后续手动补充标题、正文、备注。

---

# 十一、MVP 范围

## 11.1 MVP 必须做（第一版）

- [x] 首页 + 粘贴并保存输入框
- [x] 四平台链接识别（抖音/小红书/酷安/B站）
- [x] 基础内容解析（标题/正文/作者/时间/封面）
- [x] 图片下载保存
- [x] SQLite 数据库 + FTS5 搜索
- [x] 全局搜索（标题+正文）+ 高亮
- [x] 平台分类浏览
- [x] 四种状态分类
- [x] 二级文件夹
- [x] 内容详情页
- [x] 修改标题/正文/备注
- [x] 修改状态/移动文件夹
- [x] 删除 → 回收站 → 恢复/彻底删除
- [x] 去重检查
- [x] 媒体流/文案列表双视图
- [x] 搜索筛选（平台/状态/排序）

## 11.2 第一版可以延后

- [ ] 视频完整保存（先做标记，不强制下载）
- [ ] 图片原图保存（先保存缩略图/中等质量）
- [ ] 搜索按内容类型筛选
- [ ] 批量操作（批量移动/删除）
- [ ] 导入进度详情页
- [ ] 快捷键支持

## 11.3 第二阶段建议新增

- [ ] 标签系统
- [ ] 智能分类建议
- [ ] 导出为 PDF/HTML
- [ ] 批量导入（导入剪贴板历史）
- [ ] 快捷指令（Shortcuts）集成
- [ ] Spotlight 搜索集成
- [ ] 本地备份与恢复
- [ ] 30天自动清理回收站

## 11.4 留接口不实现

- [ ] 云同步接口（数据模型预留 version 字段）
- [ ] 多设备同步（预留 device_id 字段）
- [ ] 导入/导出 API（预留 ExportManager）
- [ ] 插件系统（预留 Parser 协议）

---

# 十二、风险点与建议

## 12.1 技术风险

| 风险 | 影响 | 应对 |
|------|------|------|
| 平台反爬策略 | 解析失败率高 | 做好兜底，保留原始记录，支持手动重试 |
| 视频文件过大 | 存储空间不足 | 先做视频大小检测，超过阈值提示用户 |
| FTS5 中文分词 | 搜索不准确 | 初版用 unicode61，后续可切换 ICU tokenizer |
| 数据库迁移 | 升级后数据丢失 | 使用 GRDB 的 Migration 系统，版本化管理 |

## 12.2 产品风险

| 风险 | 影响 | 应对 |
|------|------|------|
| 解析成功率低 | 用户体验差 | 明确告知限制，提供手动编辑能力 |
| 媒体文件丢失 | 归档价值降低 | 做好校验，定期检查文件完整性 |
| 用户整理动力不足 | 数据堆积 | 默认「待整理」状态 + 整理提醒 |

## 12.3 开发建议

1. **先做核心链路**：粘贴 → 识别 → 解析 → 保存 → 搜索，跑通后再做整理功能
2. **先做小红书**：图文为主，解析相对简单，作为第一个平台验证架构
3. **数据库设计先行**：数据模型确定后再做 UI
4. **FTS5 早期集成**：搜索是核心价值，早期验证中文搜索效果
5. **用 SwiftData 还是 GRDB**：推荐 GRDB，更灵活，FTS5 支持更好，迁移更可控

---

# 十三、项目结构

```
Archiver/
├── App/
│   ├── ArchiverApp.swift              // App入口
│   └── ContentView.swift              // 主视图（导航）
│
├── Models/
│   ├── Item.swift
│   ├── Folder.swift
│   ├── MediaAsset.swift
│   ├── ImportTask.swift
│   ├── TrashRecord.swift
│   └── Enums/
│       ├── Platform.swift
│       ├── ContentStatus.swift
│       ├── ArchiveStatus.swift
│       └── MediaStatus.swift
│
├── Database/
│   ├── DatabaseManager.swift          // 数据库初始化/迁移
│   ├── ItemRepository.swift           // Item CRUD
│   ├── FolderRepository.swift         // Folder CRUD
│   ├── MediaRepository.swift          // MediaAsset CRUD
│   ├── TrashRepository.swift          // 回收站操作
│   ├── SearchRepository.swift         // FTS5 搜索
│   └── Migrations/                    // 数据库迁移
│       └── Migration_v1.swift
│
├── Services/
│   ├── ImportService.swift            // 导入流程编排
│   ├── DeduplicationService.swift     // 去重检查
│   ├── MediaDownloadService.swift     // 媒体下载
│   ├── MediaFileManager.swift         // 本地文件管理
│   └── ExportService.swift            // 导出（预留）
│
├── Parsers/
│   ├── ContentParser.swift            // 协议定义
│   ├── PlatformRouter.swift           // 平台路由
│   ├── DouyinParser.swift
│   ├── XiaohongshuParser.swift
│   ├── CoolapkParser.swift
│   └── BilibiliParser.swift
│
├── ViewModels/
│   ├── HomeViewModel.swift
│   ├── PlatformViewModel.swift
│   ├── ItemDetailViewModel.swift
│   ├── SearchViewModel.swift
│   ├── TrashViewModel.swift
│   └── SettingsViewModel.swift
│
├── Views/
│   ├── Home/
│   │   ├── HomeView.swift
│   │   ├── PasteInputView.swift
│   │   └── RecentItemsView.swift
│   ├── Platform/
│   │   ├── PlatformView.swift
│   │   ├── StatusTabView.swift
│   │   └── FolderTreeView.swift
│   ├── Item/
│   │   ├── ItemDetailView.swift
│   │   ├── MediaGalleryView.swift
│   │   ├── VideoPlayerView.swift
│   │   └── ItemEditView.swift
│   ├── Search/
│   │   ├── SearchView.swift
│   │   └── SearchFiltersView.swift
│   ├── Trash/
│   │   └── TrashView.swift
│   ├── Settings/
│   │   └── SettingsView.swift
│   └── Components/
│       ├── ItemCardView.swift
│       ├── PlatformBadge.swift
│       ├── StatusBadge.swift
│       ├── EmptyStateView.swift
│       └── ToastView.swift
│
├── Utilities/
│   ├── URLNormalizer.swift            // 链接标准化
│   ├── Logger.swift                   // 日志封装
│   └── Constants.swift                // 常量定义
│
└── Resources/
    ├── Assets.xcassets
    └── Archiver.xcdatamodeld          // 如需CoreData兼容
```

---

# 十四、用户流程图（文字版）

```
[打开App]
    │
    ├─→ [首页]
    │     │
    │     ├─→ [粘贴链接] → [识别平台] → [解析内容] → [下载媒体] → [保存成功]
    │     │                                                          │
    │     │                                                          ↓
    │     │                                               [显示在最近导入]
    │     │
    │     ├─→ [点击平台图标] → [平台分类页] → [点击内容] → [详情页]
    │     │
    │     ├─→ [点击搜索框] → [搜索结果页] → [点击结果] → [详情页]
    │     │
    │     └─→ [点击文件夹] → [文件夹页] → [点击内容] → [详情页]
    │
    └─→ [侧边栏导航]
          │
          ├─→ [平台] → [状态] → [文件夹] → [内容列表] → [详情页]
          ├─→ [回收站] → [恢复/彻底删除]
          └─→ [设置] → [存储管理/配置]
```

---

# 十五、关键交互细节

## 15.1 粘贴并保存

- **触发方式**：`Cmd+V` 在输入框聚焦时自动粘贴
- **识别反馈**：粘贴后 100ms 内在输入框下方显示平台图标和名称
- **保存反馈**：点击保存后，按钮变为 loading 状态，完成后 toast 提示
- **键盘快捷键**：`Enter` 键直接保存

## 15.2 搜索

- **实时搜索**：输入 debounce 300ms 后自动搜索
- **高亮**：搜索结果中匹配的关键词用黄色背景高亮
- **快捷键**：`Cmd+F` 聚焦搜索框，`Escape` 清除搜索

## 15.3 内容操作

- **右键菜单**：所有内容卡片支持右键弹出操作菜单
- **拖拽**：支持拖拽内容到文件夹
- **批量选择**：按住 `Shift` 或 `Command` 多选

## 15.4 空状态设计

| 页面 | 空状态文案 | 操作建议 |
|------|-----------|---------|
| 首页 | 「还没有内容，粘贴一条链接开始归档吧」 | 高亮输入框 |
| 平台分类 | 「抖音暂无内容」 | 返回首页导入 |
| 文件夹 | 「文件夹是空的，拖入内容或新建文件夹」 | 新建文件夹按钮 |
| 搜索 | 「没有找到相关内容」 | 建议修改搜索词 |
| 回收站 | 「回收站是空的」 | 无操作 |

---

# 十六、版本规划

| 阶段 | 时间 | 核心目标 |
|------|------|---------|
| MVP | 4-6周 | 跑通核心链路：粘贴→解析→保存→搜索→整理 |
| v1.1 | +2周 | 视频完整保存 + 批量操作 + 快捷键 |
| v1.2 | +2周 | 标签系统 + 智能分类 + 导出 |
| v2.0 | +4周 | 本地备份恢复 + Spotlight集成 + Shortcuts |

---

*文档版本: v1.0 | 最后更新: 2025-05-27*
