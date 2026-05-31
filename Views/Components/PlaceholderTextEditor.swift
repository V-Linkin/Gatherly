import SwiftUI
import AppKit

class PassthroughLabel: NSTextField {
    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }
    override var acceptsFirstResponder: Bool { false }
}

struct PlaceholderTextEditor: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    
    func makeNSView(context: Context) -> PlaceholderTextEditorNSView {
        let view = PlaceholderTextEditorNSView(placeholder: placeholder)
        view.text = text
        view.onTextChange = { newText in
            DispatchQueue.main.async {
                self.text = newText
            }
        }
        return view
    }
    
    func updateNSView(_ nsView: PlaceholderTextEditorNSView, context: Context) {
        if nsView.textView.string != text {
            nsView.textView.string = text
        }
        nsView.updatePlaceholder()
    }
}



// MARK: - 可穿透的 NSScrollView（内容滚到底后传递事件给父级）

class PassthroughScrollView: NSScrollView {
    override func scrollWheel(with event: NSEvent) {
        let canScrollVertically = documentView.map { $0.bounds.height > frame.height } ?? false
        guard canScrollVertically else {
            // 内容不需要滚动，直接传递给父级
            nextResponder?.scrollWheel(with: event)
            return
        }
        
        let atBottom = (documentView!.bounds.height - (documentVisibleRect.origin.y + documentVisibleRect.height)) < 1.0
        let atTop = documentVisibleRect.origin.y < 1.0
        
        let scrollingDown = event.scrollingDeltaY > 0
        
        if (scrollingDown && atBottom) || (!scrollingDown && atTop) {
            // 已经到底/到顶，传递给父级
            nextResponder?.scrollWheel(with: event)
        } else {
            // 还能滚动，正常处理
            super.scrollWheel(with: event)
        }
    }
}

class PlaceholderTextEditorNSView: NSView, NSTextViewDelegate {
    var text: String = ""
    var onTextChange: ((String) -> Void)?
    
    let textView = NSTextView()
    var placeholderLabel: PassthroughLabel!
    var scrollView: NSScrollView!
    
    init(placeholder: String) {
        super.init(frame: .zero)
        setup(placeholder: placeholder)
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup(placeholder: "")
    }
    
    private func setup(placeholder: String) {
        textView.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        textView.textColor = NSColor.labelColor
        textView.isRichText = false
        textView.allowsUndo = true
        textView.textContainerInset = NSSize(width: 5, height: 8)
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.delegate = self
        
        scrollView = PassthroughScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        
        addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        
        placeholderLabel = PassthroughLabel(labelWithString: placeholder)
        placeholderLabel.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        placeholderLabel.textColor = .placeholderTextColor
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(placeholderLabel)
        
        // 从 debug 数据推算:
        // textContainerInset.height=8, bounds.height=80
        // NSTextView 光标顶部在 y=72 (80-8)
        // NSTextField 内部文字顶部约在 label.top - 1.5
        // 所以 label.top = 72 + 1.5 = 73.5, topOffset = 80 - 73.5 ≈ 6.5
        NSLayoutConstraint.activate([
            placeholderLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 11),
            placeholderLabel.topAnchor.constraint(equalTo: topAnchor, constant: 7)
        ])
    }
    
    func updatePlaceholder() {
        placeholderLabel.isHidden = !textView.string.isEmpty
    }
    
    func textDidChange(_ notification: Notification) {
        updatePlaceholder()
        onTextChange?(textView.string)
    }
}
