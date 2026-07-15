# Progressive Search List Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Always fetch fresh search/category metadata, render cards immediately after the response, and load covers progressively without blocking on cache persistence.

**Architecture:** Remove the persisted ordered default-list snapshot. Keep the existing asynchronous image loader and placeholder frames. Move expensive JSON serialization and cache-size scanning off the UI path after search results have rendered.

**Tech Stack:** Android Java, native Views, `ExecutorService`, `SharedPreferences`, Node regression scripts.

---

### Task 1: Remove stale default-list snapshots

**Files:**
- Modify: `app/src/main/java/com/xxcomic/MainActivity.java`
- Modify: `tools/check-default-search-cache.js`

- [ ] Replace the cache test with assertions that no `DEFAULT_LISTS_CACHE_KEY`, restore, or persist helper remains.
- [ ] Run `node tools/check-default-search-cache.js` and verify it fails before production changes.
- [ ] Remove the default-list key, state, restore/persist helpers, and clear-cache accounting.

### Task 2: Render before persistence

**Files:**
- Modify: `app/src/main/java/com/xxcomic/MainActivity.java`
- Modify: `tools/check-default-search-cache.js`

- [ ] Assert that `loadSearchPage` renders with `showTab(1, false)` before async persistence.
- [ ] Snapshot cache collections on the main thread and serialize them on `miscIo`.
- [ ] Keep `coverFrame` and `loadImage` unchanged so every card displays a stable placeholder while images load on `imageIo`.

### Task 3: Verify

**Files:**
- Test: `tools/check-default-search-cache.js`
- Test: `tools/check-default-search-load.js`
- Test: `tools/check-search-cancellation.js`
- Test: `tools/check-manben-source.js`
- Test: `tools/check-favorite-order.js`

- [ ] Run all Node regression scripts.
- [ ] Run `git diff --check`.
- [ ] Run `.\gradlew.bat assembleDebug --no-daemon` and verify `BUILD SUCCESSFUL`.
