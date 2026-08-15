package com.xxcomic;

import android.app.Activity;
import android.app.Dialog;
import android.content.res.ColorStateList;
import android.graphics.Color;
import android.graphics.Typeface;
import android.os.Handler;
import android.os.Looper;
import android.text.TextUtils;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.view.Window;
import android.view.WindowManager;
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

import com.xxcomic.source.Mh18ComicSource;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.IOException;
import java.util.Locale;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;

final class Mh18WebViewSession implements Mh18ComicSource.BrowserSession {
    private static final String VERIFY_URL = "https://18mh.org/manga";
    private static final String BRIDGE_NAME = "XXComicBridge";
    private static final long TIMEOUT_MS = 180000L;
    private static final long POLL_DELAY_MS = 800L;

    private final Activity activity;
    private final Handler main;
    private final Object requestLock = new Object();
    private final AtomicInteger requestSequence = new AtomicInteger();
    private volatile boolean shutdown;
    private Dialog dialog;
    private WebView webView;
    private View statusCard;
    private ProgressBar progress;
    private TextView status;
    private FetchRequest activeRequest;
    private int navigation;
    private boolean browserReady;
    private boolean closingViews;

    Mh18WebViewSession(Activity activity, Handler main) {
        this.activity = activity;
        this.main = main;
    }

    @Override
    public String fetch(String url) throws IOException {
        if (Looper.myLooper() == Looper.getMainLooper()) {
            throw new IOException("18漫画请求不能阻塞主线程");
        }
        synchronized (requestLock) {
            if (shutdown) throw new IOException("18漫画浏览器会话已停止");
            FetchRequest request = new FetchRequest(
                    Integer.toString(requestSequence.incrementAndGet()), url);
            main.post(() -> startRequest(request));
            try {
                if (!request.latch.await(TIMEOUT_MS, TimeUnit.MILLISECONDS)) {
                    request.cancelled = true;
                    main.post(() -> complete(request, null, "18漫画请求超时"));
                    throw new IOException("18漫画请求超时");
                }
            } catch (InterruptedException interrupted) {
                request.cancelled = true;
                main.post(() -> complete(request, null, "18漫画请求已取消"));
                Thread.currentThread().interrupt();
                throw new IOException("18漫画请求已取消", interrupted);
            }
            if (!TextUtils.isEmpty(request.error)) throw new IOException(request.error);
            if (request.result == null) throw new IOException("18漫画请求未完成");
            return request.result;
        }
    }

    void shutdown() {
        shutdown = true;
        Runnable close = () -> {
            if (activeRequest != null) complete(activeRequest, null, "18漫画浏览器会话已停止");
            closeViews();
        };
        if (Looper.myLooper() == Looper.getMainLooper()) close.run();
        else main.post(close);
    }

    private void startRequest(FetchRequest request) {
        if (request.cancelled) return;
        if (shutdown || activity.isFinishing()) {
            complete(request, null, "18漫画浏览器会话无法打开");
            return;
        }
        if (activeRequest != null && !activeRequest.completed) {
            complete(request, null, "18漫画浏览器会话正忙");
            return;
        }
        activeRequest = request;
        try {
            ensureViews();
            if (browserReady) executeFetch(request);
            else beginVerification(request);
        } catch (Exception error) {
            complete(request, null, "18漫画浏览器会话启动失败");
        }
    }

    private void ensureViews() {
        if (webView != null && dialog != null && dialog.isShowing()) return;

        FrameLayout page = new FrameLayout(activity);
        page.setBackgroundColor(Color.TRANSPARENT);

        WebView browser = new WebView(activity);
        browser.setAlpha(0.01f);
        browser.setBackgroundColor(Color.TRANSPARENT);
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
                browserReady = false;
                FetchRequest request = activeRequest;
                if (request != null && request.verifying) showVerifyingState();
            }

            @Override
            public void onPageFinished(WebView view, String url) {
                FetchRequest request = activeRequest;
                if (request != null && request.verifying) {
                    inspectVerification(request, view, navigation);
                }
            }

            @Override
            public void onReceivedError(WebView view, WebResourceRequest request, WebResourceError error) {
                FetchRequest active = activeRequest;
                if (active != null && active.verifying && request != null && request.isForMainFrame()) {
                    complete(active, null, "18漫画验证页面加载失败");
                }
            }
        });

        Dialog sessionDialog = new Dialog(activity);
        sessionDialog.requestWindowFeature(Window.FEATURE_NO_TITLE);
        sessionDialog.setContentView(page);
        sessionDialog.setCancelable(true);
        sessionDialog.setCanceledOnTouchOutside(false);
        sessionDialog.setOnCancelListener(ignored -> {
            if (activeRequest != null) complete(activeRequest, null, "18漫画验证已取消");
        });
        sessionDialog.setOnDismissListener(ignored -> {
            if (!closingViews && !shutdown) releaseDismissedViews();
        });
        sessionDialog.show();
        Window window = sessionDialog.getWindow();
        if (window != null) window.setBackgroundDrawableResource(android.R.color.transparent);

        dialog = sessionDialog;
        webView = browser;
        statusCard = card;
        progress = spinner;
        status = label;
    }

    private void beginVerification(FetchRequest request) {
        if (request.cancelled || request.completed || activeRequest != request) return;
        if (request.verificationAttempts >= 1) {
            browserReady = false;
            complete(request, null, "18漫画验证后仍被拦截");
            return;
        }
        request.verificationAttempts++;
        request.verifying = true;
        browserReady = false;
        showVerificationWindow();
        webView.loadUrl(VERIFY_URL);
    }

    private void inspectVerification(FetchRequest request, WebView browser, int expectedNavigation) {
        if (!isActive(request) || !request.verifying || expectedNavigation != navigation) return;
        if (System.currentTimeMillis() - request.startedAt >= TIMEOUT_MS) {
            complete(request, null, "18漫画验证超时");
            return;
        }
        String script = "(function(){return JSON.stringify({"
                + "title:document.title||'',"
                + "text:(document.body&&document.body.innerText||'').slice(0,2400),"
                + "ready:document.readyState||'',url:location.href||''});})()";
        browser.evaluateJavascript(script, encoded -> {
            if (!isActive(request) || !request.verifying || expectedNavigation != navigation) return;
            try {
                JSONObject page = new JSONObject(decodeJavascriptString(encoded));
                if (isChallenge(page.optString("url"), page.optString("title"),
                        page.optString("text"), 0, "")) {
                    showVerifyingState();
                    browser.postDelayed(() -> inspectVerification(
                            request, browser, expectedNavigation), POLL_DELAY_MS);
                    return;
                }
                if (!"complete".equalsIgnoreCase(page.optString("ready"))) {
                    browser.postDelayed(() -> inspectVerification(
                            request, browser, expectedNavigation), POLL_DELAY_MS);
                    return;
                }
                android.webkit.CookieManager.getInstance().flush();
                request.verifying = false;
                browserReady = true;
                showVerifiedState();
                browser.postDelayed(() -> {
                    if (!isActive(request)) return;
                    showBackgroundWindow();
                    executeFetch(request);
                }, 550L);
            } catch (Exception error) {
                complete(request, null, "18漫画验证结果解析失败");
            }
        });
    }

    private void executeFetch(FetchRequest request) {
        if (!isActive(request)) return;
        showBackgroundWindow();
        String script = "(function(){var id=" + JSONObject.quote(request.id)
                + ",url=" + JSONObject.quote(request.url) + ";"
                + "fetch(url,{credentials:'include',redirect:'follow',headers:{Accept:'text/html,application/json;q=0.9,*/*;q=0.8'}})"
                + ".then(function(r){return r.text().then(function(body){"
                + "window." + BRIDGE_NAME + ".onFetchResult(id,JSON.stringify({status:r.status,url:r.url||url,"
                + "mitigated:r.headers.get('cf-mitigated')||'',body:body}));});})"
                + ".catch(function(e){window." + BRIDGE_NAME
                + ".onFetchResult(id,JSON.stringify({error:String(e)}));});})();";
        webView.evaluateJavascript(script, null);
    }

    private void handleFetchResult(String id, String payload) {
        FetchRequest request = activeRequest;
        if (request == null || !request.id.equals(id) || !isActive(request)) return;
        try {
            JSONObject response = new JSONObject(payload == null ? "" : payload);
            String error = response.optString("error");
            if (!TextUtils.isEmpty(error)) {
                complete(request, null, "18漫画浏览器请求失败");
                return;
            }
            int statusCode = response.optInt("status", 0);
            String body = response.optString("body", "");
            if (isChallenge(response.optString("url"), "", body, statusCode,
                    response.optString("mitigated"))) {
                beginVerification(request);
                return;
            }
            if (statusCode < 200 || statusCode >= 400) {
                complete(request, null, "18漫画请求失败：HTTP " + statusCode);
                return;
            }
            complete(request, body, "");
        } catch (Exception error) {
            complete(request, null, "18漫画浏览器响应解析失败");
        }
    }

    private boolean isChallenge(String url, String title, String body, int statusCode, String mitigated) {
        String content = ((url == null ? "" : url) + " "
                + (title == null ? "" : title) + " "
                + (body == null ? "" : body)).toLowerCase(Locale.US);
        return (statusCode == 403 && "challenge".equalsIgnoreCase(mitigated))
                || content.contains("/cdn-cgi/challenge-platform")
                || content.contains("cf-chl-")
                || content.contains("just a moment")
                || content.contains("attention required")
                || content.contains("checking your browser")
                || content.contains("performing security verification")
                || content.contains("verify you are human")
                || content.contains("请稍候")
                || content.contains("正在验证")
                || content.contains("安全验证");
    }

    private boolean isActive(FetchRequest request) {
        return request != null && !request.cancelled && !request.completed
                && activeRequest == request && !shutdown;
    }

    private void showVerificationWindow() {
        if (dialog == null) return;
        dialog.setCancelable(true);
        if (statusCard != null) statusCard.setVisibility(View.VISIBLE);
        showVerifyingState();
        Window window = dialog.getWindow();
        if (window == null) return;
        window.clearFlags(WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE
                | WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE);
        window.addFlags(WindowManager.LayoutParams.FLAG_DIM_BEHIND);
        WindowManager.LayoutParams params = window.getAttributes();
        params.width = ViewGroup.LayoutParams.MATCH_PARENT;
        params.height = ViewGroup.LayoutParams.MATCH_PARENT;
        params.gravity = Gravity.CENTER;
        params.dimAmount = 0.16f;
        window.setAttributes(params);
    }

    private void showBackgroundWindow() {
        if (dialog == null) return;
        dialog.setCancelable(false);
        if (statusCard != null) statusCard.setVisibility(View.GONE);
        Window window = dialog.getWindow();
        if (window == null) return;
        window.clearFlags(WindowManager.LayoutParams.FLAG_DIM_BEHIND);
        window.addFlags(WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE
                | WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE);
        WindowManager.LayoutParams params = window.getAttributes();
        params.width = 1;
        params.height = 1;
        params.gravity = Gravity.TOP | Gravity.START;
        params.dimAmount = 0f;
        window.setAttributes(params);
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
        if (!shutdown && webView != null) showBackgroundWindow();
        request.latch.countDown();
    }

    private void releaseDismissedViews() {
        WebView browser = webView;
        webView = null;
        dialog = null;
        statusCard = null;
        progress = null;
        status = null;
        browserReady = false;
        if (browser != null) {
            browser.stopLoading();
            browser.removeJavascriptInterface(BRIDGE_NAME);
            browser.removeAllViews();
            browser.destroy();
        }
    }

    private void closeViews() {
        WebView browser = webView;
        Dialog sessionDialog = dialog;
        webView = null;
        dialog = null;
        statusCard = null;
        progress = null;
        status = null;
        browserReady = false;
        closingViews = true;
        if (browser != null) {
            browser.stopLoading();
            browser.removeJavascriptInterface(BRIDGE_NAME);
            browser.removeAllViews();
            browser.destroy();
        }
        if (sessionDialog != null && sessionDialog.isShowing()) sessionDialog.dismiss();
        closingViews = false;
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
        int verificationAttempts;

        FetchRequest(String id, String url) {
            this.id = id;
            this.url = url;
        }
    }
}
