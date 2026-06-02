import SwiftUI
import AVKit

/// 视频查看器 — 独立窗口中播放视频
struct VideoViewerView: NSViewRepresentable {
    let player: AVPlayer
    
    func makeNSView(context: Context) -> AVPlayerView {
        let playerView = AVPlayerView()
        playerView.controlsStyle = .inline
        playerView.showsFullScreenToggleButton = true
        playerView.videoGravity = .resizeAspect
        playerView.player = player
        return playerView
    }
    
    func updateNSView(_ nsView: AVPlayerView, context: Context) {}
}
