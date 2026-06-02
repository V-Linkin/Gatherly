import SwiftUI

struct ImageViewerView: View {
    let images: [NSImage]
    @Binding var currentIndex: Int
    @Binding var isPresented: Bool
    
    @State private var scale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastDragTranslation: CGSize = .zero
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.white.ignoresSafeArea()
                
                if !images.isEmpty {
                    currentImage(geo)
                    navigationButtons
                    pageInfo
                }
            }
        }
        .onKeyDown { event in
            handleKeyPress(event)
        }
        .onScrollWheelEvent { event in
            handleScrollWheel(event)
        }
        .onAppear {
            resetZoom()
        }
        .onChange(of: currentIndex) { _, _ in
            resetZoom()
        }
        .frame(minWidth: 400, minHeight: 300)
    }
    
    // MARK: - Current Image
    
    @ViewBuilder
    private func currentImage(_ geo: GeometryProxy) -> some View {
        if currentIndex >= 0 && currentIndex < images.count {
            Image(nsImage: images[currentIndex])
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: geo.size.width * 0.85, maxHeight: geo.size.height * 0.85)
                .scaleEffect(scale)
                .offset(offset)
                .gesture(
                    DragGesture(minimumDistance: 1)
                        .onChanged { value in
                            let dx = value.translation.width - lastDragTranslation.width
                            let dy = value.translation.height - lastDragTranslation.height
                            lastDragTranslation = value.translation
                            offset = CGSize(
                                width: offset.width + dx,
                                height: offset.height + dy
                            )
                        }
                        .onEnded { _ in
                            lastDragTranslation = .zero
                            if scale <= 1.0 {
                                withAnimation { offset = .zero }
                            } else {
                                clampOffset()
                            }
                        }
                )
                .onTapGesture(count: 2) {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        if scale > 1.0 {
                            scale = 1.0
                            offset = .zero
                        } else {
                            scale = 2.0
                        }
                    }
                }
                .id(currentIndex)
                .transition(.asymmetric(
                    insertion: .move(edge: currentIndex > 0 ? .trailing : .leading),
                    removal: .move(edge: currentIndex > 0 ? .leading : .trailing)
                ))
                .animation(.easeInOut(duration: 0.25), value: currentIndex)
        }
    }
    
    // MARK: - Navigation Buttons
    
    private var navigationButtons: some View {
        HStack {
            if currentIndex > 0 {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        currentIndex -= 1
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(.primary)
                        .frame(width: 44, height: 44)
                        .background(Color.black.opacity(0.08))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .padding(.leading, 20)
            }
            
            Spacer()
            
            if currentIndex < images.count - 1 {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        currentIndex += 1
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(.primary)
                        .frame(width: 44, height: 44)
                        .background(Color.black.opacity(0.08))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .padding(.trailing, 20)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(true)
    }
    
    // MARK: - Page Info
    
    private var pageInfo: some View {
        VStack {
            Spacer()
            if images.count > 1 {
                Text("\(currentIndex + 1) / \(images.count)")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.primary.opacity(0.6))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.08))
                    .clipShape(Capsule())
                    .padding(.bottom, 24)
            }
        }
    }
    
    // MARK: - Close Button
    

    
    // MARK: - Helpers
    
    private func resetZoom() {
        withAnimation(.easeInOut(duration: 0.2)) {
            scale = 1.0
            offset = .zero
            lastDragTranslation = .zero
        }
    }
    
    private func clampOffset() {
        withAnimation {
            let maxX = (scale - 1.0) * 300
            let maxY = (scale - 1.0) * 200
            offset.width = min(max(offset.width, -maxX), maxX)
            offset.height = min(max(offset.height, -maxY), maxY)
        }
    }
    
    private func handleKeyPress(_ event: NSEvent) {
        switch event.keyCode {
        case 53:
            withAnimation(.easeInOut(duration: 0.2)) {
                isPresented = false
            }
        case 123:
            if currentIndex > 0 {
                withAnimation(.easeInOut(duration: 0.2)) {
                    currentIndex -= 1
                }
            }
        case 124:
            if currentIndex < images.count - 1 {
                withAnimation(.easeInOut(duration: 0.2)) {
                    currentIndex += 1
                }
            }
        default:
            break
        }
    }
    
    private func handleScrollWheel(_ event: NSEvent) {
        let delta = event.scrollingDeltaY
        scale = min(max(scale + delta * 0.008, 0.5), 5.0)
    }
}

// MARK: - Keyboard & ScrollWheel Event Monitor

private struct EventMonitorModifier: ViewModifier {
    let keyHandler: (NSEvent) -> Void
    let scrollHandler: (NSEvent) -> Void
    
    func body(content: Content) -> some View {
        content.background(
            EventMonitorRepresenter(keyHandler: keyHandler, scrollHandler: scrollHandler)
        )
    }
}

private struct EventMonitorRepresenter: NSViewRepresentable {
    let keyHandler: (NSEvent) -> Void
    let scrollHandler: (NSEvent) -> Void
    
    func makeNSView(context: Context) -> EventMonitorNSView {
        let view = EventMonitorNSView()
        view.keyHandler = keyHandler
        view.scrollHandler = scrollHandler
        return view
    }
    
    func updateNSView(_ nsView: EventMonitorNSView, context: Context) {
        nsView.keyHandler = keyHandler
        nsView.scrollHandler = scrollHandler
    }
}

private class EventMonitorNSView: NSView {
    var keyHandler: ((NSEvent) -> Void)?
    var scrollHandler: ((NSEvent) -> Void)?
    nonisolated(unsafe) private var keyMonitor: Any?
    nonisolated(unsafe) private var scrollMonitor: Any?
    
    override var acceptsFirstResponder: Bool { true }
    
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                self?.keyHandler?(event)
                if event.keyCode == 53 { return nil }
                return event
            }
            scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                self?.scrollHandler?(event)
                return event
            }
            window?.makeFirstResponder(self)
        } else {
            removeMonitors()
        }
    }
    
    private func removeMonitors() {
        if let keyMonitor = keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        if let scrollMonitor = scrollMonitor {
            NSEvent.removeMonitor(scrollMonitor)
            self.scrollMonitor = nil
        }
    }
    
    deinit {
        if let keyMonitor = keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        if let scrollMonitor = scrollMonitor {
            NSEvent.removeMonitor(scrollMonitor)
        }
    }
}

extension View {
    func onKeyDown(handler: @escaping (NSEvent) -> Void) -> some View {
        modifier(EventMonitorModifier(keyHandler: handler, scrollHandler: { _ in }))
    }
    
    func onScrollWheelEvent(handler: @escaping (NSEvent) -> Void) -> some View {
        modifier(EventMonitorModifier(keyHandler: { _ in }, scrollHandler: handler))
    }
}
