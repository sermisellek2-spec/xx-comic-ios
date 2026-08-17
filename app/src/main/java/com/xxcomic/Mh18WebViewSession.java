package com.xxcomic;

import android.app.Activity;
import android.app.Dialog;
import android.content.Context;
import android.graphics.Color;
import android.graphics.drawable.ColorDrawable;
import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;
import android.text.TextUtils;
import android.view.Gravity;
import android.view.ViewGroup;
import android.view.Window;
import android.webkit.CookieManager;
import android.webkit.WebResourceError;
import android.webkit.WebResourceRequest;
import android.webkit.WebResourceResponse;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.TextView;

import com.xxcomic.source.BrowserSession;
import com.xxcomic.source.Mh18ComicSource;
import com.xxcomic.source.VerificationCancelledException;
import com.xxcomic.source.VerificationRequiredException;

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
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Semaphore;
import java.util.concurrent.TimeUnit;

final class Mh18WebViewSession implements BrowserSession {
    private static final String PREFS_NAME = "mh18_verification";
    private static final String VERIFIED_AT_KEY = "verified_at";
    private static final long TIMEOUT_MS = 120000L;
    private static final long SUCCESS_DELAY_MS = 600L;
    private static final long INSPECTION_DELAY_MS = 600L;
    private static final String USER_AGENT = "Mozilla/5.0 (Linux; Android 14) "
            + "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36";
    private static final int CONNECT_TIMEOUT_MS = 10000;
    private static final int READ_TIMEOUT_MS = 25000;
    private static final ExecutorService HTTP_EXECUTOR =
            Executors.newSingleThreadExecutor(runnable -> {
                Thread thread = new Thread(runnable, "Mh18VerificationProbe");
                thread.setDaemon(true);
                return thread;
            });

    private final Activity activity;
    private final Handler main;
    private final String sourceName;
    private final String userAgent;
    private final VerificationStatusListener verificationStatus;
    private final VerificationRetryListener verificationRetry;
    private final Semaphore requestLock = new Semaphore(1, true);
    private volatile boolean shutdown;
    private InteractiveRequest activeRequest;

    Mh18WebViewSession(Activity activity, Handler main, String sourceName,
                       VerificationStatusListener verificationStatus) {
        this(activity, main, sourceName, verificationStatus, () -> {
        });
    }

    Mh18WebViewSession(Activity activity, Handler main, String sourceName,
                       VerificationStatusListener verificationStatus,
                       VerificationRetryListener verificationRetry) {
        this.activity = activity;
        this.main = main;
        this.sourceName = sourceName;
        this.userAgent = fixedUserAgent();
        this.verificationStatus = verificationStatus;
        this.verificationRetry = verificationRetry == null ? () -> {
        } : verificationRetry;
    }

    interface VerificationStatusListener {
        void onStatus(String message);
    }

    interface VerificationRetryListener {
        void onRetry();
    }

    static String fixedUserAgent() {
        return USER_AGENT;
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

    @Override
    public String fetch(String url) throws IOException {
        requireWorkerThread();
        boolean acquired = false;
        try {
            acquired = requestLock.tryAcquire(TIMEOUT_MS, TimeUnit.MILLISECONDS);
            if (!acquired) throw new IOException(sourceName + "请求超时");
            if (shutdown) throw new IOException(sourceName + "浏览器会话已停止");
            HttpFetch response = fetchHttp(url);
            HttpAction action = httpAction(
                    response.statusCode, response.mitigated, response.body);
            if (action == HttpAction.VERIFICATION_REQUIRED) {
                throw new VerificationRequiredException(sourceName + "需要验证");
            }
            if (action == HttpAction.FAIL) {
                throw new IOException(sourceName + "请求失败：HTTP " + response.statusCode);
            }
            return response.body;
        } catch (InterruptedException interrupted) {
            Thread.currentThread().interrupt();
            throw new IOException(sourceName + "请求已取消", interrupted);
        } finally {
            if (acquired) requestLock.release();
        }
    }

    @Override
    public String fetchInteractive(String url) throws IOException {
        requireWorkerThread();
        if (shutdown) throw new IOException(sourceName + "浏览器会话已停止");
        InteractiveRequest request = new InteractiveRequest(url);
        main.post(() -> startInteractive(request));
        try {
            request.latch.await();
        } catch (InterruptedException interrupted) {
            main.post(() -> cancelInteractive(request));
            Thread.currentThread().interrupt();
            throw new VerificationCancelledException(sourceName + "验证已取消");
        }
        if (request.failure != null) throw request.failure;
        if (request.result == null) throw new IOException(sourceName + "验证未完成");
        return request.result;
    }

    private void requireWorkerThread() throws IOException {
        if (Looper.myLooper() == Looper.getMainLooper()) {
            throw new IOException(sourceName + "请求不能阻塞主线程");
        }
    }

    private HttpFetch fetchHttp(String url) throws IOException {
        HttpURLConnection connection = (HttpURLConnection) new URL(url).openConnection();
        try {
            connection.setInstanceFollowRedirects(true);
            connection.setConnectTimeout(CONNECT_TIMEOUT_MS);
            connection.setReadTimeout(READ_TIMEOUT_MS);
            connection.setRequestProperty("User-Agent", userAgent);
            connection.setRequestProperty("Accept-Language", "zh-CN,zh;q=0.9");
            String cookie = CookieManager.getInstance().getCookie(url);
            if (!TextUtils.isEmpty(cookie)) connection.setRequestProperty("Cookie", cookie);
            int statusCode = connection.getResponseCode();
            String mitigated = connection.getHeaderField("cf-mitigated");
            persistResponseCookies(url, connection.getHeaderFields());
            if (statusCode == 403 && "challenge".equalsIgnoreCase(mitigated)) {
                return new HttpFetch(statusCode, mitigated, "");
            }
            InputStream stream = statusCode >= 400
                    ? connection.getErrorStream() : connection.getInputStream();
            return new HttpFetch(statusCode, mitigated, readBody(stream));
        } finally {
            connection.disconnect();
        }
    }

    private void persistResponseCookies(String url, Map<String, List<String>> headers) {
        if (headers == null) return;
        CookieManager manager = CookieManager.getInstance();
        for (Map.Entry<String, List<String>> header : headers.entrySet()) {
            if (header.getKey() == null
                    || !"Set-Cookie".equalsIgnoreCase(header.getKey())) continue;
            for (String value : header.getValue()) manager.setCookie(url, value);
        }
        manager.flush();
    }

    private String readBody(InputStream stream) throws IOException {
        if (stream == null) return "";
        try (BufferedReader reader = new BufferedReader(
                new InputStreamReader(stream, "UTF-8"))) {
            StringBuilder body = new StringBuilder();
            String line;
            while ((line = reader.readLine()) != null) body.append(line).append('\n');
            return body.toString();
        }
    }

    private void startInteractive(InteractiveRequest request) {
        if (shutdown || activity.isFinishing() || activity.isDestroyed()) {
            finishRequest(request, null, new IOException(sourceName + "验证窗口无法打开"));
            return;
        }
        if (activeRequest != null && !activeRequest.completed) {
            finishRequest(request, null, new IOException(sourceName + "验证窗口正忙"));
            return;
        }
        activeRequest = request;
        try {
            createDialog(request);
            notifyVerification("正在检查站点");
            scheduleTimeout(request);
            beginPreflight(request);
        } catch (Exception error) {
            finishRequest(request, null, new IOException(sourceName + "验证窗口无法打开", error));
        }
    }

    private void createDialog(InteractiveRequest request) {
        LinearLayout root = new LinearLayout(activity);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setPadding(dp(12), dp(10), dp(12), dp(10));
        root.setBackground(UIHelpers.round(UIHelpers.CARD, dp(8), UIHelpers.BORDER_SOFT));

        TextView source = UIHelpers.text(
                activity, sourceName, 15, UIHelpers.TEXT, android.graphics.Typeface.BOLD);
        root.addView(source, new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));

        TextView status = UIHelpers.text(
                activity, "正在检查站点", 12, UIHelpers.TEXT2,
                android.graphics.Typeface.NORMAL);
        LinearLayout.LayoutParams statusParams = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        statusParams.topMargin = dp(2);
        statusParams.bottomMargin = dp(8);
        root.addView(status, statusParams);

        WebView browser = new WebView(activity);
        browser.setVisibility(android.view.View.GONE);
        root.addView(browser, new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f));

        LinearLayout controls = new LinearLayout(activity);
        controls.setGravity(Gravity.END | Gravity.CENTER_VERTICAL);
        TextView reload = UIHelpers.text(activity, "重新加载", 12,
                UIHelpers.ACCENT, android.graphics.Typeface.BOLD);
        reload.setText("重新加载");
        reload.setGravity(Gravity.CENTER);
        reload.setBackground(UIHelpers.round(
                UIHelpers.ACCENT_LIGHT, dp(6), UIHelpers.BORDER_SOFT));
        ImageView close = UIHelpers.vectorIconButton(
                activity, R.drawable.ic_close, UIHelpers.TEXT2, 6);
        close.setContentDescription("关闭验证");
        controls.addView(reload, new LinearLayout.LayoutParams(dp(88), dp(34)));
        LinearLayout.LayoutParams closeParams = new LinearLayout.LayoutParams(dp(34), dp(34));
        closeParams.leftMargin = dp(6);
        controls.addView(close, closeParams);
        LinearLayout.LayoutParams controlsParams = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        controlsParams.topMargin = dp(6);
        root.addView(controls, controlsParams);

        Dialog dialog = new Dialog(activity);
        dialog.setCancelable(false);
        dialog.setCanceledOnTouchOutside(false);
        dialog.setContentView(root);
        dialog.show();
        Window window = dialog.getWindow();
        if (window != null) {
            window.setBackgroundDrawable(new ColorDrawable(Color.TRANSPARENT));
            int width = activity.getResources().getDisplayMetrics().widthPixels;
            window.setLayout(width * 9 / 10, ViewGroup.LayoutParams.WRAP_CONTENT);
        }

        request.dialog = dialog;
        request.webView = browser;
        request.status = status;
        request.reload = reload;
        request.close = close;

        WebSettings settings = browser.getSettings();
        settings.setUserAgentString(userAgent);
        settings.setJavaScriptEnabled(true);
        settings.setDomStorageEnabled(true);
        settings.setDatabaseEnabled(true);
        settings.setLoadsImagesAutomatically(true);
        settings.setJavaScriptCanOpenWindowsAutomatically(false);
        CookieManager cookies = CookieManager.getInstance();
        cookies.setAcceptCookie(true);
        cookies.setAcceptThirdPartyCookies(browser, true);

        browser.setWebViewClient(new WebViewClient() {
            @Override
            public void onPageStarted(WebView view, String url,
                                      android.graphics.Bitmap favicon) {
                if (!isActive(request)) return;
                request.navigation++;
                request.probeRunning = false;
                request.inspecting = false;
                cancelInspection(request);
                if (request.stopped) {
                    view.stopLoading();
                    return;
                }
                request.statusCode = 0;
                request.mitigated = "";
                setStatus(request, "正在加载验证页");
            }

            @Override
            public void onPageFinished(WebView view, String url) {
                if (isActive(request)) {
                    inspectPage(request, request.attempt, request.navigation);
                }
            }

            @Override
            public boolean shouldOverrideUrlLoading(WebView view,
                                                    WebResourceRequest navigation) {
                if (navigation != null && navigation.isForMainFrame()
                        && shouldBlockNavigation(
                                request.url, navigation.getUrl().toString())) {
                    return true;
                }
                return false;
            }

            @Override
            public void onReceivedError(WebView view, WebResourceRequest failed,
                                        WebResourceError error) {
                if (failed != null && failed.isForMainFrame()) {
                    stopAttempt(request, "网络加载失败，请重试");
                }
            }

            @Override
            public void onReceivedHttpError(WebView view, WebResourceRequest failed,
                                            WebResourceResponse response) {
                if (!isActive(request) || failed == null || !failed.isForMainFrame()
                        || response == null) return;
                request.statusCode = response.getStatusCode();
                Map<String, String> headers = response.getResponseHeaders();
                if (headers == null) return;
                for (Map.Entry<String, String> header : headers.entrySet()) {
                    if ("cf-mitigated".equalsIgnoreCase(header.getKey())) {
                        request.mitigated = header.getValue();
                        break;
                    }
                }
            }
        });
        reload.setOnClickListener(ignored -> retryInteractive(request));
        close.setOnClickListener(ignored -> cancelInteractive(request));
    }

    private void loadInteractive(InteractiveRequest request) {
        if (!isActive(request) || request.succeeded) return;
        request.attempt++;
        request.navigation = 0;
        request.probeRunning = false;
        request.stopped = false;
        request.webView.setVisibility(android.view.View.VISIBLE);
        Window window = request.dialog == null ? null : request.dialog.getWindow();
        if (window != null) {
            int width = activity.getResources().getDisplayMetrics().widthPixels;
            int height = activity.getResources().getDisplayMetrics().heightPixels;
            window.setLayout(width * 9 / 10, height * 7 / 10);
        }
        setStatus(request, "正在加载验证页");
        request.webView.loadUrl(request.url);
    }

    private void retryInteractive(InteractiveRequest request) {
        if (!isActive(request) || request.succeeded) return;
        finishRequest(request, null,
                new VerificationCancelledException(sourceName + "验证已取消"));
        verificationRetry.onRetry();
    }

    private void beginPreflight(InteractiveRequest request) {
        request.preflightRunning = true;
        HTTP_EXECUTOR.execute(() -> {
            try {
                HttpFetch response = fetchHttp(request.url);
                main.post(() -> finishPreflight(request, response, null));
            } catch (IOException error) {
                main.post(() -> finishPreflight(request, null, error));
            }
        });
    }

    private void finishPreflight(InteractiveRequest request, HttpFetch response,
                                 IOException failure) {
        if (!isActive(request) || !request.preflightRunning || request.stopped) return;
        request.preflightRunning = false;
        if (failure != null) {
            stopAttempt(request, "站点检查失败，请重试");
            return;
        }
        InteractiveAction action = interactiveAction(
                response.statusCode, response.mitigated, response.body);
        if (action == InteractiveAction.COMPLETE) {
            completeVerification(request, response.body);
        } else if (action == InteractiveAction.OPEN_BROWSER) {
            loadInteractive(request);
        } else {
            stopAttempt(request, "站点检查失败，请重试");
        }
    }

    private void scheduleTimeout(InteractiveRequest request) {
        if (request.timeout != null) main.removeCallbacks(request.timeout);
        request.timeout = () -> {
            if (!shouldStopForTimeout(
                    isActive(request), request.succeeded)) return;
            if (request.webView != null) request.webView.stopLoading();
            stopAttempt(request, "验证超时，请重试");
        };
        long remaining = remainingRequestMs(request.deadline, SystemClock.elapsedRealtime());
        if (remaining == 0L) request.timeout.run();
        else main.postDelayed(request.timeout, remaining);
    }

    private void inspectPage(InteractiveRequest request, int attempt, int navigation) {
        if (!isActiveAttempt(request, attempt) || request.navigation != navigation
                || request.probeRunning || request.inspecting || request.stopped) return;
        cancelInspection(request);
        request.inspecting = true;
        String script = "(function(){return JSON.stringify({url:location.href||'',"
                + "title:document.title||'',html:document.documentElement.outerHTML||''});})()";
        request.webView.evaluateJavascript(script, encoded -> {
            request.inspecting = false;
            if (!isActiveAttempt(request, attempt) || request.navigation != navigation
                    || request.probeRunning || request.stopped) return;
            try {
                JSONObject page = new JSONObject(decodeJavascriptString(encoded));
                String actualUrl = page.optString("url");
                String html = page.optString("html");
                boolean challenge = isChallenge(actualUrl, page.optString("title"), html,
                        request.statusCode, request.mitigated);
                boolean expectedPage = isExpectedPage(request.url, actualUrl);
                boolean browserCatalog = Mh18ComicSource.hasCatalogMarker(html);
                PageAction action = pageAction(challenge, expectedPage, browserCatalog);
                if (action == PageAction.WAIT) {
                    setStatus(request, "请完成安全验证");
                    scheduleInspection(request, attempt, navigation);
                    return;
                }
                if (action == PageAction.FAIL) {
                    stopAttempt(request, "页面不正确，请重新加载");
                    return;
                }
                beginProbe(request, attempt, navigation, browserCatalog);
            } catch (Exception error) {
                stopAttempt(request, "页面读取失败，请重试");
            }
        });
    }

    private void scheduleInspection(InteractiveRequest request, int attempt, int navigation) {
        if (!isActiveAttempt(request, attempt) || request.navigation != navigation
                || request.probeRunning || request.stopped) return;
        cancelInspection(request);
        request.inspection = () -> {
            request.inspection = null;
            inspectPage(request, attempt, navigation);
        };
        main.postDelayed(request.inspection, INSPECTION_DELAY_MS);
    }

    private void cancelInspection(InteractiveRequest request) {
        if (request.inspection == null) return;
        main.removeCallbacks(request.inspection);
        request.inspection = null;
    }

    private void beginProbe(InteractiveRequest request, int attempt, int navigation,
                            boolean browserCatalog) {
        request.probeRunning = true;
        cancelInspection(request);
        setStatus(request, "正在确认验证结果");
        CookieManager.getInstance().flush();
        HTTP_EXECUTOR.execute(() -> {
            try {
                HttpFetch response = fetchHttp(request.url);
                main.post(() -> finishProbe(
                        request, attempt, navigation, browserCatalog, response, null));
            } catch (IOException error) {
                main.post(() -> finishProbe(
                        request, attempt, navigation, browserCatalog, null, error));
            }
        });
    }

    private void finishProbe(InteractiveRequest request, int attempt, int navigation,
                             boolean browserCatalog, HttpFetch response,
                             IOException failure) {
        if (!probeCanComplete(isActiveAttempt(request, attempt), request.probeRunning,
                request.stopped, navigation, request.navigation)) return;
        request.probeRunning = false;
        if (failure != null) {
            stopAttempt(request, "网络确认失败，请重试");
            return;
        }
        HttpAction action = httpAction(
                response.statusCode, response.mitigated, response.body);
        if (action == HttpAction.VERIFICATION_REQUIRED) {
            stopAttempt(request, "验证尚未生效，请重试");
            return;
        }
        if (action == HttpAction.FAIL) {
            stopAttempt(request, "确认请求失败，请重试");
            return;
        }
        boolean probeCatalog = Mh18ComicSource.hasCatalogMarker(response.body);
        if (!verificationComplete(browserCatalog, probeCatalog)) {
            stopAttempt(request, "页面确认失败，请重试");
            return;
        }

        completeVerification(request, response.body);
    }

    private void completeVerification(InteractiveRequest request, String result) {
        activity.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .edit().putLong(VERIFIED_AT_KEY, System.currentTimeMillis()).apply();
        request.succeeded = true;
        request.reload.setEnabled(false);
        request.close.setEnabled(false);
        setStatus(request, "验证完成");
        notifyVerification("验证完成");
        main.postDelayed(() -> {
            if (isActive(request) && request.succeeded) {
                finishRequest(request, result, null);
            }
        }, SUCCESS_DELAY_MS);
    }

    private void stopAttempt(InteractiveRequest request, String message) {
        if (!isActive(request) || request.succeeded) return;
        request.preflightRunning = false;
        request.probeRunning = false;
        request.inspecting = false;
        request.stopped = true;
        cancelInspection(request);
        if (request.timeout != null) main.removeCallbacks(request.timeout);
        setStatus(request, message);
    }

    private void cancelInteractive(InteractiveRequest request) {
        if (!isActive(request) || request.succeeded) return;
        finishRequest(request, null,
                new VerificationCancelledException(sourceName + "验证已取消"));
    }

    void shutdown() {
        shutdown = true;
        Runnable close = () -> {
            InteractiveRequest request = activeRequest;
            if (request != null) {
                finishRequest(request, null,
                        new IOException(sourceName + "浏览器会话已停止"));
            }
        };
        if (Looper.myLooper() == Looper.getMainLooper()) close.run();
        else main.post(close);
    }

    void clearCache() {
        activity.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .edit().remove(VERIFIED_AT_KEY).apply();
        Runnable clear = () -> {
            InteractiveRequest request = activeRequest;
            if (request != null) {
                finishRequest(request, null,
                        new IOException(sourceName + "验证状态已清除"));
            }
        };
        if (Looper.myLooper() == Looper.getMainLooper()) clear.run();
        else main.post(clear);
    }

    private void finishRequest(InteractiveRequest request, String result,
                               IOException failure) {
        if (request.completed) return;
        request.completed = true;
        request.result = result;
        request.failure = failure;
        cancelInspection(request);
        if (request.timeout != null) main.removeCallbacks(request.timeout);
        if (activeRequest == request) activeRequest = null;

        WebView browser = request.webView;
        Dialog dialog = request.dialog;
        request.webView = null;
        request.dialog = null;
        if (dialog != null && dialog.isShowing()) dialog.dismiss();
        if (browser != null) {
            browser.stopLoading();
            browser.removeAllViews();
            browser.destroy();
        }
        request.latch.countDown();
    }

    private boolean isActive(InteractiveRequest request) {
        return request != null && !request.completed
                && activeRequest == request && !shutdown;
    }

    private boolean isActiveAttempt(InteractiveRequest request, int attempt) {
        return isActive(request) && request.attempt == attempt;
    }

    private void setStatus(InteractiveRequest request, String message) {
        if (request.status != null) request.status.setText(message);
    }

    private void notifyVerification(String message) {
        if (verificationStatus != null) {
            verificationStatus.onStatus(sourceName + " " + message);
        }
    }

    private int dp(int value) {
        return UIHelpers.dp(activity, value);
    }

    private String decodeJavascriptString(String encoded) {
        if (TextUtils.isEmpty(encoded) || "null".equals(encoded)) return "";
        try {
            return new JSONArray("[" + encoded + "]").optString(0, "");
        } catch (Exception ignored) {
            return "";
        }
    }

    static boolean verificationComplete(boolean browserCatalog, boolean probeCatalog) {
        return browserCatalog && probeCatalog;
    }

    static boolean probeCanComplete(boolean activeAttempt, boolean probeRunning,
                                    boolean stopped, int capturedNavigation,
                                    int currentNavigation) {
        return activeAttempt && probeRunning && !stopped
                && capturedNavigation == currentNavigation;
    }

    enum HttpAction {
        RETURN_BODY,
        VERIFICATION_REQUIRED,
        FAIL
    }

    enum InteractiveAction {
        COMPLETE,
        OPEN_BROWSER,
        FAIL
    }

    enum PageAction {
        WAIT,
        PROBE,
        FAIL
    }

    static InteractiveAction interactiveAction(int statusCode, String mitigated, String body) {
        HttpAction action = httpAction(statusCode, mitigated, body);
        if (action == HttpAction.VERIFICATION_REQUIRED) return InteractiveAction.OPEN_BROWSER;
        if (action == HttpAction.FAIL || !Mh18ComicSource.hasCatalogMarker(body)) {
            return InteractiveAction.FAIL;
        }
        return InteractiveAction.COMPLETE;
    }

    static PageAction pageAction(boolean challenge, boolean expectedPage,
                                 boolean browserCatalog) {
        if (expectedPage && browserCatalog) return PageAction.PROBE;
        if (challenge) return PageAction.WAIT;
        if (!expectedPage) return PageAction.FAIL;
        return PageAction.WAIT;
    }

    static boolean shouldStopForTimeout(boolean active, boolean succeeded) {
        return active && !succeeded;
    }

    static HttpAction httpAction(int statusCode, String mitigated, String body) {
        if (isChallenge("", "", body, statusCode, mitigated)) {
            return HttpAction.VERIFICATION_REQUIRED;
        }
        return statusCode >= 200 && statusCode < 400
                ? HttpAction.RETURN_BODY : HttpAction.FAIL;
    }

    static boolean isChallenge(String url, String title, String body, int statusCode,
                               String mitigated) {
        String content = ((url == null ? "" : url) + " "
                + (title == null ? "" : title) + " "
                + (body == null ? "" : body)).toLowerCase(Locale.US);
        return statusCode == 403 && "challenge".equalsIgnoreCase(mitigated)
                || content.contains("/orchestrate/chl_page/")
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
    }

    static boolean isExpectedPage(String requested, String actual) {
        try {
            URL expected = new URL(requested);
            URL received = new URL(actual);
            return sameSite(expected, received)
                    && "/manga".equals(normalizedPath(received.getPath()))
                    && "/manga".equals(normalizedPath(expected.getPath()));
        } catch (Exception ignored) {
            return false;
        }
    }

    static boolean shouldBlockNavigation(String requested, String actual) {
        return !sameSite(requested, actual);
    }

    private static boolean sameSite(String requested, String actual) {
        try {
            return sameSite(new URL(requested), new URL(actual));
        } catch (Exception ignored) {
            return false;
        }
    }

    private static boolean sameSite(URL expected, URL received) {
        String expectedHost = expected.getHost().toLowerCase(Locale.US);
        String receivedHost = received.getHost().toLowerCase(Locale.US);
        boolean sameHost = expectedHost.equals(receivedHost)
                || expectedHost.endsWith("." + receivedHost)
                || receivedHost.endsWith("." + expectedHost);
        return sameHost && expected.getProtocol().equalsIgnoreCase(received.getProtocol());
    }

    private static String normalizedPath(String value) {
        String path = value == null || value.isEmpty() ? "/" : value;
        while (path.length() > 1 && path.endsWith("/")) {
            path = path.substring(0, path.length() - 1);
        }
        return path;
    }

    private static final class InteractiveRequest {
        final String url;
        final CountDownLatch latch = new CountDownLatch(1);
        final long deadline = requestDeadlineMs(SystemClock.elapsedRealtime());
        volatile String result;
        volatile IOException failure;
        volatile boolean completed;
        Dialog dialog;
        WebView webView;
        TextView status;
        TextView reload;
        ImageView close;
        Runnable timeout;
        Runnable inspection;
        int attempt;
        int navigation;
        int statusCode;
        String mitigated = "";
        boolean probeRunning;
        boolean preflightRunning;
        boolean inspecting;
        boolean stopped;
        boolean succeeded;

        InteractiveRequest(String url) {
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
