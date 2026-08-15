# Cuimh Source Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Cuimh as a complete built-in source while explicitly excluding it from keyword search.

**Architecture:** Keep all site-specific HTML and AES handling in `CuimhComicSource`. Add one backward-compatible source capability to `ComicSource`, register the client through the existing `MainActivity` source lifecycle, and reuse the current reader image pipeline with the chapter URL as Referer.

**Tech Stack:** Android Java, `HttpURLConnection`, `javax.crypto`, JUnit 4, Android Gradle Plugin 7.4.2, Tencent COS.

---

### Task 1: Lock the parser contract with failing tests

**Files:**
- Create: `app/src/test/java/com/xxcomic/source/CuimhComicSourceTest.java`

- [ ] **Step 1: Add compact HTML fixtures in the test for one list card, all supported filter groups, one detail, and two chapter links.**

- [ ] **Step 2: Add a fixed AES test vector whose plaintext contains two image URLs.**

- [ ] **Step 3: Assert `parseCards`, `parseFilterGroups`, `buildCategoryPath`, `parseDetail`, `parseChapters`, `decryptParams`, and `supportsSearch`.**

- [ ] **Step 4: Run `\.\gradlew.bat :app:testReleaseUnitTest --tests com.xxcomic.source.CuimhComicSourceTest --no-daemon`.**

Expected: compilation fails because `CuimhComicSource` does not exist.

### Task 2: Implement the Cuimh parser

**Files:**
- Create: `app/src/main/java/com/xxcomic/source/CuimhComicSource.java`
- Modify: `app/src/main/java/com/xxcomic/source/SourceConfig.java`

- [ ] **Step 1: Add `SourceConfig.cuimh(boolean)` with `/category`, detail, and chapter routes.**

- [ ] **Step 2: Implement list and filter parsing with ordered exact-label deduplication and omit the fee group.**

- [ ] **Step 3: Implement detail and chapter parsing with absolute URLs and stable `cuimh:` comic IDs.**

- [ ] **Step 4: Implement `AES/CBC/PKCS5Padding` decryption using key `9S8$vJnU2ANeSRoF`, validate the host, and return the JSON image array.**

- [ ] **Step 5: Run the focused test and confirm it passes.**

### Task 3: Register capability and App lifecycle

**Files:**
- Modify: `app/src/main/java/com/xxcomic/source/ComicSource.java`
- Modify: `app/src/main/java/com/xxcomic/MainActivity.java`
- Modify: `app/src/test/java/com/xxcomic/source/CuimhComicSourceTest.java`

- [ ] **Step 1: Add `default boolean supportsSearch() { return true; }` and override it to `false` in Cuimh.**

- [ ] **Step 2: Add Cuimh config, client, enabled preference, settings row, source resolution, health check, and import/export persistence alongside existing built-ins.**

- [ ] **Step 3: Use searchable enabled sources for global search and guard single-source keyword submission with the existing Rem toast.**

- [ ] **Step 4: Route Cuimh CDN/body images to the current chapter URL Referer.**

- [ ] **Step 5: Run all release unit tests and source contract checks.**

### Task 4: Release 1.0.21

**Files:**
- Modify: `app/build.gradle`
- Modify: `tools/check-rem-visual-contract.js`
- Publish outside Git: `release/xx-comic-1.0.21.apk`
- Publish outside Git: `release/android-release.json`

- [ ] **Step 1: Set `versionCode 21` and `versionName "1.0.21"`, and update the existing version assertion.**

- [ ] **Step 2: Run `\.\gradlew.bat :app:testReleaseUnitTest :app:assembleRelease --no-daemon`.**

- [ ] **Step 3: Verify package `com.xxcomic`, version, signature, byte size, and SHA-256.**

- [ ] **Step 4: Stage only scoped source, test, spec, plan, and version files; commit and push `master` without force.**

- [ ] **Step 5: Upload the APK to `xx-1321588235/apk/xx-comic/xx-comic.bin`, update the server fallback APK and metadata, then fetch both public APKs and compare SHA-256 with the local artifact.**
