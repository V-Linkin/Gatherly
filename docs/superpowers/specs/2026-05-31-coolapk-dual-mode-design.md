# 酷安双模式解析器设计文档

## 1. 背景与目标

### 1.1 问题描述
当前 `CoolapkParser` 仅通过 HTTP 请求解析酷安页面，面临以下问题：
- 酷安网页版有严格的反爬机制，HTTP 请求常返回"请用酷安APP扫码"提示页
- 无法获取正文内容、图片列表、作者信息
- 只能通过 Meta 标签获取基础的标题、描述、封面信息

### 1.2 设计目标
- 实现双模式解析：HTTP 快速尝试 + WebView 降级
- 最大化内容获取成功率
- 复用现有基础设施，降低维护成本
- 保持与小红书解析器一致的架构模式

## 2. 架构设计

### 2.1 整体架构
```
CoolapkParser.parse(url)
    ├─ 1. HTTP 模式尝试
    │   ├─ 成功 → 返回解析结果
    │   └─ 失败 → 进入 WebView 模式
    └─ 2. WebView 模式
        ├─ 加载页面 → 提取内容
        └─ 返回解析结果
```

### 2.2 模式切换逻辑
```swift
func parse(url: URL) async throws -> ParsedContent {
    // 1. 先尝试 HTTP 快速获取
    if let content = try? await parseViaHTTP(url: url) {
        return content
    }
    
    // 2. HTTP 失败，使用 WKWebView 降级
    return try await parseViaWebView(url: url)
}
```

## 3. HTTP 模式实现

### 3.1 请求优化
- 复用现有 URLSession 配置
- 添加更多请求头模拟真实浏览器
- 实现请求间隔控制（类似豆瓣）

### 3.2 SSR 数据检测
- 检查 `window.__INITIAL_STATE__` 存在性
- 解析 JSON 数据提取内容
- 如果 SSR 数据完整，直接返回

### 3.3 Meta 标签回退
- 如果 SSR 数据不完整，提取 Meta 标签
- 获取基础信息：标题、描述、封面、作者

## 4. WebView 模式实现

### 4.1 复用 ZhihuWebLoader
- 完全复用现有的 `ZhihuWebLoader` 类
- 利用其超时控制、轮询等待机制
- 无需修改 WebView 基础设施

### 4.2 酷安页面特征分析
基于酷安页面结构，设计 JavaScript 提取策略：

#### 4.2.1 页面类型识别
- **动态页面**：包含 `window.__INITIAL_STATE__`
- **静态页面**：包含文章内容区域
- **登录页面**：需要特殊处理

#### 4.2.2 内容提取策略
1. **SSR 数据提取**（优先）
   ```javascript
   if (window.__INITIAL_STATE__) {
       // 提取 feed 内容、作者、图片列表
   }
   ```

2. **DOM 结构提取**（备选）
   ```javascript
   // 酷安文章页面结构
   var selectors = [
       '.detail-content',  // 文章内容
       '.feed-content',    // 动态内容
       '.post-content',    // 帖子内容
       '[class*="content"]' // 通用内容匹配
   ];
   ```

3. **图片提取策略**
   ```javascript
   // 图片选择器
   var imageSelectors = [
       '.detail-content img',
       '.feed-content img',
       'article img',
       '[class*="content"] img'
   ];
   ```

4. **作者信息提取**
   ```javascript
   // 作者信息选择器
   var authorSelectors = [
       '.user-name',
       '.author-name',
       '[class*="user"]',
       '[class*="author"]'
   ];
   ```

### 4.3 JavaScript 提取逻辑
在 `ZhihuWebLoader.extractContent(from:)` 中添加酷安处理：

```javascript
// === 酷安 ===
if (url.indexOf('coolapk.com') !== -1 || url.indexOf('coolapk1s.com') !== -1) {
    var coolapkResult = {
        title: '',
        text: '',
        author: '',
        images: [],
        cover: ''
    };
    
    // 1. 尝试 SSR 数据提取
    if (window.__INITIAL_STATE__) {
        try {
            var state = JSON.parse(window.__INITIAL_STATE__);
            // 提取逻辑：根据实际页面结构实现具体提取逻辑
        } catch(e) {}
    }
    
    // 2. DOM 结构提取
    if (!coolapkResult.text) {
        var contentEl = document.querySelector('.detail-content') || 
                       document.querySelector('.feed-content') ||
                       document.querySelector('article');
        if (contentEl) {
            coolapkResult.text = contentEl.innerText.trim();
        }
    }
    
    // 3. 图片提取
    var imgEls = document.querySelectorAll('.detail-content img, .feed-content img, article img');
    coolapkResult.images = Array.from(imgEls).map(function(img) {
        return img.src;
    }).filter(function(src) {
        return src && src.indexOf('http') === 0;
    });
    
    // 4. 作者提取
    var authorEl = document.querySelector('.user-name') || 
                  document.querySelector('.author-name') ||
                  document.querySelector('[class*="user"]');
    if (authorEl) {
        coolapkResult.author = authorEl.innerText.trim();
    }
    
    // 5. 封面设置
    coolapkResult.cover = coolapkResult.images.length > 0 ? coolapkResult.images[0] : '';
    
    if (coolapkResult.text.length > 20 || coolapkResult.images.length > 0) {
        return 'COOLAPK_JSON:' + JSON.stringify(coolapkResult);
    }
}
```

## 5. 数据模型适配

### 5.1 ParsedContent 初始化
使用命名参数初始化，确保字段完整性：
```swift
return ParsedContent(
    title: title,
    body: body,
    author: author,
    coverURL: coverURL,
    imageURLs: imageURLs,
    platformContentID: extractContentID(from: url)
)
```

### 5.2 媒体下载逻辑
复用现有的 `downloadMedia` 实现，支持：
- 封面下载
- 正文图片下载
- 媒体文件命名规范

## 6. 错误处理与降级策略

### 6.1 错误类型
- **HTTP 请求失败**：网络错误、状态码异常
- **SSR 数据解析失败**：JSON 格式错误、数据缺失
- **WebView 加载失败**：超时、页面错误
- **内容提取失败**：选择器不匹配、内容为空

### 6.2 降级策略
1. **HTTP → WebView**：HTTP 失败时自动降级
2. **SSR → DOM**：SSR 数据不完整时尝试 DOM 提取
3. **内容 → Meta**：无法提取正文时使用 Meta 描述

### 6.3 用户体验
- 显示加载状态和进度
- 失败时保留原始链接和基础信息
- 提供手动重试机制

## 7. 性能优化

### 7.1 请求优化
- 实现请求间隔控制，避免触发反爬
- 复用 URLSession 连接池
- 合理设置超时时间

### 7.2 WebView 优化
- 复用 `ZhihuWebLoader` 的轮询机制
- 合理设置超时时间（15秒）
- 及时清理 WebView 资源

## 8. 测试策略

### 8.1 单元测试
- HTTP 模式解析测试
- WebView 模式解析测试
- 错误处理测试

### 8.2 集成测试
- 完整解析流程测试
- 媒体下载测试
- 并发解析测试

### 8.3 兼容性测试
- 不同酷安页面类型测试
- 不同网络环境测试
- 不同 macOS 版本测试

## 9. 实现计划

### 9.1 第一阶段：基础架构
1. 修改 `CoolapkParser` 采用双模式架构
2. 实现 HTTP 模式优化
3. 集成 `ZhihuWebLoader`

### 9.2 第二阶段：WebView 提取
1. 分析酷安页面结构
2. 实现 JavaScript 提取逻辑
3. 调试和优化提取效果

### 9.3 第三阶段：完善功能
1. 实现媒体下载优化
2. 添加错误处理和降级策略
3. 编写测试用例

### 9.4 第四阶段：验证发布
1. 功能测试和性能测试
2. 文档更新
3. 发布准备

## 10. 风险评估

### 10.1 技术风险
- **WebView 兼容性**：不同 macOS 版本的 WebView 差异
- **页面结构变化**：酷安页面结构可能更新
- **反爬机制升级**：酷安可能加强反爬措施

### 10.2 缓解措施
- 保持选择器的灵活性和容错性
- 实现多层降级策略
- 定期维护和更新解析逻辑

## 11. 总结

本设计通过双模式解析方案，结合 HTTP 快速尝试和 WebView 降级，旨在解决酷安内容获取问题。方案复用现有基础设施，保持与小红书解析器一致的架构模式，最大化内容获取成功率，同时控制维护成本。

关键优势：
- **高成功率**：双模式确保内容获取
- **复用性强**：充分利用现有代码
- **维护简单**：统一的架构模式
- **用户体验好**：渐进式加载和降级

---
**设计完成时间**：2026-05-31
**设计状态**：已完成，等待用户评审
