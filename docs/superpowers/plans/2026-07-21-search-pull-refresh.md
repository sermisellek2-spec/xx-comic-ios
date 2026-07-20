# Search Pull Refresh Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop automatic default-list refresh when returning to the search Tab and add dependency-free pull-to-refresh that preserves the active query and filters.

**Architecture:** Keep the existing `ScrollView` search page. Remove the one-shot cached refresh flag, then add a small pull gesture state machine and a dedicated refresh request mode that keeps old results visible while reusing existing generation and source guards.

**Tech Stack:** Android Java platform Views, `ScrollView`, `ProgressBar`, `MotionEvent`, Node source-contract tests, Gradle.

---

### Task 1: Stop Re-Entry Refresh Flicker

**Files:**
- Modify: `app/src/main/java/com/xxcomic/MainActivity.java`
- Modify: `tools/check-default-search-load.js`

- [ ] **Step 1: Add a failing contract**

Require `showTab()` not to set `defaultSearchRefreshPending`, require the field to be absent, and require `scheduleDefaultSearchLoad()` to return whenever `searchResults` is non-empty.

- [ ] **Step 2: Run RED**

```powershell
node tools/check-default-search-load.js
```

Expected: failure because returning to search currently marks cached results for refresh.

- [ ] **Step 3: Implement the minimum fix**

Delete `defaultSearchRefreshPending` and its assignment. Simplify the scheduling guard to:

```java
if (currentTab != 1 || selectedSource() == null || !searchResults.isEmpty()
        || !TextUtils.isEmpty(searchQuery.trim()) || searchLoading) return;
```

Keep initial empty-list loading unchanged.

- [ ] **Step 4: Run GREEN**

Run `node tools/check-default-search-load.js`; expect exit 0.

### Task 2: Native Pull-To-Refresh

**Files:**
- Modify: `app/src/main/java/com/xxcomic/MainActivity.java`
- Create: `tools/check-search-pull-refresh.js`
- Modify: `tools/check-search-pagination-ui.js`

- [ ] **Step 1: Add failing pull-refresh contracts**

Check for a dedicated `searchRefreshing` state, top-only touch handling, a 72dp trigger, a platform `ProgressBar`, preserved query/source/region/state snapshots, first-page refresh, old-result preservation on failure, generation guards, and cleanup on success/failure/cancel/screen exit.

- [ ] **Step 2: Run RED**

```powershell
node tools/check-search-pull-refresh.js
```

Expected: failure because pull-refresh state and handlers do not exist.

- [ ] **Step 3: Add gesture and indicator state**

Add only the required fields: refresh boolean, pull start Y, pull distance, indicator reference, and a 72dp constant. Bind one `OnTouchListener` to the search `ScrollView`; track downward motion only at `scrollY == 0`, translate the list with a bounded resistance factor, and trigger on release above threshold. Reset translation and state on release/cancel.

- [ ] **Step 4: Add refresh request mode**

Create `refreshCurrentSearch()` that captures current keyword, source, region and state, rejects concurrent search/append/refresh, sets `searchRefreshing`, and requests page 1 with category mode determined by an empty keyword. Extend `loadSearchPage()` minimally so pull refresh does not rebuild to a loading skeleton and failure retains existing results.

- [ ] **Step 5: Complete all terminal paths**

On success replace results and reset paging. On failure keep results, clear indicator/state, log and toast. On new search, filter/source change, Tab switch, cancellation, and activity destruction, reset pull translation and refresh state. Existing generation/source checks remain authoritative.

- [ ] **Step 6: Run GREEN and regressions**

```powershell
node tools/check-search-pull-refresh.js
node tools/check-default-search-load.js
node tools/check-search-pagination-ui.js
node tools/check-search-cancellation.js
node tools/check-navigation-lifecycle.js
node tools/check-main-interactions.js
gradlew.bat :app:assembleDebug
git diff --check
```

Expected: all scripts exit 0, debug APK builds, and diff check is clean.

- [ ] **Step 7: Commit**

Commit only the Java and test files with Chinese message `feat: 添加搜索列表下拉刷新` using the worktree Git message file and separate add/commit commands.
