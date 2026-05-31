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
Utilities/              工具类 (BrowserDetector, URLNormalizer, ZhihuWebLoader 等)
Views/                  SwiftUI 视图层
  ├── Home/             首页
  ├── Platform/         平台分类 + 文件夹
  ├── Item/             内容详情 + 编辑
  ├── Search/           搜索结果
  ├── Trash/            回收站
  ├── Settings/         设置
  └── Components/       通用组件 (NavDebounce 防抖, PlaceholderTextEditor 等)
Tests/                  单元测试
scripts/                打包/发布脚本
docs/                   产品规格 + 设计文档
```

## 关键约定

- **Parser 继承**: `BilibiliParser` 和 `XParser` 继承 `BaseParser`（提供公共下载/HTML 工具方法），其余解析器直接实现 `ContentParser` 协议
- **ParsedContent 初始化**: 使用命名参数 (title, body, author, coverURL, imageURLs, platformContentID)
- **@MainActor**: Swift 6 并发安全 — `BrowserDetector`、`ImportService`、`UpdateChecker`、`FilePicker`、`PlatformRouter`、`ZhihuWebLoader` 均标记了 `@MainActor`
- **XcodeGen**: 不要直接编辑 `.xcodeproj`，修改 `project.yml` 后运行 `xcodegen generate`
- **UserDefaults**: 浏览器选择存储在 `selectedBrowserBundleIdentifier` 键
- **DMG 命名**: 使用 `build_release.sh` 脚本打包，文件名固定为 `Archiver_v{version}.dmg`（英文名，避免中文丢失）
- **请求频率控制**: 豆瓣等有反爬的平台，`DoubanParser` 内置了 actor-based 请求间隔限制（2秒），新增平台需评估是否需要类似机制
- **导航防抖**: `NavDebounce`（Views/Components/DebounceHelper.swift）用于防止双击重复导航，列表页点击事件需调用 `NavDebounce.shared.canNavigate()` 判断
- **图片缓存**: `ItemDetailView` 中 `bodyImageCache` 使用 `@State` 而非 `let`，确保跨视图重建时缓存实例不变（`AsyncImageView` 网络加载的图片需与 `openBodyViewer` 共享同一缓存）
- **占位文本框**: `PlaceholderTextEditor`（Views/Components/PlaceholderTextEditor.swift）用 `NSViewRepresentable` 包装自定义 `PlaceholderNSTextView`，通过 `draw(_:)` 原生绘制占位文字，确保与光标精确对齐。`PassthroughLabel` 子类重写 `hitTest` 返回 nil，使点击穿透到 NSTextView。
- **豆瓣影评解析**: 服务端返回反爬挑战页（JS proof-of-work），HTTP 请求无法获取真实内容。`DoubanParser` 通过 WKWebView 解决挑战后提取内容，合并时优先使用 webview 结果（需排除模板代码 `{{=`）。封面始终从 subject 页面获取电影海报。
- **微博 AJAX API**: 微博移动页面和桌面页面均有严格反爬验证（Sina Visitor System），WKWebView 无法通过。`WeiboParser` 优先使用 `m.weibo.cn/statuses/show?id=` AJAX 接口（需 `X-Requested-With: XMLHttpRequest` 请求头），直接返回 JSON 数据，包含正文、作者、图片列表。兜底使用 HTML `render_data` 解析。

## 支持平台

抖音 · 小红书 · 酷安 · B站 · GitHub · YouTube · X(Twitter) · 微博 · 知乎 · 豆瓣

## 深入文档

| 文档 | 内容 |
|------|------|
| `docs/PRODUCT_SPEC.md` | 完整产品规格 |
| `docs/superpowers/specs/` | 功能设计文档 |
| `docs/superpowers/plans/` | 实现计划 |

## 已知问题（待修复）

1. **酷安网页版反爬严格** — `CoolapkParser` 通过 HTTP 请求获取的页面不包含实际内容（返回"请用酷安APP扫码"提示页），`__INITIAL_STATE__` 和 OG tags 均不存在。当前仅能提取基础 meta 信息。需要 WKWebView 或 Playwright 等方案才能获取完整内容。
2. **微博短链解析失败** — `WeiboParser` 的 `extractWeiboID` 不支持 `t.cn` 短链格式。已支持 `weibo.com/UID/POSTID` 格式。微博解析优先使用 AJAX API（`m.weibo.cn/statuses/show`）绕过反爬验证，兜底使用 HTML `render_data` 解析。
3. **豆瓣影评正文图片未提取** — `DoubanParser` 影评正文的 `<img>` 标签被 `innerText` 忽略，正文只保留文字。`MarkdownView` 已支持渲染 `![alt](url)` 格式（含本地缓存优先、图片查看器），但解析器尚未将图片嵌入正文。封面已修复（review 页面始终从 subject 页面获取电影海报，兜底 `og:image`）。正文区域已恢复为完整显示（移除了固定高度滚动框），备注框移至正文上方并支持实时编辑保存。
