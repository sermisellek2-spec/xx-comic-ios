# Independent Protected Source Verification Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give 18mh and JMComic separate fixed Chrome 124 verification implementations.

**Architecture:** Split the current shared Cloudflare WebView session into two source-owned classes. Preserve the existing `BrowserSession` contract and source behavior while removing all cross-source verification implementation sharing.

**Tech Stack:** Android Java, WebView, JUnit 4, Node.js contract checks, Gradle

---

### Task 1: Lock independent session behavior

**Files:**
- Create: `app/src/test/java/com/xxcomic/ProtectedSourceSessionIsolationTest.java`

- [ ] Add a test that references two independent session classes and verifies both select the fixed Chrome 124 user agent.
- [ ] Run `gradlew.bat testDebugUnitTest --tests com.xxcomic.ProtectedSourceSessionIsolationTest` and confirm compilation fails because the classes do not exist.

### Task 2: Split the implementations

**Files:**
- Create: `app/src/main/java/com/xxcomic/Mh18WebViewSession.java`
- Create: `app/src/main/java/com/xxcomic/JmComicWebViewSession.java`
- Delete: `app/src/main/java/com/xxcomic/CloudflareWebViewSession.java`
- Modify: `app/src/main/java/com/xxcomic/MainActivity.java`
- Modify: `app/src/test/java/com/xxcomic/CloudflareWebViewSessionTest.java`
- Modify: `tools/check-protected-source-session.js`

- [ ] Give each class its own WebView, request state, fixed user agent, challenge flow, and browser-context cache.
- [ ] Wire each comic source to its own concrete session type.
- [ ] Move session behavior coverage to the source-specific implementations.
- [ ] Update the static contract to reject the removed shared class.
- [ ] Run the focused unit and contract tests and confirm they pass.

### Task 3: Release

**Files:**
- Modify: `app/build.gradle`
- Modify: version assertions under `tools/`
- Create: release metadata and upload helpers under `release/`

- [ ] Increment the Android release to `1.0.43 (43)`.
- [ ] Run the complete unit suite, contract checks, and release APK build.
- [ ] Commit and push `master`.
- [ ] Upload the APK and metadata to the existing server fallback and COS key.
- [ ] Download both published artifacts and verify their SHA-256 hashes match the local APK.
