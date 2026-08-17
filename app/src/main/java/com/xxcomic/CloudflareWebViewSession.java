package com.xxcomic;

import android.app.Activity;
import android.content.res.ColorStateList;
import android.graphics.Color;
import android.graphics.Typeface;
import android.os.Handler;
import android.os.Looper;
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
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;

final class CloudflareWebViewSession implements BrowserSession {
    private static final String BRIDGE_NAME = "XXComicBridge";
    private static final long TIMEOUT_MS = 180000L;
    private static final long POLL_DELAY_MS = 800L;
    private static final long INTERACTIVE_DELAY_MS = 1200L;
    private static final String USER_AGENT = "Mozilla/5.0 (Linux; Android 14) "
            + "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36";
    private static final int CONNECT_TIMEOUT_MS = 10000;
    private static final int READ_TIMEOUT_MS = 25000;

    private final Activity activity;
    private final Handler main;
    private final String sourceName;
    private final boolean preferHttp;
    private final Object requestLock = new Object();
    private final AtomicInteger requestSequence = new AtomicInteger();
    private volatile boolean shutdown;
    private FrameLayout host;
    private WebView webView;
    private View statusCard;
    private ProgressBar progress;
    private TextView status;
    private FetchRequest activeRequest;
    private int navigation;

    CloudflareWebViewSession(Activity activity, Handler main, String sourceName,
                             boolean preferHttp) {
        this.activity = activity;
        this.main = main;
        this.sourceName = sourceName;
        this.preferHttp = preferHttp;
    }

    @Override
    public String fetch(String url) throws IOException {
        if (Looper.myLooper() == Looper.getMainLooper()) {
            throw new IOException(sourceName + "请求不能阻塞主线程");
        }
        synchronized (requestLock) {
            if (shutdown) throw new IOException(sourceName + "浏览器会话已停止");
            if (preferHttp) {
                HttpFetch response = fetchHttp(url);
                HttpAction action = httpAction(
                        response.statusCode, response.mitigated, response.body);
                if (action == HttpAction.RETURN_BODY) return response.body;
                if (action == HttpAction.FAIL) {
                    throw new IOException(sourceName + " HTTP " + response.statusCode);
                }
            }
            return fetchWithBrowser(url);
        }
    }

    private String fetchWithBrowser(String url) throws IOException {
        FetchRequest request = new FetchRequest(
                Integer.toString(requestSequence.incrementAndGet()), url);
        main.post(() -> startRequest(request));
        try {
            if (!request.latch.await(TIMEOUT_MS, TimeUnit.MILLISECONDS)) {
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
        if (!TextUtils.isEmpty(request.error)) throw new IOException(request.error);
        if (request.result == null) throw new IOException(sourceName + "请求未完成");
        return request.result;
    }

    private HttpFetch fetchHttp(String url) throws IOException {
        HttpURLConnection connection = (HttpURLConnection) new URL(url).openConnection();
        connection.setInstanceFollowRedirects(true);
        connection.setConnectTimeout(CONNECT_TIMEOUT_MS);
        connection.setReadTimeout(READ_TIMEOUT_MS);
        connection.setRequestProperty("User-Agent", USER_AGENT);
        connection.setRequestProperty("Accept-Language", "zh-CN,zh;q=0.9");
        String cookie = android.webkit.CookieManager.getInstance().getCookie(url);
        if (!TextUtils.isEmpty(cookie)) connection.setRequestProperty("Cookie", cookie);
        try {
            int statusCode = connection.getResponseCode();
            persistResponseCookies(url, connection.getHeaderFields());
            InputStream stream = statusCode >= 400
                    ? connection.getErrorStream() : connection.getInputStream();
            return new HttpFetch(statusCode,
                    connection.getHeaderField("cf-mitigated"), readBody(stream));
        } finally {
            connection.disconnect();
        }
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

    private static String readBody(InputStream stream) throws IOException {
        if (stream == null) return "";
        try (BufferedReader reader = new BufferedReader(new InputStreamReader(stream, "UTF-8"))) {
            StringBuilder body = new StringBuilder();
            String line;
            while ((line = reader.readLine()) != null) body.append(line).append('\n');
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
            webView.loadUrl(request.url);
        } catch (Exception error) {
            complete(request, null, sourceName + "浏览器会话启动失败");
        }
    }

    private void ensureViews() {
        if (webView != null && host != null && host.getParent() != null) return;
        ViewGroup content = activity.findViewById(android.R.id.content);
        if (content == null) throw new IllegalStateException("Missing activity content view");

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
        if (System.currentTimeMillis() - request.startedAt >= TIMEOUT_MS) {
            complete(request, null, timeoutError(request));
            return;
        }
        String script = "(function(){return JSON.stringify({"
                + "title:document.title||'',text:(document.body&&document.body.innerText||'').slice(0,2400),"
                + "html:(document.documentElement.outerHTML||'').slice(0,12000),"
                + "ready:document.readyState||'',url:location.href||''});})()";
        browser.evaluateJavascript(script, encoded -> {
            if (!isActive(request) || expectedNavigation != navigation) return;
            try {
                JSONObject page = new JSONObject(decodeJavascriptString(encoded));
                boolean challenge = isChallenge(page.optString("url"), page.optString("title"),
                        page.optString("text") + " " + page.optString("html"),
                        request.statusCode, request.mitigated, request.verifying);
                boolean ready = "complete".equalsIgnoreCase(page.optString("ready"));
                request.currentUrl = page.optString("url");
                request.challengeDom = challenge;
                request.pageReady = ready;
                PageAction action = pageAction(request.verifying, challenge, ready, request.statusCode);
                if (action == PageAction.SHOW_VERIFICATION) {
                    request.verifying = true;
                    showVerificationView(false);
                    browser.postDelayed(() -> {
                        if (isActive(request) && request.verifying) showVerificationView(true);
                    }, INTERACTIVE_DELAY_MS);
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
                        showVerifiedState();
                        browser.postDelayed(() -> captureCurrentPage(
                                request, browser, expectedNavigation), 550L);
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
        host.setBackgroundColor(Color.TRANSPARENT);
        host.setClickable(false);
        host.setFocusable(false);
        if (webView != null) {
            webView.setAlpha(0.01f);
            webView.setClickable(false);
        }
        if (statusCard != null) statusCard.setVisibility(View.GONE);
    }

    private FrameLayout.LayoutParams verificationLayoutParams() {
        return new FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT, Gravity.CENTER);
    }

    private FrameLayout.LayoutParams backgroundLayoutParams() {
        return new FrameLayout.LayoutParams(1, 1, Gravity.TOP | Gravity.START);
    }

    private void showVerifyingState() {
        if (status != null) status.setText("正在验证");
        if (progress != null) progress.setVisibility(View.VISIBLE);
    }

    private void showVerifiedState() {
        if (status != null) status.setText("验证完成");
        if (progress != null) progress.setVisibility(View.INVISIBLE);
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
        WebView browser = webView;
        FrameLayout page = host;
        webView = null;
        host = null;
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
        final CountDownLatch latch = new CountDownLatch(1);
        final long startedAt = System.currentTimeMillis();
        volatile boolean cancelled;
        volatile boolean completed;
        volatile String result;
        volatile String error = "";
        volatile String currentUrl = "";
        volatile boolean challengeDom;
        volatile boolean pageReady;
        boolean verifying;
        int statusCode;
        String mitigated = "";

        FetchRequest(String id, String url) {
            this.id = id;
            this.url = url;
        }
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
