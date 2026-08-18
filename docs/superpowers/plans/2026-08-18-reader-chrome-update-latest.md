# Reader Chrome And Latest Update Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make reader immersion chrome fade out softly and remove the reinstall action when the installed version is already current.

**Architecture:** Keep the existing reader chrome state machine and update state flow. Adjust only the shared reader chrome animation timing/easing and the latest-version scene composition; do not change reader gestures, chapter navigation, download verification, or installation behavior.

**Tech Stack:** Android Java `ViewPropertyAnimator`, existing `MainActivity`, Gradle release build, Node source contracts, Tencent COS release flow.

---

### Task 1: Soften immersion chrome transitions

**Files:**
- Modify: `app/src/main/java/com/xxcomic/MainActivity.java`
- Test: `tools/check-detail-release.js`

- [x] **Step 1: Extend the shared chrome animation constants**

Use one longer duration and a shorter fade-only settle phase. Keep the existing 6dp travel distance so the chrome does not jump across the page.

- [x] **Step 2: Update `animateReaderChrome()`**

Cancel the previous animation, make the view visible before showing it, then animate alpha and translation with `AccelerateDecelerateInterpolator`. Keep the end-action visibility guard for the hidden state.

- [x] **Step 3: Add a source contract for the soft transition**

Assert the interpolator, duration constant, and hidden-state end action are present in `tools/check-detail-release.js`.

### Task 2: Remove reinstall action from the latest-version scene

**Files:**
- Modify: `app/src/main/java/com/xxcomic/MainActivity.java`
- Modify: `app/build.gradle`
- Modify: `tools/check-detail-release.js`
- Modify: `tools/check-cuimh-source.js`
- Modify: `tools/check-rem-visual-contract.js`

- [x] **Step 1: Simplify `showUpdateLatest()`**

Render only the Rem latest-version state. Do not add a bottom action row or call `startUpdateDownload()` from this scene.

- [x] **Step 2: Increment the release identity**

Set `versionCode 52` and `versionName "1.0.52"`, then update the three release contracts.

### Task 3: Verify, publish, and synchronize public artifacts

**Files:**
- Create outside Git: `release/xx-comic-1.0.52.apk`
- Create outside Git: `release/android-release-1.0.52.json`

- [x] **Step 1: Run contracts and release tests**

Run `node tools/check-detail-release.js`, `node tools/check-cuimh-source.js`, `node tools/check-rem-visual-contract.js`, `node tools/check-dialog-toast-contract.js`, `.\gradlew.bat :app:testReleaseUnitTest`, and `.\gradlew.bat :app:assembleRelease --no-daemon --console=plain`.

- [x] **Step 2: Verify the APK identity and checksum**

Require package `com.xxcomic`, version `1.0.52 (52)`, a valid v1/v2 signature, and matching local metadata.

- [ ] **Step 3: Commit and push scoped source changes**

Stage only the Java, Gradle, contract, and plan files. Exclude `.gradle/`, `.gradle-codex/`, `app/build/`, and `release/`; commit on `master` and push without force.

- [ ] **Step 4: Publish and verify COS plus server fallback**

Upload the exact APK to `apk/xx-comic/xx-comic.bin`, update the server fallback APK and metadata, then download all public artifacts and compare size and SHA-256 with the local release artifact.
