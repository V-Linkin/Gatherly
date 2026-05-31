import Foundation
import WebKit

/// 通过 WKWebView 加载页面，获取完整内容
/// 支持知乎、豆瓣、酷安等多个平台
final class ZhihuWebLoader: NSObject, WKNavigationDelegate {

    private var webView: WKWebView?
    private var continuation: CheckedContinuation<String?, Never>?
    private var loadTimeout: Task<Void, Never>?
    private var didFinishInitialLoad = false
    private var isCompleted = false  // 防止重复调用

    @MainActor
    func loadFullContent(from url: URL) async -> String? {
        didFinishInitialLoad = false
        isCompleted = false
        
        let config = WKWebViewConfiguration()
        config.suppressesIncrementalRendering = true

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        self.webView = webView

        return await withCheckedContinuation { continuation in
            self.continuation = continuation

            self.loadTimeout = Task {
                try? await Task.sleep(for: .seconds(15))
                Task { @MainActor in
                    if !self.isCompleted {
                        self.isCompleted = true
                        self.finishWith(nil)
                    }
                }
            }

        webView.load(URLRequest(url: url))
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            if !didFinishInitialLoad {
                didFinishInitialLoad = true
            }
            // 轮询等待页面就绪（替代固定等待，大幅减少导入时间）
            await pollUntilReady(webView: webView)
        }
    }
    
    @MainActor
    private func pollUntilReady(webView: WKWebView) {
        Task {
            let maxAttempts = 12  // 最多轮询 6 秒（12 × 0.5s）
            let checkJS = "document.querySelector('#js-initialData') ? 'ready' : document.body.innerText.length > 500 ? 'loaded' : 'challenge'"
            
            for attempt in 0..<maxAttempts {
                try? await Task.sleep(for: .milliseconds(500))
                
                guard let result = try? await webView.evaluateJavaScript(checkJS) as? String else {
                    continue
                }
                
                if result == "ready" || result == "loaded" {
                    // 页面已就绪，再等 0.5s 让 DOM 稳定后提取
                    try? await Task.sleep(for: .milliseconds(500))
                    extractContent(from: webView)
                    return
                }
                // challenge 页面，继续轮询等待重定向
            }
            // 超时，尝试提取（可能内容不完整但比没有好）
            extractContent(from: webView)
        }
    }

    @MainActor
    private func extractContent(from webView: WKWebView) {
        let js = """
        (function() {
            try {
                var url = document.location.href;
                var bodyLen = document.body ? document.body.innerText.length : 0;

                // === 知乎 ===
                var initEl = document.getElementById('js-initialData');
                if (initEl) {
                    try {
                        var data = JSON.parse(initEl.textContent);
                        var entities = data.initialState && data.initialState.entities;
                        if (entities) {
                            var answers = entities.answers || {};
                            var keys = Object.keys(answers);
                            if (keys.length > 0) {
                                var answer = answers[keys[0]];
                                if (answer && answer.content) return 'ANSWER:' + keys[0] + ':' + answer.content;
                            }
                            var articles = entities.articles || {};
                            var aKeys = Object.keys(articles);
                            if (aKeys.length > 0) {
                                var article = articles[aKeys[0]];
                                if (article && article.content) return 'ARTICLE:' + aKeys[0] + ':' + article.content;
                            }
                        }
                    } catch(e) {}
                }

                // === 豆瓣 - 提取影评内容、作者、封面 ===
                if (url.indexOf('douban.com') !== -1) {
                    var doubanResult = {text: '', title: '', author: '', cover: '', debug: ''};
                    var doubanSelectors = [
                        '.review-content', '.main-review', '#link-report',
                        '.note', '#content .intro', '#content',
                        '.article .main-bd', '.article', '.status-body',
                        '.review-body', '[class*="review"]'
                    ];
                    for (var di = 0; di < doubanSelectors.length; di++) {
                        var del = document.querySelector(doubanSelectors[di]);
                        if (del && del.innerText && del.innerText.trim().length > 50) {
                            var ps = del.querySelectorAll('p');
                            if (ps.length > 0) {
                                doubanResult.text = Array.from(ps).map(function(p) { return p.innerText.trim(); }).filter(function(t) { return t.length > 0; }).join('\n\n');
                            } else {
                                doubanResult.text = del.innerText.trim();
                            }
                            break;
                        }
                    }
                    
                    // 提取作者
                    var authorEl = document.querySelector('.author a, .reviewer-name, [class*="author"]');
                    if (authorEl) {
                        doubanResult.author = authorEl.innerText.trim();
                    }
                    
                    // 提取封面（优先从 subject 页面获取）
                    var ogImage = document.querySelector('meta[property="og:image"]');
                    if (ogImage) {
                        doubanResult.cover = ogImage.content;
                    }
                    
                    // 调试信息
                    doubanResult.debug = 'bodyLen:' + bodyLen;
                    
                    if (doubanResult.text.length > 20) {
                        return 'DOUBAN_JSON:' + JSON.stringify(doubanResult);
                    }
                }

                // === 小红书 ===
                if (url.indexOf('xiaohongshu.com') !== -1 || url.indexOf('xhslink.com') !== -1) {
                    var xhsResult = {title: '', text: '', author: '', images: [], cover: '', debug: ''};
                    
                    // 尝试 SSR 数据提取
                    var initScript = document.querySelector('script[type="application/json"]#pageData');
                    if (initScript) {
                        try {
                            var data = JSON.parse(initScript.textContent);
                            if (data && data.items && data.items.length > 0) {
                                var note = data.items[0];
                                xhsResult.title = note.title || '';
                                xhsResult.text = note.desc || '';
                                xhsResult.author = note.user && note.user.nickname ? note.user.nickname : '';
                                if (note.imageList && note.imageList.length > 0) {
                                    xhsResult.images = note.imageList.map(function(img) { return img.url || img.urlDefault || ''; });
                                }
                                xhsResult.cover = xhsResult.images.length > 0 ? xhsResult.images[0] : '';
                            }
                        } catch(e) {}
                    }
                    
                    // DOM 提取备用
                    if (!xhsResult.text) {
                        var _xhsContentEl = document.querySelector('#detail-desc, .note-text, [class*="content"]');
                        if (_xhsContentEl) {
                            var _xhsPs = _xhsContentEl.querySelectorAll('p');
                            if (_xhsPs.length > 0) {
                                xhsResult.text = Array.from(_xhsPs).map(function(p) { return p.innerText.trim(); }).filter(function(t) { return t.length > 0; }).join('\n\n');
                            } else {
                                xhsResult.text = _xhsContentEl.innerText.trim();
                            }
                        }
                    }
                    if (!xhsResult.text || xhsResult.text.length < 20) {
                        var _xhsOgDesc = document.querySelector('meta[property="og:description"]');
                        xhsResult.text = _xhsOgDesc ? _xhsOgDesc.content : xhsResult.text;
                    }
                    // 兜底：遍历所有文本节点
                    if (!xhsResult.text || xhsResult.text.length < 20) {
                        var _xhsWalker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, null, false);
                        var _xhsChunks = [];
                        while(_xhsWalker.nextNode()) {
                            var _xhsT = _xhsWalker.currentNode.textContent.trim();
                            var _xhsParent = _xhsWalker.currentNode.parentElement;
                            if (_xhsParent && _xhsParent.tagName !== 'SCRIPT' && _xhsParent.tagName !== 'STYLE' && _xhsParent.tagName !== 'NOSCRIPT' && _xhsT.length > 5) {
                                _xhsChunks.push(_xhsT);
                            }
                        }
                        var _xhsBodyText = _xhsChunks.join('\n\n');
                        if (_xhsBodyText.length > 50) {
                            xhsResult.text = _xhsBodyText;
                        }
                    }
                    
                    // 提取图片
                    var _xhsImageEls = document.querySelectorAll('.image-container img, [class*="image"] img, .swiper-slide img');
                    xhsResult.images = Array.from(_xhsImageEls).map(function(img) { return img.src; }).filter(function(src) { return src && src.indexOf('http') === 0; });
                    if (xhsResult.images.length === 0) {
                        var _xhsOgImage = document.querySelector('meta[property="og:image"]');
                        if (_xhsOgImage && _xhsOgImage.content) {
                            xhsResult.images = [_xhsOgImage.content];
                        }
                    }
                    xhsResult.cover = xhsResult.images.length > 0 ? xhsResult.images[0] : '';
                    
                    // 调试信息
                    xhsResult.debug = 'bodyLen:' + bodyLen + ' | title:' + (xhsResult.title ? 'yes' : 'no') + ' | author:' + (xhsResult.author ? 'yes' : 'no') + ' | text:' + xhsResult.text.length + ' | images:' + xhsResult.images.length;
                    
                    if (xhsResult.text.length > 20 || xhsResult.images.length > 0) {
                        return 'XIAOHONGSHU_JSON:' + JSON.stringify(xhsResult);
                    }
                }

                // === 酷安 ===
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

                // === 通用 - 取主要内容区 ===
                var genericSelectors = [
                    '.AnswerItem', '.RichContent-inner',
                    '.Post-RichTextContainer', '.RichText',
                    'article', 'main'
                ];
                for (var i = 0; i < genericSelectors.length; i++) {
                    var el = document.querySelector(genericSelectors[i]);
                    if (el && el.innerHTML && el.innerHTML.trim().length > 50) {
                        return 'HTML:' + el.innerHTML;
                    }
                }

                // === 最终兜底 ===
                var bodyText = document.body.innerText || '';
                if (bodyText.trim().length > 100) {
                    return 'TEXT:' + bodyText;
                }

                return 'BODY:' + document.body.innerHTML;
            } catch(e) {
                return 'ERROR:' + e.toString();
            }
        })()
        """

        Task {
            do {
                if let result = try await webView.evaluateJavaScript(js) as? String, !result.isEmpty {
                    Task { @MainActor in
                        if !self.isCompleted {
                            self.isCompleted = true
                            self.finishWith(result)
                        }
                    }
                } else {
                    Task { @MainActor in
                        if !self.isCompleted {
                            self.isCompleted = true
                            self.finishWith(nil)
                        }
                    }
                }
            } catch {
                Task { @MainActor in
                    if !self.isCompleted {
                        self.isCompleted = true
                        self.finishWith(nil)
                    }
                }
            }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            if !self.isCompleted {
                self.isCompleted = true
                self.finishWith(nil)
            }
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        decisionHandler(.allow)
    }

    @MainActor
    private func finishWith(_ result: String?) {
        loadTimeout?.cancel()
        loadTimeout = nil
        continuation?.resume(returning: result)
        continuation = nil
        webView?.navigationDelegate = nil
        webView = nil
    }
}
