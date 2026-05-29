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

## 修复方案（已实施）

### JS 选择器（ZhihuWebLoader.swift）

优先级：`.subject-img img` → `.subject-poster img` → `.poster img` → `[data-image]` → `og:image`

```javascript
var _posterEl = document.querySelector('.subject-img img')
    || document.querySelector('.subject-poster img')
    || document.querySelector('.poster img')
    || document.querySelector('[data-image]');
if (_posterEl && _posterEl.src && _posterEl.src.indexOf('doubanio.com') !== -1) {
    doubanResult.cover = _posterEl.src;
} else if (_posterEl && _posterEl.getAttribute && _posterEl.getAttribute('data-image')) {
    doubanResult.cover = _posterEl.getAttribute('data-image');
} else {
    var _ogImg = document.querySelector('meta[property="og:image"]');
    doubanResult.cover = (_ogImg && _ogImg.content) ? _ogImg.content : '';
}
```

### Swift 兜底（DoubanParser.swift）

当 review 页面的封面为影评头图（URL 含 `thing_review`）或为空时，从 subject 页面获取 `og:image`：

```swift
let needSubjectCover = (cover == nil) || (cover?.contains("thing_review") == true)
if needSubjectCover, let subjectID = extractSubjectID(from: url) {
    let subjectURL = URL(string: "https://movie.douban.com/subject/\(subjectID)/") ?? url
    // 用桌面 UA 请求，获取 og:image
}
```

## 实施步骤（已完成）

1. ✅ 修改 `ZhihuWebLoader.swift` JS 选择器
2. ✅ 修改 `DoubanParser.swift` 增加 subject 页面兜底
3. ✅ 测试验证封面提取

## 成功标准

1. ✅ 豆瓣影评页面能正确获取电影/书籍海报
2. ✅ 封面图片 URL 有效且可下载
3. ✅ 不影响其他平台的解析功能
4. ⬜ 正文图片提取（待实现）

## 影响范围

- `Utilities/ZhihuWebLoader.swift`：JS 封面选择器
- `Parsers/DoubanParser.swift`：Swift 层 subject 页面兜底
