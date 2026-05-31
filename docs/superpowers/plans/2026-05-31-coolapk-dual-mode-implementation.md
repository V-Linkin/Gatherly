# 酷安解析器实现计划

## 项目概述
使用 `coolapk1s.com` 镜像站绕过酷安反爬，实现完整内容解析。

## 实现目标
- ✅ 三级降级架构：镜像站 → 原站 HTTP → WKWebView
- ✅ 从 `__NEXT_DATA__` JSON 提取完整 feed 数据
- ✅ 图片通过代理 URL 绕过防盗链
- ✅ 首图去重 + 正文 HTML 标签清理

## 已完成

### CoolapkParser 重写
- 文件: `Parsers/CoolapkParser.swift`
- 新增 `parseViaMirror(url:)` 方法，优先使用镜像站
- 新增 `convertToMirrorURL()` 域名转换
- 新增 `extractFromNextData()` 提取 `__NEXT_DATA__` JSON
- 新增 `convertToProxyURL()` 图片代理转换
- 正文清理：移除 HTML 标签 + 表情标签
- 首图去重：封面与首图相同时从 `imageURLs` 移除

### 文档更新
- `AGENTS.md` — 更新酷安解析器说明
- `docs/superpowers/specs/2026-05-31-coolapk-dual-mode-design.md` — 重写设计文档

## 验证结果
- ✅ 编译通过
- ✅ 测试链接解析成功
- ✅ 代理图片可正常下载
- ✅ 正文无 HTML 标签残留
- ✅ 首图不重复

---
**完成时间**: 2026-06-01
**状态**: 已完成
