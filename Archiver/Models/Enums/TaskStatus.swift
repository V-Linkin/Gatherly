import Foundation

/// 导入任务状态
enum TaskStatus: String, Codable {
    case pending       // 等待处理
    case recognizing   // 识别平台中
    case parsing       // 解析内容中
    case downloading   // 下载媒体中
    case completed     // 完成
    case failed        // 失败
}
