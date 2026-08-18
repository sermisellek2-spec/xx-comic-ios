# 六漫画站源对接 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将六漫画接入 XX Comic 的分类、列表、详情、目录和阅读流程，并在设置中可启停和持久化。

**Architecture:** 新增独立 `LiumanhuaComicSource`，复用现有 `ComicSource`/`SourceConfig` 和轻量 HTTP/正则风格；`MainActivity` 仅增加该源的注册、路由和配置项。章节参数在源类内完成 AES/CBC 解密和正文校验。

**Tech Stack:** Android Java, `HttpURLConnection`, `java.util.regex`, `org.json`, `javax.crypto`, Android `Base64`, Gradle.

---

### Task 1: Add source contract coverage

**Files:**
- Create: `tools/check-liumanhua-source.js`

- [ ] **Step 1: Write assertions for registration and parser boundaries**

  Assert that `SourceConfig.liumanhua`, `LiumanhuaComicSource`, `supportsSearch() == false`, AES constants, `.cy_list_mh`, `.cy_plist`/`.chapter__item`, `.rd-guess__comic` exclusion, and `s2.bzcdn.net` referer mapping markers exist.

- [ ] **Step 2: Run the contract and verify the expected failure**

  Run `node tools/check-liumanhua-source.js`; it must fail before production implementation because the new source and registration are absent.

### Task 2: Add six-manhua source configuration

**Files:**
- Modify: `app/src/main/java/com/xxcomic/source/SourceConfig.java`

- [ ] **Step 1: Add `SourceConfig.liumanhua(boolean)`**

  Register id `liumanhua`, name `六漫画`, domain/base URL `www.liumanhua.com`/`https://www.liumanhua.com`, routes `latest`, `categoryIndex`, `category`, `detail`, `chapter`, and empty search route.

- [ ] **Step 2: Compile the source config**

  Run `node tools/check-liumanhua-source.js`; the remaining expected failure should identify the absent source implementation and MainActivity wiring.

### Task 3: Implement list, filters, detail, chapters, and AES reader

**Files:**
- Create: `app/src/main/java/com/xxcomic/source/LiumanhuaComicSource.java`

- [ ] **Step 1: Add HTTP helpers with timeouts, UA, Referer, and resource cleanup**

  Implement `fetch` using `HttpURLConnection`, 10s connect timeout, 20s normal read timeout, 30s chapter read timeout, gzip handling, UTF-8 fallback, and `finally` disconnect.

- [ ] **Step 2: Add category and list parsing**

  Parse only `.cy_list_mh` cards, normalize relative URLs, deduplicate raw comic IDs, and implement dynamic filter group extraction from `.cy_tag` while skipping “资费”.

- [ ] **Step 3: Add detail and chapter parsing**

  Parse title/cover/metadata/description and only `.cy_plist`/`.chapter__item` links; reject recommendation cards.

- [ ] **Step 4: Add AES payload decoding and chapter page validation**

  Decode `params` with Base64, use the first 16 bytes as IV and key `9S8$vJnU2ANeSRoF`, parse JSON, validate `source_id`, host, comic/chapter IDs, image URL scheme, and deduplicate image URLs.

- [ ] **Step 5: Run parser/source contract checks**

  Run `node tools/check-liumanhua-source.js`; all static contract assertions must pass.

### Task 4: Wire source into MainActivity

**Files:**
- Modify: `app/src/main/java/com/xxcomic/MainActivity.java`

- [ ] **Step 1: Add client/config/enabled state and rebuild initialization**

  Add `liumanhuaClient`, `liumanhuaConfig`, `liumanhuaEnabled`, initialize the client, and include it in source management cards.

- [ ] **Step 2: Add source routing and enabled lists**

  Include six-manhua in `enabledBuiltinSources`, `selectedSource`, `sourceForId`, and `sourceForComicId`; leave `enabledSearchSources` behavior to `supportsSearch() == false`.

- [ ] **Step 3: Add preference and import/export persistence**

  Read/write `source.liumanhua.enabled`, restore defaults, encode/decode source configs, and include the source in import/export registration.

- [ ] **Step 4: Add image Referer mapping**

  Use `liumanhuaConfig.referer` for six-manhua pages and `s2.bzcdn.net` images.

- [ ] **Step 5: Run all relevant contract checks**

  Run `node tools/check-liumanhua-source.js`, `node tools/check-detail-release.js`, `node tools/check-cuimh-source.js`, `node tools/check-rem-visual-contract.js`, and `node tools/check-dialog-toast-contract.js`.

### Task 5: Build, verify, commit, push, and publish

**Files:**
- Modify: `app/build.gradle` (version `2.0.2`, code `202`) if not already updated.
- Generate: `release/xx-comic-2.0.2.apk` and metadata outside the commit scope.

- [ ] **Step 1: Run unit tests and release build**

  Run `./gradlew.bat :app:testReleaseUnitTest :app:assembleRelease --no-daemon --console=plain` and require exit code 0.

- [ ] **Step 2: Verify APK identity and signing**

  Use `aapt dump badging` and `apksigner verify --verbose` to confirm package `com.xxcomic`, version `2.0.2 (202)`, and v1/v2 signatures.

- [ ] **Step 3: Review and commit only source changes**

  Stage Java, Gradle, docs, and contract script changes; exclude `.gradle`, `.gradle-codex`, `app/build`, and generated release artifacts unless the repository already tracks them.

- [ ] **Step 4: Push master**

  Run `git push origin master` after the commit succeeds.

- [ ] **Step 5: Upload and verify COS/backup artifacts**

  Copy the release APK to the configured COS object `apk/xx-comic/xx-comic.bin`, update the server backup package, then read back both artifacts and compare byte size/SHA-256 with the local APK.
