# 18mh Verification Recovery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make manual 18mh verification reuse valid cached credentials and reliably finish real Cloudflare challenges without false `页面不正确` failures.

**Architecture:** Keep the independent `Mh18WebViewSession`. Add a cached HTTP preflight before creating the dialog, keep a single request deadline through browser and probe phases, and treat off-site navigation as blocked noise instead of terminal failure.

**Tech Stack:** Android Java, WebView, HttpURLConnection, JUnit 4, Gradle.

---

### Task 1: Lock The State Decisions With Tests

**Files:**
- Modify: `app/src/test/java/com/xxcomic/Mh18WebViewSessionTest.java`

- [ ] Add failing tests that expect cached catalog HTTP responses to complete without a browser, Cloudflare responses to require a browser, external navigation to be blocked without stopping the attempt, and probe activity to retain the request deadline.
- [ ] Run `./gradlew.bat :app:testDebugUnitTest --tests com.xxcomic.Mh18WebViewSessionTest --rerun-tasks --console=plain` and confirm failures refer to the missing state helpers.

### Task 2: Implement The Minimal 18mh State Fix

**Files:**
- Modify: `app/src/main/java/com/xxcomic/Mh18WebViewSession.java`
- Modify: `tools/check-protected-source-session.js`

- [ ] Preflight with `fetchHttp(request.url)` before posting dialog creation; return a catalog response immediately and open the browser only for `VERIFICATION_REQUIRED`.
- [ ] Replace fatal off-site handling with a pure navigation block:

```java
if (navigation != null && navigation.isForMainFrame()
        && shouldBlockNavigation(request.url, navigation.getUrl().toString())) {
    return true;
}
```

- [ ] Poll the active document while it remains a challenge and preserve the original 120-second timeout through the final HTTP probe.
- [ ] Run the focused test until it passes, then run `node tools/check-protected-source-session.js`.

### Task 3: Release Verification

**Files:**
- Modify: `app/build.gradle`
- Create: `release/android-release-1.0.46.json`
- Create: `release/xx-comic-1.0.46.apk`

- [ ] Set `versionCode 46` and `versionName "1.0.46"`.
- [ ] Run the full unit suite and source contract scripts.
- [ ] Build Release, verify package `com.xxcomic`, version `1.0.46 (46)`, v1/v2 signatures, size, and SHA-256.
- [ ] Commit source and version changes, push `master`, publish the APK and metadata to COS and the fallback server, then download both public APKs and compare their hashes with the local artifact.
