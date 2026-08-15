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

        LinearLayout page = new LinearLayout(activity);
        page.setOrientation(LinearLayout.VERTICAL);
        page.setBackgroundColor(UIHelpers.CARD);

        LinearLayout header = new LinearLayout(activity);
        header.setGravity(Gravity.CENTER_VERTICAL);
        header.setPadding(UIHelpers.dp(activity, 16), 0, UIHelpers.dp(activity, 14), 0);
        header.setBackgroundColor(UIHelpers.CARD);
        TextView title = UIHelpers.text(activity, "18漫画 · 安全验证", 16, UIHelpers.TEXT, Typeface.BOLD);
        header.addView(title, new LinearLayout.LayoutParams(0, UIHelpers.dp(activity, 54), 1));
        ProgressBar progress = new ProgressBar(activity, null, android.R.attr.progressBarStyleSmall);
        progress.setIndeterminateTintList(ColorStateList.valueOf(UIHelpers.ACCENT));
        header.addView(progress, new LinearLayout.LayoutParams(UIHelpers.dp(activity, 22), UIHelpers.dp(activity, 22)));
        TextView status = UIHelpers.text(activity, "正在连接", 12, UIHelpers.TEXT3, Typeface.NORMAL);
        status.setGravity(Gravity.CENTER_VERTICAL);
        status.setPadding(UIHelpers.dp(activity, 8), 0, 0, 0);
        header.addView(status, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, UIHelpers.dp(activity, 54)));
        page.addView(header, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, UIHelpers.dp(activity, 54)));

        WebView browser = new WebView(activity);
        browser.setBackgroundColor(Color.WHITE);
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
            }

            @Override
            public void onPageFinished(WebView view, String pageUrl) {
                int navigation = attempt.navigation;
                status.setText("正在确认");
                inspectClearance(attempt, view, status, navigation);
            }

            @Override
            public void onReceivedError(WebView view, WebResourceRequest request, WebResourceError error) {
                if (request != null && request.isForMainFrame()) {
                    complete(attempt, null, "18漫画验证页面加载失败");
                }
            }
        });
        page.addView(browser, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1));

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
            window.addFlags(WindowManager.LayoutParams.FLAG_DRAWS_SYSTEM_BAR_BACKGROUNDS);
            window.setStatusBarColor(UIHelpers.CARD);
            window.setNavigationBarColor(UIHelpers.CARD);
        }
        browser.loadUrl(url);
    }

    private void inspectClearance(Attempt attempt, WebView browser, TextView status, int navigation) {
        if (attempt.completed || navigation != attempt.navigation) return;
        if (System.currentTimeMillis() - attempt.startedAt >= TIMEOUT_MS) {
            complete(attempt, null, "18漫画验证超时");
            return;
        }
        browser.evaluateJavascript("document.title", encodedTitle -> {
            if (attempt.completed || navigation != attempt.navigation) return;
            String title = decodeJavascriptString(encodedTitle).toLowerCase(Locale.US);
            String cookie = CookieManager.getInstance().getCookie(VERIFY_URL);
            boolean challenge = title.contains("just a moment")
                    || title.contains("attention required")
                    || title.contains("checking your browser")
                    || title.contains("请稍候");
            if (!TextUtils.isEmpty(cookie) && cookie.contains("cf_clearance=") && !challenge) {
                CookieManager.getInstance().flush();
                complete(attempt, new Mh18ComicSource.Clearance(cookie, browser.getSettings().getUserAgentString()), "");
                return;
            }
            status.setText(challenge ? "请完成验证" : "等待验证结果");
            browser.postDelayed(() -> inspectClearance(attempt, browser, status, navigation), POLL_DELAY_MS);
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
        volatile Mh18ComicSource.Clearance result;
        volatile String error = "";
        int navigation;
    }
}
