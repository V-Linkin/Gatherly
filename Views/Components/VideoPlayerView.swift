import SwiftUI
import AVKit

/// 视频播放器视图
struct VideoPlayerView: NSViewRepresentable {
    let url: URL
    
    func makeNSView(context: Context) -> AVPlayerView {
        let playerView = AVPlayerView()
        playerView.controlsStyle = .inline
        playerView.showsFullScreenToggleButton = true
        playerView.videoGravity = .resizeAspect
        playerView.player = AVPlayer(url: url)
        
        context.coordinator.startMonitoring(playerView: playerView)
        
        return playerView
    }
    
    func updateNSView(_ nsView: AVPlayerView, context: Context) {}
    
    func makeCoordinator() -> ScrollCoordinator {
        ScrollCoordinator()
    }
}

/// 全局滚轮事件监听 - 鼠标在视频上时转发滚轮给外层 ScrollView
@MainActor
final class ScrollCoordinator {
    private var monitor: Any?
    private weak var currentPlayerView: AVPlayerView?
    
    nonisolated func startMonitoring(playerView: AVPlayerView) {
        Task { @MainActor in
            self.currentPlayerView = playerView
            
            self.monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event -> NSEvent? in
                guard let self = self,
                      let pv = self.currentPlayerView,
                      let window = pv.window else { return event }
                
                let mouseLocation = NSEvent.mouseLocation
                let locationInWindow = window.convertPoint(fromScreen: mouseLocation)
                let locationInView = pv.convert(locationInWindow, from: nil)
                
                guard pv.bounds.contains(locationInView) else { return event }
                
                // 鼠标在视频上，查找外层 ScrollView
                var current: NSView? = pv
                while let v = current {
                    if let sv = v as? NSScrollView {
                        sv.scrollWheel(with: event)
                        return nil
                    }
                    current = v.superview
                }
                
                return event
            }
        }
    }
    
    deinit {
        if let monitor = monitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}
