import Foundation
import AppKit
import UniformTypeIdentifiers

@MainActor
struct FilePicker {

    static func pickImages() -> [URL] {
        let panel = NSOpenPanel()
        panel.title = "选择图片"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.image]
        panel.directoryURL = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first

        guard panel.runModal() == .OK else { return [] }
        return panel.urls
    }

    static func pickVideos() -> [URL] {
        let panel = NSOpenPanel()
        panel.title = "选择视频"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.movie, .mpeg4Movie, .quickTimeMovie]
        panel.directoryURL = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first

        guard panel.runModal() == .OK else { return [] }
        return panel.urls
    }

    static func pickMedia() -> [URL] {
        let panel = NSOpenPanel()
        panel.title = "选择媒体文件"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.image, .movie, .mpeg4Movie, .quickTimeMovie]
        panel.directoryURL = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first

        guard panel.runModal() == .OK else { return [] }
        return panel.urls
    }
}
