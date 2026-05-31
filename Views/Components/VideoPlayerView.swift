import SwiftUI
import AVFoundation
import AppKit

/// 视频播放器视图 - 用 AVPlayerLayer 实现，完全控制事件处理
struct VideoPlayerView: NSViewRepresentable {
    let url: URL
    
    func makeNSView(context: Context) -> VideoPlayerNSView {
        let view = VideoPlayerNSView(frame: NSRect(x: 0, y: 0, width: 400, height: 280))
        view.loadVideo(url: url)
        print("[DEBUG:VideoPlayer] makeNSView url=\(url.path)")
        return view
    }
    
    func updateNSView(_ nsView: VideoPlayerNSView, context: Context) {}
}

/// 底层 NSView - 使用 AVPlayerLayer，忽略滚轮事件
class VideoPlayerNSView: NSView {
    private var player: AVPlayer?
    private var playerLayer: AVPlayerLayer?
    private var hasPlayed = false
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        print("[DEBUG:VideoPlayerNSView] init frame=\(frameRect)")
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
    }
    
    func loadVideo(url: URL) {
        print("[DEBUG:VideoPlayerNSView] loadVideo \(url.path)")
        let player = AVPlayer(url: url)
        self.player = player
        
        let playerLayer = AVPlayerLayer(player: player)
        playerLayer.videoGravity = .resizeAspect
        playerLayer.backgroundColor = NSColor.black.cgColor
        playerLayer.frame = self.bounds
        self.layer?.addSublayer(playerLayer)
        self.playerLayer = playerLayer
        
        print("[DEBUG:VideoPlayerNSView] layer bounds=\(self.bounds), playerLayer frame=\(playerLayer.frame)")
    }
    
    override func layout() {
        super.layout()
        print("[DEBUG:VideoPlayerNSView] layout bounds=\(bounds)")
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer?.frame = bounds
        CATransaction.commit()
    }
    
    /// 忽略滚轮事件
    override func scrollWheel(with event: NSEvent) {
        self.nextResponder?.scrollWheel(with: event)
    }
    
    /// 鼠标点击时播放/暂停
    override func mouseDown(with event: NSEvent) {
        if let player = player {
            if hasPlayed {
                if player.timeControlStatus == .playing {
                    player.pause()
                } else {
                    player.play()
                }
            } else {
                player.seek(to: .zero)
                player.play()
                hasPlayed = true
            }
        }
    }
    
    deinit {
        player?.pause()
    }
}
