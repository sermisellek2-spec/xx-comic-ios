# Source Filter Routing Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make built-in source category filters affect the outgoing request even when an upgraded installation still holds an older route template, then release Android 1.0.20.

**Architecture:** Keep filter definitions and UI state unchanged. Normalize Baozi's final category query immediately before the request so current selections replace stale persisted `type`, `region`, `state`, `filter`, and `page` values while all unrelated route parameters remain intact.

**Tech Stack:** Android Java, Android Gradle Plugin 7.4.2, JUnit 4, Tencent COS.

---

### Task 1: Reproduce the stale-route regression

**Files:**
- Modify: `app/build.gradle`
- Create: `app/src/test/java/com/xxcomic/source/BaoziComicSourceTest.java`

- [ ] **Step 1: Add a regression test for the old persisted route**

```java
assertEquals(
        "https://cn.bzmgcn.com/classify?type=rexie&region=jp&state=serial&filter=ABCD",
        BaoziComicSource.withCategoryFilters(oldUrl, "rexie", "jp", "serial", "ABCD", 1));
```

- [ ] **Step 2: Run the focused test and verify it fails because the request normalizer does not exist**

Run: `.\gradlew.bat :app:testReleaseUnitTest --tests com.xxcomic.source.BaoziComicSourceTest --no-daemon`

Expected: compilation failure referring to `withCategoryFilters`.

### Task 2: Normalize the final category request

**Files:**
- Modify: `app/src/main/java/com/xxcomic/source/BaoziComicSource.java`
- Test: `app/src/test/java/com/xxcomic/source/BaoziComicSourceTest.java`

- [ ] **Step 1: Preserve unrelated query fields and replace the active filter fields**

```java
static String withCategoryFilters(String url, String type, String region, String state, String filter, int page) {
    // Keep non-filter query parts, then append the current filter state.
}
```

- [ ] **Step 2: Use the normalized URL for both HTML page 1 and paged API requests**

- [ ] **Step 3: Run the focused test and the release unit test task**

Run: `.\gradlew.bat :app:testReleaseUnitTest --no-daemon`

Expected: `BUILD SUCCESSFUL`.

### Task 3: Build and publish Android 1.0.20

**Files:**
- Modify: `app/build.gradle`
- Modify: `tools/check-rem-visual-contract.js`
- Publish outside Git: `release/xx-comic-1.0.20.apk`
- Publish outside Git: `release/android-release.json`

- [ ] **Step 1: Set `versionCode 20` and `versionName "1.0.20"` and update the release assertion**

- [ ] **Step 2: Run source checks, unit tests, and `:app:assembleRelease`**

Run: `.\gradlew.bat :app:testReleaseUnitTest :app:assembleRelease --no-daemon`

Expected: `BUILD SUCCESSFUL`.

- [ ] **Step 3: Verify package id, version, signature, byte size, and SHA-256**

- [ ] **Step 4: Commit only scoped source, test, plan, and version files; push `master`**

- [ ] **Step 5: Upload `apk/xx-comic/xx-comic.bin` with `application/octet-stream`, update server fallback APK and metadata, then pull both public APKs back and compare SHA-256 with the local artifact**
