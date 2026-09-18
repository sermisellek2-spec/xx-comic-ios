# Offline Range Download and Safe Concurrency Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let users select a 1-based chapter range in the existing offline-download sheet, and speed up bulk downloads with bounded chapter concurrency and source-level 503/429 backoff.

**Architecture:** Keep the current chapter identity, selection set, queue persistence, local publishing, and reader paths. Add a pure range-selection helper for the UI; replace the single active worker lease with a bounded pool of two chapter workers; add a source-scoped request gate that spaces requests and enters exponential cooldown after 503/429 without blocking other sources.

**Tech Stack:** Android Java, JUnit 4, `HttpURLConnection`, existing SQLite-backed `DownloadStore`, `DownloadCoordinator`, `DownloadRuntime`, and native themed views.

**Spec:** Existing approved design in the conversation; preserve `docs/superpowers/specs/2026-09-18-batch-local-import-design.md` boundaries and current download/local-library contracts.

## Global Constraints

- Preserve single-chapter, select-all, clear, reverse-order, pause, resume, cancel, recovery, and already-downloaded skip behavior.
- Range inputs are 1-based positions in the current visible chapter order, not parsed title numbers.
- Default maximum active chapter tasks is 2; file-source tasks remain serialized with chapter work through the same global cap.
- Requests for the same source are spaced and cooled after 503/429; other sources continue independently.
- Do not bypass source protection, ignore `Retry-After`, or weaken existing URL/content validation.
- Add regression tests before production changes and run the existing unit-test suite before completion.

---

### Task 1: Pure range selection helper

**Files:**
- Create: `app/src/main/java/com/xxcomic/download/ChapterRangeSelection.java`
- Test: `app/src/test/java/com/xxcomic/download/ChapterRangeSelectionTest.java`

**Interfaces:**
- Produces `public static <T> List<T> select(List<T> visible, int startInclusive1Based, int endInclusive1Based)`.
- Invalid or empty ranges return an empty list; bounds are clamped to the visible list and reversed endpoints are normalized.

- [ ] **Step 1: Write the failing tests**

```java
@Test public void selectsInclusiveOneBasedRange() {
    assertEquals(Arrays.asList("c2", "c3", "c4"),
            ChapterRangeSelection.select(Arrays.asList("c1", "c2", "c3", "c4", "c5"), 2, 4));
}
@Test public void normalizesReverseAndClampsBounds() {
    assertEquals(Arrays.asList("c1", "c2", "c3"),
            ChapterRangeSelection.select(Arrays.asList("c1", "c2", "c3"), 9, 0));
}
@Test public void emptyListOrZeroRangeReturnsEmpty() {
    assertTrue(ChapterRangeSelection.select(Collections.<String>emptyList(), 1, 2).isEmpty());
    assertTrue(ChapterRangeSelection.select(Arrays.asList("c1"), 0, 0).isEmpty());
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `./gradlew.bat --no-daemon --project-cache-dir .gradle-codex/range-download :app:testDebugUnitTest --tests com.xxcomic.download.ChapterRangeSelectionTest`

Expected: FAIL because `ChapterRangeSelection` does not exist.

- [ ] **Step 3: Write the minimal implementation**

```java
public final class ChapterRangeSelection {
    private ChapterRangeSelection() {}
    public static <T> List<T> select(List<T> visible, int start, int end) {
        if (visible == null || visible.isEmpty() || start <= 0 || end <= 0) return Collections.emptyList();
        int low = Math.max(1, Math.min(start, end));
        int high = Math.min(visible.size(), Math.max(start, end));
        if (low > high) return Collections.emptyList();
        return new ArrayList<>(visible.subList(low - 1, high));
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run the same Gradle test command; expected: PASS.

- [ ] **Step 5: Commit**

```powershell
git add app/src/main/java/com/xxcomic/download/ChapterRangeSelection.java app/src/test/java/com/xxcomic/download/ChapterRangeSelectionTest.java
git commit -m "test(download): define chapter range selection"
```

### Task 2: Add range action to the existing download sheet

**Files:**
- Modify: `app/src/main/java/com/xxcomic/download/DownloadViews.java` in `selection(...)`.

**Interfaces:**
- Consumes `ChapterRangeSelection.select(...)` and the existing `visible`, `selected`, `adapter`, and `start` state.
- Produces a native themed range dialog that updates the existing selected-count button without creating a second download flow.

- [ ] **Step 1: Add a UI regression seam**

Add a package-private formatter/validator method in `DownloadViews` only if needed by the existing JVM tests; keep Android dialog creation out of the pure helper. The behavior to assert is that a valid range replaces the current selection with the matching chapter IDs and an invalid range leaves the selection unchanged.

- [ ] **Step 2: Run the focused range tests**

Run: `./gradlew.bat --no-daemon --project-cache-dir .gradle-codex/range-download :app:testDebugUnitTest --tests com.xxcomic.download.ChapterRangeSelectionTest`

Expected: PASS before UI wiring.

- [ ] **Step 3: Implement the UI wiring**

Add a compact `区间` tool beside the existing chips. The dialog contains two numeric text fields labeled `起始序号` and `结束序号`, a preview count, `取消`, and `选中` actions. On confirmation, call `ChapterRangeSelection.select(visible, start, end)`, clear `selected`, add each selected chapter ID, update the existing button text, and call `adapter.notifyDataSetChanged()`.

- [ ] **Step 4: Verify compilation and focused tests**

Run the focused Gradle test command and `:app:compileDebugJavaWithJavac`; expected: PASS.

- [ ] **Step 5: Commit**

```powershell
git add app/src/main/java/com/xxcomic/download/DownloadViews.java
git commit -m "feat(download): select a chapter range from the download sheet"
```

### Task 3: Source-scoped request gate and cooldown

**Files:**
- Create: `app/src/main/java/com/xxcomic/download/SourceRequestGate.java`
- Test: `app/src/test/java/com/xxcomic/download/SourceRequestGateTest.java`
- Modify: `app/src/main/java/com/xxcomic/download/SourceImageFetcher.java`

**Interfaces:**
- `SourceRequestGate.before(String sourceId) throws InterruptedIOException` blocks until the source's next allowed request time or the calling thread is interrupted.
- `SourceRequestGate.onSuccess(String sourceId)` reduces an elevated delay after successful requests.
- `SourceRequestGate.onFailure(String sourceId, int status, long retryAfterMillis)` applies no cooldown for unrelated statuses, and applies bounded exponential cooldown for 429/503 using `Retry-After` when present.
- `SourceImageFetcher.fetch(...)` receives an optional gate/source ID through an overload while preserving the existing signature for tests and callers that do not have a source ID.

- [ ] **Step 1: Write failing gate tests**

Cover: same-source spacing, different-source independence, 503 cooldown, `Retry-After` taking precedence, and cooldown cap.

- [ ] **Step 2: Run the gate tests to verify failure**

Run: `./gradlew.bat --no-daemon --project-cache-dir .gradle-codex/range-download :app:testDebugUnitTest --tests com.xxcomic.download.SourceRequestGateTest`

Expected: FAIL because the gate does not exist.

- [ ] **Step 3: Implement the minimal gate**

Use a synchronized map keyed by source ID, monotonic elapsed time, an initial 350ms interval, a maximum 2-minute cooldown, and a per-source consecutive-throttle counter. `before` sleeps only the remaining interval/cooldown and exits on interruption. Successful requests reset the throttle counter after the gate has observed a normal response.

- [ ] **Step 4: Integrate fetch status reporting**

Before opening an image request, call `before(sourceId)`. After a 200 response call `onSuccess`; on `HttpFailure` call `onFailure` with its status and retry delay, then rethrow. Keep all content validation and redirect behavior unchanged.

- [ ] **Step 5: Run focused gate and fetch tests**

Run the two focused test classes; expected: PASS.

- [ ] **Step 6: Commit**

```powershell
git add app/src/main/java/com/xxcomic/download/SourceRequestGate.java app/src/main/java/com/xxcomic/download/SourceImageFetcher.java app/src/test/java/com/xxcomic/download/SourceRequestGateTest.java
git commit -m "feat(download): throttle requests per source and back off on 503"
```

### Task 4: Bounded chapter worker pool

**Files:**
- Modify: `app/src/main/java/com/xxcomic/download/DownloadRuntime.java`
- Modify: `app/src/main/java/com/xxcomic/download/DownloadCoordinator.java`
- Modify: `app/src/test/java/com/xxcomic/download/DownloadCoordinatorTest.java`

**Interfaces:**
- `DownloadCoordinator.claim(...)` accepts a source-active snapshot and a global active count, and never claims more than two total tasks or two tasks from one source.
- `DownloadRuntime.kick()` fills available worker slots instead of refusing work while one task is active.

- [ ] **Step 1: Write failing coordinator tests**

Add tests proving two different tasks can be leased, a third total task is rejected, and a third task from the same source is rejected while another source remains claimable.

- [ ] **Step 2: Run coordinator tests to verify failure**

Run: `./gradlew.bat --no-daemon --project-cache-dir .gradle-codex/range-download :app:testDebugUnitTest --tests com.xxcomic.download.DownloadCoordinatorTest`

Expected: FAIL against the current single-lease signature/behavior.

- [ ] **Step 3: Implement bounded claims**

Keep the repository synchronized. Add `MAX_ACTIVE_CHAPTERS = 2`; count active leases from the store; skip candidates whose source already has two active tasks. Preserve queue ordering, retry timestamps, network gating, verification gating, and generation checks.

- [ ] **Step 4: Implement the runtime pool**

Replace the single-thread `worker` with a fixed pool of two threads and track active leases by task ID/source. `kick()` repeatedly claims until the pool is full, submits each task, and removes it from tracking in a `finally` block. `stopWorker()` invalidates all active leases through the existing queue state transition.

- [ ] **Step 5: Connect the request gate to chapter image downloads**

Pass `task.sourceId` into every image and cover fetch. Do not parallelize pages within a chapter.

- [ ] **Step 6: Run coordinator tests and the complete unit suite**

Run: `./gradlew.bat --no-daemon --project-cache-dir .gradle-codex/range-download :app:testDebugUnitTest`

Expected: all existing and new tests PASS.

- [ ] **Step 7: Commit**

```powershell
git add app/src/main/java/com/xxcomic/download/DownloadRuntime.java app/src/main/java/com/xxcomic/download/DownloadCoordinator.java app/src/test/java/com/xxcomic/download/DownloadCoordinatorTest.java
git commit -m "feat(download): run two bounded chapter workers"
```

### Task 5: Notification and recovery verification

**Files:**
- Modify: `app/src/main/java/com/xxcomic/download/DownloadService.java`
- Modify: `app/src/main/java/com/xxcomic/download/DownloadViews.java`
- Test: `app/src/test/java/com/xxcomic/download/DownloadCoordinatorTest.java`

**Interfaces:**
- Existing service tick continues to call `runtime.kick()` and reports any active task; no new UI navigation is introduced.
- Download center maps queued/cooling tasks to the existing waiting state and preserves manual retry.

- [ ] **Step 1: Add cooldown-state regression coverage**

Assert that a 503 delay affects queued tasks from the same source but not tasks from another source, and that recovery requeues interrupted active tasks without changing paused or completed tasks.

- [ ] **Step 2: Implement status text updates**

Use the existing notification/download-center text path to show `站源冷却中，稍后自动重试` when no task can be claimed because of a source cooldown. Keep user-facing error text free of URLs and credentials.

- [ ] **Step 3: Run full verification**

Run:

```powershell
./gradlew.bat --no-daemon --project-cache-dir .gradle-codex/range-download :app:testDebugUnitTest :app:assembleDebug
```

Expected: all tests PASS and debug APK builds successfully.

- [ ] **Step 4: Commit**

```powershell
git add app/src/main/java/com/xxcomic/download/DownloadService.java app/src/main/java/com/xxcomic/download/DownloadViews.java app/src/test/java/com/xxcomic/download/DownloadCoordinatorTest.java
git commit -m "fix(download): expose safe cooldown state during bulk downloads"
```

## Self-Review Checklist

- Range selection covers inclusive positions, reverse endpoints, clamped bounds, and empty input.
- Existing selection paths still use the same `selected` IDs and enqueue methods.
- Global concurrency is capped at two and per-source concurrency is capped at two.
- Same-source requests are paced; 503/429 cooldown is bounded and isolated by source.
- `Retry-After` is honored and non-throttle HTTP statuses retain existing retry behavior.
- Pause/resume/cancel/crash recovery and local publishing continue to use generation checks.
- No files outside the download UI/runtime/tests are required.
