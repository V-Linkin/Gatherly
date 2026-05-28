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
    case error(String)
}

@MainActor
@Observable
final class UpdateChecker {
    static let shared = UpdateChecker()
    
    private let repoOwner = "V-Linkin"
    private let repoName = "Archiver"
    private let logger = Logger(subsystem: "com.archiver.app", category: "Update")
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        return URLSession(configuration: config)
    }()
    
    var status: UpdateStatus = .idle
    var isChecking: Bool = false
    
    private var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }
    
    func checkForUpdates() async {
        isChecking = true
        status = .checking
        await checkViaAPI()
        isChecking = false
    }
    
    private func checkViaAPI() async {
        guard let url = URL(string: "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest") else {
            status = .error("地址错误"); return
        }
        
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.setValue("Archiver-macOS/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        
        do {
            let (data, response) = try await session.data(for: request)
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
            let (data, _) = try await session.data(from: url)
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
    
    func openReleasePage() {
        if let url = URL(string: "https://github.com/\(repoOwner)/\(repoName)/releases/latest") {
            NSWorkspace.shared.open(url)
        }
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
