# MainActivity Stability Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Complete the approved 13 stability fixes without new dependencies or unrelated refactoring.

**Architecture:** Keep `MainActivity` as the existing owner, but make page navigation explicit, gate asynchronous UI commits with request identity, confine shared comic maps to the main thread, serialize immutable cache snapshots, and virtualize reader images with a platform `ListView`. Preserve current storage formats and source APIs.

**Tech Stack:** Android Java, platform Views/Handlers/Executors/SharedPreferences, Node source-contract scripts, Gradle Android build.

---

### Task 1: Async Navigation And Request Isolation

**Files:**
- Modify: `app/src/main/java/com/xxcomic/MainActivity.java`
- Create: `tools/check-navigation-lifecycle.js`
- Create: `tools/check-reader-generation.js`
- Create: `tools/check-source-category-generation.js`

- [ ] **Step 1: Write failing contract checks**

Add Node checks that assert: loading pages store a `Runnable` back action; loading back invalidates the generation and executes that action; four toolbar back buttons call `navigateBack()`; empty/error chapter-directory paths restore detail and expose retry; `readerGeneration` increments in `enterScreen()` and chapter callbacks validate generation, comic ID, chapter URL, and visibility; `categoryGeneration` plus source ID are checked before category mutations.

- [ ] **Step 2: Verify RED**

Run:

```powershell
node tools/check-navigation-lifecycle.js
node tools/check-reader-generation.js
node tools/check-source-category-generation.js
```

Expected: each new script fails because the required fields/guards/actions are absent.

- [ ] **Step 3: Implement explicit loading navigation**

Replace `pageLoadingReturnTab` with `Runnable pageLoadingBackAction`. Change the loading API to:

```java
private int showPageLoading(String title, String desc, Runnable backAction) {
    pageLoading = true;
    pageLoadingBackAction = backAction;
    int generation = ++pageLoadingGeneration;
    // existing loading rendering
    return generation;
}
```

In `navigateBack()`, clear loading state/action, invalidate the generation, call `enterScreen()` to cancel tracked work, then run the captured action. Capture the caller's list/search state before assigning `activeDetailId` for first-detail loading. Chapter-directory loading passes `() -> showDetail(comicId)`. Clear stale actions on success and error.

- [ ] **Step 4: Implement reader and category guards**

Add `readerGeneration` and increment it in `enterScreen()`. Before a chapter request capture:

```java
int generation = readerGeneration;
String comicId = detail.summary.comicId;
String chapterUrl = chapter.url;
```

Create one predicate that requires matching generation, `readerVisible`, matching `activeDetailId`, a valid current chapter index, and matching chapter URL. Apply it before both success and failure UI commits. Compute expected cancellation on the worker thread and suppress cancelled/stale errors.

Add `categoryGeneration`; capture it and `selectedSourceId` in `loadSourceCategories()`, and check both before clearing or adding categories.

- [ ] **Step 5: Restore detail before empty/error chapter prompts**

For empty chapter lists and exceptions, first call `showDetail(comicId)`, then show the existing styled dialog with a retry action that invokes the same `ensureChaptersThen(detail, action)` operation. Stale loading callbacks do nothing.

- [ ] **Step 6: Unify toolbar return handlers**

Change full-site search, detail, reader, and history toolbar back listeners to call `navigateBack()`. Preserve the established order reader -> detail -> original search result -> search input -> favorites.

- [ ] **Step 7: Verify GREEN and regressions**

Run the three new scripts plus:

```powershell
node tools/check-search-cancellation.js
node tools/check-default-search-load.js
gradlew.bat :app:compileDebugJavaWithJavac
```

Expected: all scripts exit 0 and Java compilation succeeds.

- [ ] **Step 8: Commit**

Commit only Task 1 files with Chinese message `fix: 修正异步导航和请求竞态` using `.git/COMMIT_MSG` and separate `git add` / `git commit -F` calls.

### Task 2: Cache Refresh, Thread Ownership, And Data Semantics

**Files:**
- Modify: `app/src/main/java/com/xxcomic/MainActivity.java`
- Create: `tools/check-comic-cache-refresh.js`
- Create: `tools/check-comic-cache-threading.js`
- Create: `tools/check-reading-history-semantics.js`

- [ ] **Step 1: Write failing contract checks**

Assert that cached detail renders before a once-per-process refresh; refreshing/finished sets prevent duplicate refresh; worker blocks do not mutate `summaries`, `details`, or `chapters`; all persistence entry points snapshot on main and enqueue to `miscIo`; no synchronous cache writer can overtake queued snapshots; reading progress is committed only after a non-empty chapter page; favorite removal preserves progress, reader positions, and last-viewed time.

- [ ] **Step 2: Verify RED**

Run the three new scripts. Expected: failures identify permanent cache hits, worker-thread map writes, direct persistence, early history writes, and destructive favorite removal.

- [ ] **Step 3: Add once-per-process refresh**

Add main-thread-only `refreshedComicIds` and `refreshingComicIds`. Cached `showDetail()` renders immediately and schedules one background refresh. Fetch current detail and, when needed, its chapters through the source API. On main, atomically update `details` and `summaries`, mark refresh complete, persist a snapshot, and rerender only when the same detail remains visible. On failure retain cache and mark the automatic attempt complete for this process.

- [ ] **Step 4: Confine maps and serialize snapshots**

Move every network-result `put/remove/clear` for the three comic maps into its `main.post()` callback. Replace direct `persistComicCaches()` calls with a single method that must be called on main, copies all three map values, and enqueues JSON serialization/writing on the single-thread `miscIo`. Keep restore-time mutation on the main thread. Do not introduce concurrent collections or new executors.

- [ ] **Step 5: Correct reading and favorite semantics**

Introduce a small existing-style method that records chapter index and last-viewed time only after a valid non-empty page passes the reader guard. Call it for both cache hits and successful network pages. Make `deleteFavorite()`, cancellation in `toggleFavorite()`, and duplicate-favorite replacement remove only favorite state and `favoriteAt`.

- [ ] **Step 6: Verify GREEN and regressions**

Run the three new scripts, all pre-existing cache/favorite/reader scripts, and `gradlew.bat :app:compileDebugJavaWithJavac`. Expected: exit 0.

- [ ] **Step 7: Commit**

Commit Task 2 files with `fix: 刷新漫画缓存并统一数据线程`.

### Task 3: Virtualized Reader Images

**Files:**
- Modify: `app/src/main/java/com/xxcomic/MainActivity.java`
- Modify: `tools/check-reader-position.js`
- Create: `tools/check-reader-memory.js`

- [ ] **Step 1: Write failing reader contracts**

Assert that `renderReader()` uses `ListView` plus `BaseAdapter`, no longer creates one `ImageView` per URL, reader images bypass `imageMemoryCache`, sampled decode targets screen width, recycled views carry URL tags, callbacks validate URL and reader generation, and reader position uses first visible item plus child offset.

- [ ] **Step 2: Verify RED**

Run both reader scripts. Expected: failure because the reader still uses `ScrollView + LinearLayout` and shared full-size image loading.

- [ ] **Step 3: Replace reader page container**

Create an inline/private `BaseAdapter` matching existing single-file style. Each row reuses or creates one `ImageView`, clears its drawable, assigns the URL tag, and sets a non-zero placeholder height based on screen width so zero-height rows cannot defeat `ListView` virtualization. Remove dividers and keep the dark reader background.

- [ ] **Step 4: Add sampled reader loading**

Reuse disk cache paths and HTTP headers, but create `loadReaderImage()` that never reads or writes `imageMemoryCache`. Decode bounds first, compute a power-of-two `inSampleSize` for display width, decode the bitmap, then on main verify generation and URL tag before updating row height from aspect ratio and assigning the bitmap.

- [ ] **Step 5: Adapt position persistence**

Encode position from `firstVisiblePosition`, first child top/height, and item count into the existing 0..10000 range. Restore with `setSelectionFromTop()`. Debounce saves with the existing 250 ms policy. Do not migrate or clear stored positions.

- [ ] **Step 6: Verify GREEN and build**

Run reader scripts, `node tools/check-search-cancellation.js`, and `gradlew.bat :app:assembleDebug`. Expected: exit 0 and debug APK assembled.

- [ ] **Step 7: Commit**

Commit Task 3 files with `perf: 限制阅读器图片内存`.

### Task 4: Low-Cost Interaction Fixes

**Files:**
- Modify: `app/src/main/java/com/xxcomic/MainActivity.java`
- Modify: `app/src/main/AndroidManifest.xml`
- Modify: `tools/check-search-pagination-ui.js`
- Create: `tools/check-main-interactions.js`

- [ ] **Step 1: Write failing contracts**

Assert that append failure leaves `searchHasMore` unchanged, replaces the loading footer with a clickable retry state for the same page, and prevents automatic retry loops; current-tab taps return before `showTab()`; source menu and source cards no longer expose custom source UI while import/export storage remains; Manifest uses `adjustResize` and Java no longer overrides it.

- [ ] **Step 2: Verify RED**

Run the modified/new scripts. Expected: failure on each absent interaction.

- [ ] **Step 3: Implement append retry state**

Add `searchAppendFailed`. Reset it on paging reset/start/success. On append failure set the flag, preserve `searchHasMore`, and immediately rerender the footer as a clickable retry row. `loadNextSearchPage()` returns while failed; the footer click directly retries `searchPage + 1` and clears the flag.

- [ ] **Step 4: Implement remaining interaction changes**

Return immediately when a bottom-nav click targets `currentTab`. Remove the add-source menu item and custom source card rendering only; retain methods/data/import/export. Change Manifest to `adjustResize` and remove `SOFT_INPUT_ADJUST_NOTHING` from `onCreate()`.

- [ ] **Step 5: Verify GREEN and full regression**

Run every `tools/check-*.js` contract that does not require live network, then:

```powershell
gradlew.bat :app:assembleDebug
git diff --check
```

Expected: scripts exit 0, build succeeds, and diff check is empty.

- [ ] **Step 6: Commit**

Commit Task 4 files with `fix: 完善搜索和输入交互`.

### Task 5: Final Review And Evidence

**Files:**
- Review all files changed since the approved design commit.

- [ ] **Step 1: Spec compliance review**

Check all 13 requirements against the implementation and identify missing or extra behavior. Fix Critical/Important gaps through the responsible implementer and re-review.

- [ ] **Step 2: Code quality review**

Review request identity, cancellation, main-thread ownership, snapshot ordering, bitmap lifetime, adapter recycling, and navigation state. Fix Critical/Important findings and re-review.

- [ ] **Step 3: Fresh verification**

Run the full non-network script suite, `gradlew.bat :app:assembleDebug`, `git diff --check`, and `git status --short`. Record exact pass/fail evidence and any true device-only residual checks.
