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
        return playerView
    }
    
    func updateNSView(_ nsView: AVPlayerView, context: Context) {}
}
