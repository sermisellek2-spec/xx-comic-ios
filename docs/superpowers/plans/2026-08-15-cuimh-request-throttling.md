# Cuimh Request Throttling Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reduce Cuimh origin traffic to one request for a default catalog or fresh detail and stop repeated traffic after HTTP 403.

**Architecture:** Keep the policy inside `CuimhComicSource`: one synchronized request boundary provides URL-keyed category caching, one-second pacing, and a 30-minute 403 cooldown. Parse chapters into the detail response and make the existing activity refresh path consume them without another request.

**Tech Stack:** Android Java, `HttpURLConnection`, JUnit 4, JDK `HttpServer`, Android Gradle Plugin 7.4.2, Tencent COS.

---

### Task 1: Lock Request Behavior With Tests

**Files:**
- Modify: `app/src/test/java/com/xxcomic/source/CuimhComicSourceTest.java`

- [ ] **Step 1: Add a local HTTP-server test proving `filterGroups()` followed by the default `category()` performs one request.**
- [ ] **Step 2: Add a local HTTP-server test proving `detail()` returns parsed chapters from one request.**
- [ ] **Step 3: Add a local HTTP-server test proving a second call after HTTP 403 is rejected locally without another request.**
- [ ] **Step 4: Run `./gradlew.bat :app:testReleaseUnitTest --tests com.xxcomic.source.CuimhComicSourceTest --no-daemon` and confirm the new tests fail for missing behavior.**

### Task 2: Implement Minimal Cuimh Request Control

**Files:**
- Modify: `app/src/main/java/com/xxcomic/source/CuimhComicSource.java`
- Modify: `app/src/main/java/com/xxcomic/MainActivity.java`

- [ ] **Step 1: Route category documents through a synchronized, five-minute URL cache and normalize the default path.**
- [ ] **Step 2: Pace uncached origin requests one second apart and record a 30-minute cooldown after HTTP 403.**
- [ ] **Step 3: Return chapters from `detail()` and reuse them from the generic detail refresh path.**
- [ ] **Step 4: Mark newly fetched details fresh and remove the filter-confirm duplicate category load.**
- [ ] **Step 5: Re-run the focused test and require all cases to pass.**

### Task 3: Release 1.0.22

**Files:**
- Modify: `app/build.gradle`
- Modify: `tools/check-cuimh-source.js`
- Modify: `tools/check-detail-release.js`
- Modify: `tools/check-rem-visual-contract.js`
- Modify: `tools/check-settings-visual-contract.js`

- [ ] **Step 1: Set `versionCode 22` and `versionName "1.0.22"`, then update release assertions.**
- [ ] **Step 2: Run the Cuimh contract, release contracts, unit tests, `git diff --check`, and `:app:assembleRelease`.**
- [ ] **Step 3: Verify APK package, version, signing certificate, size, and SHA-256.**
- [ ] **Step 4: Commit only scoped source, test, documentation, and version files; push `master`.**
- [ ] **Step 5: Upload `apk/xx-comic/xx-comic.bin` to bucket `xx-1321588235`, update server fallback APK and release metadata, and download both public APKs to verify their SHA-256 equals the local release.**

