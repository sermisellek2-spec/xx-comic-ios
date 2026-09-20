import UIKit
import WebKit
import ComicCore

@MainActor
final class EpubTextContentView: UIView, WKNavigationDelegate, WKUIDelegate {
    private static let world = WKContentWorld.world(name: "XXComicReader")
    private var webView: WKWebView?
    private var handler: EpubBookSchemeHandler?
    private var loadTask: Task<Void, Never>?
    private var generation = UUID()
    private var layoutGeneration = UUID()
    private var documentURL: URL?
    private var bookID = ""
    private var preferences = TextReaderPreferences()
    private var restoring = false
    private var readable = false
    private var mainNavigationStarted = false
    private var restoreAnchor = ""
    private var restorePercent = 0.0
    private(set) var anchor = ""
    private(set) var percent = 0.0
    var onReadable: (() -> Void)?
    var onPosition: ((String, Double) -> Void)?
    var onUserRead: (() -> Void)?
    var onToggleControls: (() -> Void)?
    var onLink: ((String, String) -> Void)?
    var onExternalLink: ((URL) -> Void)?
    var onFailure: ((Error) -> Void)?

    func load(book: LocalBook, entry: EpubPublication.SpineItem, library: LocalLibrary,
              preferences: TextReaderPreferences, locator: TextLocator?) {
        cancel()
        self.bookID = book.id; self.preferences = preferences
        restoreAnchor = locator?.anchorID ?? ""; restorePercent = locator?.scrollPercentage ?? 0
        anchor = restoreAnchor; percent = restorePercent
        let token = generation
        let worker = Task.detached(priority: .userInitiated) { () throws -> (URL, Data) in
            let resource = try EpubReaderResource.url(bookID: book.id, path: entry.fullZipPath)
            let parent = (entry.fullZipPath as NSString).deletingLastPathComponent
            let path = (parent.isEmpty ? "" : parent + "/") + "__xxcomic_\(UUID().uuidString).html"
            let url = try EpubReaderResource.url(bookID: book.id, path: path)
            let body: String
            if entry.mediaType.hasPrefix("image/") {
                body = "<img alt='正文插图' src='\(Self.escape(resource.absoluteString))'>"
            } else {
                let data = try library.epubResource(bookID: book.id, path: entry.fullZipPath, maximumBytes: 8 * 1024 * 1024)
                guard let text = String(data: data, encoding: .utf8) else { throw EpubError.invalid("正文不是有效 UTF-8 文本") }
                switch entry.mediaType {
                case "application/xhtml+xml", "text/html": body = text
                case "text/plain": body = "<pre style='white-space:pre-wrap'>\(Self.escape(text))</pre>"
                default: throw EpubError.invalid("不支持的正文格式：\(entry.mediaType)")
                }
            }
            let origin = "xxcomic-book://" + book.id.lowercased()
            let csp = "default-src 'none'; script-src 'none'; img-src \(origin) data:; style-src \(origin) 'unsafe-inline'; font-src \(origin); frame-src 'none'; object-src 'none'; connect-src 'none'; base-uri 'none'; form-action 'none'"
            let prefix = "<!doctype html><meta charset='utf-8'><meta http-equiv=\"Content-Security-Policy\" content=\"\(csp)\"><meta name='viewport' content='width=device-width,initial-scale=1'>"
            return (url, Data((prefix + body).utf8))
        }
        loadTask = Task { [weak self] in
            do {
                let (url, data) = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
                let rules = try await Self.resourceRules()
                try Task.checkCancellation()
                guard let self, self.generation == token else { return }
                let config = WKWebViewConfiguration()
                config.websiteDataStore = .nonPersistent()
                config.defaultWebpagePreferences.allowsContentJavaScript = false
                config.preferences.javaScriptCanOpenWindowsAutomatically = false
                config.userContentController.add(rules)
                config.userContentController.add(WeakMessages(self), contentWorld: Self.world, name: "reader")
                config.userContentController.addUserScript(WKUserScript(source: Self.events, injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: Self.world))
                let handler = EpubBookSchemeHandler(library: library, book: book, documentURL: url, document: data)
                handler.onFailure = { [weak self] error in
                    guard let self, self.generation == token else { return }
                    self.fail(error)
                }
                config.setURLSchemeHandler(handler, forURLScheme: "xxcomic-book")
                let web = WKWebView(frame: .zero, configuration: config)
                web.navigationDelegate = self; web.uiDelegate = self
                web.isOpaque = false; web.accessibilityIdentifier = "epub.content"
                web.translatesAutoresizingMaskIntoConstraints = false
                self.addSubview(web)
                NSLayoutConstraint.activate([web.topAnchor.constraint(equalTo: self.topAnchor), web.bottomAnchor.constraint(equalTo: self.bottomAnchor), web.leadingAnchor.constraint(equalTo: self.leadingAnchor), web.trailingAnchor.constraint(equalTo: self.trailingAnchor)])
                self.handler = handler; self.webView = web; self.documentURL = url
                web.load(URLRequest(url: url))
            } catch {
                guard let self, self.generation == token, !Task.isCancelled else { return }
                self.fail(error)
            }
        }
    }

    nonisolated private static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;").replacingOccurrences(of: "'", with: "&#39;")
    }
    private static func resourceRules() async throws -> WKContentRuleList {
        try await withCheckedThrowingContinuation { continuation in
            WKContentRuleListStore.default().compileContentRuleList(forIdentifier: "XXComicEpubIsolation-v1", encodedContentRuleList:
                #"[{"trigger":{"url-filter":"^http:"},"action":{"type":"block"}},{"trigger":{"url-filter":"^https:"},"action":{"type":"block"}},{"trigger":{"url-filter":"^ws:"},"action":{"type":"block"}},{"trigger":{"url-filter":"^wss:"},"action":{"type":"block"}},{"trigger":{"url-filter":"^ftp:"},"action":{"type":"block"}},{"trigger":{"url-filter":"^file:"},"action":{"type":"block"}}]"#) { rules, error in
                    if let rules { continuation.resume(returning: rules) }
                    else { continuation.resume(throwing: error ?? EpubError.invalid("无法安装正文网络隔离规则")) }
                }
        }
    }
    func cancel() {
        generation = UUID(); loadTask?.cancel(); loadTask = nil
        readable = false; restoring = false; mainNavigationStarted = false
        handler?.cancel(); handler = nil
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "reader", contentWorld: Self.world)
        webView?.configuration.userContentController.removeAllUserScripts()
        webView?.navigationDelegate = nil; webView?.uiDelegate = nil
        webView?.stopLoading(); webView?.removeFromSuperview(); webView = nil
        documentURL = nil
    }
    private func fail(_ error: Error) {
        cancel(); onFailure?(error)
    }
    func apply(_ settings: TextReaderPreferences) {
        preferences = settings
        guard readable else { return }
        restoreAnchor = anchor; restorePercent = percent
        styleAndRestore()
    }
    func restore(anchor: String, percent: Double) {
        restoreAnchor = anchor; restorePercent = max(0, min(1, percent))
        guard readable else { return }
        styleAndRestore()
    }
    private func styleAndRestore() {
        guard let web = webView else { return }
        let token = generation
        layoutGeneration = UUID()
        let layoutToken = layoutGeneration
        restoring = true
        let colors: [String]
        switch preferences.theme {
        case .light: colors = ["#FAFAFA", "#23272E", "#4C78A8"]
        case .sepia: colors = ["#F5EEDB", "#3F3222", "#8C6239"]
        case .dark: colors = ["#12161F", "#C8D0E0", "#5E81AC"]
        }
        let css = "*{-webkit-tap-highlight-color:transparent;box-sizing:border-box}html,body{background:\(colors[0])!important;color:\(colors[1])!important;font-size:\(preferences.fontSize)px!important;line-height:\(preferences.lineHeight)!important;font-family:-apple-system,BlinkMacSystemFont,'PingFang SC',sans-serif!important;margin:0;padding:22px 18px 90px 18px;word-break:break-word;text-align:justify}p{margin-top:0!important;margin-bottom:.9em!important;text-indent:2em;line-height:\(preferences.lineHeight)!important}h1,h2,h3,h4,h5,h6{color:\(colors[1])!important;text-indent:0!important;margin-top:1.2em;margin-bottom:.6em;font-weight:bold}img{max-width:100%!important;height:auto!important;display:block!important;margin:14px auto!important;border-radius:4px}a{color:\(colors[2])!important;text-decoration:none}blockquote{margin:12px 0;padding:6px 14px;border-left:3px solid \(colors[2]);opacity:.85}"
        web.callAsyncJavaScript("let s=document.getElementById('__xxcomic_style');if(!s){s=document.createElement('style');s.id='__xxcomic_style';document.head.appendChild(s)}s.textContent=css;", arguments: ["css": css], in: nil, contentWorld: Self.world) { [weak self, weak web] result in
            guard let self, let web, self.generation == token, self.layoutGeneration == layoutToken, self.webView === web else { return }
            if case .failure(let error) = result { self.fail(error); return }
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(120)) { [weak self, weak web] in
                guard let self, let web, self.generation == token, self.layoutGeneration == layoutToken, self.webView === web else { return }
                web.callAsyncJavaScript("const e=anchor ? document.getElementById(anchor) : null;if(window.readerAnchor(e)){e.scrollIntoView()}else{window.scrollTo(0,percent*Math.max(0,document.documentElement.scrollHeight-innerHeight))}return window.readerPosition();", arguments: ["anchor": self.restoreAnchor, "percent": self.restorePercent], in: nil, contentWorld: Self.world) { [weak self, weak web] result in
                    guard let self, let web, self.generation == token, self.layoutGeneration == layoutToken, self.webView === web else { return }
                    self.restoring = false
                    switch result {
                    case .success(let position):
                        self.acceptPosition(position)
                        if !self.readable { self.readable = true; self.onReadable?() }
                    case .failure(let error): self.fail(error)
                    }
                }
            }
        }
    }
    private func acceptPosition(_ value: Any?) {
        guard let data = value as? [String: Any], let value = data["percent"] as? Double, value.isFinite else { return }
        percent = max(0, min(1, value)); anchor = data["anchor"] as? String ?? ""
        onPosition?(anchor, percent)
    }
    fileprivate func message(_ message: WKScriptMessage) {
        guard message.webView === webView, message.frameInfo.isMainFrame, readable, !restoring,
              let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        if type == "position" { acceptPosition(body) }
        if type == "user" { onUserRead?() }
        if type == "tap", let x = body["x"] as? Double {
            if x >= 0.32 && x <= 0.68 { onToggleControls?() }
            else if preferences.pagedMode {
                webView?.callAsyncJavaScript("window.scrollBy(0,direction*innerHeight*.88)", arguments: ["direction": x < 0.32 ? -1 : 1], in: nil, contentWorld: Self.world, completionHandler: nil)
                onUserRead?()
            }
        }
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard webView === self.webView else { return }
        styleAndRestore()
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        if webView === self.webView { fail(error) }
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if webView === self.webView { fail(error) }
    }
    func webView(_ webView: WKWebView, didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!) {
        if webView === self.webView { fail(EpubError.invalid("正文不允许重定向")) }
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        if webView === self.webView { fail(EpubError.invalid("正文进程已退出，请重试")) }
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard webView === self.webView, navigationAction.targetFrame?.isMainFrame == true, let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        if url == documentURL, navigationAction.navigationType == .other, !mainNavigationStarted {
            mainNavigationStarted = true; decisionHandler(.allow); return
        }
        decisionHandler(.cancel)
        guard navigationAction.navigationType == .linkActivated else { return }
        if url.scheme == "https" || url.scheme == "http" { onExternalLink?(url); return }
        guard let path = try? EpubReaderResource.path(from: url, bookID: bookID) else { return }
        let fragment = URLComponents(url: url, resolvingAgainstBaseURL: false)?.fragment ?? ""
        if let documentURL, path == (try? EpubReaderResource.path(from: documentURL, bookID: bookID)) {
            restore(anchor: fragment, percent: 0)
        } else { onLink?(path, fragment) }
    }
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? { nil }

    private static let events = #"""
    (()=>{
      const send = value => window.webkit.messageHandlers.reader.postMessage(value);
      window.readerAnchor=e=>Boolean(e&&document.body.contains(e)&&!e.id.startsWith('__xxcomic_')&&Array.from(e.getClientRects()).some(r=>r.width>0&&r.height>0));
      window.readerPosition=()=>{
        const total=Math.max(0,document.documentElement.scrollHeight-innerHeight);
        let anchor='';
        for(const e of document.body.querySelectorAll('[id]')){if(!window.readerAnchor(e))continue;if(e.getBoundingClientRect().top<=8)anchor=e.id;else break}
        return {type:'position',percent:total ? Math.max(0,Math.min(1,scrollY/total)):0,anchor};
      };
      let last=0, timer=0;
      addEventListener('scroll',()=>{const report=()=>{last=performance.now();timer=0;send(window.readerPosition())};if(!timer)timer=setTimeout(report,Math.max(0,100-(performance.now()-last)))},{passive:true});
      let start=null;
      addEventListener('touchstart',e=>{start=e.touches.length===1?{x:e.touches[0].clientX,y:e.touches[0].clientY,t:performance.now(),valid:true}:null},{passive:true});
      addEventListener('touchmove',e=>{send({type:'user'});if(start&&(e.touches.length!==1||Math.abs(e.touches[0].clientX-start.x)>=12||Math.abs(e.touches[0].clientY-start.y)>=12))start.valid=false},{passive:true});
      addEventListener('touchcancel',()=>{start=null},{passive:true});
      addEventListener('touchend',e=>{const s=start;start=null;if(!s||!s.valid||e.touches.length||performance.now()-s.t>=300||e.target.closest('a,button,input,select,textarea'))return;send({type:'tap',x:s.x/innerWidth})},{passive:true});
      addEventListener('wheel',()=>send({type:'user'}),{passive:true});
    })();
    """#
}

@MainActor
private final class WeakMessages: NSObject, WKScriptMessageHandler {
    weak var owner: EpubTextContentView?
    init(_ owner: EpubTextContentView) { self.owner = owner }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) { owner?.message(message) }
}
