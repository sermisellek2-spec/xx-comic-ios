# Explicit Protected-Source Verification Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restrict 18mh and JMComic verification to an explicit Source Management dialog while every content screen uses cached credentials only and routes expired credentials back to Source Management.

**Architecture:** Keep `Mh18WebViewSession` and `JmComicWebViewSession` as separate implementations with separate locks, WebViews, preferences, probes, and UI lifecycles. Ordinary `BrowserSession.fetch()` performs only a cookie-backed `HttpURLConnection` request and fails fast with a data-only `VerificationRequiredException`; `fetchInteractive()` opens the owning source's verification dialog, validates its business DOM, then validates the same cached HTTP path before closing.

**Tech Stack:** Android Java, platform `WebView`/`CookieManager`/`Dialog`, `HttpURLConnection`, JUnit 4, Node.js source contracts, Android Gradle Plugin 7.4.2, Tencent COS, SSH fallback release server.

---

## File Structure

- Create `app/src/main/java/com/xxcomic/source/VerificationRequiredException.java`: data-only signal for an expired or missing protected-source credential.
- Create `app/src/main/java/com/xxcomic/source/VerificationCancelledException.java`: data-only signal for an explicit user cancellation.
- Modify `app/src/main/java/com/xxcomic/source/Mh18ComicSource.java`: expose the 18mh catalog marker used by the session's final probe.
- Modify `app/src/main/java/com/xxcomic/source/JmComicSource.java`: expose the JMComic catalog marker used by the session's final probe.
- Modify `app/src/main/java/com/xxcomic/Mh18WebViewSession.java`: independent 18mh cached transport and explicit verification dialog.
- Modify `app/src/main/java/com/xxcomic/JmComicWebViewSession.java`: independent JMComic cached transport and explicit verification dialog.
- Modify `app/src/main/java/com/xxcomic/MainActivity.java`: Source Management trigger, verification-required states, routing, and cache cleanup.
- Modify focused JVM tests and `tools/check-protected-source-session.js`: lock transport, success, cancellation, UI routing, and source isolation.
- Modify `app/build.gradle` and three current-version contracts: release `1.0.45 (45)`.

### Task 1: Add explicit verification signals and business probes

**Files:**
- Create: `app/src/main/java/com/xxcomic/source/VerificationRequiredException.java`
- Create: `app/src/main/java/com/xxcomic/source/VerificationCancelledException.java`
- Modify: `app/src/main/java/com/xxcomic/source/Mh18ComicSource.java`
- Modify: `app/src/main/java/com/xxcomic/source/JmComicSource.java`
- Test: `app/src/test/java/com/xxcomic/source/Mh18ComicSourceTest.java`
- Test: `app/src/test/java/com/xxcomic/source/JmComicSourceTest.java`

- [ ] **Step 1: Write failing probe tests**

Add tests that require real list markers and reject challenge or shell documents:

```java
@Test
public void catalogMarkerRequiresAn18mhComicCard() {
    assertTrue(Mh18ComicSource.hasCatalogMarker(
            "<a href='/manga/hero/1'><img src='a.jpg'><h3 class='cardtitle'>Hero</h3></a>"));
    assertFalse(Mh18ComicSource.hasCatalogMarker("<title>Just a moment...</title>"));
}

@Test
public void catalogMarkerRequiresAJmcomicAlbumCard() {
    assertTrue(JmComicSource.hasCatalogMarker(
            "<a href='/album/123/title'><img title='Title' src='cover.jpg'></a>"));
    assertFalse(JmComicSource.hasCatalogMarker("<div class='btnmg'>shell only</div>"));
}
```

- [ ] **Step 2: Run RED**

```powershell
.\gradlew.bat :app:testDebugUnitTest --tests com.xxcomic.source.Mh18ComicSourceTest --tests com.xxcomic.source.JmComicSourceTest --rerun-tasks --console=plain
```

Expected: compilation fails because the public marker methods do not exist.

- [ ] **Step 3: Add the minimum signals and probes**

Create both exception classes as one-constructor `IOException` subclasses. Add `public static boolean hasCatalogMarker(String html)` to each source, using its existing card parser pattern. Change `verifyAccess()` to reuse that method.

```java
public final class VerificationRequiredException extends IOException {
    public VerificationRequiredException(String message) { super(message); }
}
```

```java
public static boolean hasCatalogMarker(String html) {
    return CARD_PATTERN.matcher(html == null ? "" : html).find();
}
```

- [ ] **Step 4: Run GREEN and commit**

Run the focused tests above and require `BUILD SUCCESSFUL`, then commit only the two exceptions, two source files, and two source tests.

### Task 2: Make 18mh content cached-only and verification explicit

**Files:**
- Modify: `app/src/main/java/com/xxcomic/Mh18WebViewSession.java`
- Modify: `app/src/test/java/com/xxcomic/Mh18WebViewSessionTest.java`

- [ ] **Step 1: Replace automatic-fallback tests with failing cached-only tests**

Lock the HTTP decision and dialog completion policy:

```java
@Test
public void cachedChallengeRequiresExplicitVerification() {
    assertEquals(Mh18WebViewSession.HttpAction.VERIFICATION_REQUIRED,
            Mh18WebViewSession.httpAction(403, "challenge", "<title>Just a moment...</title>"));
}

@Test
public void verificationClosesOnlyAfterBothBusinessProbesPass() {
    assertFalse(Mh18WebViewSession.verificationComplete(true, false));
    assertFalse(Mh18WebViewSession.verificationComplete(false, true));
    assertTrue(Mh18WebViewSession.verificationComplete(true, true));
}
```

- [ ] **Step 2: Run RED**

```powershell
.\gradlew.bat :app:testDebugUnitTest --tests com.xxcomic.Mh18WebViewSessionTest --rerun-tasks --console=plain
```

Expected: failure because `VERIFICATION_REQUIRED` and `verificationComplete` are missing.

- [ ] **Step 3: Remove ordinary-request browser promotion**

Make `fetch(String url)` acquire only the 18mh lock, call `fetchHttp`, and map challenge responses directly to `VerificationRequiredException`. Delete the ordinary browser-context and automatic interactive branches; keep browser navigation reachable only from `fetchInteractive`.

```java
HttpFetch response = fetchHttp(url, deadline);
HttpAction action = httpAction(response.statusCode, response.mitigated, response.body);
if (action == HttpAction.VERIFICATION_REQUIRED) {
    throw new VerificationRequiredException(sourceName + "需要验证");
}
if (action == HttpAction.FAIL) throw new IOException(sourceName + " HTTP " + response.statusCode);
return response.body;
```

- [ ] **Step 4: Build the independent 18mh verification dialog**

Create an Android `Dialog` containing a rounded panel sized to 90 percent width and 70 percent height, a compact header, the WebView, status text, Reload, and Close. `fetchInteractive` opens it immediately, waits for `/manga`, checks `Mh18ComicSource.hasCatalogMarker(browserBody)`, flushes cookies, performs one `fetchHttp` probe, checks the marker again, stores `verified_at`, shows `验证完成`, and dismisses after a short delay.

Close sets `cancelledByUser` and completes the request with `VerificationCancelledException`. Timeout or a failed marker leaves the dialog visible and exposes Reload; Reload closes the stale request and invokes the 18mh retry callback only.

- [ ] **Step 5: Clear only 18mh verification metadata in the session cleanup**

Use an 18mh-specific preferences name and clear `verified_at` plus in-memory request state from `clearCache()`; do not read or mutate the JMComic preference.

- [ ] **Step 6: Run GREEN and commit**

Run the focused test, `node tools/check-protected-source-session.js`, and require both to pass. Commit only 18mh session and test changes.

### Task 3: Make JMComic content cached-only and verification explicit

**Files:**
- Modify: `app/src/main/java/com/xxcomic/JmComicWebViewSession.java`
- Modify: `app/src/test/java/com/xxcomic/JmComicWebViewSessionTest.java`

- [ ] **Step 1: Write the JMComic cached-only RED tests**

Mirror the behavior, not the implementation:

```java
@Test
public void cachedChallengeRequiresExplicitVerification() {
    assertEquals(JmComicWebViewSession.HttpAction.VERIFICATION_REQUIRED,
            JmComicWebViewSession.httpAction(403, "challenge", "<title>Just a moment...</title>"));
}

@Test
public void verificationClosesOnlyAfterBothBusinessProbesPass() {
    assertFalse(JmComicWebViewSession.verificationComplete(true, false));
    assertFalse(JmComicWebViewSession.verificationComplete(false, true));
    assertTrue(JmComicWebViewSession.verificationComplete(true, true));
}
```

- [ ] **Step 2: Run RED**

```powershell
.\gradlew.bat :app:testDebugUnitTest --tests com.xxcomic.JmComicWebViewSessionTest --rerun-tasks --console=plain
```

Expected: failure because the cached-only decision and completion helper are absent.

- [ ] **Step 3: Implement the independent JMComic flow**

Change ordinary `fetch` to HTTP plus cookies only and map a challenge directly to `VerificationRequiredException`. Delete JMComic automatic takeover/browser-context behavior. Implement a separate JMComic dialog, JMComic request lifecycle, and JMComic-only retry callback. Validate `/albums?o=mr&page=1` first from the WebView and then from `fetchHttp` with `JmComicSource.hasCatalogMarker` before persisting the JMComic `verified_at` value and closing.

- [ ] **Step 4: Preserve JMComic-only credential migration and cleanup**

Keep the fixed Chrome 124 fingerprint preference migration scoped to `18comic.vip`. Extend `clearCache()` to clear JMComic `verified_at`; do not reference the 18mh preference or request object.

- [ ] **Step 5: Run GREEN and isolation checks, then commit**

```powershell
.\gradlew.bat :app:testDebugUnitTest --tests com.xxcomic.JmComicWebViewSessionTest --tests com.xxcomic.ProtectedSourceSessionIsolationTest --rerun-tasks --console=plain
node tools/check-jmcomic-bootstrap.js
node tools/check-protected-source-session.js
```

Expected: every command exits with code 0. Commit only JMComic session, tests, and updated contracts.

### Task 4: Route credential failures to Source Management

**Files:**
- Modify: `app/src/main/java/com/xxcomic/MainActivity.java`
- Modify: `app/src/test/java/com/xxcomic/ProtectedSourceUiTest.java`
- Modify: `app/src/test/java/com/xxcomic/SearchPagingTest.java`
- Modify: `tools/check-protected-source-session.js`

- [ ] **Step 1: Write failing UI-policy tests**

Add pure policy helpers and lock their expected routing:

```java
@Test
public void verificationRequiredRoutesProtectedSourcesToManagement() {
    assertTrue(MainActivity.shouldOfferSourceVerification("mh18", true));
    assertTrue(MainActivity.shouldOfferSourceVerification("jmcomic", true));
    assertFalse(MainActivity.shouldOfferSourceVerification("baozimh", true));
    assertFalse(MainActivity.shouldOfferSourceVerification("mh18", false));
}

@Test
public void protectedSourcesUseNormalGlobalSearchTimeout() {
    assertEquals(10L, MainActivity.globalSearchTimeoutSeconds("mh18"));
    assertEquals(10L, MainActivity.globalSearchTimeoutSeconds("jmcomic"));
}
```

- [ ] **Step 2: Run RED**

```powershell
.\gradlew.bat :app:testDebugUnitTest --tests com.xxcomic.ProtectedSourceUiTest --tests com.xxcomic.SearchPagingTest --rerun-tasks --console=plain
```

Expected: the new policy method is missing and protected-source timeout assertions fail.

- [ ] **Step 3: Make Source Management the only verification trigger**

Remove the old verification-start and successful-catalog-reload toasts from `verifyProtectedSource`. Pass each session its own retry callback. Treat `VerificationCancelledException` as a silent completion and leave all other interactive failures inside the still-visible verification dialog.

- [ ] **Step 4: Add the Rem-themed verification-required state**

Add a focused helper that opens Source Management without starting verification:

```java
private View verificationRequiredState(String sourceId) {
    return remState(R.drawable.rem_error, sourceNameForId(sourceId) + "需要验证",
            "请先完成站点验证", "去验证", this::showSourceManagement);
}
```

Use it for first-page Discover failures and equivalent detail, catalog, and reader entry failures. Detect `VerificationRequiredException` before generic logging so it does not become a generic error page.

- [ ] **Step 5: Preserve results when pagination credentials expire**

Track a separate `searchAppendVerificationRequired` flag. `renderSearchPagingFooter` renders `验证已失效 · 去验证` and routes to Source Management instead of retrying. Clear the flag in `clearSearchAppendFailure`.

- [ ] **Step 6: Make global search report protected-source verification**

Track protected source IDs that throw `VerificationRequiredException`. When that source tab is selected with no results, render the verification-required state instead of `暂无结果`. Change protected-source global search timeout from 185 seconds to the standard 10 seconds because no verification is allowed there.

- [ ] **Step 7: Run focused and full tests, then commit**

```powershell
.\gradlew.bat :app:testDebugUnitTest --rerun-tasks --console=plain
node tools/check-jmcomic-bootstrap.js
node tools/check-protected-source-session.js
```

Expected: all tests and contracts pass. Commit MainActivity, UI tests, paging tests, and contract changes.

### Task 5: Release Android 1.0.45

**Files:**
- Modify: `app/build.gradle`
- Modify: `tools/check-cuimh-source.js`
- Modify: `tools/check-detail-release.js`
- Modify: `tools/check-rem-visual-contract.js`
- Generate outside Git: `release/xx-comic-1.0.45.apk`
- Generate outside Git: `release/android-release-1.0.45.json`

- [ ] **Step 1: Increment and verify release contracts**

Set `versionCode 45` and `versionName "1.0.45"`; update the three exact current-version assertions from `1.0.44 (44)` to `1.0.45 (45)`.

- [ ] **Step 2: Run complete verification and build**

```powershell
.\gradlew.bat :app:testDebugUnitTest --rerun-tasks --console=plain
node tools/check-jmcomic-bootstrap.js
node tools/check-protected-source-session.js
node tools/check-cuimh-source.js
node tools/check-detail-release.js
node tools/check-rem-visual-contract.js
.\gradlew.bat :app:assembleRelease --rerun-tasks --console=plain
git diff --check
```

Expected: all commands exit with code 0 and `app/build/outputs/apk/release/app-release.apk` exists.

- [ ] **Step 3: Verify and stage the artifact**

Use Android SDK `aapt.exe` and `apksigner.bat` to require package `com.xxcomic`, version `1.0.45 (45)`, and a valid signature. Copy the APK to `release/xx-comic-1.0.45.apk`, calculate size and lowercase SHA-256, and write matching release metadata without adding `release/` to Git.

- [ ] **Step 4: Commit scoped release changes and push master**

Stage only tracked source, tests, contracts, plan, and version files. Exclude `.gradle/`, `.gradle-codex/`, `app/build/`, and `release/`. Commit, require `git status` to show only pre-existing build artifacts, then push `master`.

- [ ] **Step 5: Publish and verify both public artifacts**

Upload the exact local APK to COS bucket `xx-1321588235`, key `apk/xx-comic/xx-comic.bin`. Use `C:\Users\15361\.ssh\xx-agent-deploy` to atomically update `/var/lib/xx-comic/releases/android/xx-comic.apk` and `/var/lib/xx-comic/releases/android-release.json` on `root@123.207.35.196`. Download the COS and `https://weifeng.cloud/xx-comic/releases/xx-comic.apk` artifacts to distinct temporary files and require their byte size and SHA-256 to equal `release/xx-comic-1.0.45.apk`.

## Plan Self-Review

- Every approved design requirement maps to Tasks 1-4; release and public verification map to Task 5.
- The ordinary path is explicitly `HttpURLConnection` only and cannot create or navigate WebView.
- Both sessions depend only on their own source parser, domain, lock, dialog, preferences, and retry callback.
- Cancellation, timeout, post-verification HTTP probing, first-page routing, pagination preservation, global search, detail, catalog, reader, and cache cleanup are covered.
- All identifiers introduced in tests match the implementation steps, and the plan contains no deferred placeholders.
