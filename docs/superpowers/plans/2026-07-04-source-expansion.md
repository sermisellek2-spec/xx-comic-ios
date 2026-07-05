# Source Expansion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Verify the next practical comic source and implement the lowest-risk usable source path.

**Architecture:** First run the existing probe scripts for `mangabz` to decide whether chapter images can be fetched without WebView. If direct image extraction is not reliable, switch to `mkzhan` probing and implement only after search/detail/chapter/image flow is verified. Keep changes scoped to `source/`, `SourceConfig`, and `MainActivity` source registration.

**Tech Stack:** Native Android Java, existing `ComicSource` interface, existing Node.js probe scripts.

---

### Task 1: Verify mangabz Image Path

**Files:**
- Read: `tools/probe-mangabz.js`
- Read: `tools/probe-mangabz-images.js`
- Read: `tools/probe-mangabz-page.js`

- [ ] Run `node tools/probe-mangabz.js`.
- [ ] Run `node tools/probe-mangabz-images.js`.
- [ ] Run `node tools/probe-mangabz-page.js`.
- [ ] If the probes expose direct image URLs or a simple AJAX API, implement `MangabzComicSource`.
- [ ] If probes still require WebView execution, defer `mangabz` and move to Task 2.

### Task 2: Verify mkzhan Full Chain

**Files:**
- Read: `tools/probe-mkzhan.js`

- [ ] Run `node tools/probe-mkzhan.js`.
- [ ] Confirm search result, detail URL, chapter URL, and image URL extraction.
- [ ] If all steps work, implement `MkzhanComicSource`.
- [ ] If chapter images are not available, stop and report the blocker.

### Task 3: Implement One Verified Source

**Files:**
- Create: `app/src/main/java/com/xxcomic/source/<SourceName>ComicSource.java`
- Modify: `app/src/main/java/com/xxcomic/source/SourceConfig.java`
- Modify: `app/src/main/java/com/xxcomic/MainActivity.java`

- [ ] Add a `ComicSource` implementation for the verified source.
- [ ] Add a `SourceConfig` factory method.
- [ ] Register the source in `MainActivity` source fields, source rebuild, enabled list, source name lookup, source lookup, import/export config, and health check.
- [ ] Run `.\gradlew.bat assembleDebug`.

### Task 4: Verify

**Files:**
- Build output: `app/build/outputs/apk/debug/app-debug.apk`

- [ ] Run source probe again after implementation.
- [ ] Run `.\gradlew.bat assembleDebug`.
- [ ] Report which source was implemented and which source was deferred.
