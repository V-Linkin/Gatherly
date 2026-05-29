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
Models/                 数据模型 + 枚举
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
  └── Components/       通用组件
Tests/                  单元测试
scripts/                打包/发布脚本
docs/                   产品规格 + 设计文档
```

## 关键约定

- **Parser 继承**: 所有 Parser 继承 `BaseParser`，覆写方法必须加 `override`
- **ParsedContent 初始化**: 使用命名参数 (title, body, author, coverURL, imageURLs, platformContentID)
- **@MainActor**: `BrowserDetector.shared` 和 `ImportService.shared` 需要 `@MainActor` 注解 (Swift 6 并发安全)
- **XcodeGen**: 不要直接编辑 `.xcodeproj`，修改 `project.yml` 后运行 `xcodegen generate`
- **UserDefaults**: 浏览器选择存储在 `selectedBrowserBundleIdentifier` 键
- **DMG 命名**: 使用 `build_release.sh` 脚本打包，文件名固定为 `Archiver_v{version}.dmg`（英文名，避免中文丢失）

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
2. **微博短链解析失败** — `WeiboParser` 的 `extractWeiboID` 仅匹配 `weibo.com/status/`、`m.weibo.cn/detail/`、`m.weibo.cn/status/` 三种格式，不支持 `t.cn` 短链和 `weibo.com/u/UID/status/ID` 格式。
3. **豆瓣影评正文图片未提取** — `DoubanParser` 影评页面的正文图片（`<img>` 标签）在 JS 提取时被 `innerText` 忽略，导致正文只保留文字。封面已修复（JS 优先 `.subject-img img` 等海报选择器，Swift 兜底从 subject 页面获取 `og:image`）。
