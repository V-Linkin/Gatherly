# 独立窗口查看器 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the full-screen overlay image/video viewer with independent NSWindow windows, supporting multiple simultaneous windows and window size persistence.

**Architecture:** A `ViewerWindowManager` singleton creates and manages `NSWindow` instances for image and video viewing. Each window hosts the existing `ImageViewerView` or a new `VideoViewerView`. Window size is persisted via `UserDefaults`. The overlay code in `ContentView` is removed entirely.

**Tech Stack:** Swift, SwiftUI, AppKit (NSWindow, AVPlayerView), UserDefaults

---

## File Map

| Action | File | Responsibility |
|--------|------|----------------|
| Create | `Utilities/ViewerWindowManager.swift` | NSWindow lifecycle, size persistence |
| Create | `Views/Components/VideoViewerView.swift` | Video player in独立窗口 |
| Modify | `Views/Components/ImageViewerView.swift` | White background, dark controls, ESC closes window |
| Modify | `App/ContentView.swift` | Remove overlay state/ZStack, remove body viewer bindings |
| Modify | `Views/Item/ItemDetailView.swift` | Remove bindings, use ViewerWindowManager, add video tap |

---

### Task 1: Create ViewerWindowManager

**Files:**
- Create: `Utilities/ViewerWindowManager.swift`

- [ ] **Step 1: Create the ViewerWindowManager**

```swift
import AppKit
import SwiftUI

@MainActor
final class ViewerWindowManager {
    static let shared = ViewerWindowManager()
    
    private var windows: [NSWindow] = []
    private let userDefaultsKey = "viewerWindowSize"
    private let defaultSize = NSSize(width: 800, height: 600)
    private let minSize = NSSize(width: 400, height: 300)
    
    private init() {}
    
    // MARK: - Image Viewer
    
    func openImageViewer(images: [NSImage], startIndex: Int = 0) {
        guard !images.isEmpty else { return }
        
        let savedSize = savedWindowSize()
        let contentView = ImageViewerWindowContent(
            images: images,
            startIndex: startIndex
        )
        
        let window = createWindow(size: savedSize, contentView: contentView)
        windows.append(window)
        window.makeKeyAndOrderFront(nil)
    }
    
    // MARK: - Video Viewer
    
    func openVideoViewer(url: URL) {
        let savedSize = savedWindowSize()
        let contentView = VideoViewerView(url: url)
            .frame(minWidth: minSize.width, minHeight: minSize.height)
        
        let window = createWindow(size: savedSize, contentView: contentView)
        windows.append(window)
        window.makeKeyAndOrderFront(nil)
    }
    
    // MARK: - Close All
    
    func closeAll() {
        for window in windows {
            window.close()
        }
        windows.removeAll()
    }
    
    // MARK: - Window Factory
    
    private func createWindow(size: NSSize, contentView: some View) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        
        window.titlebarAppearsTransparent = true
        window.backgroundColor = NSColor.white
        window.contentView = NSHostingView(rootView: contentView)
        window.minSize = minSize
        window.isReleasedWhenClosed = false
        window.center()
        
        // Save size on close
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.saveWindowSize(window.frame.size)
                self?.windows.removeAll { $0 === window }
            }
        }
        
        return window
    }
    
    // MARK: - Size Persistence
    
    private func savedWindowSize() -> NSSize {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let nsValue = try? NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(data) as? NSValue else {
            return defaultSize
        }
        return nsValue.sizeValue
    }
    
    private func saveWindowSize(_ size: NSSize) {
        let nsValue = NSValue(size: size)
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: nsValue, requiringSecureCoding: false) {
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        }
    }
}

// MARK: - Image Viewer Window Content

/// Wraps ImageViewerView for use in NSWindow, handling ESC key to close window
private struct ImageViewerWindowContent: View {
    let images: [NSImage]
    @State var currentIndex: Int
    @State private var isPresented = true
    
    var body: some View {
        ImageViewerView(
            images: images,
            currentIndex: $currentIndex,
            isPresented: $isPresented
        )
        .onChange(of: isPresented) { _, presented in
            if !presented {
                NSApp.keyWindow?.close()
            }
        }
        .onKeyDown { event in
            if event.keyCode == 53 { // ESC
                NSApp.keyWindow?.close()
            }
        }
    }
}
```

- [ ] **Step 2: Verify build**

Run: `xcodegen generate && xcodebuild build -project Archiver.xcodeproj -scheme Archiver -destination 'platform=macOS' 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add Utilities/ViewerWindowManager.swift
git commit -m "feat: add ViewerWindowManager for independent viewer windows"
```

---

### Task 2: Create VideoViewerView

**Files:**
- Create: `Views/Components/VideoViewerView.swift`

- [ ] **Step 1: Create VideoViewerView**

```swift
import SwiftUI
import AVKit

/// 视频查看器 — 独立窗口中播放视频
struct VideoViewerView: NSViewRepresentable {
    let url: URL
    
    func makeNSView(context: Context) -> AVPlayerView {
        let playerView = AVPlayerView()
        playerView.controlsStyle = .inline
        playerView.showsFullScreenToggleButton = true
        playerView.videoGravity = .resizeAspect
        playerView.player = AVPlayer(url: url)
        playerView.player?.play()
        return playerView
    }
    
    func updateNSView(_ nsView: AVPlayerView, context: Context) {}
}
```

- [ ] **Step 2: Verify build**

Run: `xcodegen generate && xcodebuild build -project Archiver.xcodeproj -scheme Archiver -destination 'platform=macOS' 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add Views/Components/VideoViewerView.swift
git commit -m "feat: add VideoViewerView for video playback in viewer window"
```

---

### Task 3: Modify ImageViewerView for window mode

**Files:**
- Modify: `Views/Components/ImageViewerView.swift`

- [ ] **Step 1: Change background from black to white, adjust control colors**

In `Views/Components/ImageViewerView.swift`, make these changes:

1. Change background color (line ~22):
   - FROM: `Color.black.opacity(0.92).ignoresSafeArea()`
   - TO: `Color.white.ignoresSafeArea()`

2. Remove the background tap gesture that closes the viewer (lines ~25-29):
   - Remove `.onTapGesture { withAnimation { isPresented = false } }` from the background color

3. Change navigation button colors from white to dark (chevron.left, chevron.right):
   - All `.foregroundStyle(.white)` on navigation buttons → `.foregroundStyle(.primary)`
   - Background `.Color.white.opacity(0.15)` → `.Color.black.opacity(0.1)`

4. Change close button color:
   - `.foregroundStyle(.white)` → `.foregroundStyle(.primary)`
   - Background `.Color.white.opacity(0.15)` → `.Color.black.opacity(0.1)`

5. Change page info text color:
   - `.foregroundStyle(.white)` → `.foregroundStyle(.primary)`

6. In `handleKeyPress`, ESC (keyCode 53) currently sets `isPresented = false`. Keep this — the parent `ImageViewerWindowContent` will handle closing the window via the `onChange(of: isPresented)`.

- [ ] **Step 2: Verify build**

Run: `xcodegen generate && xcodebuild build -project Archiver.xcodeproj -scheme Archiver -destination 'platform=macOS' 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add Views/Components/ImageViewerView.swift
git commit -m "feat: update ImageViewerView for white background window mode"
```

---

### Task 4: Update ContentView — remove overlay

**Files:**
- Modify: `App/ContentView.swift`

- [ ] **Step 1: Remove body viewer overlay state and ZStack**

In `App/ContentView.swift`:

1. Remove the three body viewer state properties (around lines 40-42):
   ```swift
   // REMOVE these three lines:
   @State private var bodyImages: [NSImage] = []
   @State private var bodyImageIndex: Int = 0
   @State private var showBodyViewer: Bool = false
   ```

2. In the `.overlay` block (around lines 96-104), remove the body viewer section:
   ```swift
   // REMOVE this entire block:
   if showBodyViewer && !bodyImages.isEmpty {
       ImageViewerView(
           images: bodyImages,
           currentIndex: $bodyImageIndex,
           isPresented: $showBodyViewer
       )
       .transition(.opacity)
       .animation(.easeInOut(duration: 0.2), value: showBodyViewer)
   }
   ```

3. In `detailView` computed property, update the `ItemDetailView` instantiation (around line 190). Remove the three body viewer binding parameters:
   ```swift
   // Change from:
   ItemDetailView(
       itemID: id,
       selectedNav: $selectedNav,
       previousNav: $previousNav,
       coverImages: $coverImages,
       coverImageIndex: $coverImageIndex,
       showCoverViewer: $showCoverViewer,
       bodyImages: $bodyImages,        // REMOVE
       bodyImageIndex: $bodyImageIndex, // REMOVE
       showBodyViewer: $showBodyViewer  // REMOVE
   )
   // To:
   ItemDetailView(
       itemID: id,
       selectedNav: $selectedNav,
       previousNav: $previousNav,
       coverImages: $coverImages,
       coverImageIndex: $coverImageIndex,
       showCoverViewer: $showCoverViewer
   )
   ```

- [ ] **Step 2: Verify build**

Run: `xcodegen generate && xcodebuild build -project Archiver.xcodeproj -scheme Archiver -destination 'platform=macOS' 2>&1 | tail -5`
Expected: Build will fail because ItemDetailView still expects the removed parameters. This is expected — Task 5 will fix it.

- [ ] **Step 3: Commit**

```bash
git add App/ContentView.swift
git commit -m "refactor: remove body viewer overlay from ContentView"
```

---

### Task 5: Update ItemDetailView — use ViewerWindowManager

**Files:**
- Modify: `Views/Item/ItemDetailView.swift`

- [ ] **Step 1: Remove body viewer binding parameters**

In `Views/Item/ItemDetailView.swift`:

1. Remove the three binding declarations (lines 12-14):
   ```swift
   // REMOVE:
   @Binding var bodyImages: [NSImage]
   @Binding var bodyImageIndex: Int
   @Binding var showBodyViewer: Bool
   ```

2. Update `openBodyViewer` method (around line 387) to use ViewerWindowManager:
   ```swift
   private func openBodyViewer(from tappedIndex: Int) {
       guard !bodyViewerDebounce else { return }
       bodyViewerDebounce = true
       DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
           bodyViewerDebounce = false
       }
       
       let urls = bodyImageURLs.isEmpty ? Self.extractImageURLs(from: item?.body ?? "") : bodyImageURLs
       let images = urls.compactMap { bodyImageCache.get($0) }
       guard !images.isEmpty else { return }
       ViewerWindowManager.shared.openImageViewer(images: images, startIndex: tappedIndex)
   }
   ```

3. Update `openCoverViewer` method (around line 316) to use ViewerWindowManager:
   ```swift
   private func openCoverViewer(from tappedIndex: Int) {
       var images: [NSImage] = []
       for asset in mediaAssets {
           if asset.type == .image, let path = asset.localPath {
               let url = DataDirectory.media.appendingPathComponent(path)
               if let nsImage = NSImage(contentsOf: url) {
                   images.append(nsImage)
               }
           }
       }
       guard !images.isEmpty else { return }
       ViewerWindowManager.shared.openImageViewer(images: images, startIndex: tappedIndex)
   }
   ```

4. In the media carousel, replace the inline `VideoPlayerView` with a static thumbnail that opens a viewer window on tap. Find the video section in `mediaSection` (around line 200) and replace:
   ```swift
   // REPLACE the video block:
   if asset.type == .video {
       VideoPlayerView(url: url)
           .frame(width: 400, height: 280)
           .clipShape(RoundedRectangle(cornerRadius: 8))
           .contextMenu { ... }
   // WITH:
   if asset.type == .video {
       Group {
           if let coverURL = content.coverURL,
              let coverImage = NSImage(contentsOf: URL(string: coverURL) ?? URL(fileURLWithPath: "")) {
               Image(nsImage: coverImage)
                   .resizable()
                   .aspectRatio(contentMode: .fit)
           } else if let nsImage = NSImage(contentsOf: url) {
               Image(nsImage: nsImage)
                   .resizable()
                   .aspectRatio(contentMode: .fit)
           } else {
               RoundedRectangle(cornerRadius: 8)
                   .fill(.quaternary)
                   .overlay {
                       Image(systemName: "play.circle")
                           .font(.largeTitle)
                           .foregroundStyle(.secondary)
                   }
           }
       }
       .frame(width: 400, height: 280)
       .clipShape(RoundedRectangle(cornerRadius: 8))
       .onTapGesture {
           ViewerWindowManager.shared.openVideoViewer(url: url)
       }
       .contextMenu {
           Button {
               let success = MediaExporter.exportSingle(asset: asset, item: item, from: appState)
               if success {
                   appState.showToast("导出成功")
               }
           } label: {
               Label("另存为", systemImage: "square.and.arrow.down")
           }
           .disabled(asset.localPath == nil)
       }
   }
   ```

   Note: The `content` variable is not in scope here. Instead, use the `item` parameter. We need to get the cover URL from the item. Actually, looking at the code, `item` is available in `mediaSection`. But `item` is an `Item` model, not `ParsedContent`. Let me check what properties `Item` has.

   Actually, looking more carefully, we should use the video file itself to generate a thumbnail. The simplest approach: use `AVAssetImageGenerator` to get a thumbnail from the video file. But that adds complexity. 

   Simpler approach: just show a play icon overlay on a generic background, since the video file itself can't be easily converted to an NSImage thumbnail without AVFoundation. Let me revise:

   ```swift
   if asset.type == .video {
       ZStack {
           RoundedRectangle(cornerRadius: 8)
               .fill(.black)
               .opacity(0.05)
           Image(systemName: "play.circle.fill")
               .font(.system(size: 48))
               .foregroundStyle(.white)
               .shadow(color: .black.opacity(0.3), radius: 4)
       }
       .frame(width: 400, height: 280)
       .clipShape(RoundedRectangle(cornerRadius: 8))
       .onTapGesture {
           ViewerWindowManager.shared.openVideoViewer(url: url)
       }
       .contextMenu {
           Button {
               let success = MediaExporter.exportSingle(asset: asset, item: item, from: appState)
               if success {
                   appState.showToast("导出成功")
               }
           } label: {
               Label("另存为", systemImage: "square.and.arrow.down")
           }
           .disabled(asset.localPath == nil)
       }
   }
   ```

   Wait, but the user might want to see a thumbnail of the video. Let me use AVAssetImageGenerator to extract a frame. This is a common pattern and not overly complex:

   ```swift
   if asset.type == .video {
       let thumbnail = VideoViewerView.generateThumbnail(from: url)
       Group {
           if let thumb = thumbnail {
               Image(nsImage: thumb)
                   .resizable()
                   .aspectRatio(contentMode: .fit)
           } else {
               ZStack {
                   Color.black.opacity(0.05)
                   Image(systemName: "play.circle.fill")
                       .font(.system(size: 48))
                       .foregroundStyle(.white)
               }
           }
       }
       .frame(width: 400, height: 280)
       .clipShape(RoundedRectangle(cornerRadius: 8))
       .onTapGesture {
           ViewerWindowManager.shared.openVideoViewer(url: url)
       }
       .contextMenu { ... }
   }
   ```

   And add a static method to VideoViewerView for thumbnail generation. Actually, let me keep it simple and put the thumbnail generation as a utility function. Or even simpler — just use the play icon approach. The user said "视频跟图片一样的预览方式" but for video the thumbnail is less important since you click to play anyway.

   Let me go with the simple play icon approach to keep YAGNI. The user can always enhance later.

- [ ] **Step 2: Verify build**

Run: `xcodegen generate && xcodebuild build -project Archiver.xcodeproj -scheme Archiver -destination 'platform=macOS' 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add Views/Item/ItemDetailView.swift
git commit -m "feat: use ViewerWindowManager for image/video viewing"
```

---

### Task 6: Final build verification

- [ ] **Step 1: Full clean build**

Run: `xcodegen generate && xcodebuild build -project Archiver.xcodeproj -scheme Archiver -destination 'platform=macOS' 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 2: Manual test checklist**

- 点击正文图片 → 打开独立窗口，白色背景，可拖动/缩放/关闭
- ESC 键关闭窗口
- 点击媒体轮播图片 → 打开独立窗口
- 点击视频缩略图 → 打开独立窗口播放视频
- 调整窗口大小后关闭，再次打开 → 恢复上次大小
- 同时打开多个图片窗口 → 可以并排对比
- 左右箭头键切换图片
- 双击图片缩放

- [ ] **Step 3: Final commit if any fixes needed**

```bash
git add -A
git commit -m "fix: address issues from manual testing"
```
