<p align="center">
  <img src="icon.png" width="128" alt="拾屿 Logo">
</p>

<h1 align="center">拾屿 Archiver</h1>

<p align="center">跨平台的私人内容岛</p>

<p align="center">
  <a href="https://github.com/V-Linkin/Archiver/releases/latest">
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

首页支持多行粘贴框，可粘贴含分享文案的混合文本（如小红书分享卡片），自动识别并导入链接。

复制任意链接，粘贴即可保存。支持含分享文案的混合文本，自动提取 URL 并识别平台。

**支持平台：** 抖音（图文+视频） · 小红书 · 酷安 · B站 · GitHub · YouTube · X(Twitter) · 微博 · 知乎 · 豆瓣

### 🖼️ 内容归档

保存标题、正文、作者、封面、图片和视频，尽可能完整地留存内容。即使原帖被删，你本地依然可以查看。

支持 Markdown 格式渲染，正文中的标题、粗体、列表、链接、图片均可正常显示。详情页支持 Markdown 编辑器，直接编辑正文和备注，修改自动保存。

### 📂 自由整理

- 创建自定义平台分类
- 二级文件夹管理
- 修改标题、正文、作者
- Markdown 编辑器：编辑正文和备注支持格式化输入与预览
- 备注框位于正文上方，支持实时编辑保存
- 添加或删除图片、视频
- 视频笔记支持下载保存（小红书、X/Twitter、B站等）
- 独立窗口预览：图片和视频在独立窗口中查看，支持多窗口同时打开对比，窗口大小自动记忆，ESC 键快速关闭
- 抖音视频去水印
- 右键菜单支持复制图片到剪贴板
- 媒体另存为：右键单个导出或批量导出到本地，自动按平台_作者_日期创建子文件夹
- 移动、删除、回收站
- 详情页工具栏置顶，滚动内容时操作按钮始终可见

### 📅 最近导入

首页展示最近 7 天内导入的内容，超过 7 天自动隐藏。新建自定义平台后，自动归类已有的未分类内容。

### 🔍 全局搜索

输入关键词，快速检索所有平台的内容。

### 💾 存储管理

修改数据目录时自动迁移旧数据（数据库、媒体文件、平台 Logo）到新目录。

### 💾 备份与还原

一键导出为 zip 文件，换电脑或重装系统后可合并还原数据（不会删除现有内容）。

### 🌐 浏览器选择

在设置中选择用哪个浏览器打开内容的原始链接，支持 Safari、Chrome、Firefox、Edge、Arc。

### 🔄 自动更新

通过 GitHub Release 自动检测新版本，支持一键下载安装。

### ❓ 使用帮助

设置页包含完整的使用文档，分 6 个可展开/收缩的区块介绍软件功能：快速入门、支持平台、内容整理、媒体导出、备份还原、常见问题。

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
