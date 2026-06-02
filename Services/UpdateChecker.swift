import Foundation
import OSLog
import AppKit

struct GitHubRelease: Codable {
    let tagName: String
    let name: String
    let body: String?
    let htmlURL: String
    let publishedAt: String?
    
    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name, body
        case htmlURL = "html_url"
        case publishedAt = "published_at"
    }
}

enum UpdateStatus {
    case idle
    case checking
    case upToDate
    case updateAvailable(version: String, release: GitHubRelease)
    case downloading(progress: Double)
    case downloaded(dmgPath: URL, version: String)
    case error(String)
}

@MainActor
@Observable
final class UpdateChecker: NSObject {
    static let shared = UpdateChecker()
    
    private let repoOwner = "V-Linkin"
    private let repoName = "Archiver"
    private let logger = Logger(subsystem: "com.archiver.app", category: "Update")
    
    var status: UpdateStatus = .idle
    var isChecking: Bool = false
    
    private var downloadContinuation: CheckedContinuation<URL, Never>?
    private var expectedFileSize: Int64 = 0
    
    private var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }
    
    override init() {
        super.init()
    }
    
    // MARK: - Check
    
    func checkForUpdates() async {
        isChecking = true
        status = .checking
        await checkViaAPI()
        isChecking = false
    }
    
    // MARK: - Download
    
    func downloadUpdate(version: String, dmgURL: URL) async {
        status = .downloading(progress: 0)
        
        // 获取预期文件大小
        if let resourceValues = try? dmgURL.resourceValues(forKeys: [.fileSizeKey]) {
            expectedFileSize = Int64(resourceValues.fileSize ?? 0)
        }
        
        // 检查磁盘空间
        let tempDir = FileManager.default.temporaryDirectory
        let available = (try? FileManager.default.attributesOfFileSystem(forPath: tempDir.path)[.systemFreeSize] as? Int64) ?? 0
        if expectedFileSize > 0 && available < expectedFileSize * 2 {
            status = .error("磁盘空间不足，需要至少 \(expectedFileSize * 2 / 1024 / 1024)MB")
            return
        }
        
        let config = URLSessionConfiguration.default
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        
        let downloadTask = session.downloadTask(with: dmgURL)
        downloadTask.resume()
        
        let tempURL = await withCheckedContinuation { continuation in
            self.downloadContinuation = continuation
        }
        
        let dmgPath = tempDir.appendingPathComponent("Archiver_update.dmg")
        do {
            if FileManager.default.fileExists(atPath: dmgPath.path) {
                try FileManager.default.removeItem(at: dmgPath)
            }
            try FileManager.default.moveItem(at: tempURL, to: dmgPath)
            status = .downloaded(dmgPath: dmgPath, version: version)
        } catch {
            logger.error("移动 DMG 失败: \(error.localizedDescription, privacy: .public)")
            status = .error("下载失败：\(error.localizedDescription)")
        }
    }
    
    // MARK: - Install
    
    func installUpdate(dmgPath: URL) {
        guard let scriptPath = Bundle.main.path(forResource: "install_update", ofType: "sh") else {
            status = .error("找不到安装脚本")
            return
        }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [scriptPath, dmgPath.path]
        
        do {
            try process.run()
            // 给脚本一点时间启动，然后退出 app
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                NSApplication.shared.terminate(nil)
            }
        } catch {
            logger.error("启动安装脚本失败: \(error.localizedDescription, privacy: .public)")
            status = .error("安装失败：\(error.localizedDescription)")
        }
    }
    
    // MARK: - Check downloaded update on launch
    
    func checkForDownloadedUpdate() {
        let dmgPath = FileManager.default.temporaryDirectory.appendingPathComponent("Archiver_update.dmg")
        guard FileManager.default.fileExists(atPath: dmgPath.path) else { return }
        status = .downloaded(dmgPath: dmgPath, version: "新版本")
    }
    
    // MARK: - Release Page (fallback)
    
    func openReleasePage() {
        if let url = URL(string: "https://github.com/\(repoOwner)/\(repoName)/releases/latest") {
            NSWorkspace.shared.open(url)
        }
    }
    
    // MARK: - Helpers
    
    func dmgDownloadURL(version: String) -> URL? {
        URL(string: "https://github.com/\(repoOwner)/\(repoName)/releases/download/v\(version)/Archiver_v\(version).dmg")
    }
    
    func resetStatus() {
        status = .idle
    }
    
    // MARK: - Private
    
    private func checkViaAPI() async {
        guard let url = URL(string: "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest") else {
            status = .error("地址错误"); return
        }
        
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.setValue("Archiver-macOS/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { status = .error("网络异常"); return }
            
            if http.statusCode == 403 {
                await checkViaAtomFeed(); return
            }
            guard http.statusCode == 200 else {
                status = http.statusCode == 404 ? .upToDate : .error("GitHub 返回 \(http.statusCode)")
                return
            }
            
            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            let latest = release.tagName.replacingOccurrences(of: "v", with: "")
            if compareVersions(latest, isNewerThan: currentVersion) {
                status = .updateAvailable(version: latest, release: release)
            } else {
                status = .upToDate
            }
        } catch {
            await checkViaAtomFeed()
        }
    }
    
    private func checkViaAtomFeed() async {
        guard let url = URL(string: "https://github.com/\(repoOwner)/\(repoName)/releases.atom") else {
            status = .error("地址错误"); return
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let xml = String(data: data, encoding: .utf8) else { status = .error("解析失败"); return }
            if let version = extractVersionFromAtom(xml), compareVersions(version, isNewerThan: currentVersion) {
                let release = GitHubRelease(tagName: "v\(version)", name: "v\(version)", body: nil,
                    htmlURL: "https://github.com/\(repoOwner)/\(repoName)/releases/tag/v\(version)", publishedAt: nil)
                status = .updateAvailable(version: version, release: release)
            } else {
                status = .upToDate
            }
        } catch {
            status = .error("检查失败，请检查网络")
        }
    }
    
    private func extractVersionFromAtom(_ xml: String) -> String? {
        let pattern = "<title>v([0-9]+\\.[0-9]+\\.[0-9]+)</title>"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: xml, range: NSRange(xml.startIndex..., in: xml)),
              let range = Range(match.range(at: 1), in: xml) else { return nil }
        return String(xml[range])
    }
    
    private func compareVersions(_ a: String, isNewerThan b: String) -> Bool {
        let pa = a.split(separator: ".").compactMap { Int($0) }
        let pb = b.split(separator: ".").compactMap { Int($0) }
        for i in 0..<max(pa.count, pb.count) {
            let va = i < pa.count ? pa[i] : 0
            let vb = i < pb.count ? pb[i] : 0
            if va > vb { return true }
            if va < vb { return false }
        }
        return false
    }
}

// MARK: - URLSessionDownloadDelegate

extension UpdateChecker: URLSessionDownloadDelegate {
    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // 移动到安全位置（原 location 会被系统清理）
        let tempDir = FileManager.default.temporaryDirectory
        let savedURL = tempDir.appendingPathComponent("Archiver_downloading_\(ProcessInfo.processInfo.globallyUniqueString).dmg")
        do {
            try FileManager.default.moveItem(at: location, to: savedURL)
            Task { @MainActor in
                self.downloadContinuation?.resume(returning: savedURL)
                self.downloadContinuation = nil
            }
        } catch {
            Task { @MainActor in
                self.downloadContinuation?.resume(returning: location)
                self.downloadContinuation = nil
            }
        }
    }
    
    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        Task { @MainActor in
            self.status = .downloading(progress: progress)
        }
    }
}
