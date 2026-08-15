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
import android.view.ViewGroup;
import android.view.Window;
import android.view.WindowManager;
import android.webkit.CookieManager;
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

import java.io.IOException;
import java.util.Locale;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;

final class Mh18WebViewSession implements Mh18ComicSource.BrowserSession {
    private static final String VERIFY_URL = "https://18mh.org/manga";
    private static final long TIMEOUT_MS = 180000L;
    private static final long POLL_DELAY_MS = 800L;

    private final Activity activity;
    private final Handler main;
    private final Object lock = new Object();
    private volatile Mh18ComicSource.Clearance clearance = new Mh18ComicSource.Clearance("", "");
    private Attempt activeAttempt;
    private boolean shutdown;
    private Dialog dialog;
    private WebView webView;

    Mh18WebViewSession(Activity activity, Handler main) {
        this.activity = activity;
        this.main = main;
        CookieManager cookies = CookieManager.getInstance();
        cookies.setAcceptCookie(true);
        clearance = new Mh18ComicSource.Clearance(
                cookies.getCookie(VERIFY_URL), WebSettings.getDefaultUserAgent(activity));
    }

    @Override
    public Mh18ComicSource.Clearance current() {
        return clearance;
    }

    @Override
    public Mh18ComicSource.Clearance resolve(String url, Mh18ComicSource.Clearance rejected) throws IOException {
        if (Looper.myLooper() == Looper.getMainLooper()) {
            throw new IOException("18漫画验证不能阻塞主线程");
        }
        Attempt attempt;
        boolean shouldStart = false;
        synchronized (lock) {
            if (shutdown) throw new IOException("18漫画验证已停止");
            if (!TextUtils.isEmpty(clearance.cookie) && !sameClearance(clearance, rejected)) {
                return clearance;
            }
            if (activeAttempt == null) {
                activeAttempt = new Attempt();
                shouldStart = true;
            }
            attempt = activeAttempt;
        }
        if (shouldStart) main.post(() -> showVerification(attempt, TextUtils.isEmpty(url) ? VERIFY_URL : url));
        try {
            if (!attempt.latch.await(TIMEOUT_MS, TimeUnit.MILLISECONDS)) {
                main.post(() -> complete(attempt, null, "18漫画验证超时"));
                throw new IOException("18漫画验证超时");
            }
        } catch (InterruptedException interrupted) {
            Thread.currentThread().interrupt();
            throw new IOException("18漫画验证已取消", interrupted);
        }
        if (!TextUtils.isEmpty(attempt.error)) throw new IOException(attempt.error);
        if (attempt.result == null) throw new IOException("18漫画验证未完成");
        return attempt.result;
    }

    void shutdown() {
        Attempt attempt;
        synchronized (lock) {
            shutdown = true;
            attempt = activeAttempt;
        }
        if (attempt != null) {
            if (Looper.myLooper() == Looper.getMainLooper()) complete(attempt, null, "18漫画验证已停止");
            else main.post(() -> complete(attempt, null, "18漫画验证已停止"));
        } else if (Looper.myLooper() == Looper.getMainLooper()) {
            closeViews();
        } else {
            main.post(this::closeViews);
        }
    }

    private void showVerification(Attempt attempt, String url) {
        if (activity.isFinishing() || shutdown || attempt.completed) {
            complete(attempt, null, "18漫画验证无法打开");
            return;
        }
        CookieManager cookies = CookieManager.getInstance();
        cookies.setAcceptCookie(true);

        FrameLayout page = new FrameLayout(activity);
        page.setBackgroundColor(Color.TRANSPARENT);

        WebView browser = new WebView(activity);
        browser.setAlpha(0.01f);
        browser.setBackgroundColor(Color.TRANSPARENT);
        page.addView(browser, new FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT));

        LinearLayout statusCard = new LinearLayout(activity);
        statusCard.setGravity(Gravity.CENTER_VERTICAL);
        statusCard.setPadding(UIHelpers.dp(activity, 18), UIHelpers.dp(activity, 14),
                UIHelpers.dp(activity, 18), UIHelpers.dp(activity, 14));
        statusCard.setBackground(UIHelpers.round(UIHelpers.CARD, UIHelpers.dp(activity, 10), UIHelpers.BORDER_SOFT));
        ProgressBar progress = new ProgressBar(activity, null, android.R.attr.progressBarStyleSmall);
        progress.setIndeterminateTintList(ColorStateList.valueOf(UIHelpers.ACCENT));
        LinearLayout.LayoutParams progressParams = new LinearLayout.LayoutParams(
                UIHelpers.dp(activity, 22), UIHelpers.dp(activity, 22));
        progressParams.rightMargin = UIHelpers.dp(activity, 12);
        statusCard.addView(progress, progressParams);
        TextView status = UIHelpers.text(activity, "正在验证", 14, UIHelpers.TEXT, Typeface.BOLD);
        status.setGravity(Gravity.CENTER_VERTICAL);
        statusCard.addView(status, new LinearLayout.LayoutParams(
                UIHelpers.dp(activity, 78), UIHelpers.dp(activity, 24)));
        FrameLayout.LayoutParams statusParams = new FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT, Gravity.CENTER);
        page.addView(statusCard, statusParams);

        WebSettings settings = browser.getSettings();
        settings.setJavaScriptEnabled(true);
        settings.setDomStorageEnabled(true);
        settings.setDatabaseEnabled(true);
        settings.setLoadsImagesAutomatically(true);
        settings.setJavaScriptCanOpenWindowsAutomatically(false);
        cookies.setAcceptThirdPartyCookies(browser, true);
        browser.setWebViewClient(new WebViewClient() {
            @Override
            public void onPageStarted(WebView view, String pageUrl, android.graphics.Bitmap favicon) {
                attempt.navigation++;
                status.setText("正在验证");
                progress.setVisibility(android.view.View.VISIBLE);
            }

            @Override
            public void onPageFinished(WebView view, String pageUrl) {
                int navigation = attempt.navigation;
                inspectClearance(attempt, view, status, progress, navigation);
            }

            @Override
            public void onReceivedError(WebView view, WebResourceRequest request, WebResourceError error) {
                if (request != null && request.isForMainFrame()) {
                    complete(attempt, null, "18漫画验证页面加载失败");
                }
            }
        });
        Dialog verificationDialog = new Dialog(activity);
        verificationDialog.requestWindowFeature(Window.FEATURE_NO_TITLE);
        verificationDialog.setContentView(page);
        verificationDialog.setCancelable(true);
        verificationDialog.setCanceledOnTouchOutside(false);
        verificationDialog.setOnCancelListener(ignored -> complete(attempt, null, "18漫画验证已取消"));
        verificationDialog.setOnDismissListener(ignored -> {
            if (!attempt.completed) complete(attempt, null, "18漫画验证已取消");
        });
        dialog = verificationDialog;
        webView = browser;
        verificationDialog.show();
        Window window = verificationDialog.getWindow();
        if (window != null) {
            window.setLayout(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT);
            window.setBackgroundDrawableResource(android.R.color.transparent);
            window.addFlags(WindowManager.LayoutParams.FLAG_DIM_BEHIND);
            WindowManager.LayoutParams params = window.getAttributes();
            params.dimAmount = 0.16f;
            window.setAttributes(params);
        }
        browser.loadUrl(url);
    }

    private void inspectClearance(Attempt attempt, WebView browser, TextView status,
                                  ProgressBar progress, int navigation) {
        if (attempt.completed || attempt.finishing || navigation != attempt.navigation) return;
        if (System.currentTimeMillis() - attempt.startedAt >= TIMEOUT_MS) {
            complete(attempt, null, "18漫画验证超时");
            return;
        }
        browser.evaluateJavascript("document.title", encodedTitle -> {
            if (attempt.completed || attempt.finishing || navigation != attempt.navigation) return;
            String title = decodeJavascriptString(encodedTitle).toLowerCase(Locale.US);
            String cookie = CookieManager.getInstance().getCookie(VERIFY_URL);
            boolean challenge = title.contains("just a moment")
                    || title.contains("attention required")
                    || title.contains("checking your browser")
                    || title.contains("请稍候");
            if (!TextUtils.isEmpty(cookie) && cookie.contains("cf_clearance=") && !challenge) {
                CookieManager.getInstance().flush();
                attempt.finishing = true;
                status.setText("验证完成");
                progress.setVisibility(android.view.View.INVISIBLE);
                browser.postDelayed(() -> complete(attempt, new Mh18ComicSource.Clearance(
                        cookie, browser.getSettings().getUserAgentString()), ""), 550L);
                return;
            }
            status.setText("正在验证");
            browser.postDelayed(() -> inspectClearance(attempt, browser, status, progress, navigation), POLL_DELAY_MS);
        });
    }

    private String decodeJavascriptString(String encoded) {
        if (TextUtils.isEmpty(encoded) || "null".equals(encoded)) return "";
        try {
            return new JSONArray("[" + encoded + "]").optString(0, "");
        } catch (Exception ignored) {
            return "";
        }
    }

    private void complete(Attempt attempt, Mh18ComicSource.Clearance result, String error) {
        synchronized (lock) {
            if (attempt.completed) return;
            attempt.completed = true;
            attempt.result = result;
            attempt.error = error == null ? "" : error;
            if (result != null) clearance = result;
            if (activeAttempt == attempt) activeAttempt = null;
        }
        closeViews();
        attempt.latch.countDown();
    }

    private void closeViews() {
        WebView browser = webView;
        Dialog verificationDialog = dialog;
        webView = null;
        dialog = null;
        if (browser != null) {
            browser.stopLoading();
            browser.loadUrl("about:blank");
            browser.clearHistory();
            browser.removeAllViews();
            browser.destroy();
        }
        if (verificationDialog != null && verificationDialog.isShowing()) verificationDialog.dismiss();
    }

    private boolean sameClearance(Mh18ComicSource.Clearance left, Mh18ComicSource.Clearance right) {
        if (left == right) return true;
        if (left == null || right == null) return false;
        return TextUtils.equals(left.cookie, right.cookie) && TextUtils.equals(left.userAgent, right.userAgent);
    }

    private static final class Attempt {
        final CountDownLatch latch = new CountDownLatch(1);
        final long startedAt = System.currentTimeMillis();
        volatile boolean completed;
        volatile boolean finishing;
        volatile Mh18ComicSource.Clearance result;
        volatile String error = "";
        int navigation;
    }
}
