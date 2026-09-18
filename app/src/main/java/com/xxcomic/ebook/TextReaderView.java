package com.xxcomic.ebook;

import android.annotation.SuppressLint;
import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.LinearGradient;
import android.graphics.Paint;
import android.graphics.RectF;
import android.graphics.Shader;
import android.graphics.Typeface;
import android.net.Uri;
import android.os.Handler;
import android.os.Looper;
import android.text.Layout;
import android.text.StaticLayout;
import android.text.TextPaint;
import android.text.TextUtils;
import android.view.Gravity;
import android.view.MotionEvent;
import android.view.View;
import android.webkit.JavascriptInterface;
import android.webkit.WebResourceRequest;
import android.webkit.WebResourceResponse;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.FrameLayout;

import com.xxcomic.UIHelpers;
import com.xxcomic.local.ArchiveIndex;

import java.io.ByteArrayInputStream;
import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.URI;
import java.nio.charset.StandardCharsets;
import java.util.Locale;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import java.util.zip.ZipEntry;
import java.util.zip.ZipFile;

@SuppressLint("SetJavaScriptEnabled")
public class TextReaderView extends FrameLayout {

    public static final int THEME_LIGHT = 0;
    public static final int THEME_SEPIA = 1;
    public static final int THEME_DARK = 2;

    public interface Listener {
        void onPositionChanged(TextLocator locator);
        void onToggleControls();
        void onNavigateChapter(int delta);
        void onExternalLinkClicked(String url);
    }

    private final WebView webView;
    private final Handler mainHandler = new Handler(Looper.getMainLooper());

    private File epubFile;
    private ZipFile zipFile;
    private String bookId;
    private int currentChapterIndex = 0;
    private int currentSpineIndex = 0;
    private String currentEntryPath = "";
    private Listener listener;

    private int fontSizeSp = 18;
    private float lineHeight = 1.75f;
    private int readerTheme = THEME_DARK;
    private boolean pagedMode = false;

    private float currentScrollPercent = 0.0f;
    private TextLocator pendingRestoreLocator = null;

    public TextReaderView(Context context) {
        super(context);
        webView = new WebView(context);
        setupWebView();
        addView(webView, new FrameLayout.LayoutParams(-1, -1));
    }

    private void setupWebView() {
        WebSettings settings = webView.getSettings();
        settings.setJavaScriptEnabled(true);
        settings.setAllowFileAccess(false);
        settings.setAllowContentAccess(false);
        settings.setAllowFileAccessFromFileURLs(false);
        settings.setAllowUniversalAccessFromFileURLs(false);
        settings.setBlockNetworkLoads(true);
        settings.setBlockNetworkImage(false);
        settings.setSupportZoom(false);
        settings.setBuiltInZoomControls(false);
        settings.setDisplayZoomControls(false);

        webView.setBackgroundColor(getThemeBackgroundColor(readerTheme));
        webView.setHorizontalScrollBarEnabled(false);
        webView.setVerticalScrollBarEnabled(false);
        webView.setOverScrollMode(View.OVER_SCROLL_NEVER);

        webView.addJavascriptInterface(new JsBridge(), "TextBridge");

        webView.setWebViewClient(new WebViewClient() {
            @Override
            public WebResourceResponse shouldInterceptRequest(WebView view, WebResourceRequest request) {
                Uri uri = request.getUrl();
                if (uri != null && "epub.local".equalsIgnoreCase(uri.getHost())) {
                    String path = uri.getPath();
                    if (path != null && path.startsWith("/")) path = path.substring(1);
                    return handleZipResource(path);
                }
                return new WebResourceResponse("text/plain", "UTF-8", new ByteArrayInputStream(new byte[0]));
            }

            @Override
            public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest request) {
                Uri uri = request.getUrl();
                if (uri != null) {
                    if ("epub.local".equalsIgnoreCase(uri.getHost())) {
                        String fragment = uri.getFragment();
                        if (!TextUtils.isEmpty(fragment)) {
                            scrollToAnchor(fragment);
                            return true;
                        }
                    } else if (listener != null) {
                        listener.onExternalLinkClicked(uri.toString());
                        return true;
                    }
                }
                return true;
            }

            @Override
            public void onPageFinished(WebView view, String url) {
                super.onPageFinished(view, url);
                if (pendingRestoreLocator != null) {
                    final TextLocator loc = pendingRestoreLocator;
                    pendingRestoreLocator = null;
                    mainHandler.postDelayed(() -> {
                        if (!TextUtils.isEmpty(loc.anchorId)) {
                            scrollToAnchor(loc.anchorId);
                        } else if (loc.scrollPercentage > 0.01f) {
                            scrollToPercent(loc.scrollPercentage);
                        }
                    }, 120);
                }
            }
        });
    }

    public void setListener(Listener listener) {
        this.listener = listener;
    }

    public void setEpubFile(File file, String bookId) throws IOException {
        this.epubFile = file;
        this.bookId = bookId;
        if (this.zipFile != null) {
            try { this.zipFile.close(); } catch (Exception ignored) {}
        }
        this.zipFile = ArchiveIndex.openZipWithFallbackCharset(file);
    }

    public void setSettings(int fontSizeSp, float lineHeight, int theme, boolean pagedMode) {
        this.fontSizeSp = Math.max(12, Math.min(32, fontSizeSp));
        this.lineHeight = Math.max(1.2f, Math.min(2.5f, lineHeight));
        this.readerTheme = theme;
        this.pagedMode = pagedMode;
        webView.setBackgroundColor(getThemeBackgroundColor(theme));
        setBackgroundColor(getThemeBackgroundColor(theme));
    }

    public void loadSpineEntry(int chapterIndex, int spineIndex, String entryPath, TextLocator locator) {
        this.currentChapterIndex = chapterIndex;
        this.currentSpineIndex = spineIndex;
        this.currentEntryPath = entryPath;
        this.pendingRestoreLocator = locator;

        if (zipFile == null || TextUtils.isEmpty(entryPath)) return;
        ZipEntry entry = zipFile.getEntry(entryPath);
        if (entry == null) return;

        try (InputStream in = zipFile.getInputStream(entry)) {
            byte[] bytes = readAllBytes(in);
            String rawHtml = new String(bytes, StandardCharsets.UTF_8);
            String preparedHtml = prepareHtmlContent(rawHtml, entryPath);
            String baseUrl = "https://epub.local/" + entryPath;
            webView.loadDataWithBaseURL(baseUrl, preparedHtml, "text/html", "UTF-8", null);
        } catch (Exception ignored) {}
    }

    private String prepareHtmlContent(String rawHtml, String entryPath) {
        String parentDir = getParentZipDir(entryPath);
        String cleaned = rawHtml.replaceAll("(?i)<script[\\s\\S]*?</script>", "");

        // Rewrite relative img src
        Pattern imgPattern = Pattern.compile("(?i)(<img[^>]+src=[\"'])([^\"']+)([\"'][^>]*>)");
        Matcher m = imgPattern.matcher(cleaned);
        StringBuffer sb = new StringBuffer();
        while (m.find()) {
            String prefix = m.group(1);
            String src = m.group(2);
            String suffix = m.group(3);
            if (!src.startsWith("http://") && !src.startsWith("https://") && !src.startsWith("data:")) {
                String resolved = resolveZipPath(parentDir, src);
                m.appendReplacement(sb, Matcher.quoteReplacement(prefix + "https://epub.local/" + resolved + suffix));
            } else {
                m.appendReplacement(sb, Matcher.quoteReplacement(m.group(0)));
            }
        }
        m.appendTail(sb);
        String withImages = sb.toString();

        String css = generateCss();
        String js = generateJs();

        int headEnd = withImages.indexOf("</head>");
        if (headEnd != -1) {
            return withImages.substring(0, headEnd) + css + js + withImages.substring(headEnd);
        } else {
            return "<html><head>" + css + js + "</head><body>" + withImages + "</body></html>";
        }
    }

    private String generateCss() {
        String bgColor;
        String textColor;
        String accentColor;

        if (readerTheme == THEME_LIGHT) {
            bgColor = "#FAFAFA";
            textColor = "#23272E";
            accentColor = "#4C78A8";
        } else if (readerTheme == THEME_SEPIA) {
            bgColor = "#F5EEDB";
            textColor = "#3F3222";
            accentColor = "#8C6239";
        } else {
            bgColor = "#12161F";
            textColor = "#C8D0E0";
            accentColor = "#5E81AC";
        }

        return "<style>\n" +
                "  * { -webkit-tap-highlight-color: transparent; box-sizing: border-box; }\n" +
                "  html, body {\n" +
                "    background-color: " + bgColor + " !important;\n" +
                "    color: " + textColor + " !important;\n" +
                "    font-size: " + fontSizeSp + "px !important;\n" +
                "    line-height: " + lineHeight + " !important;\n" +
                "    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'PingFang SC', 'Hiragino Sans GB', 'Microsoft YaHei', sans-serif !important;\n" +
                "    margin: 0;\n" +
                "    padding: 22px 18px 90px 18px;\n" +
                "    word-break: break-word;\n" +
                "    text-align: justify;\n" +
                "  }\n" +
                "  p {\n" +
                "    margin-top: 0 !important;\n" +
                "    margin-bottom: 0.9em !important;\n" +
                "    text-indent: 2em;\n" +
                "    line-height: " + lineHeight + " !important;\n" +
                "  }\n" +
                "  h1, h2, h3, h4, h5, h6 {\n" +
                "    color: " + textColor + " !important;\n" +
                "    text-indent: 0 !important;\n" +
                "    margin-top: 1.2em;\n" +
                "    margin-bottom: 0.6em;\n" +
                "    font-weight: bold;\n" +
                "  }\n" +
                "  img {\n" +
                "    max-width: 100% !important;\n" +
                "    height: auto !important;\n" +
                "    display: block !important;\n" +
                "    margin: 14px auto !important;\n" +
                "    border-radius: 4px;\n" +
                "  }\n" +
                "  a { color: " + accentColor + " !important; text-decoration: none; }\n" +
                "  blockquote { margin: 12px 0; padding: 6px 14px; border-left: 3px solid " + accentColor + "; opacity: 0.85; }\n" +
                "</style>\n";
    }

    private String generateJs() {
        return "<script>\n" +
                "  let lastReported = 0;\n" +
                "  window.addEventListener('scroll', function() {\n" +
                "    let total = document.documentElement.scrollHeight - window.innerHeight;\n" +
                "    let percent = total > 0 ? (window.pageYOffset / total) : 0;\n" +
                "    percent = Math.max(0, Math.min(1, percent));\n" +
                "    let now = Date.now();\n" +
                "    if (now - lastReported > 100) {\n" +
                "      lastReported = now;\n" +
                "      if (window.TextBridge) window.TextBridge.onScroll(percent);\n" +
                "    }\n" +
                "  });\n" +
                "  let downX = 0, downY = 0, downTime = 0;\n" +
                "  document.addEventListener('touchstart', function(e) {\n" +
                "    if (e.touches.length === 1) {\n" +
                "      downX = e.touches[0].clientX;\n" +
                "      downY = e.touches[0].clientY;\n" +
                "      downTime = Date.now();\n" +
                "    }\n" +
                "  }, {passive: true});\n" +
                "  document.addEventListener('touchend', function(e) {\n" +
                "    if (e.changedTouches.length === 1) {\n" +
                "      let dx = Math.abs(e.changedTouches[0].clientX - downX);\n" +
                "      let dy = Math.abs(e.changedTouches[0].clientY - downY);\n" +
                "      let duration = Date.now() - downTime;\n" +
                "      if (dx < 12 && dy < 12 && duration < 300) {\n" +
                "        let x = e.changedTouches[0].clientX;\n" +
                "        let w = window.innerWidth;\n" +
                "        if (x > w * 0.32 && x < w * 0.68) {\n" +
                "          if (window.TextBridge) window.TextBridge.onCenterTap();\n" +
                "        } else if (x <= w * 0.32) {\n" +
                "          if (window.TextBridge) window.TextBridge.onLeftTap();\n" +
                "        } else {\n" +
                "          if (window.TextBridge) window.TextBridge.onRightTap();\n" +
                "        }\n" +
                "      }\n" +
                "    }\n" +
                "  }, {passive: true});\n" +
                "</script>\n";
    }

    private WebResourceResponse handleZipResource(String path) {
        if (zipFile == null || TextUtils.isEmpty(path)) return null;
        try {
            ZipEntry entry = zipFile.getEntry(path);
            if (entry != null) {
                String mime = ArchiveIndex.detectMimeType(null, 0, path);
                if (path.endsWith(".css")) mime = "text/css";
                else if (path.endsWith(".js")) mime = "application/javascript";
                InputStream stream = zipFile.getInputStream(entry);
                return new WebResourceResponse(mime, "UTF-8", stream);
            }
        } catch (Exception ignored) {}
        return new WebResourceResponse("text/plain", "UTF-8", new ByteArrayInputStream(new byte[0]));
    }

    public void scrollToAnchor(String anchorId) {
        webView.evaluateJavascript(
                "(function() { var el = document.getElementById('" + anchorId + "') || document.getElementsByName('" + anchorId + "')[0]; " +
                        "if (el) el.scrollIntoView(); })();", null);
    }

    public void scrollToPercent(float percent) {
        webView.evaluateJavascript(
                "(function() { var total = document.documentElement.scrollHeight - window.innerHeight; " +
                        "window.scrollTo(0, Math.max(0, total * " + percent + ")); })();", null);
    }

    public void scrollByPages(int pageDelta) {
        webView.evaluateJavascript(
                "(function() { var step = window.innerHeight * 0.88 * " + pageDelta + "; " +
                        "window.scrollBy({top: step, behavior: 'smooth'}); })();", null);
    }

    private class JsBridge {
        @JavascriptInterface
        public void onScroll(float percent) {
            currentScrollPercent = percent;
            mainHandler.post(() -> {
                if (listener != null) {
                    TextLocator loc = new TextLocator(bookId, currentChapterIndex, currentSpineIndex,
                            currentEntryPath, "", currentScrollPercent, 0);
                    listener.onPositionChanged(loc);
                }
            });
        }

        @JavascriptInterface
        public void onCenterTap() {
            mainHandler.post(() -> {
                if (listener != null) listener.onToggleControls();
            });
        }

        @JavascriptInterface
        public void onLeftTap() {
            mainHandler.post(() -> {
                if (pagedMode) {
                    scrollByPages(-1);
                }
            });
        }

        @JavascriptInterface
        public void onRightTap() {
            mainHandler.post(() -> {
                if (pagedMode) {
                    scrollByPages(1);
                }
            });
        }
    }

    public static int getThemeBackgroundColor(int theme) {
        if (theme == THEME_LIGHT) return 0xFFFAFAFA;
        if (theme == THEME_SEPIA) return 0xFFF5EEDB;
        return 0xFF12161F;
    }

    public void release() {
        if (zipFile != null) {
            try { zipFile.close(); } catch (Exception ignored) {}
            zipFile = null;
        }
        webView.stopLoading();
        webView.loadUrl("about:blank");
    }

    private static String getParentZipDir(String path) {
        if (path == null) return "";
        int idx = path.lastIndexOf('/');
        return (idx != -1) ? path.substring(0, idx + 1) : "";
    }

    private static String resolveZipPath(String baseDir, String relativePath) {
        try {
            URI base = new URI("file:///" + (baseDir != null ? baseDir : ""));
            URI resolved = base.resolve(relativePath);
            String path = resolved.getPath();
            if (path != null && path.startsWith("/")) path = path.substring(1);
            return path != null ? path : relativePath;
        } catch (Exception e) {
            return (baseDir != null ? baseDir : "") + relativePath;
        }
    }

    private static byte[] readAllBytes(InputStream in) throws IOException {
        byte[] buf = new byte[8192];
        java.io.ByteArrayOutputStream out = new java.io.ByteArrayOutputStream();
        int n;
        while ((n = in.read(buf)) != -1) {
            out.write(buf, 0, n);
        }
        return out.toByteArray();
    }

    public static boolean generateTextCover(String title, String author, File targetFile) {
        try {
            int w = 600;
            int h = 900;
            Bitmap bitmap = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888);
            Canvas canvas = new Canvas(bitmap);

            // Rem theme gradient background
            Paint bgPaint = new Paint();
            bgPaint.setShader(new LinearGradient(0, 0, 0, h,
                    new int[]{0xFF243B55, 0xFF141E30}, null, Shader.TileMode.CLAMP));
            canvas.drawRect(0, 0, w, h, bgPaint);

            // Border & inner frame
            Paint borderPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
            borderPaint.setStyle(Paint.Style.STROKE);
            borderPaint.setStrokeWidth(4f);
            borderPaint.setColor(0x40FFFFFF);
            canvas.drawRoundRect(new RectF(28, 28, w - 28, h - 28), 16, 16, borderPaint);

            // Badge "EPUB 小说"
            Paint badgeBg = new Paint(Paint.ANTI_ALIAS_FLAG);
            badgeBg.setColor(0x306CA0DC);
            canvas.drawRoundRect(new RectF(50, 60, 210, 102), 8, 8, badgeBg);

            Paint badgeText = new Paint(Paint.ANTI_ALIAS_FLAG);
            badgeText.setColor(0xFF8AB4F8);
            badgeText.setTextSize(22f);
            badgeText.setTypeface(Typeface.create("sans-serif-medium", Typeface.BOLD));
            canvas.drawText("EPUB 电子书", 66, 90, badgeText);

            // Title
            TextPaint titlePaint = new TextPaint(Paint.ANTI_ALIAS_FLAG);
            titlePaint.setColor(Color.WHITE);
            titlePaint.setTextSize(46f);
            titlePaint.setTypeface(Typeface.create("sans-serif", Typeface.BOLD));
            String displayTitle = !TextUtils.isEmpty(title) ? title : "未命名小说";
            StaticLayout titleLayout = new StaticLayout(displayTitle, titlePaint, w - 100,
                    Layout.Alignment.ALIGN_NORMAL, 1.2f, 0, false);

            canvas.save();
            canvas.translate(50, 220);
            titleLayout.draw(canvas);
            canvas.restore();

            // Author
            if (!TextUtils.isEmpty(author)) {
                Paint authorPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
                authorPaint.setColor(0xB3FFFFFF);
                authorPaint.setTextSize(26f);
                authorPaint.setTypeface(Typeface.create("sans-serif", Typeface.NORMAL));
                canvas.drawText("作者 · " + author, 50, h - 90, authorPaint);
            }

            File parent = targetFile.getParentFile();
            if (parent != null && !parent.exists()) parent.mkdirs();
            try (OutputStream out = new FileOutputStream(targetFile)) {
                bitmap.compress(Bitmap.CompressFormat.JPEG, 88, out);
            } finally {
                bitmap.recycle();
            }
            return targetFile.exists() && targetFile.length() > 0;
        } catch (Exception ignored) {
            return false;
        }
    }
}
