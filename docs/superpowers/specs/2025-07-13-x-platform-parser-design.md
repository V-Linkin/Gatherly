# X (Twitter) 平台解析器设计文档

## 概述

为拾屿 App 新增 X (Twitter) 平台支持，通过 Syndication API 实现未登录状态下的推文内容解析与归档。同时重构公共代码，抽取 `BaseParser` 基类减少重复逻辑。

## 目标

1. 支持解析 X 平台推文链接（x.com / twitter.com）
2. 提取推文全文、作者信息、媒体图片、发布时间
3. 下载推文图片到本地
4. 与现有平台架构保持一致

## 研究结论

### X 平台
- Syndication API (`syndication.twitter.com/srv/timeline-profile/screen-name/{用户名}`) 可用
- 未登录状态下可获取用户最近 100 条推文的完整数据
- 数据包含：全文、作者、媒体 URL、互动数据、时间
- 限制：只能获取最近 100 条，无法直接查单条推文

### Instagram（暂缓）
- 未登录状态下无法获取任何有效内容
- 页面为纯 JavaScript 渲染，无 SSR 数据
- oembed API 不可用
- 暂不实现

## 技术方案

### 整体流程

```
用户粘贴 x.com 链接
       ↓
PlatformRouter 识别为 .x 平台
       ↓
XParser.parse(url:) 被调用
       ↓
从 URL 提取 @用户名 和 推文 ID
       ↓
调用 Syndication API 获取用户最近 100 条推文
       ↓
在推文列表中匹配目标 ID
       ↓
解析推文数据 → 返回 ParsedContent
       ↓
下载媒体文件（图片）
```

### URL 识别与解析

支持的 URL 格式：
- `https://x.com/elonmusk/status/1234567890`
- `https://twitter.com/elonmusk/status/1234567890`
- `https://x.com/i/status/1234567890`（无用户名，需特殊处理）

从 URL 中提取：
- `username` — 用于调用 syndication API
- `tweetID` — 用于在返回结果中匹配

对于无用户名的链接（`x.com/i/status/...`），syndication API 需要用户名，这种情况提示用户。

### Syndication API 调用

API 地址：`https://syndication.twitter.com/srv/timeline-profile/screen-name/{用户名}`

返回 JSON 结构（在 `__NEXT_DATA__` 中）：
- `timeline.entries[].content.tweet` — 推文数据
- `full_text` — 推文全文
- `user.name` / `user.screen_name` / `user.profile_image_url_https` — 作者信息
- `entities.media[]` — 媒体列表
- `created_at` — 发布时间
- `favorite_count` / `retweet_count` / `reply_count` — 互动数据
- `id_str` — 推文 ID

### 数据映射

| ParsedContent 字段 | X 数据来源 |
|---|---|
| title | full_text 截取前 50 字符 |
| body | full_text |
| author | user.name |
| authorID | user.screen_name |
| publishDate | created_at 解析 |
| coverURL | entities.media[0].media_url_https |
| imageURLs | entities.media[type=photo].media_url_https |
| platformContentID | id_str |
| rawMetadata | likes, retweets, replies 等 |

### 媒体下载

- 封面图 → 推文第一张图片
- 图片列表 → `entities.media` 中所有 `type=photo` 的项
- 视频 → 暂不下载（需要登录），只记录元数据
- 图片可直接通过 HTTP 下载，无需特殊处理

### 公共代码抽取

新增 `BaseParser` 基类，抽取公共逻辑：

```
BaseParser (抽象基类)
├── downloadMedia(content:itemID:mediaDir:) → 公共实现
├── downloadFile(from:to:) → 公共工具方法
├── extractMeta(html:property:) → 公共 meta 标签提取
└── extractFirst(html:pattern:) → 公共正则提取
```

每个具体解析器继承 `BaseParser`，只需实现：
- `canParse(url:)` — URL 识别
- `parse(url:)` — 核心解析逻辑
- `downloadMedia` 的特殊处理（如果有）

### Platform 集成

修改的文件：
1. `Platform` 枚举 — 新增 `.x` case
2. `PlatformRouter` — 注册 `XParser`
3. `URLNormalizer` — 新增 X 的 URL 识别、标准化、内容 ID 提取

URL 标准化规则：
- `twitter.com/xxx/status/123` → `x://tweet/123`
- `x.com/xxx/status/123` → `x://tweet/123`

### 异常处理

| 异常情况 | 处理方式 |
|---|---|
| 推文不在最近 100 条内 | 提示"该推文较旧，暂无法解析"，保留原始记录 |
| 用户主页链接（非推文） | 提示"请粘贴具体推文链接" |
| 网络请求失败 | 标记为解析失败，保留原始记录 |
| 推文被删除 | syndication API 不返回，提示"无法解析" |

## 文件结构

```
Parsers/
├── BaseParser.swift          (新增 - 公共基类)
├── XParser.swift             (新增 - X 平台解析器)
├── ContentParser.swift       (保持不变 - 协议定义)
├── PlatformRouter.swift      (修改 - 注册 XParser)
├── XiaohongshuParser.swift   (修改 - 继承 BaseParser)
├── BilibiliParser.swift      (修改 - 继承 BaseParser)
├── DouyinParser.swift        (修改 - 继承 BaseParser)
├── CoolapkParser.swift       (修改 - 继承 BaseParser)
├── GitHubParser.swift        (修改 - 继承 BaseParser)
└── YouTubeParser.swift       (修改 - 继承 BaseParser)

Models/
└── Platform.swift            (修改 - 新增 .x case)

Utilities/
└── URLNormalizer.swift       (修改 - 新增 X URL 处理)
```

## MVP 范围

### 必做
- XParser 实现
- BaseParser 基类抽取
- Platform 枚举扩展
- URLNormalizer 扩展
- PlatformRouter 注册
- 媒体下载（图片）

### 可延后
- 视频下载（需登录态）
- Instagram 支持
- 推文翻页扫描（处理超过 100 条的旧推文）
