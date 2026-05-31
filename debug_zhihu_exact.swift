import Foundation
import WebKit

// 与 ZhihuWebLoader 完全相同的测试
final class ExactZhihuWebLoader: NSObject, WKNavigationDelegate {
    private var webView: WKWebView?
    private var continuation: CheckedContinuation<String?, Never>?
    private var loadTimeout: Task<Void, Never>?
    private var didFinishInitialLoad = false
    
    @MainActor
    func loadFullContent(from url: URL) async -> String? {
        print("🔍 [ZhihuWebLoader] 开始加载: \(url.absoluteString)")
        
        didFinishInitialLoad = false
        let config = WKWebViewConfiguration()
        config.suppressesIncrementalRendering = true
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        self.webView = webView
        
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            
            self.loadTimeout = Task {
                print("🔍 [ZhihuWebLoader] 设置 15秒 超时")
                try? await Task.sleep(for: .seconds(15))
                if self.continuation != nil {
                    print("🔍 [ZhihuWebLoader] 超时触发，返回 nil")
                    self.finishWith(nil)
                }
            }
            
            print("🔍 [ZhihuWebLoader] 开始加载 URL")
            webView.load(URLRequest(url: url))
        }
    }
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        print("🔍 [ZhihuWebLoader] 页面加载完成")
        
        Task { @MainActor in
            if !didFinishInitialLoad {
                didFinishInitialLoad = true
            }
            
            // 轮询等待页面就绪
            await pollUntilReady(webView: webView)
        }
    }
    
    @MainActor
    private func pollUntilReady(webView: WKWebView) {
        Task {
            let maxAttempts = 12
            let checkJS = "document.querySelector('#js-initialData') ? 'ready' : document.body.innerText.length > 500 ? 'loaded' : 'challenge'"
            
            print("🔍 [ZhihuWebLoader] 开始轮询检查")
            
            for attempt in 0..<maxAttempts {
                try? await Task.sleep(for: .milliseconds(500))
                
                guard let result = try? await webView.evaluateJavaScript(checkJS) as? String else {
                    print("🔍 [ZhihuWebLoader] 第 \(attempt + 1) 次检查: JavaScript 执行失败")
                    continue
                }
                
                print("🔍 [ZhihuWebLoader] 第 \(attempt + 1) 次检查: \(result)")
                
                if result == "ready" || result == "loaded" {
                    print("🔍 [ZhihuWebLoader] 页面已就绪，开始提取")
                    try? await Task.sleep(for: .milliseconds(500))
                    extractContent(from: webView)
                    return
                }
                
                if result == "challenge" {
                    print("🔍 [ZhihuWebLoader] 检测到 challenge 页面")
                }
            }
            
            print("🔍 [ZhihuWebLoader] 轮询超时，尝试提取")
            extractContent(from: webView)
        }
    }
    
    @MainActor
    private func extractContent(from webView: WKWebView) {
        print("🔍 [ZhihuWebLoader] 开始执行 JavaScript")
        
        let js = """
        (function() {
            try {
                var url = document.location.href;
                var bodyLen = document.body ? document.body.innerText.length : 0;
                
                if (url.indexOf('coolapk.com') !== -1 || url.indexOf('coolapk1s.com') !== -1) {
                    var coolapkResult = {
                        title: '',
                        text: '',
                        author: '',
                        images: [],
                        cover: '',
                        debug: 'bodyLen:' + bodyLen
                    };
                    
                    // 1. 尝试从页面标题提取实际文章标题
                    var pageTitle = document.title || '';
                    if (pageTitle && pageTitle !== '酷安APP' && pageTitle.length > 5) {
                        coolapkResult.title = pageTitle;
                    }
                    
                    // 2. 提取正文内容（使用正确的选择器）
                    var contentEl = document.querySelector('.content');
                    if (contentEl) {
                        coolapkResult.text = contentEl.innerText.trim();
                    }
                    
                    // 3. 提取图片（使用正确的选择器）
                    var imgEls = document.querySelectorAll('.content img, .message-image img');
                    var allImages = Array.from(imgEls).map(function(img) {
                        return img.src;
                    }).filter(function(src) {
                        return src && src.indexOf('http') === 0;
                    });
                    
                    // 过滤掉常见非内容图片
                    var contentImages = allImages.filter(function(src) {
                        return !src.includes('static.coolapk.com/static/web') &&
                               !src.includes('avatar.coolapk.com') &&
                               !src.includes('emoticons') &&
                               !src.includes('product_logo') &&
                               !src.includes('beian.png') &&
                               !src.includes('qr/image');
                    });
                    
                    coolapkResult.images = contentImages;
                    
                    // 4. 提取作者信息（使用正确的选择器）
                    var authorEl = document.querySelector('.common-userinfo-group, .userinfo-item, .username-item');
                    if (authorEl && authorEl.innerText) {
                        coolapkResult.author = authorEl.innerText.trim().replace(/\\n/g, ' ').replace(/\\s+/g, ' ');
                    }
                    
                    // 5. 设置封面（取第一张内容图片）
                    coolapkResult.cover = coolapkResult.images.length > 0 ? coolapkResult.images[0] : '';
                    
                    // 更新调试信息
                    coolapkResult.debug = 'bodyLen:' + bodyLen + 
                                        ',title:' + (coolapkResult.title ? 'yes' : 'no') +
                                        ',author:' + (coolapkResult.author ? 'yes' : 'no') +
                                        ',text:' + coolapkResult.text.length +
                                        ',images:' + coolapkResult.images.length;
                    
                    if (coolapkResult.text.length > 20 || coolapkResult.images.length > 0) {
                        return 'COOLAPK_JSON:' + JSON.stringify(coolapkResult);
                    }
                }
                
                return 'NO_CONTENT';
            } catch(e) {
                return 'ERROR:' + e.toString();
            }
        })()
        """
        
        Task {
            do {
                print("🔍 [ZhihuWebLoader] 执行 JavaScript")
                if let result = try await webView.evaluateJavaScript(js) as? String, !result.isEmpty {
                    print("🔍 [ZhihuWebLoader] JavaScript 执行成功")
                    print("🔍 [ZhihuWebLoader] 结果类型: \(result.hasPrefix("COOLAPK_JSON:") ? "COOLAPK_JSON" : "其他")")
                    self.finishWith(result)
                } else {
                    print("🔍 [ZhihuWebLoader] JavaScript 执行失败或返回空")
                    self.finishWith(nil)
                }
            } catch {
                print("🔍 [ZhihuWebLoader] JavaScript 错误: \(error)")
                self.finishWith(nil)
            }
        }
    }
    
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        print("🔍 [ZhihuWebLoader] 页面加载失败: \(error)")
        Task { @MainActor in
            self.finishWith(nil)
        }
    }
    
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        decisionHandler(.allow)
    }
    
    @MainActor
    private func finishWith(_ result: String?) {
        print("🔍 [ZhihuWebLoader] finishWith 被调用: \(result?.prefix(50) ?? "nil")")
        loadTimeout?.cancel()
        loadTimeout = nil
        continuation?.resume(returning: result)
        continuation = nil
        webView?.navigationDelegate = nil
        webView = nil
    }
}

@MainActor
func debugExact() async {
    let loader = ExactZhihuWebLoader()
    let testURL = URL(string: "https://www.coolapk.com/feed/72069721?s=M2I2ZDE5NTIxYzA3MTgyZzZhMWMyYzIwega1620")!
    
    print("=== 精确调试 ZhihuWebLoader ===")
    print("测试链接: \(testURL.absoluteString)")
    print()
    
    let result = await loader.loadFullContent(from: testURL)
    
    print()
    print("=== 最终结果 ===")
    if let result = result {
        if result.hasPrefix("COOLAPK_JSON:") {
            print("✅ 成功！返回 COOLAPK_JSON")
            let jsonStr = String(result.dropFirst("COOLAPK_JSON:".count))
            if let jsonData = jsonStr.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                print("标题: \(json["title"] ?? "无")")
                print("作者: \(json["author"] ?? "无")")
                print("正文长度: \((json["text"] as? String ?? "").count) 字符")
                print("图片数量: \((json["images"] as? [String] ?? []).count)")
            }
        } else if result == "NO_CONTENT" {
            print("❌ 没有提取到内容")
        } else if result.hasPrefix("ERROR:") {
            print("❌ JavaScript 错误: \(result)")
        } else {
            print("❓ 未知结果: \(result.prefix(100))")
        }
    } else {
        print("❌ 返回 nil")
        print("这说明 finishWith(nil) 被调用了")
    }
}

// 运行测试
if #available(macOS 14.0, *) {
    Task { @MainActor in
        await debugExact()
        exit(0)
    }
    
    RunLoop.main.run()
} else {
    print("需要 macOS 14.0+")
    exit(1)
}
