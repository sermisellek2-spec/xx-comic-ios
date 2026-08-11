# 漫画屋站源退役实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 从所有活动站源入口移除 `mhua5`，同时让旧收藏、历史和缓存通过无网络兼容适配器继续安全读取。

**Architecture:** 将 `Mhua5ComicSource` 缩减为实现既有 `ComicSource` 契约的退役适配器，保留稳定 ID 路由但让所有远程方法立即失败。`MainActivity` 删除漫画屋的活动配置和启用状态，并在既有封面、正文图片加载路径中传递 `cacheOnly`，使退役内容只读取内存或磁盘缓存。

**Tech Stack:** Android Java、现有 `ComicSource` 接口、原生图片磁盘缓存、Node.js 结构校验、Gradle/AGP 7.4.2。

---

### Task 1: 退役站源适配器与活动注册

**Files:**
- Create: `tools/check-retired-mhua5-source.js`
- Modify: `app/src/main/java/com/xxcomic/source/Mhua5ComicSource.java`
- Modify: `app/src/main/java/com/xxcomic/source/SourceConfig.java`
- Modify: `app/src/main/java/com/xxcomic/MainActivity.java`
- Test: `tools/check-retired-mhua5-source.js`

- [x] **Step 1: 写入活动站源退役校验**

创建无需第三方依赖的 Node.js 校验脚本：

```javascript
const fs = require("fs");

const main = fs.readFileSync("app/src/main/java/com/xxcomic/MainActivity.java", "utf8");
const config = fs.readFileSync("app/src/main/java/com/xxcomic/source/SourceConfig.java", "utf8");
const retired = fs.readFileSync("app/src/main/java/com/xxcomic/source/Mhua5ComicSource.java", "utf8");

function check(condition, message) {
  if (!condition) throw new Error(message);
}

for (const marker of [
  "private SourceConfig mhua5Config",
  "mhua5Enabled",
  "SourceConfig.mhua5",
  "source.mhua5.enabled",
  "sources.add(mhua5Client)",
  "names.add(mhua5Client.name())",
  "sources.put(mhua5Config",
]) {
  check(!main.includes(marker), `active mhua5 marker remains: ${marker}`);
}

check(!/static SourceConfig mhua5\s*\(/.test(config), "SourceConfig.mhua5 still exists");
check(main.includes("private ComicSource mhua5Client;"), "legacy mhua5 resolver missing");
check(main.includes("mhua5Client = new Mhua5ComicSource();"), "retired adapter not constructed");
check(main.includes("if (mhua5Client.id().equals(sourceId)) return mhua5Client;"), "legacy source id does not resolve");
check(main.includes("comicId.startsWith(mhua5Client.id() + \":\")"), "legacy comic id prefix does not resolve");
check(!main.includes("漫画屋的搜索、详情、阅读图片"), "about text still advertises mhua5");

check(retired.includes('private static final String SOURCE_ID = "mhua5";'), "stable source id missing");
check(retired.includes('return "漫画屋（已下线）";'), "retired source label missing");
check(retired.includes('return new IOException("漫画屋站源已下线");'), "offline error missing");
for (const marker of ["HttpURLConnection", "new URL(", "Pattern.compile", "SourceConfig"]) {
  check(!retired.includes(marker), `retired adapter still has live implementation: ${marker}`);
}

console.log("retired mhua5 source checks ok");
```

- [x] **Step 2: 运行校验并确认 RED**

Run:

```powershell
& 'C:\Users\15361\.cache\codex-runtimes\codex-primary-runtime\dependencies\node\bin\node.exe' tools/check-retired-mhua5-source.js
```

Expected: FAIL，首个错误为 `active mhua5 marker remains`，证明旧站源仍在活动注册中。

- [x] **Step 3: 将 `Mhua5ComicSource` 缩减为无网络兼容适配器**

保留类型和接口，删除全部 HTTP、HTML、正则解析及 `SourceConfig` 依赖。实现保持如下行为：

```java
public class Mhua5ComicSource implements ComicSource {
    private static final String SOURCE_ID = "mhua5";
    private static final String DOMAIN = "www.mhua5.com";

    @Override public String id() { return SOURCE_ID; }
    @Override public String name() { return "漫画屋（已下线）"; }
    @Override public String domain() { return DOMAIN; }

    @Override public List<ComicModels.ComicSummary> latest(int page) throws IOException { throw unavailable(); }
    @Override public List<ComicModels.ComicSummary> search(String keyword, int page) throws IOException { throw unavailable(); }
    @Override public List<String> categories() throws IOException { throw unavailable(); }
    @Override public List<ComicModels.ComicSummary> category(String region, String state, int page) throws IOException { throw unavailable(); }
    @Override public ComicModels.ComicDetail detail(String comicId) throws IOException { throw unavailable(); }
    @Override public List<ComicModels.Chapter> chapters(String comicId) throws IOException { throw unavailable(); }
    @Override public ComicModels.ChapterPage chapter(String chapterUrl) throws IOException { throw unavailable(); }
    @Override public boolean healthCheck() { return false; }

    private IOException unavailable() {
        return new IOException("漫画屋站源已下线");
    }
}
```

- [x] **Step 4: 删除活动配置和 UI/搜索注册**

从 `SourceConfig.java` 删除 `mhua5(boolean)` 工厂。

从 `MainActivity.java` 删除 `mhua5Config`、`mhua5Enabled` 以及所有活动接入点，包括站源卡片、`selectedSource()`、`enabledBuiltinSources()`、名称下拉、配置导入导出、`source.configs` 编解码、偏好读写和旧 Referer 分支。

保留以下兼容路由：

```java
private ComicSource mhua5Client;

private String sourceNameForId(String sourceId) {
    // 其他现有分支保持原顺序
    if (mhua5Client.id().equals(sourceId)) return mhua5Client.name();
}

private ComicSource sourceForId(String sourceId) {
    if (mhua5Client.id().equals(sourceId)) return mhua5Client;
    // 其他现有分支保持不变
}

private void rebuildSourceClients() {
    sourceClient = new BaoziComicSource(baoziConfig.withEnabled(sourceEnabled));
    mhua5Client = new Mhua5ComicSource();
    // 其他现有客户端保持不变
}
```

`sourceForComicId()` 保留 `mhua5:` 前缀分支。关于页文案改为不枚举已退役站源的通用描述，例如“XX Comic 已接入多个漫画站源，支持搜索、详情、阅读图片和本地缓存。”

- [x] **Step 5: 运行校验并确认 GREEN**

Run:

```powershell
& 'C:\Users\15361\.cache\codex-runtimes\codex-primary-runtime\dependencies\node\bin\node.exe' tools/check-retired-mhua5-source.js
```

Expected: `retired mhua5 source checks ok`。

- [x] **Step 6: 提交退役适配器和活动注册清理**

```powershell
git add tools/check-retired-mhua5-source.js app/src/main/java/com/xxcomic/source/Mhua5ComicSource.java app/src/main/java/com/xxcomic/source/SourceConfig.java app/src/main/java/com/xxcomic/MainActivity.java
git commit -m "refactor: 退役漫画屋活动站源"
```

### Task 2: 旧内容图片缓存只读

**Files:**
- Create: `tools/check-retired-mhua5-cache-only.js`
- Modify: `app/src/main/java/com/xxcomic/MainActivity.java`
- Modify: `tools/check-reader-prefetch.js`
- Modify: `tools/check-reader-memory.js`
- Test: `tools/check-retired-mhua5-cache-only.js`
- Test: `tools/check-reader-prefetch.js`
- Test: `tools/check-reader-memory.js`

- [x] **Step 1: 写入缓存只读校验**

新增结构校验，验证退役来源标识会传递到封面、详情大图、正文加载和预加载：

```javascript
const fs = require("fs");
const source = fs.readFileSync("app/src/main/java/com/xxcomic/MainActivity.java", "utf8");

function check(condition, message) {
  if (!condition) throw new Error(message);
}

check(/private boolean isRetiredSource\(String sourceId\)/.test(source), "retired source helper missing");
check(/coverFrame\(String url, int widthDp, int heightDp, boolean cacheOnly\)/.test(source), "cache-only cover overload missing");
check(/loadImage\(ImageView target, String imageUrl, String pageReferer, boolean cacheOnly\)/.test(source), "cache-only image loader missing");
check(/if \(cacheOnly\) \{[\s\S]*?setImageDrawable/.test(source), "cover cache miss still reaches network");
check(/boolean ensureReaderImageCached\(String imageUrl, String chapterUrl, boolean cacheOnly\)/.test(source), "reader cache-only loader missing");
check(/if \(cacheOnly\) return false;/.test(source), "reader cache miss still reaches network");
check(/prefetchReaderImages\([\s\S]*?boolean cacheOnly\)/.test(source), "reader prefetch does not receive cache-only state");
check(/loadReaderImage\([\s\S]*?boolean cacheOnly\)/.test(source), "reader rows do not receive cache-only state");
check(source.includes("boolean cacheOnly = isRetiredSource(detail.summary.sourceId);"), "detail/reader does not derive retired state");
check(source.includes("coverFrame(cover, 86, 116, isRetiredComic(id))"), "favorite cover can still use network");
check(source.includes("coverFrame(summary.coverUrl, 80, 107, isRetiredSource(summary.sourceId))"), "history cover can still use network");
check(source.includes("if (!isRetiredSource(detail.summary.sourceId)) loadImageToCache(detail.summary.coverUrl);"), "favorite action can still pre-download retired cover");

console.log("retired mhua5 cache-only checks ok");
```

同时更新既有阅读器结构契约：

```javascript
// tools/check-reader-prefetch.js
const ensure = method("private boolean ensureReaderImageCached", "private Future<?> loadReaderImage");
// visible loader must forward cacheOnly
if (!loader.includes("ensureReaderImageCached(imageUrl, chapterUrl, cacheOnly)")) {
  fail("visible loader does not preserve retired cache-only state");
}

// tools/check-reader-memory.js
const readerCacheLoader = method("private boolean ensureReaderImageCached", "private Future<?> loadReaderImage");
```

这些测试修改必须和新增校验一起在生产代码修改前完成。

- [x] **Step 2: 运行校验并确认 RED**

Run:

```powershell
& 'C:\Users\15361\.cache\codex-runtimes\codex-primary-runtime\dependencies\node\bin\node.exe' tools/check-retired-mhua5-cache-only.js
```

Expected: FAIL with `retired source helper missing`。

同时运行更新后的 `check-reader-prefetch.js` 和 `check-reader-memory.js`，预期因 `private boolean ensureReaderImageCached` 尚不存在而失败，证明契约测试确实覆盖新签名。

- [x] **Step 3: 为封面加载增加缓存只读参数**

增加来源判断：

```java
private boolean isRetiredSource(String sourceId) {
    return mhua5Client.id().equals(sourceId);
}

private boolean isRetiredComic(String comicId) {
    ComicModels.ComicDetail detail = details.get(comicId);
    ComicModels.ComicSummary summary = summaries.get(comicId);
    String sourceId = detail != null && detail.summary != null
            ? detail.summary.sourceId
            : summary == null ? "" : summary.sourceId;
    return isRetiredSource(sourceId)
            || (TextUtils.isEmpty(sourceId) && comicId != null && comicId.startsWith(mhua5Client.id() + ":"));
}
```

给 `coverFrame`、`coverView`、`addBlurredHeroCover` 和 `loadImage` 增加 `cacheOnly` 重载。`loadImage` 仍先查内存和磁盘缓存；磁盘未命中或损坏且 `cacheOnly` 为真时设置现有占位色并返回，代码必须位于 `new URL(imageUrl)` 之前。

收藏行、历史行和详情页根据 `sourceId` 传入该标志。普通搜索结果继续调用原三参数或默认 `cacheOnly=false` 的重载。

收藏退役漫画时保留收藏数据写入，但使用：

```java
if (!isRetiredSource(detail.summary.sourceId)) loadImageToCache(detail.summary.coverUrl);
```

- [x] **Step 4: 为阅读器和预加载增加缓存只读参数**

将 `ensureReaderImageCached` 改为返回缓存是否可用：

```java
private boolean ensureReaderImageCached(String imageUrl, String chapterUrl, boolean cacheOnly) throws IOException {
    File cached = imageCacheFile(imageUrl);
    long[] cachedIdentity = captureImageCacheIdentity(cached);
    if (cachedIdentity != null && cachedIdentity[0] > 0L) {
        cached.setLastModified(System.currentTimeMillis());
        return true;
    }
    deleteImageCacheIfUnchanged(cached, cachedIdentity);
    if (cacheOnly) return false;
    // 保留现有网络下载块
    return true;
}
```

`renderReader()` 计算一次 `cacheOnly`，并传给 `loadReaderImage()` 与 `prefetchReaderImages()`。前台加载在 `ensureReaderImageCached()` 返回 `false` 时直接设置占位并结束；预加载静默跳过，不记录错误。

- [x] **Step 5: 运行新增及现有阅读器校验并确认 GREEN**

Run:

```powershell
& 'C:\Users\15361\.cache\codex-runtimes\codex-primary-runtime\dependencies\node\bin\node.exe' tools/check-retired-mhua5-cache-only.js
& 'C:\Users\15361\.cache\codex-runtimes\codex-primary-runtime\dependencies\node\bin\node.exe' tools/check-reader-prefetch.js
& 'C:\Users\15361\.cache\codex-runtimes\codex-primary-runtime\dependencies\node\bin\node.exe' tools/check-reader-memory.js
```

Expected: 三个脚本均退出 0；新增脚本输出 `retired mhua5 cache-only checks ok`。

- [x] **Step 6: 提交缓存只读实现**

```powershell
git add tools/check-retired-mhua5-cache-only.js tools/check-reader-prefetch.js tools/check-reader-memory.js app/src/main/java/com/xxcomic/MainActivity.java
git commit -m "fix: 禁止退役站源图片回源"
```

### Task 3: 删除仅服务于漫画屋的探测资产

**Files:**
- Modify: `tools/check-retired-mhua5-source.js`
- Delete: `tools/sim-mhua5-parse.js`
- Delete: `tools/probe-mhua5-search.html`
- Delete: `tools/probe-mhua5-detail.html`
- Delete: `tools/probe-mhua5-chapter.html`
- Test: `tools/check-retired-mhua5-source.js`

- [x] **Step 1: 先增加旧资产不存在校验**

在 `tools/check-retired-mhua5-source.js` 末尾、成功输出前加入：

```javascript
for (const path of [
  "tools/sim-mhua5-parse.js",
  "tools/probe-mhua5-search.html",
  "tools/probe-mhua5-detail.html",
  "tools/probe-mhua5-chapter.html",
]) {
  check(!fs.existsSync(path), `retired mhua5 probe remains: ${path}`);
}
```

- [x] **Step 2: 运行校验并确认 RED**

Run:

```powershell
& 'C:\Users\15361\.cache\codex-runtimes\codex-primary-runtime\dependencies\node\bin\node.exe' tools/check-retired-mhua5-source.js
```

Expected: FAIL with `retired mhua5 probe remains: tools/sim-mhua5-parse.js`。

- [x] **Step 3: 删除四个纯漫画屋探测文件**

删除上述四个文件。保留 `probe-mhua5-aikan-chapters.js`、`probe-aikan-mhua5-images.js` 和 `probe-image-referer.js`，因为它们还包含其他站源的探测逻辑。

- [x] **Step 4: 运行校验并确认 GREEN**

Run:

```powershell
& 'C:\Users\15361\.cache\codex-runtimes\codex-primary-runtime\dependencies\node\bin\node.exe' tools/check-retired-mhua5-source.js
```

Expected: `retired mhua5 source checks ok`。

- [x] **Step 5: 提交探测资产清理**

```powershell
git add tools/check-retired-mhua5-source.js tools/sim-mhua5-parse.js tools/probe-mhua5-search.html tools/probe-mhua5-detail.html tools/probe-mhua5-chapter.html
git commit -m "chore: 清理漫画屋探测资产"
```

### Task 4: 完整回归验证

**Files:**
- Test: `tools/check-retired-mhua5-source.js`
- Test: `tools/check-retired-mhua5-cache-only.js`
- Test: existing source, search, cache, reader checks
- Test: Android release build

- [x] **Step 1: 运行站源与缓存专项校验**

```powershell
$node = 'C:\Users\15361\.cache\codex-runtimes\codex-primary-runtime\dependencies\node\bin\node.exe'
& $node tools/check-retired-mhua5-source.js
& $node tools/check-retired-mhua5-cache-only.js
& $node tools/check-default-search-load.js
& $node tools/check-default-search-cache.js
& $node tools/check-reader-prefetch.js
& $node tools/check-reader-memory.js
& $node tools/check-reader-generation.js
```

Expected: 所有脚本退出 0。

`tools/check-android-source.js` 在本次修改前已有旧版本号、旧视觉样式和旧全站搜索时序断言失败，经用户确认不纳入本任务通过门槛，也不在本次顺手修复。

- [x] **Step 2: 检查源码残留和差异格式**

```powershell
rg -n "mhua5Config|mhua5Enabled|SourceConfig\.mhua5|source\.mhua5\.enabled" app/src/main/java
git diff --check
```

Expected: `rg` 无匹配；`git diff --check` 退出 0。

- [x] **Step 3: 运行 Android 测试与 release 构建**

```powershell
.\gradlew.bat :app:testReleaseUnitTest :app:assembleRelease
```

Expected: `BUILD SUCCESSFUL`；若单元测试目录为空，`testReleaseUnitTest` 可显示 `NO-SOURCE`。

- [x] **Step 4: 检查最终提交和工作区**

```powershell
git status --short --branch
git log -5 --oneline
```

Expected: 只有已忽略的构建产物，源文件无未提交修改；最近提交依次包含计划、活动站源退役、缓存只读和探测资产清理。
