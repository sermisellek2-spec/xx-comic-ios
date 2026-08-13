# Rem Visual Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the existing Android programmatic UI with the approved compact blue-white anime visual system while preserving every existing search, source, favorite, detail, reader, cache, history, update, import, and export behavior.

**Architecture:** Keep the existing source clients, caches, executors, persistence keys, update flow, and navigation state machine in `MainActivity`. Change only theme tokens, view composition, visual state helpers, and the placement of existing actions. Add source-contract checks because this repository has no JVM test sources, then verify with the existing behavioral checks, a release build, APK signature inspection, and device screenshots when an Android target is available.

**Tech Stack:** Android Java programmatic Views, Gradle/AGP 7.4.2, existing Shimmer dependency, Node.js source-contract checks, Android build-tools, user-supplied PNG assets.

---

### Task 1: Lock The Approved Visual Contract

**Files:**
- Create: `tools/check-rem-visual-contract.js`
- Modify: `docs/superpowers/plans/2026-08-13-rem-visual-redesign.md`

- [ ] **Step 1: Write a failing source-contract check**

Create a Node check that asserts the new blue-white theme values, exactly three bottom tabs (`书架`, `发现`, `设置`), the single borderless `单站`/`全站` search-mode button, Rem state resources, long-press favorite deletion, settings-owned source management, absence of visible secondary-page back buttons, and version `1.0.6` / code `6`.

- [ ] **Step 2: Verify the contract fails against the old UI**

Run: `node tools/check-rem-visual-contract.js`

Expected: FAIL on the first missing blue-white or three-tab assertion.

- [ ] **Step 3: Keep existing behavior checks as the protected baseline**

Run the applicable checks individually, including navigation, reader generation/memory/position/prefetch, search cancellation/grid/pagination/pull-refresh, source category generation, cache policy/threading, favorite order, reading-history semantics, and launcher resources.

Expected: all selected baseline checks pass before production edits; scripts requiring fixtures or containing stale version/source-count assertions are excluded and documented.

### Task 2: Apply The Blue-White Visual System And Rem States

**Files:**
- Modify: `app/src/main/java/com/xxcomic/UIHelpers.java`
- Modify: `app/src/main/java/com/xxcomic/MainActivity.java`
- Add: `app/src/main/res/drawable-nodpi/rem_loading.png`
- Add: `app/src/main/res/drawable-nodpi/rem_error.png`
- Add: `app/src/main/res/drawable-nodpi/rem_empty.png`
- Add: `app/src/main/res/drawable-nodpi/rem_reader_boundary.png`
- Add: `app/src/main/res/drawable-nodpi/rem_reader_resume.png`

- [ ] **Step 1: Replace day/night tokens**

Use a white/ice-blue day palette and a neutral charcoal/blue night palette. Keep existing public token names so all current callers continue to compile. Restrict card radii to 8dp and reduce elevation and vertical padding for the approved compact density.

- [ ] **Step 2: Add reusable Rem state views**

Implement one shared state builder for loading, error, empty, reader boundary, and reader resume states. It accepts an image resource, one short title, optional compact description, and optional action; it must not add a back button.

- [ ] **Step 3: Replace skeleton-only and text-only full states**

Use `rem_loading`, `rem_error`, and `rem_empty` for page and local drawer states while retaining current retry callbacks and async cancellation guards.

- [ ] **Step 4: Verify the contract progresses**

Run: `node tools/check-rem-visual-contract.js`

Expected: theme and resource assertions pass; later navigation/page assertions still fail.

### Task 3: Implement The Three Primary Screens

**Files:**
- Modify: `app/src/main/java/com/xxcomic/MainActivity.java`
- Modify: `tools/check-main-interactions.js`
- Modify: `tools/check-android-source.js`

- [ ] **Step 1: Re-map primary navigation without changing stored data**

Render exactly three tabs: `书架` -> favorites, `发现` -> the combined single/global search page, and `设置` -> local preferences. Remove sources and profile from bottom navigation; expose source management from settings. Update tab indices and internal back routing consistently.

- [ ] **Step 2: Rebuild the bookshelf states**

Keep cover/title/progress opening behavior. Replace swipe/overflow deletion with long-press selection, a cover scrim, and a trash icon; tapping the trash keeps the existing confirmation and deletion semantics. Use the Rem empty state when no favorites exist.

- [ ] **Step 3: Rebuild discovery initial and result states**

Place a single borderless text button inside the search row, showing the alternate/current mode consistently and toggling between `单站` and `全站`. Single-site mode initially loads the first enabled source list. Global mode initially shows compact recent-search words and hides them after a keyboard Search action. Results contain only cover and title.

- [ ] **Step 4: Make source/category rows compact and horizontally scrollable**

Use single-line horizontal scrolling for available sources and categories. Keep source/filter pickers in right drawers; render filter options in three columns and preserve current category-generation rollback behavior.

- [ ] **Step 5: Rebuild settings and source management**

Settings contains theme, handedness, history, source management, cache, logs, update, and about. Source management exposes only enable/disable, availability check, import, and export; do not render add-source/custom-source entry points. Secondary screens have no visible back icon.

- [ ] **Step 6: Verify primary-screen contracts and existing behaviors**

Run the new visual contract and all search/navigation/source/favorite/history checks. Expected: PASS.

### Task 4: Implement Compact Detail, Async Chapter Drawer, And Reader States

**Files:**
- Modify: `app/src/main/java/com/xxcomic/MainActivity.java`

- [ ] **Step 1: Recompose detail mode B**

Use the approved compact cover/header layout, compact metadata/tags, favorite action, and a single continue/start-reading command. Remove visible play and back buttons. Keep cached-detail refresh and retirement behavior unchanged.

- [ ] **Step 2: Keep chapters asynchronous in the right drawer**

Opening the catalog immediately shows a Rem loading state while existing chapter parsing runs. On success show compact chapter rows in the existing batches; on failure keep the error and retry inside the drawer instead of replacing the detail page.

- [ ] **Step 3: Recompose reader controls without changing image loading**

Retain list paging, sampled decode, cache writes, prefetch, generation guards, touch areas, handedness, position saving, and fullscreen. Remove any chapter-end page. Right/left boundary taps switch chapters; the final chapter shows the Rem boundary light prompt. Restored positions show the Rem resume light prompt.

- [ ] **Step 4: Verify reader contracts**

Run reader generation, memory, position, prefetch, navigation lifecycle, reading-history semantics, and the new visual contract. Expected: PASS.

### Task 5: Version, Build, Install, And Visual QA

**Files:**
- Modify: `app/build.gradle`
- Create outside Git: `.worktrees/artifacts/xx-comic-1.0.6-release.apk`
- Create outside Git: `.worktrees/artifacts/android-release.json`

- [ ] **Step 1: Increment the release**

Set `versionCode 6` and `versionName "1.0.6"` without changing package id or signing configuration.

- [ ] **Step 2: Run the complete applicable verification set**

Run: `git diff --check`, the selected Node checks, and `./gradlew.bat :app:testReleaseUnitTest :app:assembleRelease --no-daemon`.

Expected: every selected check passes and Gradle exits 0.

- [ ] **Step 3: Verify APK identity and signature**

Use the newest SDK `aapt2`/`apkanalyzer` available to confirm package `com.xxcomic`, version 6 / 1.0.6, then run `apksigner verify --verbose --print-certs`.

- [ ] **Step 4: Install and visually inspect when a target is available**

Install with `adb install -r`, capture bookshelf/discovery/settings/detail/reader and Rem-state screenshots, and compare density, spacing, colors, clipping, and navigation with the approved HTML atlas. If no device or AVD is available, record that limitation explicitly instead of claiming screenshot verification.

- [ ] **Step 5: Generate immutable release artifacts**

Copy the APK to `.worktrees/artifacts/xx-comic-1.0.6-release.apk`, calculate byte size and SHA-256, and generate `android-release.json` with `versionName`, `versionCode`, `size`, and lowercase `sha256`.

### Task 6: Commit, Push, And Publish COS Update

**Files:**
- Commit only approved source, resource, plan, and check files
- Publish outside Git: `xx-comic.apk` and `android-release.json`

- [ ] **Step 1: Review and stage exact paths**

Confirm no `.gradle/**`, old `release/**`, private credentials, or unrelated user files are staged. Stage only the visual implementation, five PNGs, tests, version, and plan.

- [ ] **Step 2: Commit and push**

Commit on `codex/rem-visual-redesign`, merge the verified commit into `master` as authorized by the user's direct request, rerun the release build on the merged result, and push `master` to `origin` without force.

- [ ] **Step 3: Upload both update objects**

Use environment-provided COS credentials only. Upload APK to `xx-comic/releases/xx-comic.apk` and metadata to `xx-comic/releases/android-release.json` with `no-cache` and the APK SHA-256 metadata. Do not delete unrelated COS objects.

- [ ] **Step 4: Verify the public release**

Fetch both public URLs with cache-busting query strings. Confirm metadata is version 1.0.6/code 6 and that downloaded APK byte size and SHA-256 equal the local artifact.

---

## Self-Review

- Spec coverage: all approved bookshelf, discovery, detail, reader, settings, global state, navigation, no-login, and source-management constraints map to Tasks 2-4.
- Behavior protection: source parsing and data/persistence/update contracts are explicitly unchanged and covered by existing checks.
- Release coverage: versioning, build, signature, artifact metadata, push, COS upload, and public checksum verification map to Tasks 5-6.
- Placeholder scan: no deferred implementation placeholders remain.
- Scope control: no new dependency, page architecture, account feature, custom source editor, or unrelated refactor is included.
