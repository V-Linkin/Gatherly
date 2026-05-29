<p align="center">
  <img src="icon.png" width="128" alt="拾屿 Logo">
</p>

<h1 align="center">拾屿 Archiver</h1>

<p align="center">跨平台的私人内容岛</p>

<p align="center">
  <a href="https://github.com/V-Linkin/Archiver/releases/latest">
    <img src="https://img.shields.io/github/v/release/V-Linkin/Archiver?style=flat-square&label=最新版本" alt="Release">
  </a>
  <img src="https://img.shields.io/badge/macOS-14.0+-blue?style=flat-square" alt="macOS">
  <img src="https://img.shields.io/badge/Swift-6.0-orange?style=flat-square" alt="Swift">
</p>

---

## 它是什么

拾屿是一个 macOS 本地应用，帮你把散落在各个平台的内容统一收集、保存和管理。

看到一篇好文章？一个有用的教程？一段值得回顾的视频？复制链接，粘贴进去，拾屿自动识别平台、抓取内容、下载图片，归档到你的私人资料库。

**所有数据存储在本地，不上传云端，不登录账号，完全属于你。**

## 核心功能

### 📋 链接导入

复制任意链接，粘贴即可保存。自动识别平台并解析内容。

**支持平台：** 抖音 · 小红书 · 酷安 · B站 · GitHub · YouTube · X(Twitter) · 微博 · 知乎 · 豆瓣

### 🖼️ 内容归档

保存标题、正文、作者、封面、原图，尽可能完整地留存内容。即使原帖被删，你本地依然可以查看。

支持 Markdown 格式渲染，正文中的标题、粗体、列表、链接、图片均可正常显示。

### 📂 自由整理

- 创建自定义平台分类
- 二级文件夹管理
- 修改标题、正文、作者、备注
- 添加或删除图片、视频
- 移动、删除、回收站

### 🔍 全局搜索

输入关键词，快速检索所有平台的内容。

### 💾 备份与还原

一键导出为 zip 文件，换电脑或重装系统后可完整还原所有数据。

### 🌐 浏览器选择

在设置中选择用哪个浏览器打开内容的原始链接，支持 Safari、Chrome、Firefox、Edge、Arc。

### 🔄 检查更新

通过 GitHub Release 自动检测新版本。

## 下载安装

前往 [Releases](https://github.com/V-Linkin/Archiver/releases/latest) 下载最新 `.dmg` 文件，打开后将「拾屿」拖入 Applications 文件夹即可。

**系统要求：** macOS 14.0 (Sonoma) 或更高版本

### ⚠️ 首次打开提示"无法验证开发者"

由于 App 未使用 Apple Developer 证书签名，首次打开时 macOS 会弹出安全警告。按以下步骤操作即可：

1. 弹出警告窗口后，点击「完成」关闭弹窗
2. 打开 **系统设置** → **隐私与安全性**
3. 滑动到最下面，找到「拾屿」的阻止提示
4. 点击 **「仍要打开」**
5. 输入密码确认，之后双击即可正常启动

## 从源码构建

```bash
# 克隆仓库
git clone https://github.com/V-Linkin/Archiver.git
cd Archiver

# 安装 XcodeGen（如果没有）
brew install xcodegen

# 生成 Xcode 项目
xcodegen generate

# 打开项目
open Archiver.xcodeproj
```

Xcode 打开后会自动下载 GRDB 依赖，等右上角进度条走完，按 `Cmd+R` 运行。

## 项目结构

```
App/                    应用入口 + 全局状态 + 导航
Models/                 数据模型
  └── Enums/            枚举定义（平台/状态/类型）
Database/               数据库层（GRDB + FTS5）
Parsers/                平台解析器（协议 + 10个实现）
Services/               导入/备份/更新服务
Utilities/              工具类（URL 标准化、浏览器选择等）
Views/                  UI 层
  ├── Home/             首页
  ├── Platform/         平台分类 + 文件夹
  ├── Item/             内容详情 + 编辑
  ├── Search/           搜索结果
  ├── Trash/            回收站
  ├── Settings/         设置
  └── Components/       通用组件
```

## 联系方式

- GitHub：[@V-Linkin](https://github.com/V-Linkin)

## 许可证

MIT License
