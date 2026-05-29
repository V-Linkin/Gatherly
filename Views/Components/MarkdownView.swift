import SwiftUI

struct MarkdownView: View {
    let text: String
    
    var body: some View {
        let blocks = parseBlocks()
        return VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .text(let content):
                    ParagraphText(content: content)
                case .image(let url, let alt):
                    AsyncImageView(url: url, alt: alt)
                }
            }
        }
    }
    
    private enum Block {
        case text(String)
        case image(url: String, alt: String)
    }
    
    private func parseBlocks() -> [Block] {
        if !text.contains("![") {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? [] : [.text(trimmed)]
        }
        
        var blocks: [Block] = []
        let lines = text.components(separatedBy: "\n")
        var currentText = ""
        
        let imagePattern = #"!\[([^\]]*)\]\(([^)]*)\)"#
        guard let imageRegex = try? NSRegularExpression(pattern: imagePattern) else {
            return [.text(text)]
        }
        
        for line in lines {
            let nsLine = line as NSString
            let matches = imageRegex.matches(in: line, range: NSRange(location: 0, length: nsLine.length))
            
            if matches.isEmpty {
                if !currentText.isEmpty { currentText += "\n" }
                currentText += line
            } else {
                if !currentText.isEmpty {
                    blocks.append(.text(currentText.trimmingCharacters(in: .whitespacesAndNewlines)))
                    currentText = ""
                }
                var lastEnd = 0
                for match in matches {
                    let before = nsLine.substring(to: match.range.location)
                    if !before.isEmpty {
                        blocks.append(.text(before.trimmingCharacters(in: .whitespacesAndNewlines)))
                    }
                    let alt = nsLine.substring(with: match.range(at: 1))
                    let url = nsLine.substring(with: match.range(at: 2))
                    blocks.append(.image(url: url, alt: alt))
                    lastEnd = match.range.location + match.range.length
                }
                let remaining = nsLine.substring(from: lastEnd)
                if !remaining.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    currentText = remaining
                }
            }
        }
        
        if !currentText.isEmpty {
            let trimmed = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                blocks.append(.text(trimmed))
            }
        }
        
        return blocks.isEmpty ? [.text(text)] : blocks
    }
}

// MARK: - ParagraphText（通用长文本拆分渲染组件）

/// 自动将长文本拆分为多个小段落渲染，避免 SwiftUI 单个 Text 视图过大导致布局卡顿。
/// 可复用于任何需要渲染长文本的场景。
struct ParagraphText: View {
    let content: String
    
    /// 单个 Text 视图的最大安全字符数
    private static let maxChunkSize = 500
    
    var body: some View {
        let chunks = smartSplit(content)
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(chunks.enumerated()), id: \.offset) { _, chunk in
                if let attributedString = try? AttributedString(
                    markdown: chunk,
                    options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
                ) {
                    Text(attributedString)
                        .textSelection(.enabled)
                } else {
                    Text(chunk)
                        .textSelection(.enabled)
                }
            }
        }
    }
    
    /// 智能拆分：先按段落，再按句子，最后按固定长度兜底
    private func smartSplit(_ text: String) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        
        // 如果文本很短，直接返回
        if trimmed.count <= Self.maxChunkSize {
            return [trimmed]
        }
        
        // 第一级：按双换行拆段落
        let paragraphs = trimmed.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        
        var result: [String] = []
        for para in paragraphs {
            if para.count <= Self.maxChunkSize {
                result.append(para)
            } else {
                // 第二级：段落太长，按句子拆分
                result.append(contentsOf: splitBySentences(para))
            }
        }
        
        return result.isEmpty ? [trimmed] : result
    }
    
    /// 按句子拆分，保持句子完整性
    private func splitBySentences(_ text: String) -> [String] {
        // 中英文句子结束符
        let pattern = "(?<=[。！？.!?])\\s*"
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return splitByLength(text)
        }
        
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        let splits = regex.matches(in: text, range: range).map { $0.range.location }
        
        guard !splits.isEmpty else {
            return splitByLength(text)
        }
        
        var sentences: [String] = []
        var lastEnd = 0
        for splitPos in splits {
            let sentence = nsText.substring(with: NSRange(location: lastEnd, length: splitPos - lastEnd))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !sentence.isEmpty {
                sentences.append(sentence)
            }
            lastEnd = splitPos
        }
        let remaining = nsText.substring(from: lastEnd)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !remaining.isEmpty {
            sentences.append(remaining)
        }
        
        // 合并短句子，避免碎片化
        return mergeSmallChunks(sentences)
    }
    
    /// 按固定长度兜底拆分
    private func splitByLength(_ text: String) -> [String] {
        var result: [String] = []
        var start = text.startIndex
        while start < text.endIndex {
            let end = text.index(start, offsetBy: Self.maxChunkSize, limitedBy: text.endIndex) ?? text.endIndex
            result.append(String(text[start..<end]))
            start = end
        }
        return result
    }
    
    /// 合并过短的块，减少视图数量
    private func mergeSmallChunks(_ chunks: [String]) -> [String] {
        var result: [String] = []
        var buffer = ""
        
        for chunk in chunks {
            if buffer.isEmpty {
                buffer = chunk
            } else if buffer.count + chunk.count + 1 <= Self.maxChunkSize {
                buffer += "\n" + chunk
            } else {
                result.append(buffer)
                buffer = chunk
            }
        }
        if !buffer.isEmpty {
            result.append(buffer)
        }
        
        return result
    }
}

// MARK: - AsyncImageView

struct AsyncImageView: View {
    let url: String
    let alt: String
    
    @State private var image: NSImage?
    @State private var isLoading = true
    
    var body: some View {
        Group {
            if let image = image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else if isLoading {
                ProgressView()
                    .frame(height: 100)
            } else {
                HStack {
                    Image(systemName: "photo")
                        .foregroundStyle(.tertiary)
                    Text(alt.isEmpty ? "图片加载失败" : alt)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, minHeight: 80)
                .background(.quaternary)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .onAppear { loadImage() }
    }
    
    private func loadImage() {
        guard let imageURL = URL(string: url) else {
            isLoading = false
            return
        }
        Task {
            let session = URLSession.shared
            var request = URLRequest(url: imageURL)
            request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
            guard let (data, _) = try? await session.data(for: request),
                  let nsImage = NSImage(data: data) else {
                isLoading = false
                return
            }
            self.image = nsImage
            self.isLoading = false
        }
    }
}
