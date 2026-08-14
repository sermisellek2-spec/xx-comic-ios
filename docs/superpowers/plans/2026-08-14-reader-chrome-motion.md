# Reader Chrome Motion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make reader controls fade and move gently without resizing comic content.

**Architecture:** Keep the existing reader state and gesture handlers. Recompose only the completed reader screen as a full-screen `FrameLayout`, render the top/bottom controls as overlays, and animate their alpha/translation while maintaining stable system-bar layout flags.

**Tech Stack:** Android Java programmatic views, platform `ViewPropertyAnimator`, Gradle/AGP 7.4.2.

---

### Task 1: Stabilize Reader Layout

**Files:**
- Modify: `app/src/main/java/com/xxcomic/MainActivity.java`

- [ ] **Step 1: Keep the reader decor in a stable full-screen layout**

Add a stable-layout variant of `applyReaderSystemBars` that always applies `LAYOUT_FULLSCREEN`, `LAYOUT_HIDE_NAVIGATION`, and `LAYOUT_STABLE`, then adds the existing immersive flags only when `readerFullscreen` is true.

- [ ] **Step 2: Convert completed reader content to an overlay composition**

Use a `FrameLayout` shell with the comic list filling the frame. Position the toolbar below the status-bar inset and the reading counter above the navigation-bar inset. Keep the chapter progress line independently anchored so it remains visible in both modes.

### Task 2: Add Soft Control Motion

**Files:**
- Modify: `app/src/main/java/com/xxcomic/MainActivity.java`

- [ ] **Step 1: Initialize controls without layout changes**

Use `VISIBLE` or `INVISIBLE`, alpha, and a 6 dp translation for initial control state. Do not use `GONE` for reader chrome.

- [ ] **Step 2: Animate center-tap transitions**

Cancel any in-flight control animations, make controls visible before showing, and animate to the target alpha/translation over 180 ms. Guard the hide completion against rapid repeated taps.

- [ ] **Step 3: Preserve progress-line placement**

Animate the progress line between the physical screen bottom in immersive mode and the area immediately above the visible bottom controls.

### Task 3: Package Release 1.0.18

**Files:**
- Modify: `app/build.gradle`
- Modify: `tools/check-rem-visual-contract.js`

- [ ] **Step 1: Increment release identity**

Set `versionCode 18`, `versionName "1.0.18"`, and update the existing release assertions.

- [ ] **Step 2: Build without running tests**

Run `./gradlew.bat :app:assembleRelease --no-daemon` and require `BUILD SUCCESSFUL`.

- [ ] **Step 3: Verify and publish**

Verify package `com.xxcomic`, version `1.0.18 (18)`, signature, size, and SHA-256. Commit only scoped source/docs, push `master`, then update COS `apk/xx-comic/xx-comic.bin`, server metadata, fallback APK, and the download filename. Pull both public APKs back and compare them with the local artifact.

## Self-Review

- Spec coverage: stable content geometry, overlay chrome, 180 ms fade, 6 dp movement, progress visibility, and unchanged gestures are all mapped above.
- Scope: no parser, cache, chapter, persistence, drawer, or unrelated screen changes.
- Verification: automated tests are intentionally omitted per user instruction; release build and artifact/publication integrity checks remain required.
