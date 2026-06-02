# 独立窗口查看器设计

## 概述

将图片/视频查看从全屏黑色叠加层改为独立 NSWindow 窗口，支持多窗口同时打开方便图片对比，窗口大小记忆。

## 新建组件

### ViewerWindowManager

单例，管理所有查看器窗口的创建、生命周期、尺寸持久化。

```swift
@MainActor
final class ViewerWindowManager {
    static let shared = ViewerWindowManager()
    
    private var windows: [NSWindow] = []
    private let userDefaultsKey = "viewerWindowSize"
    private let defaultSize = NSSize(width: 800, height: 600)
    private let minSize = NSSize(width: 400, height: 300)
}
```

**API：**
- `openImageViewer(images: currentIndex:)` — 打开图片查看器窗口
- `openVideoViewer(url:)` — 打开视频播放器窗口
- `close()` — 关闭所有窗口

**窗口属性：**
- 无标题栏（`.titlebarAppearsTransparent`），保留交通灯按钮
- 白色背景
- 可拖动、可调整大小、可关闭、可最小化
- 不限制窗口数量，每次打开创建新窗口
- 打开时恢复上次保存的尺寸，居中显示
- 关闭时（`windowWillClose` 通知）保存当前尺寸到 UserDefaults
- 所有窗口共享同一个保存的尺寸

## 改动组件

### ContentView.swift

- 移除 `@State` 的 `bodyImages`、`bodyImageIndex`、`showBodyViewer`
- 移除 body viewer 的 ZStack 叠加层
- `ItemDetailView` 调用处移除这三个 binding 参数

### ItemDetailView.swift

- 移除 `@Binding var bodyImages`、`@Binding var bodyImageIndex`、`@Binding var showBodyViewer`
- `openBodyViewer` 改为调用 `ViewerWindowManager.shared.openImageViewer(images:currentIndex:)`
- 媒体轮播中视频缩略图改为静态封面图（点击才打开播放器）
- 视频点击调用 `ViewerWindowManager.shared.openVideoViewer(url:)`

### ImageViewerView.swift

- 背景色从 `Color.black.opacity(0.92)` 改为 `Color.white`
- 关闭按钮和导航按钮颜色调整为深色
- 移除背景的 `.onTapGesture` 关闭（窗口已有关闭按钮）
- 键盘 ESC 关闭：调用 `NSApp.keyWindow?.close()`

## 视频查看器窗口

- 白色背景，窗口标题为空
- 内容区放 AVPlayerView（复用现有 VideoPlayerView），铺满窗口
- 交通灯按钮保留，支持 ESC 关闭

## 不变组件

- `VideoPlayerView` — 不变

## 尺寸记忆

- UserDefaults 键：`viewerWindowSize`，存储 `CGSize` 的 `NSValue`
- 所有查看器窗口共享同一保存尺寸
- 窗口关闭时保存 frame size
- 下次打开时读取并应用
- 首次默认 800×600，最小 400×300
