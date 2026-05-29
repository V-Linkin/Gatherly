# 豆瓣影评封面选择器修复设计

## 问题描述

豆瓣影评页面的封面图片无法正确获取。当前 JS 选择器 `.subject-cover img` 和 `.main-bd img` 未匹配到豆瓣影评页面的实际 DOM 结构。

## 根本原因分析

### 桌面端页面结构（成功）

1. **影评封面图片**：
   - 位于 `data-image` 属性中
   - 示例：`data-image="https://img9.doubanio.com/view/thing_review/large/public/p10468996.jpg"`

2. **书籍封面图片**：
   - 位于 `.subject-img img` 元素
   - 示例：`<img src="https://img9.doubanio.com/view/subject/l/public/s34751195.jpg">`

3. **影评内容区域**：
   - `.main-bd` 区域包含影评正文
   - `.review-content` 包含实际文本内容

### 移动端页面结构（失败）

1. **og:image**：只返回豆瓣 logo，不是实际封面
2. **影评内容**：通过 AJAX 动态加载，初始 HTML 不包含内容

### 当前 JS 选择器问题

```javascript
var coverEl = document.querySelector('.subject-cover img') 
    || document.querySelector('.main-bd img') 
    || document.querySelector('[class*="cover"] img');
```

问题：
- `.subject-cover` 类不存在于桌面端页面
- `.main-bd img` 匹配到影评正文中的图片，不是封面
- 需要从 `data-image` 属性或 `.subject-img img` 获取封面

## 修复方案

### 方案 A：修改 JS 选择器（推荐）

更新 `ZhihuWebLoader.swift` 中的豆瓣封面提取逻辑：

```javascript
// 提取封面 - 优先从 data-image 属性获取
var coverEl = document.querySelector('[data-image]');
if (coverEl) {
    doubanResult.cover = coverEl.getAttribute('data-image');
} else {
    // 兜底：从 subject-img 获取书籍封面
    var subjectImgEl = document.querySelector('.subject-img img');
    if (subjectImgEl) {
        doubanResult.cover = subjectImgEl.src;
    } else {
        // 再兜底：从 og:image 获取
        var ogImage = document.querySelector('meta[property="og:image"]');
        doubanResult.cover = ogImage ? ogImage.content : '';
    }
}
```

### 方案 B：从 HTML 直接提取 meta 信息

在 `DoubanParser.swift` 的 `parseReviewPage` 方法中，优先从 `og:image` meta 标签获取封面：

```swift
// meta 标签获取基本信息
let metaCover = extractMeta(html, property: "og:image")

// 组装封面：优先 webview 提取，兜底 meta
let cover = webResult.cover ?? metaCover
```

当前代码已经实现了这个逻辑，但 `og:image` 在移动端返回的是豆瓣 logo。

## 实施步骤

1. **修改 `ZhihuWebLoader.swift`**：
   - 更新 JS 选择器，优先从 `data-image` 属性获取封面
   - 添加 `.subject-img img` 作为兜底
   - 保留 `og:image` 作为最后兜底

2. **测试验证**：
   - 使用豆瓣影评 URL 测试封面提取
   - 验证桌面端和移动端页面都能正确获取封面

## 成功标准

1. 豆瓣影评页面能正确获取封面图片
2. 封面图片 URL 有效且可下载
3. 不影响其他平台的解析功能

## 影响范围

- `Utilities/ZhihuWebLoader.swift`：修改 JS 选择器
- `Parsers/DoubanParser.swift`：无需修改（已有兜底逻辑）
