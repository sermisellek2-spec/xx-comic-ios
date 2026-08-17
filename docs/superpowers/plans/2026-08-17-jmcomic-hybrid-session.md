# JMComic Hybrid Session Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (- [ ]) syntax for tracking.

**Goal:** Make JMComic verify through WebView only when its Cloudflare cookie is missing or expired, then load catalog, categories, and detail pages through cookie-backed HTTP while keeping verification UI lightweight.

**Architecture:** Extend the existing CloudflareWebViewSession with an opt-in HTTP-first path used only by JMComic. A pure response-policy method classifies HTTP responses as return, browser fallback, or failure; the serialized WebView request remains the only challenge solver. Category parsing is relaxed around semantic h4 and ul.btnmg boundaries without hard-coding category values.

**Tech Stack:** Android Java, HttpURLConnection, Android CookieManager, WebView, JUnit 4, Node.js source contracts, Gradle.

---

### Task 1: Make category parsing resilient to wrapper changes

**Files:**
- Modify: app/src/test/java/com/xxcomic/source/JmComicSourceTest.java
- Modify: app/src/main/java/com/xxcomic/source/JmComicSource.java:31-39

- [ ] **Step 1: Write the failing wrapper-change test**

Add beside parsesOnlyRealThemeRowsAndNormalizesLabels():

    @Test
    public void categoryGroupsDoNotDependOnTheOuterRowWrapper() {
        String html = "<section class=\"theme-block\"><header><h4>熱門成人主題</h4></header>"
                + "<div><ul class=\"btnmg compact btn-toolbar\">"
                + "<li><a href=\"/search/photos?search_query=完結\">完結</a></li>"
                + "</ul></div></section>"
                + "<article><h4>類別</h4><div><ul class=\"btn-toolbar x btnmg\">"
                + "<li><a href=\"/albums?o=mr\">最新A漫</a></li>"
                + "</ul></div></article>";

        List<ComicModels.FilterGroup> groups = JmComicSource.parseFilterGroups(
                html, "https://18comic.vip");

        assertEquals(2, groups.size());
        assertEquals("热门", groups.get(0).label);
        assertEquals("类别", groups.get(1).label);
    }

- [ ] **Step 2: Run the focused test and verify RED**

Run:

    .\gradlew.bat :app:testDebugUnitTest --tests com.xxcomic.source.JmComicSourceTest.categoryGroupsDoNotDependOnTheOuterRowWrapper --rerun-tasks --console=plain

Expected: FAIL because THEME_SECTION requires div.row and direct h4/ul siblings.

- [ ] **Step 3: Replace the rigid section pattern**

Replace THEME_SECTION with:

    private static final Pattern THEME_SECTION = Pattern.compile(
            "<h4[^>]*>([\\s\\S]*?)</h4>[\\s\\S]{0,1600}?"
                    + "<ul\\b[^>]*class\\s*=\\s*[\"'][^\"']*\\bbtnmg\\b[^\"']*[\"'][^>]*>"
                    + "([\\s\\S]*?)</ul>", Pattern.CASE_INSENSITIVE);

Keep parseFilterGroups() unchanged so dynamic labels, link filtering, de-duplication, and 全部 remain centralized.

- [ ] **Step 4: Run all JMComic tests and verify GREEN**

    .\gradlew.bat :app:testDebugUnitTest --tests com.xxcomic.source.JmComicSourceTest --rerun-tasks --console=plain

Expected: BUILD SUCCESSFUL; the old 7-group sample and wrapper-change sample pass.

- [ ] **Step 5: Commit**

    git add app/src/main/java/com/xxcomic/source/JmComicSource.java app/src/test/java/com/xxcomic/source/JmComicSourceTest.java
    git commit -m "fix: tolerate jmcomic category wrapper changes"

### Task 2: Lock the HTTP-to-WebView fallback policy

**Files:**
- Modify: app/src/test/java/com/xxcomic/CloudflareWebViewSessionTest.java
- Modify: app/src/main/java/com/xxcomic/CloudflareWebViewSession.java:37-42

- [ ] **Step 1: Write failing response-policy tests**

    @Test
    public void successfulBusinessHttpResponseReturnsWithoutBrowser() {
        assertEquals(CloudflareWebViewSession.HttpAction.RETURN_BODY,
                CloudflareWebViewSession.httpAction(
                        200, "", "<a href='/album/123'><img title='漫画'></a>"));
    }

    @Test
    public void cloudflareHttpChallengeFallsBackToBrowser() {
        assertEquals(CloudflareWebViewSession.HttpAction.OPEN_BROWSER,
                CloudflareWebViewSession.httpAction(
                        403, "challenge", "<title>Just a moment...</title>"));
    }

    @Test
    public void ordinaryHttpErrorsNeverOpenVerification() {
        assertEquals(CloudflareWebViewSession.HttpAction.FAIL,
                CloudflareWebViewSession.httpAction(403, "", "Forbidden"));
        assertEquals(CloudflareWebViewSession.HttpAction.FAIL,
                CloudflareWebViewSession.httpAction(500, "", "Server error"));
    }

- [ ] **Step 2: Run and verify RED**

    .\gradlew.bat :app:testDebugUnitTest --tests com.xxcomic.CloudflareWebViewSessionTest --rerun-tasks --console=plain

Expected: compilation fails because HttpAction and httpAction() do not exist.

- [ ] **Step 3: Add the minimal response policy**

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

- [ ] **Step 4: Run and verify GREEN**

    .\gradlew.bat :app:testDebugUnitTest --tests com.xxcomic.CloudflareWebViewSessionTest --rerun-tasks --console=plain

Expected: BUILD SUCCESSFUL.

- [ ] **Step 5: Commit**

    git add app/src/main/java/com/xxcomic/CloudflareWebViewSession.java app/src/test/java/com/xxcomic/CloudflareWebViewSessionTest.java
    git commit -m "test: lock protected http fallback policy"

### Task 3: Reuse WebView cookies through HTTP for JMComic

**Files:**
- Modify: app/src/main/java/com/xxcomic/CloudflareWebViewSession.java:3-181
- Modify: app/src/main/java/com/xxcomic/MainActivity.java:342-352
- Modify: tools/check-jmcomic-bootstrap.js

- [ ] **Step 1: Add a failing source contract**

Append:

    check("jmcomic opts into cookie-backed http",
      main.includes("jmcomicConfig.name, true")
      && session.includes("fetchHttp(url)")
      && session.includes('setRequestProperty("Cookie", cookie)')
      && session.includes("HttpAction.OPEN_BROWSER"));
    check("mh18 keeps its current browser-only path",
      main.includes("mh18Config.name, false"));

- [ ] **Step 2: Run and verify RED**

    node tools/check-jmcomic-bootstrap.js

Expected: FAIL at jmcomic opts into cookie-backed http.

- [ ] **Step 3: Add opt-in configuration and split browser fetch**

Add:

    private static final String USER_AGENT = "Mozilla/5.0 (Linux; Android 14) "
            + "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36";
    private static final int CONNECT_TIMEOUT_MS = 10000;
    private static final int READ_TIMEOUT_MS = 25000;
    private final boolean preferHttp;

Use this constructor:

    CloudflareWebViewSession(Activity activity, Handler main, String sourceName,
                              boolean preferHttp) {
        this.activity = activity;
        this.main = main;
        this.sourceName = sourceName;
        this.preferHttp = preferHttp;
    }

Keep synchronized (requestLock) in fetch(), move the existing latch path to fetchWithBrowser(), and use:

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

fetchWithBrowser() contains the existing FetchRequest creation, main.post(startRequest), latch wait, timeout handling, and result checks without acquiring requestLock again.

- [ ] **Step 4: Implement cookie-backed HTTP**

Add imports for BufferedReader, InputStream, InputStreamReader, HttpURLConnection, Map, and List. Add:

    private HttpFetch fetchHttp(String url) throws IOException {
        HttpURLConnection connection = (HttpURLConnection) new URL(url).openConnection();
        connection.setInstanceFollowRedirects(true);
        connection.setConnectTimeout(CONNECT_TIMEOUT_MS);
        connection.setReadTimeout(READ_TIMEOUT_MS);
        connection.setRequestProperty("User-Agent", USER_AGENT);
        connection.setRequestProperty("Accept-Language", "zh-CN,zh;q=0.9");
        String cookie = android.webkit.CookieManager.getInstance().getCookie(url);
        if (!TextUtils.isEmpty(cookie)) {
            connection.setRequestProperty("Cookie", cookie);
        }
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
        try (BufferedReader reader =
                     new BufferedReader(new InputStreamReader(stream, "UTF-8"))) {
            StringBuilder body = new StringBuilder();
            String line;
            while ((line = reader.readLine()) != null) body.append(line).append('\n');
            return body.toString();
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

Set the WebView to the same User-Agent:

    settings.setUserAgentString(USER_AGENT);

- [ ] **Step 5: Opt only JMComic into HTTP-first behavior**

    mh18BrowserSession = new CloudflareWebViewSession(
            this, main, mh18Config.name, false);
    jmcomicBrowserSession = new CloudflareWebViewSession(
            this, main, jmcomicConfig.name, true);

- [ ] **Step 6: Run contract and focused tests**

    node tools/check-jmcomic-bootstrap.js
    .\gradlew.bat :app:testDebugUnitTest --tests com.xxcomic.CloudflareWebViewSessionTest --tests com.xxcomic.source.JmComicSourceTest --rerun-tasks --console=plain

Expected: all contract checks pass and Gradle reports BUILD SUCCESSFUL.

- [ ] **Step 7: Commit**

    git add app/src/main/java/com/xxcomic/CloudflareWebViewSession.java app/src/main/java/com/xxcomic/MainActivity.java tools/check-jmcomic-bootstrap.js
    git commit -m "fix: reuse jmcomic verification cookies over http"

### Task 4: Keep automatic verification lightweight

**Files:**
- Modify: app/src/test/java/com/xxcomic/CloudflareWebViewSessionTest.java
- Modify: app/src/main/java/com/xxcomic/CloudflareWebViewSession.java:37-288
- Modify: app/src/main/java/com/xxcomic/MainActivity.java:342-352
- Modify: tools/check-jmcomic-bootstrap.js

- [ ] **Step 1: Add a failing delay test**

    @Test
    public void interactiveVerificationWaitsForAutomaticChallengeToFinish() {
        assertEquals(4000L, CloudflareWebViewSession.interactiveDelayMs());
    }

- [ ] **Step 2: Run and verify RED**

    .\gradlew.bat :app:testDebugUnitTest --tests com.xxcomic.CloudflareWebViewSessionTest.interactiveVerificationWaitsForAutomaticChallengeToFinish --rerun-tasks --console=plain

Expected: compilation fails because interactiveDelayMs() does not exist.

- [ ] **Step 3: Add callback and delay**

    private static final long INTERACTIVE_DELAY_MS = 4000L;

    interface VerificationStatusListener {
        void onStatus(String message);
    }

    static long interactiveDelayMs() {
        return INTERACTIVE_DELAY_MS;
    }

Add the listener to the constructor:

    private final VerificationStatusListener verificationStatus;

    CloudflareWebViewSession(Activity activity, Handler main, String sourceName,
                              boolean preferHttp,
                              VerificationStatusListener verificationStatus) {
        this.activity = activity;
        this.main = main;
        this.sourceName = sourceName;
        this.preferHttp = preferHttp;
        this.verificationStatus = verificationStatus;
    }

Add:

    private void notifyVerification(String message) {
        if (verificationStatus != null) {
            verificationStatus.onStatus(sourceName + " " + message);
        }
    }

In SHOW_VERIFICATION:

    request.verifying = true;
    notifyVerification("正在验证");
    showBackgroundView();
    browser.postDelayed(() -> {
        if (isActive(request) && request.verifying) showVerificationView(true);
    }, INTERACTIVE_DELAY_MS);

In CAPTURE:

    if (request.verifying) {
        notifyVerification("验证完成");
        showVerifiedState();
        browser.postDelayed(() -> captureCurrentPage(
                request, browser, expectedNavigation), 300L);
    } else {
        captureCurrentPage(request, browser, expectedNavigation);
    }

- [ ] **Step 4: Wire the existing themed toast**

    mh18BrowserSession = new CloudflareWebViewSession(
            this, main, mh18Config.name, false, this::showRemToast);
    jmcomicBrowserSession = new CloudflareWebViewSession(
            this, main, jmcomicConfig.name, true, this::showRemToast);

This reuses the existing Rem-style toast instead of adding another overlay.

- [ ] **Step 5: Update the source contract**

Replace the immediate-overlay assertion with:

    check("automatic verification stays lightweight before interaction",
      session.includes("INTERACTIVE_DELAY_MS = 4000L")
      && session.includes('notifyVerification("正在验证")')
      && session.includes("showBackgroundView()")
      && session.includes("showVerificationView(true)"));
    check("verification status uses the themed app toast",
      main.includes("this::showRemToast"));

- [ ] **Step 6: Run tests and contracts**

    node tools/check-jmcomic-bootstrap.js
    .\gradlew.bat :app:testDebugUnitTest --tests com.xxcomic.CloudflareWebViewSessionTest --tests com.xxcomic.ProtectedSourceUiTest --rerun-tasks --console=plain

Expected: contract checks pass and Gradle reports BUILD SUCCESSFUL.

- [ ] **Step 7: Commit**

    git add app/src/main/java/com/xxcomic/CloudflareWebViewSession.java app/src/main/java/com/xxcomic/MainActivity.java app/src/test/java/com/xxcomic/CloudflareWebViewSessionTest.java tools/check-jmcomic-bootstrap.js
    git commit -m "fix: lighten protected source verification ui"

### Task 5: Full regression and handoff build

**Files:**
- No source changes expected.

- [ ] **Step 1: Run all JVM tests**

    .\gradlew.bat testDebugUnitTest testReleaseUnitTest --rerun-tasks --console=plain

Expected: BUILD SUCCESSFUL with no failed tests.

- [ ] **Step 2: Run all release contracts**

    node tools/check-jmcomic-bootstrap.js
    node tools/check-protected-source-session.js
    node tools/check-settings-visual-contract.js
    node tools/check-release-regressions.js

Expected: every script exits with code 0.

- [ ] **Step 3: Build the installable debug APK**

    .\gradlew.bat assembleDebug --rerun-tasks --console=plain

Expected: BUILD SUCCESSFUL and app/build/outputs/apk/debug/app-debug.apk exists.

- [ ] **Step 4: Check repository scope**

    git diff --check
    git status --short
    git log --oneline -8

Expected: no uncommitted source or test changes from this work. Existing .gradle, .gradle-codex, app/build, and release artifacts remain outside commits.

- [ ] **Step 5: Hand off real-device acceptance**

Follow the six acceptance steps in docs/superpowers/specs/2026-08-17-jmcomic-hybrid-session-design.md: clear cache, verify once, observe list then categories, exercise paging/category/detail without another challenge, restart and reuse the cookie, then clear cache and verify once again.

