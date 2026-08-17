package com.xxcomic;

import android.app.Activity;
import android.content.res.ColorStateList;
import android.graphics.Color;
import android.graphics.Typeface;
import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;
import android.text.TextUtils;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.webkit.JavascriptInterface;
import android.webkit.WebResourceError;
import android.webkit.WebResourceRequest;
import android.webkit.WebResourceResponse;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.FrameLayout;
import android.widget.LinearLayout;
import android.widget.ProgressBar;
import android.widget.TextView;

import com.xxcomic.source.BrowserSession;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.net.HttpURLConnection;
import java.net.URL;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.Executors;
import java.util.concurrent.Semaphore;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.ScheduledFuture;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicBoolean;

final class CloudflareWebViewSession implements BrowserSession {
    private static final String BRIDGE_NAME = "XXComicBridge";
    private static final long TIMEOUT_MS = 120000L;
    private static final long POLL_DELAY_MS = 800L;
    private static final long INTERACTIVE_DELAY_MS = 4000L;
    private static final String USER_AGENT = "Mozilla/5.0 (Linux; Android 14) "
            + "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36";
    private static final int CONNECT_TIMEOUT_MS = 10000;
    private static final int READ_TIMEOUT_MS = 25000;
    private static final ScheduledExecutorService HTTP_TIMEOUTS =
            Executors.newSingleThreadScheduledExecutor(runnable -> {
                Thread thread = new Thread(runnable, "XXComicHttpTimeout");
                thread.setDaemon(true);
                return thread;
            });

    private final Activity activity;
    private final Handler main;
    private final String sourceName;
    private final boolean preferHttp;
    private final boolean fullViewportBackground;
    private final boolean automaticInteractiveFallback;
    private final VerificationStatusListener verificationStatus;
    private final Semaphore requestLock = new Semaphore(1, true);
    private final AtomicInteger requestSequence = new AtomicInteger();
    private volatile boolean shutdown;
    private FrameLayout host;
    private WebView webView;
    private View foregroundContent;
    private View statusCard;
    private ProgressBar progress;
    private TextView status;
    private FetchRequest activeRequest;
    private int navigation;
    private volatile boolean browserContextReady;

    CloudflareWebViewSession(Activity activity, Handler main, String sourceName,
                             boolean preferHttp,
                             VerificationStatusListener verificationStatus) {
        this(activity, main, sourceName, preferHttp, false, false, verificationStatus);
    }

    CloudflareWebViewSession(Activity activity, Handler main, String sourceName,
                             boolean preferHttp, boolean fullViewportBackground,
                             VerificationStatusListener verificationStatus) {
        this(activity, main, sourceName, preferHttp, fullViewportBackground, false,
                verificationStatus);
    }

    CloudflareWebViewSession(Activity activity, Handler main, String sourceName,
                             boolean preferHttp, boolean fullViewportBackground,
                             boolean automaticInteractiveFallback,
                             VerificationStatusListener verificationStatus) {
        this.activity = activity;
        this.main = main;
        this.sourceName = sourceName;
        this.preferHttp = preferHttp;
        this.fullViewportBackground = fullViewportBackground;
        this.automaticInteractiveFallback = automaticInteractiveFallback;
        this.verificationStatus = verificationStatus;
    }

    interface VerificationStatusListener {
        void onStatus(String message);
    }

    static long interactiveDelayMs() {
        return INTERACTIVE_DELAY_MS;
    }

    static long requestTimeoutMs() {
        return TIMEOUT_MS;
    }

    static long requestDeadlineMs(long startedAt) {
        return startedAt + TIMEOUT_MS;
    }

    static long remainingRequestMs(long deadline, long now) {
        return Math.max(0L, deadline - now);
    }

    static long httpWatchdogDelayMs(long deadline, long now) {
        return remainingRequestMs(deadline, now);
    }

    static boolean shouldShowInteractive(boolean interactiveAllowed, boolean verifying) {
        return interactiveAllowed && verifying;
    }

    static boolean allowsInteractiveChallenge(boolean explicitlyAllowed,
                                              boolean automaticInteractiveFallback) {
        return explicitlyAllowed || automaticInteractiveFallback;
    }

    static boolean shouldHandOffInteractive(boolean interactiveVisible,
                                            boolean turnstileSolved,
                                            String clearanceBefore,
                                            String clearanceNow) {
        boolean clearanceChanged = clearanceNow != null && !clearanceNow.isEmpty()
                && !clearanceNow.equals(clearanceBefore == null ? "" : clearanceBefore);
        return interactiveVisible && (turnstileSolved || clearanceChanged);
    }

    static String cookieValue(String cookies, String name) {
        if (cookies == null || name == null || name.isEmpty()) return "";
        for (String cookie : cookies.split(";")) {
            int separator = cookie.indexOf('=');
            if (separator > 0 && name.equals(cookie.substring(0, separator).trim())) {
                return cookie.substring(separator + 1).trim();
            }
        }
        return "";
    }

    static int backgroundExtent(boolean fullViewport) {
        return fullViewport ? ViewGroup.LayoutParams.MATCH_PARENT : 1;
    }

    @Override
    public String fetch(String url) throws IOException {
        return fetch(url, false);
    }

    @Override
    public String fetchInteractive(String url) throws IOException {
        return fetch(url, true);
    }

    private String fetch(String url, boolean interactiveAllowed) throws IOException {
        if (Looper.myLooper() == Looper.getMainLooper()) {
            throw new IOException(sourceName + "请求不能阻塞主线程");
        }
        long deadline = requestDeadlineMs(SystemClock.elapsedRealtime());
        boolean allowInteractive = allowsInteractiveChallenge(
                interactiveAllowed, automaticInteractiveFallback);
        boolean acquired = false;
        try {
            long lockWait = remainingRequestMs(deadline, SystemClock.elapsedRealtime());
            if (lockWait == 0L || !requestLock.tryAcquire(lockWait, TimeUnit.MILLISECONDS)) {
                throw new IOException(sourceName + "请求超时");
            }
            acquired = true;
            if (shutdown) throw new IOException(sourceName + "浏览器会话已停止");
            RequestTransport transport = requestTransport(preferHttp, browserContextReady);
            if (transport == RequestTransport.BROWSER_CONTEXT) {
                try {
                    return fetchWithBrowserContext(url, deadline);
                } catch (ContextChallengeException challenge) {
                    browserContextReady = false;
                    String body = fetchWithBrowser(url, allowInteractive, deadline);
                    browserContextReady = true;
                    return body;
                }
            }
            if (transport == RequestTransport.HTTP) {
                HttpFetch response = fetchHttp(url, deadline);
                HttpAction action = httpAction(
                        response.statusCode, response.mitigated, response.body);
                if (action == HttpAction.RETURN_BODY) return response.body;
                if (action == HttpAction.FAIL) {
                    throw new IOException(sourceName + " HTTP " + response.statusCode);
                }
            }
            String body = fetchWithBrowser(url, allowInteractive, deadline);
            if (preferHttp) browserContextReady = true;
            return body;
        } catch (InterruptedException interrupted) {
            Thread.currentThread().interrupt();
            throw new IOException(sourceName + "请求已取消", interrupted);
        } finally {
            if (acquired) requestLock.release();
        }
    }

    enum RequestTransport {
        HTTP,
        BROWSER_CONTEXT,
        BROWSER_NAVIGATION
    }

    static RequestTransport requestTransport(boolean preferHttp, boolean browserContextReady) {
        if (!preferHttp) return RequestTransport.BROWSER_NAVIGATION;
        return browserContextReady ? RequestTransport.BROWSER_CONTEXT : RequestTransport.HTTP;
    }

    private String fetchWithBrowser(String url, boolean interactiveAllowed,
                                    long deadline) throws IOException {
        FetchRequest request = new FetchRequest(
                Integer.toString(requestSequence.incrementAndGet()), url, false,
                interactiveAllowed, deadline);
        main.post(() -> startRequest(request));
        return awaitRequest(request);
    }

    private String fetchWithBrowserContext(String url, long deadline) throws IOException {
        FetchRequest request = new FetchRequest(
                Integer.toString(requestSequence.incrementAndGet()), url, true, false, deadline);
        main.post(() -> startRequest(request));
        return awaitRequest(request);
    }

    private String awaitRequest(FetchRequest request) throws IOException {
        try {
            long wait = remainingRequestMs(request.deadline, SystemClock.elapsedRealtime());
            if (wait == 0L || !request.latch.await(wait, TimeUnit.MILLISECONDS)) {
                request.cancelled = true;
                String error = timeoutError(request);
                main.post(() -> complete(request, null, error));
                throw new IOException(error);
            }
        } catch (InterruptedException interrupted) {
            request.cancelled = true;
            main.post(() -> complete(request, null, sourceName + "请求已取消"));
            Thread.currentThread().interrupt();
            throw new IOException(sourceName + "请求已取消", interrupted);
        }
        if (request.contextChallenge) throw new ContextChallengeException();
        if (!TextUtils.isEmpty(request.error)) throw new IOException(request.error);
        if (request.result == null) throw new IOException(sourceName + "请求未完成");
        return request.result;
    }

    private HttpFetch fetchHttp(String url, long deadline) throws IOException {
        HttpURLConnection connection = (HttpURLConnection) new URL(url).openConnection();
        long watchdogDelay = httpWatchdogDelayMs(deadline, SystemClock.elapsedRealtime());
        if (watchdogDelay == 0L) {
            connection.disconnect();
            throw new IOException(sourceName + "请求超时");
        }
        AtomicBoolean timedOut = new AtomicBoolean();
        ScheduledFuture<?> watchdog = HTTP_TIMEOUTS.schedule(() -> {
            timedOut.set(true);
            connection.disconnect();
        }, watchdogDelay, TimeUnit.MILLISECONDS);
        try {
            connection.setInstanceFollowRedirects(true);
            connection.setConnectTimeout(remainingTimeout(deadline, CONNECT_TIMEOUT_MS));
            connection.setReadTimeout(remainingTimeout(deadline, READ_TIMEOUT_MS));
            connection.setRequestProperty("User-Agent", USER_AGENT);
            connection.setRequestProperty("Accept-Language", "zh-CN,zh;q=0.9");
            String cookie = android.webkit.CookieManager.getInstance().getCookie(url);
            if (!TextUtils.isEmpty(cookie)) connection.setRequestProperty("Cookie", cookie);
            int statusCode = connection.getResponseCode();
            connection.setReadTimeout(remainingTimeout(deadline, READ_TIMEOUT_MS));
            persistResponseCookies(url, connection.getHeaderFields());
            InputStream stream = statusCode >= 400
                    ? connection.getErrorStream() : connection.getInputStream();
            return new HttpFetch(statusCode,
                    connection.getHeaderField("cf-mitigated"), readBody(stream, deadline));
        } catch (IOException error) {
            if (timedOut.get() || httpWatchdogDelayMs(
                    deadline, SystemClock.elapsedRealtime()) == 0L) {
                throw new IOException(sourceName + "请求超时", error);
            }
            throw error;
        } finally {
            watchdog.cancel(false);
            connection.disconnect();
        }
    }

    private int remainingTimeout(long deadline, int maximum) throws IOException {
        long remaining = remainingRequestMs(deadline, SystemClock.elapsedRealtime());
        if (remaining == 0L) throw new IOException(sourceName + "请求超时");
        return (int) Math.min(maximum, remaining);
    }

    private void persistResponseCookies(String url, Map<String, List<String>> headers) {
        if (headers == null) return;
        android.webkit.CookieManager manager = android.webkit.CookieManager.getInstance();
        for (Map.Entry<String, List<String>> header : headers.entrySet()) {
            if (header.getKey() == null
                    || !"Set-Cookie".equalsIgnoreCase(header.getKey())) continue;
            for (String value : header.getValue()) manager.setCookie(url, value);
        }
        manager.flush();
    }

    private String readBody(InputStream stream, long deadline) throws IOException {
        if (stream == null) return "";
        try (BufferedReader reader = new BufferedReader(new InputStreamReader(stream, "UTF-8"))) {
            StringBuilder body = new StringBuilder();
            String line;
            while ((line = reader.readLine()) != null) {
                if (remainingRequestMs(deadline, SystemClock.elapsedRealtime()) == 0L) {
                    throw new IOException(sourceName + "请求超时");
                }
                body.append(line).append('\n');
            }
            return body.toString();
        }
    }

    void shutdown() {
        shutdown = true;
        Runnable close = () -> {
            if (activeRequest != null) complete(activeRequest, null, sourceName + "浏览器会话已停止");
            closeViews();
        };
        if (Looper.myLooper() == Looper.getMainLooper()) close.run();
        else main.post(close);
    }

    void clearCache() {
        browserContextReady = false;
        Runnable clear = () -> {
            if (webView == null) return;
            webView.clearCache(true);
            webView.clearHistory();
            webView.clearFormData();
        };
        if (Looper.myLooper() == Looper.getMainLooper()) clear.run();
        else main.post(clear);
    }

    private void startRequest(FetchRequest request) {
        if (request.cancelled) return;
        if (shutdown || activity.isFinishing() || activity.isDestroyed()) {
            complete(request, null, sourceName + "浏览器会话无法打开");
            return;
        }
        if (activeRequest != null && !activeRequest.completed) {
            complete(request, null, sourceName + "浏览器会话正忙");
            return;
        }
        activeRequest = request;
        try {
            ensureViews();
            showBackgroundView();
            request.clearanceBefore = clearanceCookie(request.url);
            if (request.browserContext) {
                webView.evaluateJavascript(browserContextScript(request), null);
            } else {
                webView.loadUrl(request.url);
            }
        } catch (Exception error) {
            complete(request, null, sourceName + "浏览器会话启动失败");
        }
    }

    private void ensureViews() {
        if (webView != null && host != null && host.getParent() != null) return;
        ViewGroup content = activity.findViewById(android.R.id.content);
        if (content == null) throw new IllegalStateException("Missing activity content view");
        if (foregroundContent == null && content.getChildCount() > 0) {
            foregroundContent = content.getChildAt(0);
        }

        FrameLayout page = new FrameLayout(activity);
        page.setBackgroundColor(Color.TRANSPARENT);
        page.setClickable(false);
        page.setFocusable(false);

        WebView browser = new WebView(activity);
        browser.setAlpha(0.01f);
        browser.setBackgroundColor(Color.TRANSPARENT);
        browser.setClickable(false);
        page.addView(browser, new FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT));

        LinearLayout card = new LinearLayout(activity);
        card.setGravity(Gravity.CENTER_VERTICAL);
        card.setPadding(UIHelpers.dp(activity, 18), UIHelpers.dp(activity, 14),
                UIHelpers.dp(activity, 18), UIHelpers.dp(activity, 14));
        card.setBackground(UIHelpers.round(
                UIHelpers.CARD, UIHelpers.dp(activity, 10), UIHelpers.BORDER_SOFT));
        ProgressBar spinner = new ProgressBar(activity, null, android.R.attr.progressBarStyleSmall);
        spinner.setIndeterminateTintList(ColorStateList.valueOf(UIHelpers.ACCENT));
        LinearLayout.LayoutParams spinnerParams = new LinearLayout.LayoutParams(
                UIHelpers.dp(activity, 22), UIHelpers.dp(activity, 22));
        spinnerParams.rightMargin = UIHelpers.dp(activity, 12);
        card.addView(spinner, spinnerParams);
        TextView label = UIHelpers.text(activity, "正在验证", 14, UIHelpers.TEXT, Typeface.BOLD);
        label.setGravity(Gravity.CENTER_VERTICAL);
        card.addView(label, new LinearLayout.LayoutParams(
                UIHelpers.dp(activity, 78), UIHelpers.dp(activity, 24)));
        FrameLayout.LayoutParams statusParams = new FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT,
                Gravity.TOP | Gravity.CENTER_HORIZONTAL);
        statusParams.topMargin = UIHelpers.dp(activity, 18);
        page.addView(card, statusParams);

        WebSettings settings = browser.getSettings();
        settings.setUserAgentString(USER_AGENT);
        settings.setJavaScriptEnabled(true);
        settings.setDomStorageEnabled(true);
        settings.setDatabaseEnabled(true);
        settings.setLoadsImagesAutomatically(true);
        settings.setJavaScriptCanOpenWindowsAutomatically(false);
        android.webkit.CookieManager cookies = android.webkit.CookieManager.getInstance();
        cookies.setAcceptCookie(true);
        cookies.setAcceptThirdPartyCookies(browser, true);
        browser.addJavascriptInterface(new FetchBridge(), BRIDGE_NAME);
        browser.setWebViewClient(new WebViewClient() {
            @Override
            public void onPageStarted(WebView view, String url, android.graphics.Bitmap favicon) {
                navigation++;
                FetchRequest request = activeRequest;
                if (request != null) {
                    request.currentUrl = url == null ? "" : url;
                    request.statusCode = 0;
                    request.mitigated = "";
                    request.challengeDom = false;
                    request.pageReady = false;
                    if (request.verifying) showVerifyingState();
                }
            }

            @Override
            public void onPageFinished(WebView view, String url) {
                FetchRequest request = activeRequest;
                if (request != null) inspectPage(request, view, navigation);
            }

            @Override
            public void onReceivedError(WebView view, WebResourceRequest request, WebResourceError error) {
                FetchRequest active = activeRequest;
                if (active != null && request != null && request.isForMainFrame()) {
                    complete(active, null, sourceName + "页面加载失败");
                }
            }

            @Override
            public void onReceivedHttpError(WebView view, WebResourceRequest request,
                                            WebResourceResponse response) {
                FetchRequest active = activeRequest;
                if (active == null || request == null || !request.isForMainFrame() || response == null) return;
                active.statusCode = response.getStatusCode();
                java.util.Map<String, String> headers = response.getResponseHeaders();
                if (headers != null) {
                    for (java.util.Map.Entry<String, String> header : headers.entrySet()) {
                        if ("cf-mitigated".equalsIgnoreCase(header.getKey())) {
                            active.mitigated = header.getValue();
                            break;
                        }
                    }
                }
            }
        });

        content.addView(page, backgroundLayoutParams());
        host = page;
        webView = browser;
        statusCard = card;
        progress = spinner;
        status = label;
    }

    private void inspectPage(FetchRequest request, WebView browser, int expectedNavigation) {
        if (!isActive(request) || expectedNavigation != navigation) return;
        if (remainingRequestMs(request.deadline, SystemClock.elapsedRealtime()) == 0L) {
            complete(request, null, timeoutError(request));
            return;
        }
        String script = "(function(){return JSON.stringify({"
                + "title:document.title||'',text:(document.body&&document.body.innerText||'').slice(0,2400),"
                + "html:(document.documentElement.outerHTML||'').slice(0,12000),"
                + "turnstileSolved:!!((document.querySelector('[name=\"cf-turnstile-response\"]')||{}).value),"
                + "ready:document.readyState||'',url:location.href||''});})()";
        browser.evaluateJavascript(script, encoded -> {
            if (!isActive(request) || expectedNavigation != navigation) return;
            try {
                JSONObject page = new JSONObject(decodeJavascriptString(encoded));
                boolean challenge = isChallenge(page.optString("url"), page.optString("title"),
                        page.optString("text") + " " + page.optString("html"),
                        request.statusCode, request.mitigated, request.verifying);
                boolean ready = "complete".equalsIgnoreCase(page.optString("ready"));
                boolean turnstileSolved = page.optBoolean("turnstileSolved");
                request.currentUrl = page.optString("url");
                request.challengeDom = challenge;
                request.pageReady = ready;
                String clearanceNow = clearanceCookie(request.url);
                if (shouldHandOffInteractive(request.interactiveVisible, turnstileSolved,
                        request.clearanceBefore, clearanceNow)) {
                    request.interactiveVisible = false;
                    if (automaticInteractiveFallback) {
                        notifyVerification("正在完成验证");
                        showCompletingBehindApp();
                    } else {
                        showBackgroundView();
                    }
                }
                PageAction action = pageAction(request.verifying, challenge, ready, request.statusCode);
                if (action == PageAction.SHOW_VERIFICATION) {
                    request.verifying = true;
                    notifyVerification("正在验证");
                    showBackgroundView();
                    if (request.interactiveAllowed) {
                        browser.postDelayed(() -> {
                            if (isActive(request) && shouldShowInteractive(
                                    request.interactiveAllowed, request.verifying)) {
                                request.interactiveVisible = true;
                                showVerificationView(true);
                            }
                        }, INTERACTIVE_DELAY_MS);
                    }
                } else if (action == PageAction.KEEP_VERIFYING) {
                    showVerifyingState();
                } else if (action == PageAction.FAIL) {
                    complete(request, null, sourceName + "请求失败：HTTP "
                            + request.statusCode + requestDiagnostic(request));
                    return;
                } else if (action == PageAction.CAPTURE) {
                    if (!isExpectedPage(request.url, page.optString("url"))) {
                        complete(request, null, sourceName + "页面跳转异常"
                                + requestDiagnostic(request));
                        return;
                    }
                    android.webkit.CookieManager.getInstance().flush();
                    if (request.verifying) {
                        notifyVerification("验证完成");
                        if (automaticInteractiveFallback) showBackgroundView();
                        else showVerifiedState();
                        browser.postDelayed(() -> captureCurrentPage(
                                request, browser, expectedNavigation), 300L);
                    } else {
                        captureCurrentPage(request, browser, expectedNavigation);
                    }
                    return;
                }
                browser.postDelayed(() -> inspectPage(
                        request, browser, expectedNavigation), POLL_DELAY_MS);
            } catch (Exception error) {
                complete(request, null, sourceName + "页面结果解析失败");
            }
        });
    }

    private void captureCurrentPage(FetchRequest request, WebView browser, int expectedNavigation) {
        if (!isActive(request) || expectedNavigation != navigation) return;
        request.verifying = false;
        showBackgroundView();
        String script = "(function(){var id=" + JSONObject.quote(request.id) + ";try{window."
                + BRIDGE_NAME + ".onFetchResult(id,JSON.stringify({url:location.href||'',body:"
                + "document.documentElement.outerHTML||''}));}catch(e){window." + BRIDGE_NAME
                + ".onFetchResult(id,JSON.stringify({error:String(e)}));}})();";
        browser.evaluateJavascript(script, null);
    }

    private String browserContextScript(FetchRequest request) {
        String id = JSONObject.quote(request.id);
        String url = JSONObject.quote(request.url);
        return "(function(){var id=" + id + ",url=" + url + ";try{fetch(url,{"
                + "credentials:\"include\",cache:\"no-store\",redirect:\"follow\"})"
                + ".then(function(response){return response.text().then(function(body){window."
                + BRIDGE_NAME + ".onFetchResult(id,JSON.stringify({url:response.url||url,status:"
                + "response.status||0,mitigated:response.headers.get('cf-mitigated')||'',body:body||''}));});})"
                + ".catch(function(error){window." + BRIDGE_NAME
                + ".onFetchResult(id,JSON.stringify({error:String(error)}));});}catch(error){window."
                + BRIDGE_NAME + ".onFetchResult(id,JSON.stringify({error:String(error)}));}})();";
    }

    private void handleFetchResult(String id, String payload) {
        FetchRequest request = activeRequest;
        if (request == null || !request.id.equals(id) || !isActive(request)) return;
        try {
            JSONObject response = new JSONObject(payload == null ? "" : payload);
            if (!TextUtils.isEmpty(response.optString("error"))) {
                complete(request, null, sourceName + "浏览器请求失败");
                return;
            }
            String body = response.optString("body", "");
            if (request.browserContext) {
                request.statusCode = response.optInt("status", 0);
                request.mitigated = response.optString("mitigated", "");
                HttpAction action = httpAction(request.statusCode, request.mitigated, body);
                if (action == HttpAction.OPEN_BROWSER) {
                    request.contextChallenge = true;
                    complete(request, null, "");
                    return;
                }
                if (action == HttpAction.FAIL) {
                    complete(request, null, sourceName + " HTTP " + request.statusCode);
                    return;
                }
            }
            if (!isExpectedPage(request.url, response.optString("url", ""))) {
                complete(request, null, sourceName + "页面跳转异常");
                return;
            }
            if (TextUtils.isEmpty(body)) {
                complete(request, null, sourceName + "页面内容为空");
                return;
            }
            complete(request, body, "");
        } catch (Exception error) {
            complete(request, null, sourceName + "浏览器响应解析失败");
        }
    }

    static boolean isChallenge(String url, String title, String body, int statusCode,
                               String mitigated, boolean verifying) {
        String content = ((url == null ? "" : url) + " " + (title == null ? "" : title)
                + " " + (body == null ? "" : body)).toLowerCase(Locale.US);
        boolean responseChallenge = statusCode == 403 && "challenge".equalsIgnoreCase(mitigated);
        boolean domChallenge = content.contains("/orchestrate/chl_page/")
                || content.contains("cf-chl-widget")
                || content.contains("cf-turnstile-response")
                || content.contains("just a moment")
                || content.contains("attention required")
                || content.contains("checking your browser")
                || content.contains("performing security verification")
                || content.contains("verify you are human")
                || content.contains("请稍候")
                || content.contains("正在验证")
                || content.contains("安全验证");
        return domChallenge || (!verifying && responseChallenge);
    }

    enum PageAction {
        WAIT,
        SHOW_VERIFICATION,
        KEEP_VERIFYING,
        CAPTURE,
        FAIL
    }

    enum HttpAction {
        RETURN_BODY,
        OPEN_BROWSER,
        FAIL
    }

    static HttpAction httpAction(int statusCode, String mitigated, String body) {
        if (isChallenge("", "", body, statusCode, mitigated, false)) {
            return HttpAction.OPEN_BROWSER;
        }
        return statusCode >= 200 && statusCode < 400
                ? HttpAction.RETURN_BODY : HttpAction.FAIL;
    }

    static PageAction pageAction(boolean verifying, boolean challenge, boolean ready) {
        return pageAction(verifying, challenge, ready, 0);
    }

    static PageAction pageAction(boolean verifying, boolean challenge, boolean ready, int statusCode) {
        if (challenge) {
            return verifying ? PageAction.KEEP_VERIFYING : PageAction.SHOW_VERIFICATION;
        }
        if (statusCode >= 400 && !verifying) return PageAction.FAIL;
        return ready ? PageAction.CAPTURE : PageAction.WAIT;
    }

    static boolean isExpectedPage(String requested, String actual) {
        try {
            URL expected = new URL(requested);
            URL received = new URL(actual);
            String expectedHost = expected.getHost().toLowerCase(Locale.US);
            String receivedHost = received.getHost().toLowerCase(Locale.US);
            boolean sameHost = expectedHost.equals(receivedHost)
                    || expectedHost.endsWith("." + receivedHost)
                    || receivedHost.endsWith("." + expectedHost);
            if (!sameHost || !expected.getProtocol().equalsIgnoreCase(received.getProtocol())) return false;
            String expectedPath = normalizedPath(expected.getPath());
            String receivedPath = normalizedPath(received.getPath());
            return expectedPath.equals(receivedPath) || receivedPath.startsWith(expectedPath + "/");
        } catch (Exception ignored) {
            return false;
        }
    }

    private static String normalizedPath(String value) {
        String path = value == null || value.isEmpty() ? "/" : value;
        while (path.length() > 1 && path.endsWith("/")) path = path.substring(0, path.length() - 1);
        return path;
    }

    private boolean isActive(FetchRequest request) {
        return request != null && !request.cancelled && !request.completed
                && activeRequest == request && !shutdown;
    }

    private void showVerificationView(boolean interactive) {
        if (host == null) return;
        host.setLayoutParams(verificationLayoutParams());
        host.setTranslationX(0f);
        host.setBackgroundColor(Color.argb(42, 18, 39, 56));
        host.setClickable(true);
        host.setFocusable(true);
        if (webView != null) {
            webView.setAlpha(interactive ? 1f : 0.01f);
            webView.setClickable(interactive);
        }
        if (statusCard != null) statusCard.setVisibility(View.VISIBLE);
        showVerifyingState();
        host.bringToFront();
    }

    private void showBackgroundView() {
        if (host == null) return;
        host.setLayoutParams(backgroundLayoutParams());
        host.setTranslationX(fullViewportBackground
                ? activity.getResources().getDisplayMetrics().widthPixels + 1f : 0f);
        host.setBackgroundColor(Color.TRANSPARENT);
        host.setClickable(false);
        host.setFocusable(false);
        if (webView != null) {
            webView.setAlpha(0.01f);
            webView.setClickable(false);
        }
        if (statusCard != null) statusCard.setVisibility(View.GONE);
    }

    private void showCompletingBehindApp() {
        if (host == null) return;
        host.setLayoutParams(verificationLayoutParams());
        host.setTranslationX(0f);
        host.setBackgroundColor(Color.TRANSPARENT);
        host.setClickable(false);
        host.setFocusable(false);
        if (webView != null) {
            webView.setAlpha(1f);
            webView.setClickable(false);
        }
        if (statusCard != null) statusCard.setVisibility(View.GONE);
        if (foregroundContent != null) foregroundContent.bringToFront();
    }

    private FrameLayout.LayoutParams verificationLayoutParams() {
        return new FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT, Gravity.CENTER);
    }

    private FrameLayout.LayoutParams backgroundLayoutParams() {
        int extent = backgroundExtent(fullViewportBackground);
        return new FrameLayout.LayoutParams(extent, extent, Gravity.TOP | Gravity.START);
    }

    private void showVerifyingState() {
        if (status != null) status.setText("正在验证");
        if (progress != null) progress.setVisibility(View.VISIBLE);
    }

    private void showVerifiedState() {
        if (status != null) status.setText("验证完成");
        if (progress != null) progress.setVisibility(View.INVISIBLE);
    }

    private void notifyVerification(String message) {
        if (verificationStatus != null) {
            verificationStatus.onStatus(sourceName + " " + message);
        }
    }

    private String clearanceCookie(String url) {
        return cookieValue(android.webkit.CookieManager.getInstance().getCookie(url),
                "cf_clearance");
    }

    private String requestDiagnostic(FetchRequest request) {
        return " [url=" + request.currentUrl + ", status=" + request.statusCode
                + ", verifying=" + request.verifying + ", challenge="
                + request.challengeDom + ", ready=" + request.pageReady + "]";
    }

    private String timeoutError(FetchRequest request) {
        return sourceName + (request.verifying ? "验证超时" : "请求超时")
                + requestDiagnostic(request);
    }

    private String decodeJavascriptString(String encoded) {
        if (TextUtils.isEmpty(encoded) || "null".equals(encoded)) return "";
        try {
            return new JSONArray("[" + encoded + "]").optString(0, "");
        } catch (Exception ignored) {
            return "";
        }
    }

    private void complete(FetchRequest request, String result, String error) {
        if (request == null || request.completed) return;
        request.completed = true;
        request.result = result;
        request.error = error == null ? "" : error;
        if (activeRequest == request) activeRequest = null;
        if (!shutdown && webView != null) showBackgroundView();
        request.latch.countDown();
    }

    private void closeViews() {
        browserContextReady = false;
        WebView browser = webView;
        FrameLayout page = host;
        webView = null;
        host = null;
        foregroundContent = null;
        statusCard = null;
        progress = null;
        status = null;
        if (page != null && page.getParent() instanceof ViewGroup) {
            ((ViewGroup) page.getParent()).removeView(page);
        }
        if (browser != null) {
            browser.stopLoading();
            browser.removeJavascriptInterface(BRIDGE_NAME);
            browser.removeAllViews();
            browser.destroy();
        }
    }

    private final class FetchBridge {
        @JavascriptInterface
        public void onFetchResult(String id, String payload) {
            main.post(() -> handleFetchResult(id, payload));
        }
    }

    private static final class FetchRequest {
        final String id;
        final String url;
        final boolean browserContext;
        final boolean interactiveAllowed;
        final long deadline;
        final CountDownLatch latch = new CountDownLatch(1);
        volatile boolean cancelled;
        volatile boolean completed;
        volatile String result;
        volatile String error = "";
        volatile String currentUrl = "";
        volatile boolean challengeDom;
        volatile boolean pageReady;
        volatile boolean contextChallenge;
        boolean verifying;
        boolean interactiveVisible;
        int statusCode;
        String mitigated = "";
        String clearanceBefore = "";

        FetchRequest(String id, String url, boolean browserContext,
                     boolean interactiveAllowed, long deadline) {
            this.id = id;
            this.url = url;
            this.browserContext = browserContext;
            this.interactiveAllowed = interactiveAllowed;
            this.deadline = deadline;
        }
    }

    private static final class ContextChallengeException extends IOException {
    }

    private static final class HttpFetch {
        final int statusCode;
        final String mitigated;
        final String body;

        HttpFetch(int statusCode, String mitigated, String body) {
            this.statusCode = statusCode;
            this.mitigated = mitigated == null ? "" : mitigated;
            this.body = body == null ? "" : body;
        }
    }
}
