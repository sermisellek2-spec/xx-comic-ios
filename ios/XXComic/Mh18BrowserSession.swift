import UIKit
import WebKit
import ComicCore

/// Keep a WebKit context alive until its asynchronous data-removal callback.
/// An unresponsive framework must produce a retryable failure, not leave the
/// cache screen permanently disabled or announce a cleanup that never finished.
@MainActor
private final class WebCacheRemoval {
    private var continuation: CheckedContinuation<Void, Error>?
    private var timeout: Task<Void, Never>?
    private var context: WKWebView?

    func run() async throws {
        try Task.checkCancellation()
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        // No document or network request is loaded by this context.
        context = WKWebView(frame: .zero, configuration: configuration)
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            timeout = Task { [self] in
                do { try await Task.sleep(nanoseconds: 8_000_000_000) } catch { return }
                finish(.failure(URLError(.timedOut)))
            }
            configuration.websiteDataStore.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast) { [self] in
                Task { @MainActor [self] in finish(.success(())) }
            }
        }
    }

    private func finish(_ result: Result<Void, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        timeout?.cancel(); timeout = nil
        context?.stopLoading(); context = nil
        continuation.resume(with: result)
    }
}

/// Owns one persistent WebKit document and serializes its HTTP and browser requests.
@MainActor
final class Mh18BrowserSession: NSObject, ComicBrowserSession, WKNavigationDelegate, WKHTTPCookieStoreObserver {
    nonisolated static let userAgent = "Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36"
    private let defaults: UserDefaults
    private let cookieStore = WKWebsiteDataStore.default().httpCookieStore
    private let redirectGuard = Mh18RedirectGuard()
    private lazy var http: URLSession = {
        redirectGuard.owner = self
        let configuration = URLSessionConfiguration.default
        configuration.httpCookieStorage = .shared
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 25
        configuration.timeoutIntervalForResource = 120
        return URLSession(configuration: configuration, delegate: redirectGuard, delegateQueue: nil)
    }()
    private var browser: WKWebView?
    private var browserReady = false
    private var browserGeneration = UUID()
    private let cookieSync = Mh18CookieSynchronizer()
    private var jobs: [Job] = []
    private var interactive: Interactive?
    private weak var presenter: UIViewController?
    var statusChanged: (() -> Void)?
    var status: String { interactive?.screen.statusLabel.text ?? (defaults.object(forKey: "mh18.verifiedAt") == nil ? "未验证" : "已验证") }
    private var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    init(defaults: UserDefaults) {
        self.defaults = defaults
        super.init()
        cookieStore.add(self)
        NotificationCenter.default.addObserver(self, selector: #selector(backgrounded), name: UIApplication.didEnterBackgroundNotification, object: nil)
    }

    func verify(from presenter: UIViewController) async throws {
        guard interactive == nil else { throw failure("验证窗口正忙") }
        self.presenter = presenter
        defer { self.presenter = nil }
        _ = try await fetchInteractive(URL(string: "https://18mh.org/manga")!)
    }

    func fetch(_ url: URL) async throws -> String {
        let response = try await request(url, transport: .automatic)
        switch Mh18VerificationRules.httpAction(statusCode: response.status, mitigated: response.mitigated, body: response.body) {
        case .returnBody: return response.body
        case .verificationRequired:
            browserReady = false
            defaults.removeObject(forKey: "mh18.verifiedAt")
            statusChanged?()
            throw Mh18SourceError.verificationRequired
        case .fail: throw failure("请求失败：HTTP \(response.status)")
        }
    }

    func fetchInteractive(_ url: URL) async throws -> String {
        try Task.checkCancellation()
        guard Mh18BrowserTrust.allowsRequest(url), url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")) == "manga" else { throw failure("验证地址不受信任") }
        guard interactive == nil, let presenter, presenter.presentedViewController == nil else { throw failure("验证窗口无法打开") }
        let id = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard !Task.isCancelled else { continuation.resume(throwing: CancellationError()); return }
                let screen = Mh18VerificationViewController()
                let item = Interactive(id: id, url: url, screen: screen, startedAt: now, continuation: continuation)
                interactive = item
                screen.onClose = { [weak self] in self?.finishInteractive(id, result: .failure(CancellationError())) }
                screen.onRetry = { [weak self] in self?.retryInteractive(id) }
                presenter.present(screen, animated: true)
                beginAttempt(item)
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.finishInteractive(id, result: .failure(CancellationError())) }
        }
    }

    func clearCache() async throws {
        try Task.checkCancellation()
        reset()
        HTTPCookieStorage.shared.cookies?.forEach { HTTPCookieStorage.shared.deleteCookie($0) }
        try await WebCacheRemoval().run()
        try Task.checkCancellation()
    }

    /// Reset active browser work before invalidating verification data.
    func reset() {
        for job in jobs { finish(job, result: .failure(CancellationError()), startNext: false) }
        if let item = interactive { finishInteractive(item.id, result: .failure(CancellationError())) }
        destroyBrowser()
        defaults.removeObject(forKey: "mh18.verifiedAt")
        statusChanged?()
    }

    @objc private func backgrounded() { reset() }

    private func beginAttempt(_ item: Interactive) {
        destroyBrowser()
        defaults.removeObject(forKey: "mh18.verifiedAt")
        item.screen.setStatus("正在检查站点")
        statusChanged?()
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--ui-testing"), arguments.contains("--verification-fixtures") {
            // Exercise the real presentation/retry/cancel lifetime without a live site.
            // This document never marks verification complete or copies any cookies.
            let config = WKWebViewConfiguration()
            config.websiteDataStore = .nonPersistent()
            let view = WKWebView(frame: .zero, configuration: config)
            browser = view; item.screen.install(view)
            view.loadHTMLString("<meta http-equiv='Content-Security-Policy' content=\"default-src 'none'\"><h1>隔离验证页面</h1><p>用于关闭、重开与重试验收。</p>", baseURL: nil)
            item.screen.setStatus("等待验证 · 隔离验收页面")
            return
        }
        #endif
        let token = item.attempt.token
        let remaining = max(0, item.attempt.deadline - now)
        item.timeout = Task { [weak self, weak item] in
            do { try await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000)) } catch { return }
            guard let self, let item, self.interactive === item, !item.attempt.succeeded else { return }
            self.stop(item, message: "验证超时，请重新加载")
        }
        item.work = Task { [weak self, weak item] in
            guard let self, let item else { return }
            do {
                let response = try await self.request(item.url, transport: .http, deadline: item.attempt.deadline)
                guard self.accepts(item, token) else { return }
                guard Mh18VerificationRules.isExpectedPage(requested: item.url, actual: response.url) else { throw self.failure("页面跳转异常") }
                switch Mh18VerificationRules.interactiveAction(statusCode: response.status, mitigated: response.mitigated, body: response.body) {
                case .complete: await self.succeed(item, token: token, body: response.body, retainBrowser: false)
                case .openBrowser:
                    let view = try await self.makeBrowser()
                    guard self.accepts(item, token) else { return }
                    self.browser = view
                    item.screen.install(view)
                    self.load(item)
                case .fail: self.stop(item, message: "站点检查失败，请重新加载")
                }
            } catch {
                guard self.accepts(item, token), !(error is CancellationError) else { return }
                self.stop(item, message: error.localizedDescription)
            }
        }
    }

    private func retryInteractive(_ id: UUID) {
        guard let item = interactive, item.id == id, !item.attempt.succeeded else { return }
        item.attempt.stop()
        item.work?.cancel()
        item.timeout?.cancel()
        item.screen.removeBrowser()
        item.attempt = Mh18VerificationAttempt(startedAt: now)
        beginAttempt(item)
    }

    private func load(_ item: Interactive) {
        guard interactive === item, !item.attempt.stopped else { return }
        item.screen.setStatus("请完成安全验证")
        browser?.load(urlRequest(item.url))
    }

    private func accepts(_ item: Interactive, _ token: Mh18VerificationAttempt.Token) -> Bool {
        interactive === item && item.attempt.accepts(token, now: now)
    }

    private func inspect(_ item: Interactive) {
        item.work?.cancel()
        let token = item.attempt.token
        item.work = Task { [weak self, weak item] in
            guard let self, let item else { return }
            do {
                while self.accepts(item, token) {
                    guard let view = self.browser else { throw self.failure("浏览器会话已停止") }
                    let value = try await view.callAsyncJavaScript("return {url:location.href,title:document.title,html:document.documentElement.outerHTML};", arguments: [:], in: nil, contentWorld: .defaultClient)
                    guard self.accepts(item, token), !Task.isCancelled else { return }
                    guard let page = value as? [String: Any], let rawURL = page["url"] as? String, let url = URL(string: rawURL), Mh18BrowserTrust.allowsNavigation(url), let html = page["html"] as? String else { throw self.failure("页面地址异常") }
                    let challenge = Mh18VerificationRules.isChallenge(url: rawURL, title: page["title"] as? String ?? "", body: html, statusCode: item.statusCode, mitigated: item.mitigated)
                    let catalog = Mh18ComicSource.hasCatalogMarker(html)
                    let expected = Mh18BrowserTrust.allowsRequest(url) && Mh18VerificationRules.isExpectedPage(requested: item.url, actual: url)
                    switch Mh18VerificationRules.pageAction(challenge: challenge, expectedPage: expected, browserCatalog: catalog) {
                    case .wait:
                        item.screen.setStatus("请完成安全验证")
                        try await Task.sleep(nanoseconds: 600_000_000)
                    case .fail: throw self.failure("页面不正确，请重新加载")
                    case .probe:
                        item.screen.setStatus("正在确认验证结果")
                        let response = try await self.request(item.url, transport: .browser, deadline: item.attempt.deadline)
                        guard self.accepts(item, token), !Task.isCancelled else { return }
                        switch Mh18VerificationRules.probeAction(Mh18VerificationRules.httpAction(statusCode: response.status, mitigated: response.mitigated, body: response.body)) {
                        case .reload:
                            guard item.attempt.recover(now: self.now) else { throw self.failure("验证尚未生效，请重新加载") }
                            self.load(item)
                        case .fail: throw self.failure("确认请求失败，请重新加载")
                        case .complete:
                            guard Mh18VerificationRules.isExpectedPage(requested: item.url, actual: response.url), Mh18VerificationRules.verificationComplete(browserCatalog: catalog, probeCatalog: Mh18ComicSource.hasCatalogMarker(response.body)) else { throw self.failure("页面确认失败，请重新加载") }
                            await self.succeed(item, token: token, body: response.body, retainBrowser: true)
                        }
                        return
                    }
                }
            } catch {
                guard self.accepts(item, token), !(error is CancellationError) else { return }
                self.stop(item, message: error.localizedDescription)
            }
        }
    }

    private func succeed(_ item: Interactive, token: Mh18VerificationAttempt.Token, body: String, retainBrowser: Bool) async {
        guard accepts(item, token) else { return }
        // Images use URLSession.shared, so verification cannot return before this barrier applies.
        await copyCookiesToHTTP()
        guard !Task.isCancelled, interactive === item, item.attempt.complete(token, now: now) else { return }
        item.timeout?.cancel()
        browserReady = retainBrowser
        defaults.set(Date(), forKey: "mh18.verifiedAt")
        item.screen.setStatus("验证完成", succeeded: true)
        statusChanged?()
        item.successClose = Task { [weak self, weak item] in
            do { try await Task.sleep(nanoseconds: 600_000_000) } catch { return }
            guard let self, let item, self.interactive === item else { return }
            self.finishInteractive(item.id, result: .success(body))
        }
    }

    private func stop(_ item: Interactive, message: String) {
        guard interactive === item, !item.attempt.succeeded else { return }
        item.attempt.stop()
        item.work?.cancel()
        item.timeout?.cancel()
        browser?.stopLoading()
        cancelBrowserJobs()
        item.screen.setStatus(message)
        statusChanged?()
    }

    private func finishInteractive(_ id: UUID, result: Result<String, Error>) {
        guard let item = interactive, item.id == id else { return }
        interactive = nil
        item.attempt.stop()
        item.work?.cancel()
        item.successClose?.cancel()
        item.timeout?.cancel()
        if case .success = result, browserReady, let browser, let host = item.screen.view.window {
            browser.removeFromSuperview()
            browser.translatesAutoresizingMaskIntoConstraints = true
            browser.frame = CGRect(x: 0, y: 0, width: 1, height: 1)
            browser.alpha = 0.01
            browser.isUserInteractionEnabled = false
            host.addSubview(browser)
        } else { destroyBrowser() }
        if item.screen.presentingViewController == nil { item.continuation.resume(with: result) }
        else { item.screen.dismiss(animated: true) { item.continuation.resume(with: result) } }
        statusChanged?()
    }

    private func request(_ url: URL, transport: Transport, deadline: TimeInterval? = nil) async throws -> Reply {
        try Task.checkCancellation()
        guard Mh18BrowserTrust.allowsRequest(url) else { throw failure("请求地址不受信任") }
        let id = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard !Task.isCancelled else { continuation.resume(throwing: CancellationError()); return }
                let job = Job(id: id, url: url, transport: transport, continuation: continuation)
                jobs.append(job)
                let remaining = max(0, (deadline ?? (now + 120)) - now)
                job.timeout = Task { [weak self, weak job] in
                    do { try await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000)) } catch { return }
                    guard let self, let job else { return }
                    self.finish(job, result: .failure(self.failure("请求超时，请重试")))
                }
                if jobs.count == 1 { start(job) }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                guard let self, let job = self.jobs.first(where: { $0.id == id }) else { return }
                self.finish(job, result: .failure(CancellationError()))
            }
        }
    }

    private func start(_ job: Job) {
        job.work = Task { [weak self, weak job] in
            guard let self, let job else { return }
            await self.copyCookiesToHTTP()
            guard self.jobs.first === job, !Task.isCancelled else { return }
            job.useBrowser = job.transport == .browser || (job.transport == .automatic && self.browserReady)
            if job.useBrowser { self.startBrowserFetch(job) }
            else {
                let task = self.http.dataTask(with: self.urlRequest(job.url)) { [weak self, weak job] data, response, error in
                    Task { @MainActor [weak self, weak job] in
                        guard let self, let job, self.jobs.first === job else { return }
                        if let error { self.finish(job, result: .failure(error)); return }
                        guard let response = response as? HTTPURLResponse, let url = response.url, Mh18BrowserTrust.allowsRequest(url), let data else { self.finish(job, result: .failure(self.failure("页面跳转或响应异常"))); return }
                        guard !(300..<400).contains(response.statusCode) || response.value(forHTTPHeaderField: "Location") == nil else { self.finish(job, result: .failure(self.failure("页面跳转被阻止"))); return }
                        await self.persistResponseCookies(response)
                        self.finish(job, result: .success(Reply(url: url, status: response.statusCode, mitigated: response.value(forHTTPHeaderField: "cf-mitigated"), body: String(decoding: data, as: UTF8.self))))
                    }
                }
                job.httpTask = task
                task.resume()
            }
        }
    }

    private func startBrowserFetch(_ job: Job) {
        guard let browser, browserReady || interactive != nil else { finish(job, result: .failure(Mh18SourceError.verificationRequired)); return }
        let generation = browserGeneration
        job.browser = browser
        // Isolated world keeps the AbortController and fetch primitive out of page script scope.
        browser.callAsyncJavaScript(Self.fetchScript, arguments: ["url": job.url.absoluteString, "id": job.id.uuidString], in: nil, in: .defaultClient) { [weak self, weak job] result in
            guard let self, let job, self.jobs.first === job, generation == self.browserGeneration else { return }
            switch result {
            case .failure:
                self.finish(job, result: .failure(self.failure("浏览器网络请求失败，请重试")))
            case .success(let value):
                guard let response = value as? [String: Any], let rawURL = response["url"] as? String, let url = URL(string: rawURL), Mh18BrowserTrust.allowsRequest(url), let status = response["status"] as? Int, let body = response["body"] as? String else { self.finish(job, result: .failure(self.failure("浏览器返回地址或响应异常"))); return }
                self.finish(job, result: .success(Reply(url: url, status: status, mitigated: response["mitigated"] as? String, body: body)))
            }
        }
    }

    private static let fetchScript = """
        const controller = new AbortController();
        globalThis.__mh18Requests ??= new Map();
        globalThis.__mh18Requests.set(id, controller);
        try {
            const response = await fetch(url, {credentials:'include',cache:'no-store',redirect:'follow',signal:controller.signal,headers:{'Accept-Language':'zh-CN,zh;q=0.9'}});
            return {url:response.url,status:response.status,mitigated:response.headers.get('cf-mitigated') || '',body:await response.text()};
        } finally { globalThis.__mh18Requests.delete(id); }
        """

    private func finish(_ job: Job, result: Result<Reply, Error>, startNext: Bool = true) {
        guard let index = jobs.firstIndex(where: { $0 === job }) else { return }
        jobs.remove(at: index)
        job.timeout?.cancel()
        job.work?.cancel()
        job.httpTask?.cancel()
        job.browser?.callAsyncJavaScript("globalThis.__mh18Requests?.get(id)?.abort(); globalThis.__mh18Requests?.delete(id);", arguments: ["id": job.id.uuidString], in: nil, in: .defaultClient, completionHandler: nil)
        job.continuation.resume(with: result)
        if index == 0, startNext, let next = jobs.first { start(next) }
    }

    private func cancelBrowserJobs() {
        for job in jobs where job.useBrowser || job.transport == .browser { finish(job, result: .failure(Mh18SourceError.verificationRequired), startNext: false) }
        if let first = jobs.first, first.work == nil { start(first) }
    }

    private func destroyBrowser() {
        browserReady = false
        browserGeneration = UUID()
        cancelBrowserJobs()
        browser?.stopLoading()
        browser?.navigationDelegate = nil
        browser?.removeFromSuperview()
        browser = nil
    }

    private func makeBrowser() async throws -> WKWebView {
        // Keep ordinary same-site redirect:follow. WebKit enforces this network allowlist;
        // its per-redirect behavior still needs device validation. Final URLs are checked again.
        let encoded = try Mh18BrowserContentRules.encoded()
        let list: WKContentRuleList = try await withCheckedThrowingContinuation { continuation in
            WKContentRuleListStore.default().compileContentRuleList(forIdentifier: "mh18-network-boundary-v1", encodedContentRuleList: encoded) { list, error in
                if let error { continuation.resume(throwing: error) }
                else if let list { continuation.resume(returning: list) }
                else { continuation.resume(throwing: Mh18SourceError.invalidResponse("浏览器规则无法加载")) }
            }
        }
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.userContentController.add(list)
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.customUserAgent = Self.userAgent
        view.navigationDelegate = self
        view.allowsBackForwardNavigationGestures = false
        return view
    }

    private func urlRequest(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 25)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("zh-CN,zh;q=0.9", forHTTPHeaderField: "Accept-Language")
        return request
    }

    func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
        cookieSync.invalidate()
        Task { await copyCookiesToHTTP() }
    }

    private func copyCookiesToHTTP() async {
        await cookieSync.synchronize(read: { [cookieStore] in
            await withCheckedContinuation { continuation in
                cookieStore.getAllCookies { continuation.resume(returning: $0) }
            }
        }, storage: .shared)
    }

    fileprivate func persistResponseCookies(_ response: HTTPURLResponse) async {
        guard let url = response.url, Mh18BrowserTrust.allowsRequest(url), let host = url.host?.lowercased() else { return }
        cookieSync.invalidate()
        let headers = response.allHeaderFields.reduce(into: [String: String]()) { result, header in
            if let key = header.key as? String { result[key] = String(describing: header.value) }
        }
        // Copy only this response's cookies; copying the entire HTTP jar can revive old WK cookies.
        for cookie in HTTPCookie.cookies(withResponseHeaderFields: headers, for: url) where Mh18CookieSynchronizer.isSiteCookie(cookie) {
            let domain = cookie.domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
            guard host == domain || host.hasSuffix("." + domain) else { continue }
            if let expiry = cookie.expiresDate, expiry <= Date() {
                HTTPCookieStorage.shared.deleteCookie(cookie)
                await cookieStore.delete(cookie)
            } else { await cookieStore.setCookie(cookie) }
        }
        await copyCookiesToHTTP()
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard webView === browser, let url = navigationAction.request.url, Mh18BrowserTrust.allowsNavigation(url), navigationAction.targetFrame != nil else { decisionHandler(.cancel); return }
        if let item = interactive, item.attempt.stopped || item.attempt.succeeded { decisionHandler(.cancel); return }
        // A retained context cannot navigate underneath an outstanding business fetch.
        if interactive == nil, navigationAction.targetFrame?.isMainFrame == true {
            destroyBrowser()
            defaults.removeObject(forKey: "mh18.verifiedAt")
            statusChanged?()
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        guard webView === browser, let url = navigationResponse.response.url, Mh18BrowserTrust.allowsNavigation(url) else { decisionHandler(.cancel); return }
        if navigationResponse.isForMainFrame, let item = interactive, let response = navigationResponse.response as? HTTPURLResponse {
            item.statusCode = response.statusCode
            item.mitigated = response.value(forHTTPHeaderField: "cf-mitigated")
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        guard webView === browser, let item = interactive, item.attempt.navigationStarted() else { return }
        item.navigation = navigation
        item.work?.cancel()
        cancelBrowserJobs()
        item.statusCode = 200
        item.mitigated = nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard webView === browser, let item = interactive, item.navigation === navigation, !item.attempt.stopped, !item.attempt.succeeded else { return }
        inspect(item)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { navigationFailed(webView, navigation, error) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { navigationFailed(webView, navigation, error) }
    private func navigationFailed(_ view: WKWebView, _ navigation: WKNavigation?, _ error: Error) {
        guard view === browser, let item = interactive, item.navigation === navigation, (error as NSError).code != NSURLErrorCancelled else { return }
        stop(item, message: "网络加载失败，请重新加载")
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        guard webView === browser else { return }
        // A crashed process cannot keep any suspended transport or interactive continuation alive.
        for job in jobs { finish(job, result: .failure(failure("浏览器已退出，请重新验证")), startNext: false) }
        if let item = interactive { finishInteractive(item.id, result: .failure(failure("浏览器已退出，请重新验证"))) }
        destroyBrowser()
        defaults.removeObject(forKey: "mh18.verifiedAt")
        statusChanged?()
    }

    private func failure(_ text: String) -> Mh18SourceError { .invalidResponse("18漫画 " + text) }
    private enum Transport { case automatic, http, browser }
    private struct Reply { let url: URL; let status: Int; let mitigated: String?; let body: String }
    private final class Job {
        let id: UUID
        let url: URL
        let transport: Transport
        var useBrowser = false
        let continuation: CheckedContinuation<Reply, Error>
        var timeout: Task<Void, Never>?
        var work: Task<Void, Never>?
        var httpTask: URLSessionDataTask?
        weak var browser: WKWebView?
        init(id: UUID, url: URL, transport: Transport, continuation: CheckedContinuation<Reply, Error>) {
            self.id = id; self.url = url; self.transport = transport; self.continuation = continuation
        }
    }
    private final class Interactive {
        let id: UUID
        let url: URL
        let screen: Mh18VerificationViewController
        let continuation: CheckedContinuation<String, Error>
        var attempt: Mh18VerificationAttempt
        var timeout: Task<Void, Never>?
        var work: Task<Void, Never>?
        var successClose: Task<Void, Never>?
        var statusCode = 200
        var mitigated: String?
        var navigation: WKNavigation?
        init(id: UUID, url: URL, screen: Mh18VerificationViewController, startedAt: TimeInterval, continuation: CheckedContinuation<String, Error>) {
            self.id = id; self.url = url; self.screen = screen; self.continuation = continuation
            attempt = Mh18VerificationAttempt(startedAt: startedAt)
        }
    }
}

/// URLSession asks before sending the redirected request; returning nil never visits that host.
private final class Mh18RedirectGuard: NSObject, URLSessionTaskDelegate {
    @MainActor weak var owner: Mh18BrowserSession?
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        Task { @MainActor [weak self] in
            await self?.owner?.persistResponseCookies(response)
            guard task.state == .running, let url = request.url, Mh18BrowserTrust.allowsRequest(url) else { completionHandler(nil); return }
            var redirected = request
            redirected.setValue(Mh18BrowserSession.userAgent, forHTTPHeaderField: "User-Agent")
            redirected.setValue("zh-CN,zh;q=0.9", forHTTPHeaderField: "Accept-Language")
            completionHandler(redirected)
        }
    }
}

@MainActor
private final class Mh18VerificationViewController: UIViewController {
    let statusLabel = UILabel()
    var onRetry: (() -> Void)?
    var onClose: (() -> Void)?
    private let retry = UIButton(type: .system)
    private let close = UIButton(type: .system)
    private let browserHost = UIView()

    override func viewDidLoad() {
        super.viewDidLoad()
        isModalInPresentation = true
        view.backgroundColor = Palette.background
        statusLabel.numberOfLines = 0
        statusLabel.accessibilityIdentifier = "mh18.verification.status"
        retry.setTitle("重新加载", for: .normal)
        retry.accessibilityIdentifier = "mh18.verification.retry"
        retry.addAction(UIAction { [weak self] _ in self?.onRetry?() }, for: .touchUpInside)
        close.setTitle("关闭验证", for: .normal)
        close.accessibilityIdentifier = "mh18.verification.close"
        close.addAction(UIAction { [weak self] _ in self?.onClose?() }, for: .touchUpInside)
        let title = UILabel()
        title.text = "18漫画验证"
        title.font = .preferredFont(forTextStyle: .headline)
        let controls = UIStackView(arrangedSubviews: [retry, close])
        controls.distribution = .fillEqually
        let stack = UIStackView(arrangedSubviews: [title, statusLabel, browserHost, controls])
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            controls.heightAnchor.constraint(greaterThanOrEqualToConstant: 44)
        ])
    }

    func setStatus(_ message: String, succeeded: Bool = false) {
        loadViewIfNeeded()
        statusLabel.text = message
        retry.isEnabled = !succeeded
        close.isEnabled = !succeeded
    }

    func install(_ browser: WKWebView) {
        loadViewIfNeeded()
        browserHost.addSubview(browser)
        browser.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            browser.leadingAnchor.constraint(equalTo: browserHost.leadingAnchor), browser.trailingAnchor.constraint(equalTo: browserHost.trailingAnchor),
            browser.topAnchor.constraint(equalTo: browserHost.topAnchor), browser.bottomAnchor.constraint(equalTo: browserHost.bottomAnchor)
        ])
    }
    func removeBrowser() { browserHost.subviews.forEach { $0.removeFromSuperview() } }
}
