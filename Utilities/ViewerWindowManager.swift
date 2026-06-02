import AppKit
import AVFoundation
import AVKit
import SwiftUI

@MainActor
final class ViewerWindowManager {
    static let shared = ViewerWindowManager()
    
    private var windows: [NSWindow] = []
    private var players: [ObjectIdentifier: AVPlayer] = [:]
    private let userDefaultsKey = "viewerWindowSize"
    private let defaultSize = NSSize(width: 800, height: 600)
    private let minSize = NSSize(width: 400, height: 300)
    
    private init() {}
    
    // MARK: - Image Viewer
    
    func openImageViewer(images: [NSImage], startIndex: Int = 0) {
        guard !images.isEmpty else { return }
        
        let savedSize = savedWindowSize()
        let content = ImageViewerWindowContent(
            images: images,
            startIndex: startIndex
        )
        
        let window = createWindow(size: savedSize, content: content)
        windows.append(window)
        window.makeKeyAndOrderFront(self)
    }
    
    // MARK: - Video Viewer
    
    func openVideoViewer(url: URL) {
        let player = AVPlayer(url: url)
        
        let content = VideoViewerView(player: player)
            .frame(minWidth: minSize.width, minHeight: minSize.height)
            .onKeyDown { event in
                if event.keyCode == 53 {
                    NSApp.keyWindow?.close()
                }
            }
        
        let windowSize = videoWindowSize(url: url)
        let window = createWindow(size: windowSize, content: content)
        windows.append(window)
        window.makeKeyAndOrderFront(self)
        
        // Store player reference keyed by window
        let windowID = ObjectIdentifier(window)
        players[windowID] = player
        player.play()
    }
    
    private func videoWindowSize(url: URL) -> NSSize {
        let asset = AVURLAsset(url: url)
        let tracks = asset.tracks(withMediaType: .video)
        guard let track = tracks.first else { return savedWindowSize() }
        
        let size = track.naturalSize
        let transform = track.preferredTransform
        let rotatedWidth = abs(transform.a) * size.width + abs(transform.c) * size.height
        let rotatedHeight = abs(transform.b) * size.width + abs(transform.d) * size.height
        
        guard rotatedWidth > 0 && rotatedHeight > 0 else { return savedWindowSize() }
        
        let maxWidth: CGFloat = 720
        let maxHeight: CGFloat = 540
        let scale = min(maxWidth / rotatedWidth, maxHeight / rotatedHeight, 1.0)
        let targetWidth = max(rotatedWidth * scale, minSize.width)
        let targetHeight = max(rotatedHeight * scale, minSize.height)
        
        return NSSize(width: targetWidth, height: targetHeight)
    }
    
    // MARK: - Close All
    
    func closeAll() {
        stopAllPlayers()
        for window in windows {
            window.close()
        }
        windows.removeAll()
    }
    
    // MARK: - Window Factory
    
    private func createWindow(size: NSSize, content: some View) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        
        window.titlebarAppearsTransparent = true
        window.backgroundColor = NSColor.white
        window.contentView = NSHostingView(rootView: content)
        window.minSize = minSize
        window.contentMinSize = minSize
        window.isReleasedWhenClosed = false
        window.center()
        
        let windowID = ObjectIdentifier(window)
        
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.stopPlayer(for: windowID)
                self?.saveWindowSize(window.frame.size)
                self?.windows.removeAll { $0 === window }
            }
        }
        
        return window
    }
    
    // MARK: - Player Management
    
    private func stopPlayer(for windowID: ObjectIdentifier) {
        guard let player = players[windowID] else { return }
        player.pause()
        player.replaceCurrentItem(with: nil)
        players.removeValue(forKey: windowID)
    }
    
    private func stopAllPlayers() {
        for (_, player) in players {
            player.pause()
            player.replaceCurrentItem(with: nil)
        }
        players.removeAll()
    }
    
    // MARK: - Size Persistence
    
    private func savedWindowSize() -> NSSize {
        let width = UserDefaults.standard.double(forKey: "\(userDefaultsKey)_width")
        let height = UserDefaults.standard.double(forKey: "\(userDefaultsKey)_height")
        if width > 0 && height > 0 {
            return NSSize(width: width, height: height)
        }
        return defaultSize
    }
    
    private func saveWindowSize(_ size: NSSize) {
        UserDefaults.standard.set(size.width, forKey: "\(userDefaultsKey)_width")
        UserDefaults.standard.set(size.height, forKey: "\(userDefaultsKey)_height")
    }
}

// MARK: - Image Viewer Window Content

private struct ImageViewerWindowContent: View {
    let images: [NSImage]
    let startIndex: Int
    @State private var currentIndex: Int = 0
    @State private var isPresented = true
    
    var body: some View {
        ImageViewerView(
            images: images,
            currentIndex: $currentIndex,
            isPresented: $isPresented
        )
        .onAppear {
            currentIndex = startIndex
        }
        .onChange(of: isPresented) { _, presented in
            if !presented {
                NSApp.keyWindow?.close()
            }
        }
        .onKeyDown { event in
            if event.keyCode == 53 {
                NSApp.keyWindow?.close()
            }
        }
        .frame(minWidth: 400, minHeight: 300)
    }
}
