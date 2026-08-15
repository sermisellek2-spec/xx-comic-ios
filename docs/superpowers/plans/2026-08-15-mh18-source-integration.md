# 18漫画 Source Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `https://18mh.org` as the independent built-in source “18漫画” and publish Android release `1.0.23 (23)`.

**Architecture:** Keep the user-selected copy-based isolation: `Mh18ComicSource` is an independent copy of the current G社 parser with its own `mh18:` IDs and `SourceConfig.mh18`. Register it through the same explicit `MainActivity` lifecycle as the other built-ins so settings, search, cache routing, import/export, and health checks work without changing `GmhComicSource`.

**Tech Stack:** Android Java, `HttpURLConnection`, `org.json`, Android Gradle Plugin 7.4.2, Tencent COS, SSH fallback release server.

---

### Task 1: Add the independent source parser

**Files:**
- Modify: `app/src/main/java/com/xxcomic/source/SourceConfig.java`
- Create: `app/src/main/java/com/xxcomic/source/Mh18ComicSource.java`

- [ ] **Step 1: Add the `mh18` source configuration next to `gmh`.**

Use the same routes and filters as `SourceConfig.gmh`, with this identity:

```java
return new SourceConfig("mh18", "18漫画", "18mh.org", "https://18mh.org",
        "https://18mh.org/", "", "", "", "", enabled, routes, filters);
```

Keep `mangaApi` and `chapterApi` on `https://v2.apikk.top`, because the user confirmed the target has the same backend contract as G社.

- [ ] **Step 2: Create `Mh18ComicSource` as an independent copy of `GmhComicSource`.**

Apply these identity replacements throughout the copied file:

```text
GmhComicSource       -> Mh18ComicSource
SOURCE_ID = "gmh"    -> SOURCE_ID = "mh18"
SourceConfig.gmh     -> SourceConfig.mh18
G社漫画详情解析失败   -> 18漫画详情解析失败
G社漫画章节解析失败   -> 18漫画章节解析失败
G社漫画图片解密失败   -> 18漫画图片解密失败
```

Retain the current list/search/filter/detail/chapter patterns, `apikk.top` calls, encryption constants, image line hosts, request headers, timeouts, redirect handling, URL cleanup, and `healthCheck()` behavior unchanged.

- [ ] **Step 3: Review the copied source for isolation.**

Run:

```powershell
rg -n 'SOURCE_ID|SourceConfig\.|G社漫画|m\.g-mh\.org' app/src/main/java/com/xxcomic/source/Mh18ComicSource.java
```

Expected: `SOURCE_ID` is `mh18`, constructors use `SourceConfig.mh18`, and no G社 display name or main-site domain remains.

### Task 2: Register 18漫画 through the App lifecycle

**Files:**
- Modify: `app/src/main/java/com/xxcomic/MainActivity.java`

- [ ] **Step 1: Add the source objects and default state.**

Add:

```java
import com.xxcomic.source.Mh18ComicSource;
private ComicSource mh18Client;
private SourceConfig mh18Config = SourceConfig.mh18(true);
private boolean mh18Enabled = true;
```

- [ ] **Step 2: Add the settings row and client creation.**

Place the new source next to G社 in `renderSources()` and rebuild with:

```java
mh18Client = new Mh18ComicSource(mh18Config.withEnabled(mh18Enabled));
```

The switch updates `mh18Enabled`, applies `withEnabled`, rebuilds clients, and calls `finishSourceToggle()` exactly like other built-ins.

- [ ] **Step 3: Add source selection and data routing.**

Add `mh18Client` to `sourceNameForId`, `selectedSource`, `enabledBuiltinSources`, `sourceForComicId`, `sourceForId`, source name/id mapping, and displayed enabled-source names. Match comics only by the independent prefix:

```java
if (comicId != null && comicId.startsWith(mh18Client.id() + ":")) return mh18Client;
```

- [ ] **Step 4: Add persistence, import/export, and health status.**

Persist `source.mh18.enabled`; include `mh18Config` in configuration encoding, decoding, import enable-state handling, empty/corrupt fallback initialization, export output, and disabled health rows.

- [ ] **Step 5: Add image Referer handling.**

Before the generic G社 shared-CDN branch, route direct `18mh.org` images to `mh18Config.referer`. For chapter images, preserve the supplied page Referer so shared `g-mh.online` / `6wm.top` URLs use the actual 18漫画 chapter URL rather than a fixed main-site Referer.

- [ ] **Step 6: Review all explicit registration points.**

Run:

```powershell
rg -n 'mh18|Mh18' app/src/main/java/com/xxcomic/MainActivity.java app/src/main/java/com/xxcomic/source/SourceConfig.java app/src/main/java/com/xxcomic/source/Mh18ComicSource.java
```

Expected: declarations, settings, selection, routing, health, persistence, import/export, client rebuild, and image handling are all represented.

### Task 3: Release 1.0.23

**Files:**
- Modify: `app/build.gradle`
- Modify: `tools/check-cuimh-source.js`
- Modify: `tools/check-detail-release.js`
- Modify: `tools/check-rem-visual-contract.js`
- Publish outside Git: `release/xx-comic-1.0.23.apk`
- Publish outside Git: `release/android-release.json`

- [ ] **Step 1: Bump the Android release identity.**

Set:

```gradle
versionCode 23
versionName "1.0.23"
```

Update only current-release assertions from `1.0.22 (22)` to `1.0.23 (23)`.

- [ ] **Step 2: Build the Release APK without running the test suite.**

Run:

```powershell
.\gradlew.bat :app:assembleRelease --no-daemon
```

Expected: `BUILD SUCCESSFUL` and `app/build/outputs/apk/release/app-release.apk` exists.

- [ ] **Step 3: Verify publishable artifact identity.**

Use the installed Android build tools to verify package `com.xxcomic`, version `1.0.23 (23)`, and APK signature. Copy the artifact to `release/xx-comic-1.0.23.apk`, compute lowercase SHA-256 and byte size, then write both values to `release/android-release.json`.

- [ ] **Step 4: Commit and push the scoped change.**

Stage only the source/config/activity/version/contract/plan files; do not stage `.gradle`, `app/build`, or unrelated `release` history. Commit with:

```powershell
git commit -m "feat: add 18mh comic source and release 1.0.23"
git push origin master
```

- [ ] **Step 5: Publish both download paths.**

Upload the APK to COS bucket `xx-1321588235`, key `apk/xx-comic/xx-comic.bin`. Upload the same APK to `/var/lib/xx-comic/releases/android/xx-comic.apk` and metadata to `/var/lib/xx-comic/releases/android-release.json` on `123.207.35.196` using the configured SSH key.

- [ ] **Step 6: Verify published bytes.**

Download the COS object and server fallback APK to separate temporary files, calculate SHA-256, and require both hashes to equal the local `release/xx-comic-1.0.23.apk` hash. Confirm the public metadata reports `1.0.23 (23)`, the same size, and the same lowercase hash.
