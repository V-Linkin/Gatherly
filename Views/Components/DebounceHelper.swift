import Foundation

/// 导航防抖：防止双击触发多次导航
final class NavDebounce: @unchecked Sendable {
    static let shared = NavDebounce()
    
    private var lastNavigationTime: Date = .distantPast
    private let queue = DispatchQueue(label: "com.archiver.debounce")
    private let minimumInterval: TimeInterval = 0.5

    private init() {}

    /// 检查是否可以导航，如果可以则记录时间并返回 true
    func canNavigate() -> Bool {
        queue.sync {
            let now = Date()
            let elapsed = now.timeIntervalSince(lastNavigationTime)
            if elapsed >= minimumInterval {
                lastNavigationTime = now
                return true
            }
            return false
        }
    }
}
