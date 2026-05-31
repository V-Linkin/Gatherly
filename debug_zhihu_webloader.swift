import Foundation
import WebKit

// 详细调试 ZhihuWebLoader
final class DebugZhihuWebLoader: NSObject, WKNavigationDelegate {
    private var webView: WKWebView?
    private var continuation: CheckedContinuation<String?, Never>?
    private var loadTimeout: Task<Void, Never>?
    
    @MainActor
    func loadFullContent(from url: URL) async -> String? {
        print("🔍 [ZhihuWebLoader] 开始加载: \(url.absoluteString)")
        
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
                    print("🔍 [ZhihuWebLoader] 超时触发")
                    self.finishWith(nil)
                }
            }
            
            print("🔍 [ZhihuWebLoader] 开始加载 URL")
            webView.load(URLRequest(url: url))
        }
    }
    
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        print("🔍 [ZhihuWebLoader] 开始加载页面")
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
    
    private var didFinishInitialLoad = false
    
    @MainActor
    private func pollUntilReady(webView: WKWebView) {
        Task {
            let maxAttempts = 12  // 最多轮询 6 秒（12 × 0.5s）
            let checkJS = "document.querySelector('#js-initialData') ? 'ready' : document.body.innerText.length > 500 ? 'loaded' : 'challenge'"
            
            print("🔍 [ZhihuWebLoader] 开始轮询检查页面状态")
            
            for attempt in 0..<maxAttempts {
                try? await Task.sleep(for: .milliseconds(500))
                
                guard let result = try? await webView.evaluateJavaScript(checkJS) as? String else {
                    print("🔍 [ZhihuWebLoader] 第 \(attempt + 1) 次检查: JavaScript 执行失败")
                    continue
                }
                
                print("🔍 [ZhihuWebLoader] 第 \(attempt + 1) 次检查: \(result)")
                
                if result == "ready" || result == "loaded" {
                    print("🔍 [ZhihuWebLoader] 页面已就绪，开始提取内容")
                    // 页面已就绪，再等 0.5s 让 DOM 稳定后提取
                    try? await Task.sleep(for: .milliseconds(500))
                    extractContent(from: webView)
                    return
                }
                
                if result == "challenge" {
                    print("🔍 [ZhihuWebLoader] 检测到 challenge 页面，继续等待")
                }
            }
            
            print("🔍 [ZhihuWebLoader] 轮询超时，尝试提取内容")
            // 超时，尝试提取（可能内容不完整但比没有好）
            extractContent(from: webView)
        }
    }

    @MainActor
    private func extractContent(from webView: WKWebView) {
        print("🔍 [ZhihuWebLoader] 开始执行 JavaScript 提取逻辑")
        
        let js = """
        (function() {
            try {
                var url = document.location.href;
                var bodyLen = document.body ? document.body.innerText.length : 0;
                
                print("🔍 [JS] URL: " + url);
                print("🔍 [JS] 正文长度: " + bodyLen);
                
                // === 酷安 ===
                if (url.indexOf('coolapk.com') !== -1 || url.indexOf('coolapk1s.com') !== -1) {
                    print("🔍 [JS] 检测到酷安页面");
                    
                    var coolapkResult = {
                        title: '',
                        text: '',
                        author: '',
                        images: [],
                        cover: '',
                        debug: 'bodyLen:' + bodyLen
                    };
                    
                    // 1. 尝试提取文章标题
                    var titleSelectors = [
                        '.detail-title',
                        '.feed-title',
                        '.post-title',
                        'h1.title',
                        'title'
                    ];
                    
                    var foundTitle = false;
                    for (var i = 0; i < titleSelectors.length; i++) {
                        var titleEl = document.querySelector(titleSelectors[i]);
                        if (titleEl && titleEl.innerText && titleEl.innerText.trim().length > 0) {
                            var titleText = titleEl.innerText.trim();
                            if (titleText !== '酷安APP' && titleText.length > 5) {
                                coolapkResult.title = titleText;
                                foundTitle = true;
                                print("🔍 [JS] 找到标题: " + titleText.substring(0, 50));
                                break;
                            }
                        }
                    }
                    
                    if (!foundTitle) {
                        print("🔍 [JS] 未找到合适标题，尝试其他选择器");
                        var titleEls = document.querySelectorAll('[class*="title"]');
                        for (var i = 0; i < titleEls.length; i++) {
                            var titleEl = titleEls[i];
                            if (titleEl && titleEl.innerText && titleEl.innerText.trim().length > 0) {
                                var titleText = titleEl.innerText.trim();
                                if (titleText !== '酷安APP' && titleText.length > 5) {
                                    coolapkResult.title = titleText;
                                    foundTitle = true;
                                    print("🔍 [JS] 通过 [class*=\"title\"] 找到标题: " + titleText.substring(0, 50));
                                    break;
                                }
                            }
                        }
                    }
                    
                    // 2. 提取正文内容
                    var contentEl = document.querySelector('.detail-content, .feed-content, article, [class*="content"]');
                    if (contentEl) {
                        coolapkResult.text = contentEl.innerText.trim();
                        print("🔍 [JS] 找到正文，长度: " + coolapkResult.text.length);
                    } else {
                        print("🔍 [JS] 未找到正文元素");
                    }
                    
                    // 3. 提取图片
                    var imgEls = document.querySelectorAll('.detail-content img, .feed-content img, article img, [class*="content"] img');
                    print("🔍 [JS] 找到图片元素数量: " + imgEls.length);
                    
                    var allImages = Array.from(imgEls).map(function(img) {
                        return img.src;
                    }).filter(function(src) {
                        return src && src.indexOf('http') === 0;
                    });
                    
                    print("🔍 [JS] 有效图片数量: " + allImages.length);
                    
                    // 过滤非内容图片
                    var contentImages = allImages.filter(function(src) {
                        return !src.includes('static.coolapk.com/static/web') &&
                               !src.includes('avatar.coolapk.com') &&
                               !src.includes('emoticons') &&
                               !src.includes('product_logo') &&
                               !src.includes('beian.png') &&
                               !src.includes('qr/image');
                    });
                    
                    coolapkResult.images = contentImages;
                    print("🔍 [JS] 过滤后图片数量: " + contentImages.length);
                    
                    // 4. 提取作者信息
                    var authorEl = document.querySelector('.user-name, .author-name, [class*="user"]');
                    if (authorEl && authorEl.innerText) {
                        coolapkResult.author = authorEl.innerText.trim().replace(/\\n/g, ' ').replace(/\\s+/g, ' ');
                        print("🔍 [JS] 找到作者: " + coolapkResult.author.substring(0, 50));
                    } else {
                        print("🔍 [JS] 未找到作者元素");
                    }
                    
                    // 5. 设置封面
                    coolapkResult.cover = coolapkResult.images.length > 0 ? coolapkResult.images[0] : '';
                    
                    // 更新调试信息
                    coolapkResult.debug = 'bodyLen:' + bodyLen + 
                                        ',title:' + (coolapkResult.title ? 'yes' : 'no') +
                                        ',author:' + (coolapkResult.author ? 'yes' : 'no') +
                                        ',text:' + coolapkResult.text.length +
                                        ',images:' + coolapkResult.images.length;
                    
                    print("🔍 [JS] 提取结果 - " + coolapkResult.debug);
                    
                    if (coolapkResult.text.length > 20 || coolapkResult.images.length > 0) {
                        print("🔍 [JS] 返回 COOLAPK_JSON");
                        return 'COOLAPK_JSON:' + JSON.stringify(coolapkResult);
                    } else {
                        print("🔍 [JS] 内容不足，返回 NO_CONTENT");
                        return 'NO_CONTENT';
                    }
                }
                
                print("🔍 [JS] 不是酷安页面");
                return 'NO_CONTENT';
            } catch(e) {
                print("🔍 [JS] 错误: " + e.toString());
                return 'ERROR:' + e.toString();
            }
        })()
        """

        Task {
            do {
                print("🔍 [ZhihuWebLoader] 执行 JavaScript")
                if let result = try await webView.evaluateJavaScript(js) as? String, !result.isEmpty {
                    print("🔍 [ZhihuWebLoader] JavaScript 执行成功，结果长度: \(result.count)")
                    print("🔍 [ZhihuWebLoader] 结果前100字符: \(result.prefix(100))")
                    self.finishWith(result)
                } else {
                    print("🔍 [ZhihuWebLoader] JavaScript 执行失败或返回空")
                    self.finishWith(nil)
                }
            } catch {
                print("🔍 [ZhihuWebLoader] JavaScript 执行错误: \(error)")
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
        print("🔍 [ZhihuWebLoader] finishWith 被调用，结果: \(result?.prefix(50) ?? "nil")")
        loadTimeout?.cancel()
        loadTimeout = nil
        continuation?.resume(returning: result)
        continuation = nil
        webView?.navigationDelegate = nil
        webView = nil
    }
}

@MainActor
func debugZhihuWebLoader() async {
    let loader = DebugZhihuWebLoader()
    let testURL = URL(string: "https://www.coolapk.com/feed/72069721?s=M2I2ZDE5NTIxYzA3MTgyZzZhMWMyYzIwega1620")!
    
    print("=== ZhihuWebLoader 详细调试 ===")
    print("测试链接: \(testURL.absoluteString)")
    print()
    
    let result = await loader.loadFullContent(from: testURL)
    
    print()
    print("=== 最终结果 ===")
    if let result = result {
        if result.hasPrefix("COOLAPK_JSON:") {
            print("✅ 成功提取到内容")
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
            print("❌ 未知结果: \(result.prefix(100))")
        }
    } else {
        print("❌ 返回 nil")
    }
}

// 运行测试
if #available(macOS 14.0, *) {
    Task { @MainActor in
        await debugZhihuWebLoader()
        exit(0)
    }
    
    RunLoop.main.run()
} else {
    print("需要 macOS 14.0+")
    exit(1)
}
