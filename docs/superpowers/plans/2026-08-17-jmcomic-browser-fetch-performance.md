# JMComic Browser Fetch Performance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop repeated JMComic HTTP challenge probes and full WebView navigations after one successful browser verification, then remove redundant category and detail-page requests.

**Architecture:** Keep `BrowserSession` unchanged. Route JMComic requests through ordinary HTTP only before a browser context exists; after one successful browser navigation, use same-origin JavaScript `fetch` inside the persistent WebView. Cache only successfully parsed category groups and the most recent detail HTML in `JmComicSource`.

**Tech Stack:** Android Java, WebView JavaScript bridge, `HttpURLConnection`, JUnit 4, Gradle.

---

### Task 1: Lock the transport routing contract

**Files:**
- Modify: `app/src/test/java/com/xxcomic/CloudflareWebViewSessionTest.java`
- Modify: `app/src/main/java/com/xxcomic/CloudflareWebViewSession.java`

- [ ] **Step 1: Write failing routing tests**

Add tests that expect a ready JMComic browser context to skip HTTP, a fresh JMComic session to probe HTTP, and an `mh18` session to navigate directly:

```java
@Test public void readyBrowserContextSkipsRepeatedHttpProbe() {
    assertEquals(CloudflareWebViewSession.RequestTransport.BROWSER_CONTEXT,
            CloudflareWebViewSession.requestTransport(true, true));
}

@Test public void freshPreferredHttpSessionProbesHttp() {
    assertEquals(CloudflareWebViewSession.RequestTransport.HTTP,
            CloudflareWebViewSession.requestTransport(true, false));
}

@Test public void browserOnlySourceKeepsNavigation() {
    assertEquals(CloudflareWebViewSession.RequestTransport.BROWSER_NAVIGATION,
            CloudflareWebViewSession.requestTransport(false, false));
}
```

- [ ] **Step 2: Run the tests and verify RED**

Run:

```powershell
.\gradlew.bat :app:testDebugUnitTest --tests com.xxcomic.CloudflareWebViewSessionTest --rerun-tasks --console=plain
```

Expected: compilation fails because `RequestTransport` and `requestTransport` do not exist.

- [ ] **Step 3: Implement the minimal routing API**

Add the enum and selector, then make `fetch()` use it:

```java
enum RequestTransport { HTTP, BROWSER_CONTEXT, BROWSER_NAVIGATION }

static RequestTransport requestTransport(boolean preferHttp, boolean browserContextReady) {
    if (!preferHttp) return RequestTransport.BROWSER_NAVIGATION;
    return browserContextReady ? RequestTransport.BROWSER_CONTEXT : RequestTransport.HTTP;
}
```

- [ ] **Step 4: Run the focused test and verify GREEN**

Run the same Gradle command. Expected: all `CloudflareWebViewSessionTest` tests pass.

### Task 2: Fetch HTML inside the verified browser context

**Files:**
- Modify: `app/src/test/java/com/xxcomic/CloudflareWebViewSessionTest.java`
- Modify: `app/src/main/java/com/xxcomic/CloudflareWebViewSession.java`
- Modify: `tools/check-jmcomic-bootstrap.js`

- [ ] **Step 1: Write a failing browser-context source contract**

Add these assertions to `tools/check-jmcomic-bootstrap.js`:

```javascript
check("verified browser context uses same-origin fetch",
  session.includes("fetchWithBrowserContext(url)")
  && session.includes('credentials:\"include\"')
  && session.includes('cache:\"no-store\"')
  && session.includes('redirect:\"follow\"'));
check("ready browser context skips repeated http probes",
  session.indexOf("browserContextReady") >= 0
  && session.indexOf("fetchWithBrowserContext(url)")
      < session.indexOf("fetchHttp(url)"));
check("context challenge performs one navigation fallback",
  session.includes("browserContextReady = false")
  && session.includes("fetchWithBrowser(url)"));
```

- [ ] **Step 2: Run the test and verify RED**

Run `node tools/check-jmcomic-bootstrap.js`. Expected: failure at `verified browser context uses same-origin fetch` because the method and JavaScript request do not exist.

- [ ] **Step 3: Implement browser-context fetch**

Add `fetchWithBrowserContext(url)`, post a JavaScript `fetch` operation to the persistent WebView, and return `url`, `status`, `cf-mitigated`, and `body` through `XXComicBridge`. On `OPEN_BROWSER`, mark the context unavailable and call the existing `fetchWithBrowser(url)` once. Mark the context ready after a successful browser navigation. The routing shape is:

```java
RequestTransport transport = requestTransport(preferHttp, browserContextReady);
if (transport == RequestTransport.BROWSER_CONTEXT) {
    try {
        return fetchWithBrowserContext(url);
    } catch (ContextChallengeException challenge) {
        browserContextReady = false;
        String body = fetchWithBrowser(url);
        browserContextReady = true;
        return body;
    }
}
if (transport == RequestTransport.HTTP) {
    HttpFetch response = fetchHttp(url);
    HttpAction action = httpAction(response.statusCode, response.mitigated, response.body);
    if (action == HttpAction.RETURN_BODY) return response.body;
    if (action == HttpAction.FAIL) throw new IOException(sourceName + " HTTP " + response.statusCode);
}
String body = fetchWithBrowser(url);
if (preferHttp) browserContextReady = true;
return body;
```

The JavaScript must use:

```javascript
fetch(url, { credentials: "include", cache: "no-store", redirect: "follow" })
```

It must not call `location.href` or load page resources.

- [ ] **Step 4: Clear browser-context state with cache/session teardown**

Set `browserContextReady = false` in `clearCache()` and `closeViews()` so clearing credentials never retains a stale browser route.

- [ ] **Step 5: Update the source contract**

Require the ready-context branch to occur before `fetchHttp(url)`, require JavaScript credentials, and preserve `mh18Config.name, false`.

- [ ] **Step 6: Run focused tests and contract**

```powershell
.\gradlew.bat :app:testDebugUnitTest --tests com.xxcomic.CloudflareWebViewSessionTest --rerun-tasks --console=plain
node tools/check-jmcomic-bootstrap.js
```

Expected: both commands exit 0.

### Task 3: Cache categories and reuse detail HTML

**Files:**
- Modify: `app/src/test/java/com/xxcomic/source/JmComicSourceTest.java`
- Modify: `app/src/main/java/com/xxcomic/source/JmComicSource.java`

- [ ] **Step 1: Write a failing category-cache test**

Use a counting `BrowserSession`, call `filterGroups()` twice, and assert the browser session is called once while both results contain the same parsed group:

```java
@Test public void successfulCategoryGroupsAreReused() throws Exception {
    java.util.concurrent.atomic.AtomicInteger requests = new java.util.concurrent.atomic.AtomicInteger();
    BrowserSession session = url -> {
        requests.incrementAndGet();
        return row("類別", "/albums?o=mr", "最新A漫");
    };
    JmComicSource source = new JmComicSource(SourceConfig.jmcomic(true), session);

    assertEquals(1, source.filterGroups().size());
    assertEquals(1, source.filterGroups().size());
    assertEquals(1, requests.get());
}
```

- [ ] **Step 2: Run the category test and verify RED**

Expected: request count is 2 with the current implementation.

- [ ] **Step 3: Cache only successful category results**

Store a copied list after non-empty parsing and return copied lists on later calls. Do not cache exceptions or empty parsing results.

- [ ] **Step 4: Run the category test and verify GREEN**

Expected: request count is 1.

- [ ] **Step 5: Write a failing detail-page reuse test**

Use one HTML document containing valid detail metadata and one `.episode` chapter. Call `detail("jmcomic:123")` followed by `chapters("jmcomic:123")`; assert the session is called once and the chapter remains correct:

```java
@Test public void detailAndDirectoryReuseOneAlbumDocument() throws Exception {
    java.util.concurrent.atomic.AtomicInteger requests = new java.util.concurrent.atomic.AtomicInteger();
    String html = "<h1 id=\"book-name\">漫画甲</h1>"
            + "<img id=\"album_photo_cover\" src=\"/media/albums/123.jpg\">"
            + "<div class=\"episode\"><a href=\"/photo/456\" data-album=\"456\">"
            + "<h3 class=\"h2_series\">第1话</h3></a></div>";
    JmComicSource source = new JmComicSource(SourceConfig.jmcomic(true), url -> {
        requests.incrementAndGet();
        return html;
    });

    source.detail("jmcomic:123");
    assertEquals(1, source.chapters("jmcomic:123").size());
    assertEquals(1, requests.get());
}
```

- [ ] **Step 6: Run the detail test and verify RED**

Expected: request count is 2.

- [ ] **Step 7: Implement one-entry detail HTML reuse**

Route both methods through a synchronized `detailPage(rawId)` method that stores only the most recent ID and HTML. Never cache failed or empty responses.

- [ ] **Step 8: Run JMComic tests and verify GREEN**

```powershell
.\gradlew.bat :app:testDebugUnitTest --tests com.xxcomic.source.JmComicSourceTest --rerun-tasks --console=plain
```

Expected: all JMComic source tests pass.

### Task 4: Regression verification

**Files:**
- No production changes expected.

- [ ] **Step 1: Run all JVM tests**

```powershell
.\gradlew.bat testDebugUnitTest testReleaseUnitTest --rerun-tasks --console=plain
```

Expected: `BUILD SUCCESSFUL`, no failed tests.

- [ ] **Step 2: Run protected-source and release contracts**

```powershell
node tools/check-jmcomic-bootstrap.js
node tools/check-protected-source-session.js
node tools/check-settings-visual-contract.js
node tools/check-release-regressions.js
node tools/check-cuimh-source.js
node tools/check-detail-release.js
node tools/check-rem-visual-contract.js
```

Expected: every script exits 0.

- [ ] **Step 3: Build the release APK**

```powershell
.\gradlew.bat assembleRelease --rerun-tasks --console=plain
```

Expected: `BUILD SUCCESSFUL` and `app/build/outputs/apk/release/app-release.apk` exists.

- [ ] **Step 4: Review scope**

Run `git diff --check` and inspect `git status --short`. Only the approved spec, plan, JMComic session/source implementation, and their tests/contracts may be source changes; build directories remain uncommitted.
