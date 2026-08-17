# JMComic Silent Verification and Single-Chapter Fallback Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Keep protected-site verification fully non-blocking during normal App use, cap it at two minutes, preserve an explicit manual-verification path, and let JMComic single-chapter albums open through their trusted direct-read link.

**Architecture:** Add an explicit interactive fetch entry to the existing browser session while leaving the default fetch silent. Each `FetchRequest` owns its interaction permission, so concurrent or queued work cannot change another request's UI behavior. JMComic chapter parsing keeps the strict `.episode` path first and adds one narrowly scoped `.read-block` fallback without changing shared comic models.

**Tech Stack:** Android Java, WebView, Android CookieManager, HttpURLConnection, JUnit 4, Gradle, Node.js source-contract checks.

---

### Task 1: Make automatic verification silent and cap requests at two minutes

**Files:**
- Modify: `app/src/main/java/com/xxcomic/source/BrowserSession.java`
- Modify: `app/src/main/java/com/xxcomic/CloudflareWebViewSession.java:45-160,381-389,683-696`
- Modify: `app/src/test/java/com/xxcomic/CloudflareWebViewSessionTest.java`

- [ ] **Step 1: Add failing verification-policy tests**

Add these tests to `CloudflareWebViewSessionTest`:

```java
@Test
public void protectedRequestTimeoutIsTwoMinutes() {
    assertEquals(120000L, CloudflareWebViewSession.requestTimeoutMs());
}

@Test
public void automaticVerificationNeverBecomesInteractive() {
    assertFalse(CloudflareWebViewSession.shouldShowInteractive(false, true));
}

@Test
public void manualVerificationOnlyShowsWhileChallengeIsActive() {
    assertTrue(CloudflareWebViewSession.shouldShowInteractive(true, true));
    assertFalse(CloudflareWebViewSession.shouldShowInteractive(true, false));
}
```

- [ ] **Step 2: Run the focused tests and verify RED**

Run:

```powershell
.\gradlew.bat :app:testDebugUnitTest --tests com.xxcomic.CloudflareWebViewSessionTest --rerun-tasks --console=plain
```

Expected: compilation fails because `requestTimeoutMs()` and `shouldShowInteractive()` do not exist, and the current timeout is 180 seconds.

- [ ] **Step 3: Add a backward-compatible interactive fetch entry**

Change `BrowserSession` to keep one abstract method so existing lambdas remain valid:

```java
public interface BrowserSession {
    String fetch(String url) throws IOException;

    default String fetchInteractive(String url) throws IOException {
        return fetch(url);
    }
}
```

- [ ] **Step 4: Pass interaction permission through each WebView request**

In `CloudflareWebViewSession`, change the timeout and add the pure policy helpers:

```java
private static final long TIMEOUT_MS = 120000L;

static long requestTimeoutMs() {
    return TIMEOUT_MS;
}

static boolean shouldShowInteractive(boolean interactiveAllowed, boolean verifying) {
    return interactiveAllowed && verifying;
}
```

Keep `fetch(String)` silent and add the explicit manual path:

```java
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
    synchronized (requestLock) {
        if (shutdown) throw new IOException(sourceName + "浏览器会话已停止");
        RequestTransport transport = requestTransport(preferHttp, browserContextReady);
        if (transport == RequestTransport.BROWSER_CONTEXT) {
            try {
                return fetchWithBrowserContext(url);
            } catch (ContextChallengeException challenge) {
                browserContextReady = false;
                String body = fetchWithBrowser(url, interactiveAllowed);
                browserContextReady = true;
                return body;
            }
        }
        if (transport == RequestTransport.HTTP) {
            HttpFetch response = fetchHttp(url);
            HttpAction action = httpAction(
                    response.statusCode, response.mitigated, response.body);
            if (action == HttpAction.RETURN_BODY) return response.body;
            if (action == HttpAction.FAIL) {
                throw new IOException(sourceName + " HTTP " + response.statusCode);
            }
        }
        String body = fetchWithBrowser(url, interactiveAllowed);
        if (preferHttp) browserContextReady = true;
        return body;
    }
}
```

Change navigation request creation to carry the permission, while same-origin browser-context fetches stay silent:

```java
private String fetchWithBrowser(String url, boolean interactiveAllowed) throws IOException {
    FetchRequest request = new FetchRequest(
            Integer.toString(requestSequence.incrementAndGet()), url, false,
            interactiveAllowed);
    main.post(() -> startRequest(request));
    return awaitRequest(request);
}

private String fetchWithBrowserContext(String url) throws IOException {
    FetchRequest request = new FetchRequest(
            Integer.toString(requestSequence.incrementAndGet()), url, true, false);
    main.post(() -> startRequest(request));
    return awaitRequest(request);
}
```

Add the per-request field and constructor argument:

```java
final boolean interactiveAllowed;

FetchRequest(String id, String url, boolean browserContext,
             boolean interactiveAllowed) {
    this.id = id;
    this.url = url;
    this.browserContext = browserContext;
    this.interactiveAllowed = interactiveAllowed;
}
```

- [ ] **Step 5: Stop automatic requests from scheduling the visible website**

Replace the unconditional delayed expansion inside `PageAction.SHOW_VERIFICATION` with:

```java
request.verifying = true;
notifyVerification("正在验证");
showBackgroundView();
if (request.interactiveAllowed) {
    browser.postDelayed(() -> {
        if (isActive(request)
                && shouldShowInteractive(request.interactiveAllowed, request.verifying)) {
            showVerificationView(true);
        }
    }, INTERACTIVE_DELAY_MS);
}
```

Do not change `showBackgroundView()`: its transparent, non-clickable background layout is the required automatic behavior.

- [ ] **Step 6: Run the session tests and verify GREEN**

```powershell
.\gradlew.bat :app:testDebugUnitTest --tests com.xxcomic.CloudflareWebViewSessionTest --rerun-tasks --console=plain
```

Expected: `BUILD SUCCESSFUL`; the new timeout and interaction-policy tests pass, and existing challenge classification tests remain green.

- [ ] **Step 7: Commit the session boundary**

```powershell
git add app/src/main/java/com/xxcomic/source/BrowserSession.java app/src/main/java/com/xxcomic/CloudflareWebViewSession.java app/src/test/java/com/xxcomic/CloudflareWebViewSessionTest.java
git commit -m "fix: keep automatic protected verification silent"
```

### Task 2: Route settings verification through the explicit manual path

**Files:**
- Modify: `app/src/main/java/com/xxcomic/source/JmComicSource.java:61-65,393-396`
- Modify: `app/src/main/java/com/xxcomic/source/Mh18ComicSource.java:54-70,327-331`
- Modify: `app/src/main/java/com/xxcomic/MainActivity.java:169,2274-2298`
- Modify: `app/src/test/java/com/xxcomic/source/JmComicSourceTest.java`
- Modify: `app/src/test/java/com/xxcomic/source/Mh18ComicSourceTest.java`
- Modify: `tools/check-jmcomic-bootstrap.js`

- [ ] **Step 1: Add failing tests proving manual probes use `fetchInteractive()`**

Add to `JmComicSourceTest`:

```java
@Test
public void verificationProbeUsesInteractiveBrowserFetch() throws Exception {
    java.util.concurrent.atomic.AtomicBoolean interactive =
            new java.util.concurrent.atomic.AtomicBoolean();
    BrowserSession session = new BrowserSession() {
        @Override public String fetch(String url) throws java.io.IOException {
            throw new java.io.IOException("silent fetch should not run");
        }

        @Override public String fetchInteractive(String url) {
            interactive.set(true);
            return "<a href='/album/123/title'><img src='cover.jpg'></a>";
        }
    };

    new JmComicSource(SourceConfig.jmcomic(true), session).verifyAccess();

    assertTrue(interactive.get());
}
```

Add `assertTrue` import and this test to `Mh18ComicSourceTest`:

```java
@Test
public void verificationProbeUsesInteractiveBrowserFetch() throws Exception {
    java.util.concurrent.atomic.AtomicBoolean interactive =
            new java.util.concurrent.atomic.AtomicBoolean();
    BrowserSession session = new BrowserSession() {
        @Override public String fetch(String url) throws java.io.IOException {
            throw new java.io.IOException("silent fetch should not run");
        }

        @Override public String fetchInteractive(String url) {
            interactive.set(true);
            return "<a href=\"/manga/demo\"><img src=\"cover.jpg\">"
                    + "<h3 class=\"cardtitle\">测试漫画</h3></a>";
        }
    };

    new Mh18ComicSource(SourceConfig.mh18(true), session).verifyAccess();

    assertTrue(interactive.get());
}
```

- [ ] **Step 2: Run the two source test classes and verify RED**

```powershell
.\gradlew.bat :app:testDebugUnitTest --tests com.xxcomic.source.JmComicSourceTest --tests com.xxcomic.source.Mh18ComicSourceTest --rerun-tasks --console=plain
```

Expected: JMComic fails because `verifyAccess()` still uses ordinary `fetch()`; MH18 fails to compile because it has no `verifyAccess()`.

- [ ] **Step 3: Use the interactive session only from each source's access probe**

In `JmComicSource`, change the probe and add a focused helper:

```java
public void verifyAccess() throws IOException {
    String url = pageUrl(absolute(config.route("latest")), 1);
    String html = fetchInteractive(url);
    if (!hasCatalogMarker(html)) throw new IOException(config.name + " 页面未就绪");
}

private String fetchInteractive(String url) throws IOException {
    if (browserSession != null && isMainSite(url)) {
        return browserSession.fetchInteractive(url);
    }
    return fetch(url);
}
```

In `Mh18ComicSource`, add the matching access probe and helper:

```java
public void verifyAccess() throws IOException {
    String html = fetchInteractive(categoryUrl("all", 1));
    if (parseCards(html).isEmpty()) throw new IOException(config.name + " 页面未就绪");
}

private String fetchInteractive(String url) throws IOException {
    if (browserSession != null && isMainSite(url)) {
        return browserSession.fetchInteractive(url);
    }
    return fetch(url);
}
```

- [ ] **Step 4: Make the settings button call the manual probes**

Change the field type in `MainActivity`:

```java
private Mh18ComicSource mh18Client;
```

Replace the success branch in `verifyProtectedSource()` with:

```java
if ("jmcomic".equals(sourceId)) {
    jmcomicClient.verifyAccess();
    resultMessage = client.name() + " 验证完成";
} else if ("mh18".equals(sourceId)) {
    mh18Client.verifyAccess();
    resultMessage = client.name() + " 验证完成";
} else {
    resultMessage = client.name() + " 验证失败";
}
```

This keeps ordinary business requests silent; only the existing settings action can authorize the visible WebView.

- [ ] **Step 5: Update the source contract**

In `tools/check-jmcomic-bootstrap.js`, replace the old lightweight-interaction check with:

```javascript
check("automatic verification never expands the website",
  session.includes("if (request.interactiveAllowed)")
  && session.includes("shouldShowInteractive(request.interactiveAllowed, request.verifying)")
  && session.includes("showBackgroundView()"));
check("settings verification keeps an explicit interactive path",
  main.includes("jmcomicClient.verifyAccess()")
  && main.includes("mh18Client.verifyAccess()"));
```

Keep the existing themed-toast, cookie reuse, single-active-request, category and HTTP fallback checks unchanged.

- [ ] **Step 6: Run source tests and the contract**

```powershell
.\gradlew.bat :app:testDebugUnitTest --tests com.xxcomic.source.JmComicSourceTest --tests com.xxcomic.source.Mh18ComicSourceTest --rerun-tasks --console=plain
node tools/check-jmcomic-bootstrap.js
```

Expected: both source test classes report success and the script prints `JMComic bootstrap contract holds.`

- [ ] **Step 7: Commit the manual verification path**

```powershell
git add app/src/main/java/com/xxcomic/source/JmComicSource.java app/src/main/java/com/xxcomic/source/Mh18ComicSource.java app/src/main/java/com/xxcomic/MainActivity.java app/src/test/java/com/xxcomic/source/JmComicSourceTest.java app/src/test/java/com/xxcomic/source/Mh18ComicSourceTest.java tools/check-jmcomic-bootstrap.js
git commit -m "fix: reserve interactive verification for settings"
```

### Task 3: Parse trusted direct-read buttons as a single chapter

**Files:**
- Modify: `app/src/test/java/com/xxcomic/source/JmComicSourceTest.java:168-203`
- Modify: `app/src/main/java/com/xxcomic/source/JmComicSource.java:176-196`

- [ ] **Step 1: Add the failing single-chapter fixture test**

Add beside `missingEpisodeDoesNotFabricateAChapter()`:

```java
@Test
public void albumWithoutEpisodeUsesTrustedDirectReadButton() {
    String html = "<div class=\"read-block\"><span>详情</span>"
            + "<a class=\"btn reading\" href=\"/photo/1432767\">開始閱讀</a>"
            + "<a href=\"/photo/1432767?read_mode=read-by-page\">分頁閱讀</a></div>"
            + "<section class=\"recommend\"><a href=\"/photo/999\">猜你喜欢</a></section>";

    List<ComicModels.Chapter> chapters = JmComicSource.parseChapters(
            html, "https://18comic.vip");

    assertEquals(1, chapters.size());
    assertEquals("1432767", chapters.get(0).chapterId);
    assertEquals("第1话", chapters.get(0).title);
    assertEquals("https://18comic.vip/photo/1432767", chapters.get(0).url);
}
```

Keep `missingEpisodeDoesNotFabricateAChapter()` unchanged; it protects against recommendation false positives.

- [ ] **Step 2: Run the focused parser tests and verify RED**

```powershell
.\gradlew.bat :app:testDebugUnitTest --tests com.xxcomic.source.JmComicSourceTest.albumWithoutEpisodeUsesTrustedDirectReadButton --tests com.xxcomic.source.JmComicSourceTest.missingEpisodeDoesNotFabricateAChapter --rerun-tasks --console=plain
```

Expected: the new test fails with zero chapters; the recommendation-only test still passes.

- [ ] **Step 3: Add the narrowly scoped fallback after standard parsing**

At the end of `parseChapters()`, before returning, keep standard chapters authoritative and add:

```java
if (!result.isEmpty()) return result;
String readBlock = firstValue(html,
        "<div\\b[^>]*class\\s*=\\s*[\"'][^\"']*\\bread-block\\b[^\"']*[\"'][^>]*>"
                + "([\\s\\S]{0,6000}?)</div>");
Matcher directLinks = ANCHOR.matcher(readBlock);
while (directLinks.find()) {
    String href = decode(attribute(directLinks.group(1), "href")).trim();
    String label = cleanMarkup(directLinks.group(2));
    if (href.contains("read_mode=")) continue;
    boolean directRead = label.contains("开始阅读") || label.contains("開始閱讀")
            || label.contains("继续阅读") || label.contains("繼續閱讀")
            || label.contains("續看");
    if (!directRead) continue;
    Matcher id = Pattern.compile(
            "(?:https?://[^/]+)?/photo/(\\d+)/?(?:[?#].*)?$",
            Pattern.CASE_INSENSITIVE).matcher(href);
    if (!id.find()) continue;
    String chapterId = id.group(1);
    result.add(new ComicModels.Chapter(chapterId, "第1话",
            absolute(baseUrl, "/photo/" + chapterId), 0, 0));
    break;
}
return result;
```

Do not relax the existing `.episode` checks and do not scan anchors outside `.read-block`.

- [ ] **Step 4: Run all JMComic parser tests and verify GREEN**

```powershell
.\gradlew.bat :app:testDebugUnitTest --tests com.xxcomic.source.JmComicSourceTest --rerun-tasks --console=plain
```

Expected: `BUILD SUCCESSFUL`; the standard 156-chapter-style fixture, recommendation exclusion, single-chapter fallback and正文参数 tests all pass.

- [ ] **Step 5: Commit the single-chapter fallback**

```powershell
git add app/src/main/java/com/xxcomic/source/JmComicSource.java app/src/test/java/com/xxcomic/source/JmComicSourceTest.java
git commit -m "fix: support jmcomic direct-read albums"
```

### Task 4: Run protected-source regression and build checks

**Files:**
- No source changes expected.

- [ ] **Step 1: Run all JVM tests**

```powershell
.\gradlew.bat testDebugUnitTest testReleaseUnitTest --rerun-tasks --console=plain
```

Expected: `BUILD SUCCESSFUL` with no failed tests.

- [ ] **Step 2: Run protected-source and release contracts**

```powershell
node tools/check-jmcomic-bootstrap.js
node tools/check-protected-source-session.js
node tools/check-release-regressions.js
```

Expected: each script exits with code 0 and prints its final contract-success line.

- [ ] **Step 3: Build the debug APK**

```powershell
.\gradlew.bat assembleDebug --rerun-tasks --console=plain
```

Expected: `BUILD SUCCESSFUL` and `app/build/outputs/apk/debug/app-debug.apk` exists.

- [ ] **Step 4: Check commit scope**

```powershell
git diff --check
git status --short
git log --oneline -8
```

Expected: no uncommitted source or test changes from this work. Existing `.gradle`, `.gradle-codex`, `app/build` and `release` artifacts remain outside commits.

- [ ] **Step 5: Perform real-device acceptance**

On a device with VPN enabled:

1. Clear App cache and enter 禁漫天堂; only the themed “正在验证” hint may appear, never the website or URL banner.
2. Immediately switch to another page and another source; navigation and touch remain available while verification continues.
3. Let verification succeed, then return to 禁漫天堂 and retry the original action; data loads through the saved session.
4. Force a network failure or wait for the 120-second cap; the request ends with the existing retry affordance and does not loop.
5. From 设置 -> 站点管理, tap 验证; only this explicit action may reveal an interactive challenge if automatic handling cannot finish.
6. Search “美丽新世界”; the first result opens as one chapter and the second result retains its complete multi-chapter directory.
