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
