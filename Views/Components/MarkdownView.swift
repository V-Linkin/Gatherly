import SwiftUI

struct MarkdownView: View {
    let text: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(parseBlocks().enumerated()), id: \.offset) { _, block in
                switch block {
                case .text(let content):
                    if let attributedString = try? AttributedString(
                        markdown: content,
                        options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
                    ) {
                        Text(attributedString)
                            .textSelection(.enabled)
                    } else {
                        Text(content)
                            .textSelection(.enabled)
                    }
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
