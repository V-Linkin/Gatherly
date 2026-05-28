import Foundation

/// 下载状态
enum DownloadStatus: String, Codable {
    case pending      // 等待下载
    case downloading  // 下载中
    case completed    // 下载完成
    case failed       // 下载失败
    case skipped      // 已跳过
}
