# 酷安解析器设计文档

## 1. 背景与目标

### 1.1 问题描述
酷安网页版有严格的反爬机制，HTTP 请求返回"请用酷安APP扫码"提示页，WKWebView 也无法绕过（页面自身 JS 报 SyntaxError: Unexpected EOF），导致无法获取正文、图片、作者信息。

### 1.2 解决方案
使用 `coolapk1s.com` 镜像站绕过反爬。该镜像站基于 Next.js SSR，`__NEXT_DATA__` JSON 包含完整 feed 数据，无反爬限制。

## 2. 架构设计

### 2.1 三级降级架构
```
CoolapkParser.parse(url)
    ├─ 1. 镜像站模式（优先）
    │   ├─ 将 coolapk.com → coolapk1s.com
    │   ├─ HTTP 请求镜像站
    │   ├─ 提取 __NEXT_DATA__ JSON
    │   ├─ 成功 → 返回解析结果
    │   └─ 失败 → 进入原站 HTTP 模式
    ├─ 2. 原站 HTTP 模式（兜底）
    │   ├─ 检查 window.__INITIAL_STATE__
    │   ├─ 提取 Meta 标签
    │   └─ 返回基础信息
    └─ 3. WKWebView 降级（最终）
        ├─ 通过 ZhihuWebLoader 加载
        └─ JS 提取内容
```

### 2.2 模式切换逻辑
```swift
func parse(url: URL) async throws -> ParsedContent {
    // 1. 优先尝试镜像站
    if let content = try? await parseViaMirror(url: url) {
        return content
    }
    // 2. 镜像站失败，尝试原站 HTTP
    if let content = try? await parseViaHTTP(url: url) {
        return content
    }
    // 3. 都失败，使用 WKWebView 降级
    return try await parseViaWebView(url: url)
}
```

## 3. 镜像站模式实现

### 3.1 URL 转换
将 `coolapk.com` 域名替换为 `coolapk1s.com`，其他路径不变。

### 3.2 数据提取
从 `<script id="__NEXT_DATA__">` 中提取 JSON，路径为 `props.pageProps.feed`：
- `title`: 动态标题
- `username`: 作者用户名
- `message`: 正文内容（含 HTML 标签和表情标签）
- `picArr`: 图片 URL 数组
- `message_cover`: 封面 URL

### 3.3 正文清理
1. 移除 HTML 标签（`<a class="feed-link-tag">` 等）
2. 移除酷安表情标签（`[酷币]`、`[受虐滑稽]` 等）
3. Trim 空白字符

### 3.4 图片代理
通过 `image.coolapk1s.com/proxy?url={encoded_url}` 代理访问图片，绕过酷安防盗链。

### 3.5 首图去重
当封面来自 `picArr.first` 时，从正文图片列表中移除第一张图片，避免重复显示。

## 4. 数据模型

```swift
ParsedContent(
    title: title,
    body: cleanBody,
    author: username,
    coverURL: convertToProxyURL(coverURL),
    imageURLs: imageURLs.compactMap { convertToProxyURL($0) },
    platformContentID: extractContentID(from: url)
)
```

## 5. 错误处理

- 镜像站返回 400/404/500 → 降级到原站 HTTP
- `__NEXT_DATA__` 中 feed 为 null → 返回 nil，触发降级
- 原站 HTTP 返回扫码页 → 降级到 WKWebView
- WKWebView 超时（15秒） → 抛出 ParserError

## 6. 测试验证

### 测试链接
- https://www.coolapk.com/feed/72069721

### 验证结果
- ✅ 镜像站解析成功（标题/正文/作者/2张图片）
- ✅ 代理图片正常下载（91KB）
- ✅ 正文无 HTML 标签残留
- ✅ 首图不重复

---
**设计完成时间**: 2026-06-01
**设计状态**: 已实现并验证
