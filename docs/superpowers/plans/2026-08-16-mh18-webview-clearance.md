# 18漫画 WebView Clearance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let 18漫画 recover from Cloudflare browser challenges through one user-visible Android WebView verification and publish release `1.0.24 (24)`.

**Architecture:** `Mh18ComicSource` detects the specific `403 + Cf-Mitigated: challenge` response and asks a source-specific browser-session interface for fresh Cookie/User-Agent state before retrying once. A focused `Mh18WebViewSession` owns the Android WebView, deduplicates concurrent verification requests, and returns the clearance to all waiting source calls without changing other sources.

**Tech Stack:** Android Java, `HttpURLConnection`, platform `WebView`/`CookieManager`, `CountDownLatch`, Android Gradle Plugin 7.4.2, Tencent COS.

---

### Task 1: Add the 18漫画 browser-session contract

**Files:**
- Modify: `app/src/main/java/com/xxcomic/source/Mh18ComicSource.java`

- [ ] **Step 1: Add immutable clearance state and the session interface.**

```java
public static final class Clearance {
    public final String cookie;
    public final String userAgent;

    public Clearance(String cookie, String userAgent) {
        this.cookie = cookie == null ? "" : cookie;
        this.userAgent = userAgent == null ? "" : userAgent;
    }
}

public interface BrowserSession {
    Clearance current();
    Clearance resolve(String url, Clearance rejected) throws IOException;
}
```

Add a nullable `BrowserSession` constructor argument while retaining both existing constructors for compatibility.

- [ ] **Step 2: Split `fetch` into challenge-aware orchestration and one HTTP attempt.**

`fetch` gets the current clearance, calls `fetchOnce`, and catches only a private `CloudflareChallengeException`. If a browser session exists, call `resolve(config.baseUrl + "/manga", rejected)` and retry `fetchOnce` exactly once.

`fetchOnce` applies the clearance User-Agent and Cookie, calls `getResponseCode`, and throws the challenge exception only for:

```java
code == 403 && "challenge".equalsIgnoreCase(connection.getHeaderField("Cf-Mitigated"))
```

All other non-2xx/3xx responses become normal `IOException`s with the status code.

- [ ] **Step 3: Make health checks session-aware without opening WebView.**

Apply the current Cookie/User-Agent to the existing HEAD request, but never call `BrowserSession.resolve` from `healthCheck()`.

### Task 2: Implement and wire one WebView verification session

**Files:**
- Create: `app/src/main/java/com/xxcomic/Mh18WebViewSession.java`
- Modify: `app/src/main/java/com/xxcomic/MainActivity.java`

- [ ] **Step 1: Implement concurrent request deduplication.**

`Mh18WebViewSession` implements `Mh18ComicSource.BrowserSession`. Protect one active `Attempt` with a lock; each attempt owns one `CountDownLatch`, result, error, and completion flag. If the stored clearance differs from the rejected clearance, return it immediately. Otherwise all callers wait on the same attempt for at most three minutes.

- [ ] **Step 2: Build the visible verification dialog.**

On the main thread, create a full-screen cancelable `Dialog` with a compact “18漫画 · 安全验证” header, a small progress state, and one `WebView`. Enable JavaScript, DOM Storage, cookies, and third-party cookies, then load `https://18mh.org/manga`. Do not add a back button; dialog cancellation uses the system gesture.

- [ ] **Step 3: Detect completion and release waiters.**

After each page finish, poll `document.title` and `CookieManager.getCookie("https://18mh.org/manga")`. Complete successfully only when the title is no longer a Cloudflare challenge and the cookie contains `cf_clearance=`. Return the WebView User-Agent with the cookie, flush cookies, destroy the WebView, dismiss the dialog, and count down the latch.

Cancellation, timeout, main-frame load failure, or shutdown completes the attempt with a short Chinese error. Completion is idempotent so dialog dismissal cannot complete twice.

- [ ] **Step 4: Wire the session to Activity lifecycle and client rebuild.**

Create `Mh18WebViewSession` before the first `rebuildSourceClients()` call, pass it only to:

```java
mh18Client = new Mh18ComicSource(mh18Config.withEnabled(mh18Enabled), mh18WebViewSession);
```

Call `shutdown()` before `MainActivity.onDestroy()` releases its executors.

### Task 3: Release 1.0.24

**Files:**
- Modify: `app/build.gradle`
- Modify: `tools/check-cuimh-source.js`
- Modify: `tools/check-detail-release.js`
- Modify: `tools/check-rem-visual-contract.js`
- Publish outside Git: `release/xx-comic-1.0.24.apk`
- Publish outside Git: `release/android-release.json`

- [ ] **Step 1: Set `versionCode 24` and `versionName "1.0.24"`, then update current-release assertions.**

- [ ] **Step 2: Build without running the test suite.**

```powershell
.\gradlew.bat :app:assembleRelease --no-daemon
```

Expected: `BUILD SUCCESSFUL` and a release APK containing `Mh18WebViewSession`.

- [ ] **Step 3: Verify package, version, signature, size, and SHA-256.**

Require package `com.xxcomic`, release `1.0.24 (24)`, and a valid APK signature. Copy the artifact to `release/xx-comic-1.0.24.apk` and update `release/android-release.json` with exact bytes.

- [ ] **Step 4: Commit and push scoped files to `master`.**

```powershell
git commit -m "fix: handle 18mh Cloudflare clearance and release 1.0.24"
git push origin master
```

- [ ] **Step 5: Publish and verify both download paths.**

Upload the APK to COS key `apk/xx-comic/xx-comic.bin`, copy the same APK and metadata to the server fallback, then download both public APKs and require their SHA-256 values to equal the local artifact.
