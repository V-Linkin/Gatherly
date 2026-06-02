# Archiver (拾屿) — Agent 指南

## 项目概述

macOS 本地跨平台内容归档器。用户粘贴链接，应用自动解析并保存内容到本地。

- **技术栈**: Swift 6.0, SwiftUI, GRDB 7 (SQLite + FTS5), macOS 14.0+
- **构建**: XcodeGen (`xcodegen generate`) → `.xcodeproj`
- **语言**: 用户使用中文交流

## 构建与运行

```bash
xcodegen generate
xcodebuild build -project Archiver.xcodeproj -scheme Archiver -destination 'platform=macOS'
```

一键打包+上传 Release：

```bash
./scripts/build_release.sh [version]    # 不传版本号则自动读取 Info.plist
```

## 项目结构

```
App/                    应用入口 + 全局状态
Models/                 数据模型
  └── Enums/            枚举定义（平台/状态/类型）
Database/               GRDB 数据库层 + Repos
Parsers/                平台解析器 (BaseParser 基类 + 10个实现)
Services/               导入/备份/更新服务
Utilities/              工具类 (BrowserDetector, URLNormalizer, JSWebLoader, MediaExporter 等)
Views/                  SwiftUI 视图层
  ├── Home/             首页
  ├── Platform/         平台分类 + 文件夹
  ├── Item/             内容详情 + 编辑
  ├── Search/           搜索结果
  ├── Trash/            回收站
  ├── Settings/         设置
  └── Components/       通用组件 (NavDebounce 防抖, PlaceholderTextEditor, MarkdownEditor 等)
Tests/                  单元测试
scripts/                打包/发布脚本
docs/                   产品规格 + 设计文档
```

## 关键约定

- **Parser 继承**: `BilibiliParser` 和 `XParser` 继承 `BaseParser`（提供公共下载/HTML 工具方法），其余解析器直接实现 `ContentParser` 协议
- **ParsedContent 初始化**: 使用命名参数 (title, body, author, coverURL, imageURLs, platformContentID)
- **@MainActor**: Swift 6 并发安全 — `BrowserDetector`、`ImportService`、`UpdateChecker`、`FilePicker`、`PlatformRouter`、`JSWebLoader` 均标记了 `@MainActor`
- **XcodeGen**: 不要直接编辑 `.xcodeproj`，修改 `project.yml` 后运行 `xcodegen generate`
- **UserDefaults**: 浏览器选择存储在 `selectedBrowserBundleIdentifier` 键
- **自定义平台匹配**: `ImportService.findMatchingCustomPlatform` 和 `NewCustomPlatformSheet.autoAssignUncategorized` 均使用大小写不敏感比较（`caseInsensitiveCompare`），用户创建 "youtube" 平台可自动匹配 "YouTube" 检测结果
- **多选批量操作**: `PlatformView` 和 `CustomPlatformContentView` 支持右键菜单"多选"进入批量模式，工具栏显示已选数量 + 移动/删除/取消。`MoveToPlatformSheet` 新增 `itemIDs: [UUID]` 参数支持批量移动。首页最近导入卡片右键支持"不显示"（UserDefaults 存储隐藏 ID）和"删除"（移入回收站）
- **DMG 命名**: 使用 `build_release.sh` 脚本打包，文件名固定为 `Archiver_v{version}.dmg`（英文名，避免中文丢失）
- **请求频率控制**: 豆瓣等有反爬的平台，`DoubanParser` 内置了 actor-based 请求间隔限制（2秒），新增平台需评估是否需要类似机制
- **导航防抖**: `NavDebounce`（Views/Components/DebounceHelper.swift）用于防止双击重复导航，列表页点击事件需调用 `NavDebounce.shared.canNavigate()` 判断
- **图片缓存**: `ItemDetailView` 中 `bodyImageCache` 使用 `@State` 而非 `let`，确保跨视图重建时缓存实例不变（`AsyncImageView` 网络加载的图片需与 `openBodyViewer` 共享同一缓存）
- **编辑退出确认**: `EditItemView` 记录打开时的初始值（标题/正文/作者/备注）+ 追踪新增/删除的媒体文件，通过 `hasChanges` 计算属性检测变更。点"取消"时有变化弹确认框（"放弃修改？"），无变化直接退出。`removedAssetIDs` 延迟在保存时统一处理文件删除。
- **占位文本框**: `PlaceholderTextEditor`（Views/Components/PlaceholderTextEditor.swift）用 `NSViewRepresentable` 包装自定义 `PlaceholderTextView`（NSTextView 子类），通过重写 `setMarkedText`/`unmarkText` 支持中文输入法组合输入时立即隐藏占位符（避免拼音候选文字与占位符重叠）。占位符使用 `PassthroughLabel`（NSTextField 覆盖层，`hitTest` 返回 nil 实现点击穿透）。`PassthroughScrollView` 在内容到达边界时将滚轮事件传递给父视图。首页粘贴框使用 `NoScrollTextEditor`（隐藏滚动条）。
- **豆瓣影评解析**: 服务端返回反爬挑战页（JS proof-of-work），HTTP 请求无法获取真实内容。`DoubanParser` 通过 WKWebView 解决挑战后提取内容，合并时优先使用 webview 结果（需排除模板代码 `{{=`）。作者提取：JSON-LD `author.name` → `data-author` 属性 → `<header class="main-hd">` 区域匹配 → 全页 people 链接扫描。封面：从 JSON-LD `itemReviewed.image` 直接获取电影海报，不依赖 subject 页面。正文：`extractNestedDivContent` 追踪 `<div>` 嵌套深度提取完整内容（解决正则截断），正文图片通过 `extractReviewImageURLs` 提取并下载。
- **媒体另存为**: `MediaExporter` 工具类负责命名生成和文件导出，支持右键单个导出和工具栏批量导出。单个导出命名：`{平台名}_{文件夹}_{作者}_{序号}_{日期}.{扩展名}`，无文件夹时跳过该段。批量导出时自动创建子文件夹 `{自定义平台名}_{作者}_{日期}`，媒体文件放入其中。`ExportPickerSheet` 用于批量导出时的媒体类型选择（媒体区域/正文图片/全部）。
- **图片复制**: 右键菜单支持复制图片到系统剪贴板（`NSPasteboard.writeObjects`），媒体区域和正文图片均支持。
- **抖音解析**: `DouyinParser` 使用移动端 User-Agent 获取页面，从 `window._ROUTER_DATA` 提取数据（路径：`loaderData.note_(id)/page` 或 `video_(id)/page`）。通过 `aweme_type` 区分内容类型（0=视频, 2=图文）。图文笔记提取 `images[].url_list[0]` 作为图片列表，封面与首图按 URL 去重；视频笔记提取 `video.play_addr.url_list`，自动将 `/playwm/` 替换为 `/play/` 去除水印。标题优先使用 `title` 字段，无则从 `desc` 去掉 `#话题` 后截取前50字。
- **微博 AJAX API**: 微博移动页面和桌面页面均有严格反爬验证（Sina Visitor System），WKWebView 无法通过。`WeiboParser` 优先使用 `m.weibo.cn/statuses/show?id=` AJAX 接口（需 `X-Requested-With: XMLHttpRequest` 请求头），直接返回 JSON 数据，包含正文、作者、图片列表。兜底使用 HTML `render_data` 解析。
- **小红书解析**: `XiaohongshuParser` 优先使用 `URLSession`（移动端 User-Agent）直接获取 HTML 并解析 `__INITIAL_STATE__` 数据，支持视频下载（`note.video.media.stream`，h264 优先）。图片去水印：直接使用 image 对象的 `fileId` 字段构造 `sns-na-i1.xhscdn.com` 无水印 URL（`fileId` 可能含斜杠前缀如 `notes_uhdr/xxx`，不能从 URL 路径截取）。封面从 `normalNotePreloadData` 获取，与首图按 `fileId` 去重。HTTP 失败时降级 WKWebView（`JSWebLoader`），优先从 `__INITIAL_STATE__` 提取（与 HTTP 路径对齐），兜底从 DOM 提取可见图片。
- **酷安镜像站解析**: `CoolapkParser` 优先使用 `coolapk1s.com` 镜像站绕过酷安反爬（原站返回扫码挑战页）。镜像站使用 Next.js SSR，`__NEXT_DATA__` JSON 包含完整 feed 数据（标题/正文/作者/图片列表）。图片通过 `image.coolapk1s.com/proxy?url=` 代理访问绕过防盗链。降级顺序：镜像站 -> 原站 HTTP -> WKWebView。

- **X 解析器封面去重**: `XParser` 封面逻辑：视频推文优先用 `thumbnail_url` 作为封面，图片推文用首图（首图与封面相同时从 `imageURLs` 移除避免重复），纯文字兜底用头像。
- **独立窗口查看器**: `ViewerWindowManager`（Utilities/ViewerWindowManager.swift）单例管理图片/视频查看器 NSWindow。图片点击正文或媒体区域打开 `ImageViewerView`（白色背景，保留缩放/拖拽/导航/键盘快捷键），视频点击打开 `VideoViewerView`（AVPlayerView 自动播放）。窗口无标题栏但保留交通灯，支持多窗口同时打开方便图片对比，ESC 关闭窗口（事件被消费不传递到主 app）。视频窗口按原始宽高比自动调整大小（最大 720×540）。窗口尺寸通过 UserDefaults 持久化，最小 400×300。媒体轮播中视频显示 `VideoThumbnailView`（封面图 + 播放按钮），详情页内联 `VideoPlayerView`。
- **Sheet 状态传递**: `.sheet(isPresented:)` 闭包中无法可靠读取同一 action 设置的 `@State` 变量（SwiftUI 重新渲染时状态丢失，sheet 内容为空）。需要传递 item ID 时，改用 `.sheet(item:)` 并定义 `Identifiable` 包装结构。多选移动使用 `showMoveToPlatform` + `isPresented` binding（多选路径不依赖单 item 状态）。

## 支持平台

抖音 · 小红书 · 酷安 · B站 · GitHub · YouTube · X(Twitter) · 微博 · 知乎 · 豆瓣

## 深入文档

| 文档 | 内容 |
|------|------|
| `docs/PRODUCT_SPEC.md` | 完整产品规格 |
| `docs/superpowers/specs/` | 功能设计文档 |
| `docs/superpowers/plans/` | 实现计划 |

- **使用帮助**: 设置页「关于」区块包含「使用帮助」和「GitHub」链接（同一行）。点击使用帮助弹出 `HelpView` sheet，内容分 6 个可展开/收缩的区块（快速入门、支持平台、内容整理、媒体导出、备份还原、常见问题），每个条目默认折叠，点击展开。
- **自动更新**: `UpdateChecker` 通过 GitHub API 检查新版本，下载 DMG 到临时目录，挂载后用 `install_update.sh`（Resources/）脚本 ditto 替换 `/Applications` 中的旧版本并重启。app 不在 `/Applications` 时回退为打开 DMG 让用户手动安装。设置页显示下载进度条，完成后弹窗确认安装。启动时检查是否存在已下载但未安装的 DMG。`UpdateStatus` 枚举包含 `.downloading(progress:)` 和 `.downloaded(dmgPath:version:)` 两个额外状态。

## 已知问题（待修复）

1. **微博短链解析失败** — `WeiboParser` 的 `extractWeiboID` 不支持 `t.cn` 短链格式。已支持 `weibo.com/UID/POSTID` 格式。微博解析优先使用 AJAX API（`m.weibo.cn/statuses/show`）绕过反爬验证，兜底使用 HTML `render_data` 解析。

