import SwiftUI
import AVKit

/// 视频播放器视图 - 用于详情页展示本地视频
struct VideoPlayerView: NSViewRepresentable {
    let url: URL
    
    func makeNSView(context: Context) -> AVPlayerView {
        let playerView = AVPlayerView()
        playerView.controlsStyle = .inline
        playerView.showsFullScreenToggleButton = true
        playerView.videoGravity = .resizeAspect
        
        let player = AVPlayer(url: url)
        playerView.player = player
        
        return playerView
    }
    
    func updateNSView(_ nsView: AVPlayerView, context: Context) {}
}
