import Foundation
import WebKit

final class JSWebLoader: NSObject, WKNavigationDelegate {

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
                
                // 检测登录重定向
                if (url.indexOf('xiaohongshu.com/login') !== -1) {
                    return 'XHS_LOGIN_REQUIRED';
                }

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
                    // 检测是否被重定向到登录页
                    if (url.indexOf('/login') !== -1 || url.indexOf('login?redirectPath') !== -1) {
                        return 'XHS_LOGIN_REQUIRED';
                    }
                    var xhsResult = {title: '', text: '', author: '', images: [], cover: '', video: '', debug: ''};
                    
                    // 1. 尝试 SSR 数据提取（#pageData）
                    var initScript = document.querySelector('script[type="application/json"]#pageData');
                    xhsResult.debug = 'pageData:' + (initScript ? 'found' : 'NOT_FOUND') + ' | bodyLen:' + bodyLen;
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
                                // 提取视频 URL
                                xhsResult.debug += ' | noteKeys:' + Object.keys(note).join(',');
                                if (note.video) {
                                    xhsResult.debug += ' | videoKeys:' + Object.keys(note.video).join(',');
                                    xhsResult.debug += ' | videoType:' + (typeof note.video) + ' | videoStr:' + JSON.stringify(note.video).substring(0, 200);
                                    if (note.video.media && note.video.media.stream) {
                                        var stream = note.video.media.stream;
                                        var h264 = stream.h264 || [];
                                        var h265 = stream.h265 || [];
                                        var av1 = stream.av1 || [];
                                        var allCodecs = h264.concat(h265).concat(av1);
                                        xhsResult.debug += ' | codecs:' + allCodecs.length;
                                        if (allCodecs.length > 0) {
                                            allCodecs.sort(function(a, b) { return (b.width || 0) - (a.width || 0); });
                                            xhsResult.video = allCodecs[0].masterUrl || '';
                                        }
                                    } else if (note.video.url) {
                                        xhsResult.video = note.video.url;
                                    } else {
                                        xhsResult.debug += ' | videoNoStream:yes';
                                    }
                                    xhsResult.debug += ' | videoURL:' + (xhsResult.video ? 'yes(' + xhsResult.video.substring(0, 80) + ')' : 'no');
                                } else {
                                    xhsResult.debug += ' | note.video:UNDEFINED';
                                }
                            }
                        } catch(e) {
                            xhsResult.debug += ' | ssrError:' + e.toString();
                        }
                    }
                    
                    // 1b. 尝试 SSR 数据提取（__INITIAL_STATE__，与 HTTP 路径 extractFromSSRData 对齐）
                    if (xhsResult.images.length === 0) {
                        try {
                            var _allScripts = document.querySelectorAll('script');
                            for (var _si2 = 0; _si2 < _allScripts.length; _si2++) {
                                var _scriptText = _allScripts[_si2].textContent || '';
                                var _ssrMarker = '__INITIAL_STATE__=';
                                var _ssrIdx = _scriptText.indexOf(_ssrMarker);
                                if (_ssrIdx === -1) continue;
                                var _ssrJson = _scriptText.substring(_ssrIdx + _ssrMarker.length);
                                // textContent 不含 </script> 标签，无需截断
                                _ssrJson = _ssrJson.replace(/undefined/g, 'null');
                                var _ssrData = JSON.parse(_ssrJson);
                                xhsResult.debug += ' | initialState:found';
                                var _ssrNote = null;
                                if (_ssrData.note && _ssrData.note.noteDetailMap) {
                                    var _dm = _ssrData.note.noteDetailMap;
                                    var _dk = Object.keys(_dm)[0];
                                    if (_dk && _dm[_dk] && _dm[_dk].note) _ssrNote = _dm[_dk].note;
                                }
                                if (!_ssrNote && _ssrData.noteData && _ssrData.noteData.data && _ssrData.noteData.data.noteData) {
                                    _ssrNote = _ssrData.noteData.data.noteData;
                                }
                                if (_ssrNote) {
                                    if (_ssrNote.title) xhsResult.title = _ssrNote.title;
                                    if (_ssrNote.desc) xhsResult.text = _ssrNote.desc;
                                    var _ssrUser = _ssrNote.user;
                                    if (_ssrUser) xhsResult.author = _ssrUser.nickName || _ssrUser.nickname || '';
                                    if (_ssrNote.imageList && _ssrNote.imageList.length > 0) {
                                        xhsResult.images = _ssrNote.imageList.map(function(img) {
                                            if (img.fileId) return 'http://sns-na-i1.xhscdn.com/' + img.fileId + '?imageView2/2/w/1080/format/jpg';
                                            return img.urlDefault || img.url || '';
                                        }).filter(function(u) { return u && u.indexOf('http') === 0; });
                                    }
                                    var _np = _ssrData.noteData && _ssrData.noteData.normalNotePreloadData;
                                    if (_np && _np.imagesList && _np.imagesList.length > 0) {
                                        var _fi = _np.imagesList[0];
                                        xhsResult.cover = _fi.urlSizeLarge || _fi.url || '';
                                    }
                                    if (!xhsResult.cover && xhsResult.images.length > 0) xhsResult.cover = xhsResult.images[0];
                                    if (xhsResult.cover && xhsResult.images.length > 0 && xhsResult.images[0] === xhsResult.cover) xhsResult.images.shift();
                                    if (_ssrNote.video && _ssrNote.video.media && _ssrNote.video.media.stream) {
                                        var _stream = _ssrNote.video.media.stream;
                                        var _codecs = (_stream.h264 || []).concat(_stream.h265 || []).concat(_stream.av1 || []);
                                        if (_codecs.length > 0) {
                                            _codecs.sort(function(a, b) { return (b.width || 0) - (a.width || 0); });
                                            xhsResult.video = _codecs[0].masterUrl || '';
                                        }
                                    }
                                    xhsResult.debug += ' | ssrImages:' + xhsResult.images.length;
                                }
                                break;
                            }
                        } catch(_e) {
                            xhsResult.debug += ' | ssrINITError:' + _e.toString();
                        }
                    }
                    
                    // 2. DOM 提取备用 - 扩展选择器
                    if (!xhsResult.text) {
                        var _xhsSelectors = ['#detail-desc', '.note-text', '.note-content', '.content', '[class*="desc"]', '[class*="detail"]', '#detail-desc .note-text', '.note-scroller'];
                        for (var _si = 0; _si < _xhsSelectors.length; _si++) {
                            var _xhsContentEl = document.querySelector(_xhsSelectors[_si]);
                            if (_xhsContentEl && _xhsContentEl.innerText && _xhsContentEl.innerText.trim().length > 10) {
                                var _xhsPs = _xhsContentEl.querySelectorAll('p');
                                if (_xhsPs.length > 0) {
                                    xhsResult.text = Array.from(_xhsPs).map(function(p) { return p.innerText.trim(); }).filter(function(t) { return t.length > 0; }).join('\n\n');
                                } else {
                                    xhsResult.text = _xhsContentEl.innerText.trim();
                                }
                                break;
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
                    
                    // 3. DOM 兜底提取图片（仅在 SSR 未提取到图片时作为 fallback）
                    if (xhsResult.images.length === 0) {
                        var _xhsImageEls = document.querySelectorAll('.image-container img, [class*="image"] img, .swiper-slide img, .note-image img, [class*="carousel"] img, [class*="slider"] img, [class*="gallery"] img');
                        xhsResult.images = Array.from(_xhsImageEls).map(function(img) { return img.src || img.getAttribute('data-src') || ''; }).filter(function(src) { return src && src.indexOf('http') === 0; });
                    }
                    if (xhsResult.images.length === 0) {
                        var _xhsOgImage = document.querySelector('meta[property="og:image"]');
                        if (_xhsOgImage && _xhsOgImage.content) {
                            xhsResult.images = [_xhsOgImage.content];
                        }
                    }
                    if (!xhsResult.cover) xhsResult.cover = xhsResult.images.length > 0 ? xhsResult.images[0] : '';
                    // 兜底封面
                    if (!xhsResult.cover) {
                        var _xhsOgCover = document.querySelector('meta[property="og:image"]');
                        if (_xhsOgCover && _xhsOgCover.content) {
                            xhsResult.cover = _xhsOgCover.content;
                        }
                    }
                    
                    // 4. DOM 兜底提取视频
                    if (!xhsResult.video) {
                        var _videoEl = document.querySelector('video source, video');
                        if (_videoEl) {
                            xhsResult.video = _videoEl.src || _videoEl.getAttribute('src') || '';
                            xhsResult.debug += ' | domVideo:' + (xhsResult.video ? 'yes' : 'no');
                        }
                    }
                    
                    // 5. 补充标题和作者
                    if (!xhsResult.title) {
                        var _pageTitle = document.title || '';
                        if (_pageTitle && _pageTitle.length > 2 && _pageTitle.indexOf('小红书') === -1) {
                            xhsResult.title = _pageTitle.replace(/ - 小红书$/, '').replace(/ \\| 小红书$/, '').trim();
                        }
                    }
                    if (!xhsResult.author) {
                        var _ogAuthor = document.querySelector('meta[name="author"], meta[property="og:novel:author"]');
                        if (_ogAuthor && _ogAuthor.content) {
                            xhsResult.author = _ogAuthor.content;
                        }
                    }
                    
                    // 调试信息
                    xhsResult.debug += ' | bodyLen:' + bodyLen + ' | title:' + (xhsResult.title ? 'yes' : 'no') + ' | author:' + (xhsResult.author ? 'yes' : 'no') + ' | text:' + xhsResult.text.length + ' | images:' + xhsResult.images.length;
                    
                    // 始终返回结果
                    return 'XIAOHONGSHU_JSON:' + JSON.stringify(xhsResult);
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
                    
                    // 即使正文为空，也返回 debug 信息便于排查
                    return 'COOLAPK_JSON:' + JSON.stringify(coolapkResult);
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
                    // Debug: print JS result to help diagnose
                    print("[JSWebLoader] JS result: \(result)")
                    Task { @MainActor in
                        if !self.isCompleted {
                            self.isCompleted = true
                            self.finishWith(result)
                        }
                    }
                } else {
                    print("[JSWebLoader] JS returned empty or non-string")
                    Task { @MainActor in
                        if !self.isCompleted {
                            self.isCompleted = true
                            self.finishWith(nil)
                        }
                    }
                }
            } catch {
                print("[JSWebLoader] JS evaluation error: \(error)")
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
