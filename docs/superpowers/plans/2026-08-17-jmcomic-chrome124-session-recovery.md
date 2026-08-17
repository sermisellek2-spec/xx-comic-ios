# JMComic Chrome 124 Session Recovery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Recover JMComic catalog loading after the Chrome 124 fingerprint change and let manual verification take over a blocked automatic request.

**Architecture:** Keep migration and request ownership inside the dedicated `JmComicWebViewSession`. MainActivity only decides whether a successful manual verification should reload the currently visible JMComic catalog. No 18mh implementation is changed.

**Tech Stack:** Android Java, `CookieManager`, `WebStorage`, `SharedPreferences`, JUnit 4, Node static contracts, Gradle.

---

### Task 1: Lock the recovery policy

**Files:**
- Modify: `app/src/test/java/com/xxcomic/JmComicWebViewSessionTest.java`
- Modify: `app/src/test/java/com/xxcomic/ProtectedSourceUiTest.java`
- Modify: `tools/check-jmcomic-bootstrap.js`

- [ ] Add failing tests asserting a missing or changed fingerprint resets credentials, the same fingerprint does not, interactive takeover cancels only automatic work, and catalog reload requires Discover plus JMComic selection.
- [ ] Run the focused JVM tests and static contract; confirm failures identify the missing policy methods and wiring.

### Task 2: Recover the JMComic session

**Files:**
- Modify: `app/src/main/java/com/xxcomic/JmComicWebViewSession.java`
- Modify: `app/src/main/java/com/xxcomic/MainActivity.java`

- [ ] Add a JMComic-only fingerprint preference and expire `18comic.vip` cookies plus origin storage once when the fingerprint version changes.
- [ ] Mark `fetchInteractive` as a takeover, cancel active non-interactive work on the main thread, and reject queued automatic work while takeover is pending.
- [ ] Reload only the visible JMComic Discover catalog after successful manual verification.
- [ ] Run focused tests, the complete unit suite, and JMComic/protected-session contracts.

### Task 3: Release

**Files:**
- Modify: `app/build.gradle`
- Modify: current version assertions under `tools/`
- Generate outside Git: `release/xx-comic-1.0.44.apk`
- Generate outside Git: `release/android-release-1.0.44.json`

- [ ] Increment Android to `1.0.44 (44)` and update the existing version contracts.
- [ ] Build and verify the signed release APK package, version, size, and SHA-256.
- [ ] Commit scoped source, tests, contracts, and docs; push `master`.
- [ ] Publish the APK to COS and the server fallback, then download both public artifacts and require exact SHA-256 equality with the local APK.
