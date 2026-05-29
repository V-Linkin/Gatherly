# 微博、知乎、豆瓣平台支持设计文档

## 1. 概述

为拾屿 Archiver 新增三个中文内容平台的解析支持：微博、知乎、豆瓣。采用与现有解析器一致的架构模式（ContentParser 协议 + PlatformRouter 注册），通过 HTML 抓取 + 嵌入式 JSON 提取实现，无需 API Key。

## 2. 各平台内容范围

### 2.1 微博

| 内容类型 | URL 模式 | 保存字段 |
|----------|----------|----------|
| 单条微博 | `weibo.com/status/ID`, `m.weibo.cn/detail/ID` | 正文、图片（多图最多9张）、作者昵称、作者ID、发布时间、封面 |

- 不支持：头条文章、视频微博、个人主页
- 图片：下载原图（大图 URL 替换 `large` 关键词）
- 预留：头条文章、视频微博接口（Parser 内部判断类型后走不同分支）

### 2.2 知乎

| 内容类型 | URL 模式 | 保存字段 |
|----------|----------|----------|
| 回答 | `zhihu.com/question/QID/answer/AID` | 提问人、问题标题、问题描述、回答正文、回答者、发布时间 |
| 文章 | `zhihu.com/p/ID` | 标题、正文、作者、发布时间 |
| 专栏 | `zhihu.com/column/CID` | 专栏名、专栏简介、创建者、文章数（仅元数据，不批量导入文章） |

- 知乎内容支持 Markdown 格式渲染（已有的 MarkdownView）
- 正文提取时保留 Markdown 结构

### 2.3 豆瓣

| 内容类型 | URL 模式 | 保存字段 |
|----------|----------|----------|
| 书/影/音条目 | `douban.com/subject/ID` | 标题、评分、影评/书评正文、封面图、作者 |

- 不支持：小组帖子、日记文章（预留接口）
- 优先提取页面中的影评/书评内容
- 如果页面同时有简介和评论，优先保存评论内容
- 预留：小组帖子（`douban.com/group/topic/ID`）、日记文章（`douban.com/note/ID`）

## 3. 技术方案

### 3.1 解析策略

三个平台统一采用 HTML 抓取方案，按优先级尝试：

1. **嵌入式 JSON 提取**（主方案）
2. **Meta 标签提取**（兜底）
3. **HTML 结构解析**（最终兜底）

### 3.2 各平台数据源

| 平台 | 主数据源 | 兜底 |
|------|----------|------|
| 微博 | `m.weibo.cn/detail/ID` 页面中 `$render_data` JSON | `weibo.com` meta 标签 |
| 知乎 | `zhihu.com` 页面中 `window.__INITIAL_STATE__` JSON | meta 标签 |
| 豆瓣 | `douban.com/subject/ID` 页面中 `window.__DATA__` JSON 或 `application/ld+json` | meta 标签 |

### 3.3 URL 识别

在 URLNormalizer 中添加：
- 微博：`weibo.com`, `m.weibo.cn`
- 知乎：`zhihu.com`
- 豆瓣：`douban.com`

### 3.4 内容 ID 提取

| 平台 | 内容 ID 格式 |
|------|-------------|
| 微博 | 数字 ID（如 `4988881234567`） |
| 知乎回答 | `answer/AID`（如 `12345678`） |
| 知乎文章 | `p/ID`（如 `12345678`） |
| 知乎专栏 | `column/CID`（如 `my-column`） |
| 豆瓣 | `subject/ID`（如 `12345678`） |

### 3.5 媒体下载

- 微博：下载原图（替换 URL 中的 `orj360`/`orj480`/`thumb` 为 `large`）
- 知乎：下载回答/文章中的图片
- 豆瓣：下载封面图（书/影/音封面）
- 三者都不做视频下载

### 3.6 去重规则

与现有平台一致：
1. 单平台内去重
2. 优先按内容 ID 去重
3. 其次按标准化 URL 去重

## 4. 文件变更

| 操作 | 文件 | 说明 |
|------|------|------|
| 修改 | `Models/Enums/Platform.swift` | 添加 `.weibo`, `.zhihu`, `.douban` |
| 修改 | `Utilities/URLNormalizer.swift` | 添加三个平台的 URL 识别和标准化 |
| 创建 | `Parsers/WeiboParser.swift` | 微博解析器 |
| 创建 | `Parsers/ZhihuParser.swift` | 知乎解析器 |
| 创建 | `Parsers/DoubanParser.swift` | 豆瓣解析器 |
| 修改 | `Parsers/PlatformRouter.swift` | 注册三个新解析器 |

## 5. 异常处理

- **登录墙**：微博、知乎部分页面需要登录。如果检测到登录页面（HTML 中无有效数据），返回解析失败，用户可手动编辑
- **反爬**：使用标准浏览器 User-Agent，如果被拦截则返回解析失败
- **数据结构变化**：嵌入式 JSON 的 key 路径可能变化，每个解析器都有 meta 标签兜底
- **部分数据缺失**：任何字段缺失不阻断保存，标题或正文至少有一个即可保存成功

## 6. 扩展预留

- 豆瓣小组帖子和日记文章在 `DoubanParser` 内预留 `canParse` 判断，未来可直接添加解析分支
- 微博头条文章和视频微博在 `WeiboParser` 内预留类型判断分支
- 知乎想法（类似微博的短内容）预留 URL 识别接口
