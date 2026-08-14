# Discovery Visual Alignment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Align the native discovery screen with the approved 25-scene visual atlas without changing search, source, filter, refresh, pagination, or navigation behavior.

**Architecture:** Keep the existing discovery state and request methods in `MainActivity`. Recompose only the title action, single-site filter row, recent-search layout, and filter drawer dimensions; protect the resulting structure with a source-contract check and retain the existing behavior checks.

**Tech Stack:** Android Java programmatic Views, Gradle/AGP 7.4.2, Node.js source-contract checks.

---

### Task 1: Lock The Approved Discovery Contract

**Files:**
- Create: `tools/check-discovery-visual-contract.js`

- [ ] **Step 1: Add source assertions for the finalized layout**

Assert that single-site source selection is a transparent title action, global mode hides it, the lower row contains only topic/region/state, search history wraps by measured natural width instead of fixed triples, and the drawer uses compact three-column cells.

- [ ] **Step 2: Verify the contract fails before production edits**

Run: `node tools/check-discovery-visual-contract.js`

Expected: FAIL because the source selector is still in the lower filter row and history still breaks every three items.

### Task 2: Align The Native Discovery Views

**Files:**
- Modify: `app/src/main/java/com/xxcomic/MainActivity.java`

- [ ] **Step 1: Move the single-site source action into the title row**

Render the current source as a small transparent title-row action only when `globalSearchMode` is false. Keep its click target connected to `showFilterDrawer(0)`.

- [ ] **Step 2: Keep only category dimensions below the search row**

Remove the duplicate source entry and retain topic, region, and state actions with their current drawer tab mapping.

- [ ] **Step 3: Wrap recent searches by content width**

Measure each compact history label and start a new row only when the next label would exceed the available screen width. Preserve click-to-search and clear-history behavior.

- [ ] **Step 4: Compact the right drawer**

Reduce drawer padding, tab and option spacing, source-row height, and confirm-button height. Keep three columns, source-aware values, draft rollback, async category generation guards, and the right-side drawer interaction.

- [ ] **Step 5: Verify the new contract passes**

Run: `node tools/check-discovery-visual-contract.js`

Expected: PASS.

### Task 3: Verify Behavior And Build Release 1.0.17

**Files:**
- Modify: `app/build.gradle`
- Modify: `tools/check-rem-visual-contract.js`

- [ ] **Step 1: Run discovery and regression contracts**

Run the discovery, filter semantics, category generation, search pull-refresh, search cancellation, search grid, search pagination, navigation, and Rem visual checks.

Expected: all checks pass.

- [ ] **Step 2: Increment the release**

Set `versionCode 17` and `versionName "1.0.17"`, then update the version assertion in the Rem visual contract.

- [ ] **Step 3: Build the release APK**

Run: `./gradlew.bat :app:testReleaseUnitTest :app:assembleRelease --no-daemon`

Expected: Gradle exits 0 and creates `app/build/outputs/apk/release/app-release.apk`.

### Task 4: Publish And Verify

**Files:**
- Publish outside Git: `release/xx-comic-1.0.17+17-<timestamp>.apk`
- Publish outside Git: `release/android-release.json`

- [ ] **Step 1: Verify APK identity, signature, size, and SHA-256**

Confirm package `com.xxcomic`, version 17 / 1.0.17, and a valid signature before generating release metadata.

- [ ] **Step 2: Commit and push exact source paths**

Stage only `MainActivity.java`, `app/build.gradle`, the two contract checks, and this plan. Commit on the user-authorized `master` branch and push without force.

- [ ] **Step 3: Upload the APK and metadata to COS**

Upload the APK to `xx-1321588235/apk/xx-comic/xx-comic.bin` and the metadata object used by the existing update flow. Preserve the server fallback and do not delete unrelated objects.

- [ ] **Step 4: Verify the public COS objects**

Fetch metadata and APK with cache-busting query strings, then compare version, byte size, and SHA-256 with the local release artifacts.

---

## Self-Review

- Spec coverage: the four approved discovery adjustments map directly to Task 2.
- Behavior protection: existing search, filter rollback, category generation, pagination, pull-refresh, and navigation checks remain mandatory.
- Scope control: no source parser, persistence key, dependency, account feature, or unrelated screen changes are included.
