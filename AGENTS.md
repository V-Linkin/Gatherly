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

## 项目结构

```
App/                    应用入口 + 全局状态
Models/                 数据模型 + 枚举
Database/               GRDB 数据库层 + Repos
Parsers/                平台解析器 (BaseParser 基类 + 10个实现)
Services/               导入/备份/更新服务
Utilities/              工具类 (BrowserDetector, URLNormalizer 等)
Views/                  SwiftUI 视图层
  ├── Home/             首页
  ├── Platform/         平台分类 + 文件夹
  ├── Item/             内容详情 + 编辑
  ├── Search/           搜索结果
  ├── Trash/            回收站
  ├── Settings/         设置
  └── Components/       通用组件
```

## 关键约定

- **Parser 继承**: 所有 Parser 继承 `BaseParser`，覆写方法必须加 `override`
- **ParsedContent 初始化**: 使用命名参数 (title, body, author, coverURL, imageURLs, platformContentID)
- **@MainActor**: `BrowserDetector.shared` 和 `ImportService.shared` 需要 `@MainActor` 注解 (Swift 6 并发安全)
- **XcodeGen**: 不要直接编辑 `.xcodeproj`，修改 `project.yml` 后运行 `xcodegen generate`
- **UserDefaults**: 浏览器选择存储在 `selectedBrowserBundleIdentifier` 键

## 支持平台

抖音 · 小红书 · 酷安 · B站 · GitHub · YouTube · X(Twitter) · 微博 · 知乎 · 豆瓣

## 深入文档

| 文档 | 内容 |
|------|------|
| `docs/PRODUCT_SPEC.md` | 完整产品规格 |
| `docs/superpowers/specs/` | 功能设计文档 |
| `docs/superpowers/plans/` | 实现计划 |

## 已知问题（待修复）

1. **豆瓣影评封面未获取** — `DoubanParser` 的 webview JS 选择器 `.subject-cover img` / `.main-bd img` 未匹配到豆瓣影评页面的实际 DOM，需要检查页面结构后修正选择器
2. **豆瓣影评正文图片丢失** — 当前正文提取只取 `<p>` 标签的 `innerText`，图片 `<img>` 被忽略。需要在提取正文时同时收集 `<img src>` 并以 Markdown 图片语法嵌入正文
3. **微博链接解析失败** — `WeiboParser` 无法从某些微博链接提取微博 ID，可能是 URL 格式匹配规则不完整（如短链 `t.cn` 或带参数的 `m.weibo.cn` 链接）
