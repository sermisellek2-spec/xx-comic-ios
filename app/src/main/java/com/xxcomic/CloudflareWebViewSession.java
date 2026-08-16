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

import java.io.IOException;
import java.util.Locale;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;

final class CloudflareWebViewSession implements BrowserSession {
    private static final String BRIDGE_NAME = "XXComicBridge";
    private static final long TIMEOUT_MS = 180000L;
    private static final long POLL_DELAY_MS = 800L;

    private final Activity activity;
    private final Handler main;
    private final String sourceName;
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

    CloudflareWebViewSession(Activity activity, Handler main, String sourceName) {
        this.activity = activity;
        this.main = main;
        this.sourceName = sourceName;
    }

    @Override
    public String fetch(String url) throws IOException {
        if (Looper.myLooper() == Looper.getMainLooper()) {
            throw new IOException(sourceName + "请求不能阻塞主线程");
        }
        synchronized (requestLock) {
            if (shutdown) throw new IOException(sourceName + "浏览器会话已停止");
            FetchRequest request = new FetchRequest(
                    Integer.toString(requestSequence.incrementAndGet()), url);
            main.post(() -> startRequest(request));
            try {
                if (!request.latch.await(TIMEOUT_MS, TimeUnit.MILLISECONDS)) {
                    request.cancelled = true;
                    main.post(() -> complete(request, null, sourceName + "请求超时"));
                    throw new IOException(sourceName + "请求超时");
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
        page.addView(card, new FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT, Gravity.CENTER));

        WebSettings settings = browser.getSettings();
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
                if (request != null && request.verifying) showVerifyingState();
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
            complete(request, null, sourceName + "请求超时");
            return;
        }
        String script = "(function(){return JSON.stringify({"
                + "title:document.title||'',text:(document.body&&document.body.innerText||'').slice(0,2400),"
                + "ready:document.readyState||'',url:location.href||''});})()";
        browser.evaluateJavascript(script, encoded -> {
            if (!isActive(request) || expectedNavigation != navigation) return;
            try {
                JSONObject page = new JSONObject(decodeJavascriptString(encoded));
                boolean challenge = isChallenge(page.optString("url"), page.optString("title"),
                        page.optString("text"), 0, "");
                boolean ready = "complete".equalsIgnoreCase(page.optString("ready"));
                PageAction action = pageAction(request.verifying, challenge, ready);
                if (action == PageAction.SHOW_VERIFICATION) {
                    request.verifying = true;
                    showVerificationView();
                } else if (action == PageAction.KEEP_VERIFYING) {
                    showVerifyingState();
                } else if (action == PageAction.CAPTURE) {
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
            if (TextUtils.isEmpty(body)) {
                complete(request, null, sourceName + "页面内容为空");
                return;
            }
            complete(request, body, "");
        } catch (Exception error) {
            complete(request, null, sourceName + "浏览器响应解析失败");
        }
    }

    static boolean isChallenge(String url, String title, String body, int statusCode, String mitigated) {
        String content = ((url == null ? "" : url) + " " + (title == null ? "" : title)
                + " " + (body == null ? "" : body)).toLowerCase(Locale.US);
        return (statusCode == 403 && "challenge".equalsIgnoreCase(mitigated))
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

    enum PageAction {
        WAIT,
        SHOW_VERIFICATION,
        KEEP_VERIFYING,
        CAPTURE
    }

    static PageAction pageAction(boolean verifying, boolean challenge, boolean ready) {
        if (challenge) {
            return verifying ? PageAction.KEEP_VERIFYING : PageAction.SHOW_VERIFICATION;
        }
        return ready ? PageAction.CAPTURE : PageAction.WAIT;
    }

    private boolean isActive(FetchRequest request) {
        return request != null && !request.cancelled && !request.completed
                && activeRequest == request && !shutdown;
    }

    private void showVerificationView() {
        if (host == null) return;
        host.setLayoutParams(verificationLayoutParams());
        host.setBackgroundColor(Color.argb(42, 18, 39, 56));
        host.setClickable(true);
        host.setFocusable(true);
        if (webView != null) webView.setClickable(true);
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
        if (webView != null) webView.setClickable(false);
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
        boolean verifying;

        FetchRequest(String id, String url) {
            this.id = id;
            this.url = url;
        }
    }
}
