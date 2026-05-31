import Foundation
import WebKit

/// 通过 WKWebView 加载页面，获取完整内容
/// 支持知乎、豆瓣等多个平台
final class ZhihuWebLoader: NSObject, WKNavigationDelegate {


    private var webView: WKWebView?
    private var continuation: CheckedContinuation<String?, Never>?
    private var loadTimeout: Task<Void, Never>?
    private var didFinishInitialLoad = false

    @MainActor
    func loadFullContent(from url: URL) async -> String? {
        didFinishInitialLoad = false
        let config = WKWebViewConfiguration()
        config.suppressesIncrementalRendering = true

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        self.webView = webView

        return await withCheckedContinuation { continuation in
            self.continuation = continuation

            self.loadTimeout = Task {
                try? await Task.sleep(for: .seconds(15))
                if self.continuation != nil {
                    self.finishWith(nil)
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
                                doubanResult.text = Array.from(ps).map(function(p) { return p.innerText.trim(); }).filter(function(t) { return t.length > 0; }).join('\\n\\n');
                            } else {
                                doubanResult.text = del.innerText.trim();
                            }
                            doubanResult.debug = 'matched:' + doubanSelectors[di];
                            break;
                        }
                    }
                    // 兜底：取所有 <p> 标签
                    if (!doubanResult.text) {
                        var allPs = document.querySelectorAll('p');
                        var longText = Array.from(allPs).map(function(p) { return p.innerText.trim(); }).filter(function(t) { return t.length > 20; }).join('\\n\\n');
                        if (longText.length > 100) {
                            doubanResult.text = longText;
                            doubanResult.debug = 'fallback:p_tags';
                        }
                    }
                    // 再兜底：遍历文本节点
                    if (!doubanResult.text) {
                        var walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, null, false);
                        var chunks = [];
                        while(walker.nextNode()) {
                            var t = walker.currentNode.textContent.trim();
                            var parent = walker.currentNode.parentElement;
                            if (parent && parent.tagName !== 'SCRIPT' && parent.tagName !== 'STYLE' && parent.tagName !== 'NOSCRIPT' && t.length > 10) {
                                chunks.push(t);
                            }
                        }
                        var bodyText = chunks.join('\\n\\n');
                        if (bodyText.length > 100) {
                            doubanResult.text = bodyText;
                            doubanResult.debug = 'fallback:text_nodes';
                        }
                    }
                    // 提取作者 - 尝试多种选择器
                    var authorEl = document.querySelector('.main-hd .name a')
                        || document.querySelector('.author a')
                        || document.querySelector('[class*="author"] a')
                        || document.querySelector('.main-hd a')
                        || document.querySelector('.review-hd a')
                        || document.querySelector('header a')
                        || document.querySelector('.user-info a')
                        || document.querySelector('[class*="name"] a');
                    doubanResult.author = authorEl ? authorEl.innerText.trim() : '';
                    // 如果还没找到，尝试从所有链接中找
                    if (!doubanResult.author) {
                        var allLinks = document.querySelectorAll('a');
                        for (var ai = 0; ai < allLinks.length; ai++) {
                            var linkText = allLinks[ai].innerText.trim();
                            var linkHref = allLinks[ai].href || '';
                            if (linkHref.indexOf('/people/') !== -1 && linkText.length > 0 && linkText.length < 30) {
                                doubanResult.author = linkText;
                                break;
                            }
                        }
                    }
                    // 提取标题 - 影评标题
                    var _titleEl = document.querySelector('h1')
                        || document.querySelector('.article h1')
                        || document.querySelector('.main-hd h1');
                    doubanResult.title = _titleEl ? _titleEl.innerText.trim() : '';
                    // h1 太短或包含"豆瓣"时，用 og:title 兜底
                    if (!doubanResult.title || doubanResult.title.length < 3 || doubanResult.title === '豆瓣') {
                        var _ogT = document.querySelector('meta[property="og:title"]');
                        if (_ogT && _ogT.content && _ogT.content.length > 2 && _ogT.content !== '豆瓣') {
                            doubanResult.title = _ogT.content.replace(/\\s*[-—]\\s*豆瓣.*$/, '').trim();
                        }
                    }
                    // 提取封面 - 优先电影/书籍海报，兜底影评头图
                    var _posterEl = document.querySelector('.subject-img img')
                        || document.querySelector('.subject-poster img')
                        || document.querySelector('.poster img')
                        || document.querySelector('[data-image]');
                    if (_posterEl && _posterEl.src && _posterEl.src.indexOf('doubanio.com') !== -1) {
                        doubanResult.cover = _posterEl.src;
                    } else if (_posterEl && _posterEl.getAttribute && _posterEl.getAttribute('data-image')) {
                        doubanResult.cover = _posterEl.getAttribute('data-image');
                    } else {
                        var _ogImg = document.querySelector('meta[property="og:image"]');
                        doubanResult.cover = (_ogImg && _ogImg.content) ? _ogImg.content : '';
                    }

                    if (doubanResult.text.length > 30) {
                        doubanResult.debug += ' | bodyLen:' + bodyLen + ' | pageURL:' + url + ' | h1:' + (document.querySelector('h1') ? document.querySelector('h1').innerText.substring(0,50) : 'none');
                        return 'DOUBAN_JSON:' + JSON.stringify(doubanResult);
                    }
                    doubanResult.debug += ' | bodyLen:' + bodyLen + ' | pageURL:' + url + ' | h1:' + (document.querySelector('h1') ? document.querySelector('h1').innerText.substring(0,50) : 'none') + ' | reviewContent:' + (document.querySelector('.review-content') ? 'exists' : 'missing') + ' | mainReview:' + (document.querySelector('.main-review') ? 'exists' : 'missing');
                    return 'DOUBAN_JSON:' + JSON.stringify({text:'', title: doubanResult.title, author: doubanResult.author, cover: doubanResult.cover, debug: doubanResult.debug});
                }
                // === 小红书 - 提取笔记内容 ===
                if (url.indexOf('xiaohongshu.com') !== -1 || url.indexOf('xhslink.com') !== -1) {
                    var xhsResult = {title: '', author: '', text: '', images: [], cover: '', debug: ''};
                    
                    // 提取标题
                    var _xhsTitleEl = document.querySelector('h1.note-title')
                        || document.querySelector('.title')
                        || document.querySelector('h1')
                        || document.querySelector('[class*="title"]');
                    xhsResult.title = _xhsTitleEl ? _xhsTitleEl.innerText.trim() : '';
                    if (!xhsResult.title) {
                        var _xhsOgTitle = document.querySelector('meta[property="og:title"]');
                        xhsResult.title = _xhsOgTitle ? _xhsOgTitle.content : '';
                    }
                    
                    // 提取作者
                    var _xhsAuthorEl = document.querySelector('.author .username')
                        || document.querySelector('.user-name')
                        || document.querySelector('[class*="author"]')
                        || document.querySelector('[class*="nickname"]');
                    xhsResult.author = _xhsAuthorEl ? _xhsAuthorEl.innerText.trim() : '';
                    if (!xhsResult.author) {
                        var _xhsUserLink = document.querySelector('a[href*="/user/profile/"]');
                        xhsResult.author = _xhsUserLink ? _xhsUserLink.innerText.trim() : '';
                    }
                    
                    // 提取正文 - 小红书正文选择器
                    var _xhsContentEl = document.querySelector('#detail-desc')
                        || document.querySelector('.note-text')
                        || document.querySelector('[class*="detail-desc"]')
                        || document.querySelector('[class*="note-desc"]')
                        || document.querySelector('.content')
                        || document.querySelector('.desc')
                        || document.querySelector('[class*="content"]')
                        || document.querySelector('[class*="desc"]');
                    if (_xhsContentEl) {
                        var _xhsPs = _xhsContentEl.querySelectorAll('p');
                        if (_xhsPs.length > 0) {
                            xhsResult.text = Array.from(_xhsPs).map(function(p) { return p.innerText.trim(); }).filter(function(t) { return t.length > 0; }).join('\n\n');
                        } else {
                            xhsResult.text = _xhsContentEl.innerText.trim();
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
                    self.finishWith(result)
                } else {
                    self.finishWith(nil)
                }
            } catch {
                self.finishWith(nil)
            }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            self.finishWith(nil)
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
