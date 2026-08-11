# FiveUm 双站源接入 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将漫画栈和比卡漫画作为两个默认启用、数据互相隔离的内置站源接入搜索、分类、详情、目录和阅读流程。

**Architecture:** 新增一个参数化的 `FiveUmComicSource`，通过两个 `SourceConfig` 实例复用完全相同的 HTML 解析逻辑，同时保留独立 source ID。`MainActivity` 只增加现有站源注册分支，并仅对 `5um.net` 图片增加 Referer 与 `image/*` 响应校验。

**Tech Stack:** Java 8、Android `HttpURLConnection`/`Html`/`TextUtils`、现有 `ComicSource`/`SourceConfig`、Node.js 本地 fixture 检查、Gradle Android 构建。

---

## 文件结构

- Create: `app/src/main/java/com/xxcomic/source/FiveUmComicSource.java` - 两站共享的网络、路由和 HTML 解析实现。
- Modify: `app/src/main/java/com/xxcomic/source/SourceConfig.java` - 提供 `manhuazhan` 与 `bbyin` 两个默认配置。
- Modify: `app/src/main/java/com/xxcomic/MainActivity.java` - 注册、启停、持久化、查找、筛选和图片防盗链处理。
- Create: `tools/check-fiveum-source.js` - fixture 解析和生产代码注册静态检查。
- Create: `tools/fixtures/fiveum-search.html` - 搜索卡片、重复项和 HTML 实体样本。
- Create: `tools/fixtures/fiveum-category.html` - 完整动态标签区和列表卡片样本。
- Create: `tools/fixtures/fiveum-detail.html` - 详情元数据和章节目录样本。
- Create: `tools/fixtures/fiveum-chapter.html` - 正文图片范围、优先级和去重样本。

### Task 1: 建立离线契约检查

**Files:**
- Create: `tools/check-fiveum-source.js`
- Create: `tools/fixtures/fiveum-search.html`
- Create: `tools/fixtures/fiveum-category.html`
- Create: `tools/fixtures/fiveum-detail.html`
- Create: `tools/fixtures/fiveum-chapter.html`

- [ ] **Step 1: 写入最小 HTML fixture**

`fiveum-search.html` 包含两个 `.comic-item`，其中同一详情 URL 重复一次；首项使用 `data-src`，标题含 `&#40;旧&#41;`。`fiveum-category.html` 包含标题为“漫画类型”的 `.filter-section`、三个 `/category/tags/{id}` 链接和两个列表项。`fiveum-detail.html` 包含 `h1`、`.comic-main-info`、作者、状态、`.comic-description`、标签以及两个重复章节 URL。`fiveum-chapter.html` 在 `.comic-content` 外放置广告图，正文中分别提供 `data-src`、`data-original`、`src` 和重复 URL。

- [ ] **Step 2: 写失败的解析与注册检查**

检查脚本使用 Node 标准库读取 fixture 和生产代码，定义与 Java 一致的 `clean`、`attr`、`absolute`、`rawComicId`、`parseCards`、`parseCategories`、`parseDetail`、`parseChapters`、`parseImages`，并执行以下断言：

```js
assert(parseCards(search, "manhuazhan", "https://www.60ti.com")[0].comicId === "manhuazhan:doupocangkong40jiu41", "漫画栈 ID");
assert(parseCards(search, "bbyin", "https://bbyin.com")[0].comicId === "bbyin:doupocangkong40jiu41", "比卡 ID");
assert(parseCards(search, "manhuazhan", "https://www.60ti.com").length === 2, "卡片按详情 URL 去重");
assert(JSON.stringify(parseCategories(category)) === JSON.stringify(["热血", "奇幻", "治愈"]), "完整动态分类");
assert(categoryUrl("https://www.60ti.com", "", 2) === "https://www.60ti.com/category/page/2", "全部分类分页");
assert(categoryUrl("https://bbyin.com", "/category/tags/61", 3) === "https://bbyin.com/category/tags/61/page/3", "标签分页");
assert(parseDetail(detail).title === "刃牙II", "详情标题");
assert(parseChapters(detail).length === 2, "章节去重");
assert(parseImages(chapter).length === 3, "正文图片范围、优先级和去重");
assert(/class FiveUmComicSource/.test(source), "共享解析器存在");
assert(/SourceConfig\.manhuazhan/.test(main) && /SourceConfig\.bbyin/.test(main), "两个站源已注册");
assert(/isFiveUmImage/.test(main), "5um 图片类型保护存在");
```

- [ ] **Step 3: 运行检查确认 RED**

Run: `node tools/check-fiveum-source.js`

Expected: FAIL，提示 `FiveUmComicSource.java` 不存在或两个配置尚未注册。

- [ ] **Step 4: 提交测试基线**

```powershell
git add tools/check-fiveum-source.js tools/fixtures/fiveum-search.html tools/fixtures/fiveum-category.html tools/fixtures/fiveum-detail.html tools/fixtures/fiveum-chapter.html
git commit -m "test: 添加 FiveUm 双站源解析契约"
```

### Task 2: 实现配置与共享解析器

**Files:**
- Modify: `app/src/main/java/com/xxcomic/source/SourceConfig.java`
- Create: `app/src/main/java/com/xxcomic/source/FiveUmComicSource.java`
- Test: `tools/check-fiveum-source.js`

- [ ] **Step 1: 增加两个参数化配置**

在 `SourceConfig` 中加入以下工厂，并由私有方法构造公共路由：

```java
public static SourceConfig manhuazhan(boolean enabled) {
    return fiveUm("manhuazhan", "漫画栈", "www.60ti.com", "https://www.60ti.com", enabled);
}

public static SourceConfig bbyin(boolean enabled) {
    return fiveUm("bbyin", "比卡漫画", "bbyin.com", "https://bbyin.com", enabled);
}

private static SourceConfig fiveUm(String id, String name, String domain, String baseUrl, boolean enabled) {
    JSONObject routes = new JSONObject();
    try {
        routes.put("latest", "/category{pagePath}");
        routes.put("search", "/search?key={keyword}");
        routes.put("categoryIndex", "/category/");
        routes.put("category", "/category{tagPath}{pagePath}");
        routes.put("detail", "/comic_{comicId}.html");
        routes.put("chapter", "{chapterUrl}");
    } catch (JSONException ignored) {
    }
    return new SourceConfig(id, name, domain, baseUrl, baseUrl + "/", "", "", "", "", enabled, routes, new JSONObject());
}
```

- [ ] **Step 2: 实现共享解析器的身份、搜索和分类**

`FiveUmComicSource` 保存 `SourceConfig config`、`String prefix` 和不可变的 `volatile Map<String,String> categoryPaths`。`latest(page)` 调用默认分类；`search` 在 `page > 1` 时立即返回空列表，否则请求编码后的 `/search?key=`；`categories()` 先在局部 `LinkedHashMap` 中解析“漫画类型”标签区，再用 `Collections.unmodifiableMap` 一次替换快照。

```java
private volatile Map<String, String> categoryPaths = Collections.emptyMap();

@Override public String id() { return config.id; }
@Override public String name() { return config.name; }
@Override public String domain() { return config.domain; }

@Override
public List<ComicModels.ComicSummary> search(String keyword, int page) throws IOException {
    if (page > 1) return new ArrayList<>();
    String encoded = URLEncoder.encode(keyword == null ? "" : keyword.trim(), "UTF-8");
    return parseCards(fetch(absolute(config.route("search").replace("{keyword}", encoded))));
}
```

- [ ] **Step 3: 实现详情、章节和正文解析**

详情标题为空时抛 `IOException`。章节只匹配 `/chapter_{comicNumericId}_{chapterId}.html` 并按绝对 URL 去重。正文先截取 `.comic-content`，只匹配带 `.comic-image` 的 `img`，属性优先级固定为 `data-src`、`data-original`、`src`；无正文图时抛 `IOException`。

```java
if (TextUtils.isEmpty(title)) throw new IOException(config.name + " 详情解析失败：缺少标题");
if (images.isEmpty()) throw new IOException(config.name + " 章节解析失败：缺少正文图片");
return new ComicModels.ChapterPage(url, title, images, "");
```

- [ ] **Step 4: 实现 UTF-8 GET 与健康检查**

`fetch` 设置 10 秒连接、20 秒读取、浏览器 UA、站点 Referer，显式检查 HTTP 2xx/3xx；响应按 UTF-8 解码。`healthCheck()` 对 `/category/` 发 GET，并用页面同时含 `.comic-list` 或 `.filter-section` 作为成功条件。

- [ ] **Step 5: 运行局部检查**

Run: `node tools/check-fiveum-source.js`

Expected: 解析断言通过，注册断言仍因 `MainActivity` 未接入而失败。

- [ ] **Step 6: 提交共享解析器**

```powershell
git add app/src/main/java/com/xxcomic/source/SourceConfig.java app/src/main/java/com/xxcomic/source/FiveUmComicSource.java
git commit -m "feat: 添加 FiveUm 共享站源解析器"
```

### Task 3: 接入应用状态与图片保护

**Files:**
- Modify: `app/src/main/java/com/xxcomic/MainActivity.java`
- Test: `tools/check-fiveum-source.js`

- [ ] **Step 1: 注册两个客户端和默认启用状态**

导入 `FiveUmComicSource`；将搜索线程池从 9 调整为 11；新增两个 client、config 和 enabled 字段。`rebuildSourceClients()` 使用各自配置创建两个实例：

```java
manhuazhanClient = new FiveUmComicSource(manhuazhanConfig.withEnabled(manhuazhanEnabled));
bbyinClient = new FiveUmComicSource(bbyinConfig.withEnabled(bbyinEnabled));
```

- [ ] **Step 2: 接入全部现有站源分发路径**

在 `renderSources()`、`sourceNameForId()`、`selectedSource()`、`enabledBuiltinSources()`、`sourceForComicId()`、`sourceForId()`、`enabledSourceNames()`、`selectedSourceName()`、`sourceIdForName()` 中加入两个明确分支。`codeForRegion()` 在当前站源是 `manhuazhan` 或 `bbyin` 时直接返回 UI 标签原文，避免把“日本”“韩国”等动态标签转换成旧站源代码。

- [ ] **Step 3: 接入配置导入导出与本地持久化**

在 `sourceConfigJson()`、`applySourceConfigJson()`、`restoreLocalState()`、`saveLocalState()`、`restoreSourceConfigs()`、`encodeSourceConfigs()` 中加入两个 config 和 enabled 值。配置缺失时默认启用，旧版本偏好无需迁移。

```java
manhuazhanEnabled = prefs.getBoolean("source.manhuazhan.enabled", true);
bbyinEnabled = prefs.getBoolean("source.bbyin.enabled", true);
editor.putBoolean("source.manhuazhan.enabled", manhuazhanEnabled);
editor.putBoolean("source.bbyin.enabled", bbyinEnabled);
```

- [ ] **Step 4: 增加 5um.net Referer 与 Content-Type 防护**

新增 `isFiveUmImage(imageUrl)`，匹配 host 为 `5um.net` 或以 `.5um.net` 结尾。`refererForImage()` 对此类 URL 优先返回非空 `pageReferer`，否则返回 `manhuazhanConfig.referer`。在阅读器流式落盘、普通封面解码、后台封面预缓存三个入口读取响应头后调用：

```java
private void requireImageContentType(String imageUrl, String contentType) throws IOException {
    if (isFiveUmImage(imageUrl) && (contentType == null || !contentType.toLowerCase(Locale.US).startsWith("image/"))) {
        throw new IOException("Unexpected image content type: " + contentType + "; url=" + imageUrl);
    }
}
```

校验必须发生在任何缓存写入之前，其他域名维持现有宽松行为。

- [ ] **Step 5: 运行契约检查确认 GREEN**

Run: `node tools/check-fiveum-source.js`

Expected: 输出 `fiveum source ok`，进程退出码为 0。

- [ ] **Step 6: 运行相关离线回归**

```powershell
node tools/check-source-category-generation.js
node tools/check-search-source-fixes.js
node tools/check-search-pagination-ui.js
node tools/check-reader-prefetch.js
node tools/check-reader-memory.js
node tools/check-reader-generation.js
```

Expected: 六个检查均退出码 0。

- [ ] **Step 7: 提交应用接入**

```powershell
git add app/src/main/java/com/xxcomic/MainActivity.java tools/check-fiveum-source.js tools/fixtures/fiveum-search.html tools/fixtures/fiveum-category.html tools/fixtures/fiveum-detail.html tools/fixtures/fiveum-chapter.html
git commit -m "feat: 接入漫画栈与比卡漫画站源"
```

### Task 4: 真实站点和 Release 验证

**Files:**
- Modify only if a verified parser defect is found: `app/src/main/java/com/xxcomic/source/FiveUmComicSource.java`
- Modify only if a verified integration defect is found: `app/src/main/java/com/xxcomic/MainActivity.java`

- [ ] **Step 1: 对两个站点运行轻量 smoke test**

分别 GET `/search?key=%E7%8E%8B`、`/category/`、一个 `/comic_*.html` 和一个 `/chapter_*_*.html`。确认状态码 200、搜索有 `.comic-item`、分类有 `/category/tags/`、详情有 `.chapter-item`、正文有 `.comic-image`。

- [ ] **Step 2: 验证图片防盗链契约**

选取一个 `5um.net` 图片 URL，确认无 Referer 的响应不是 `image/*`，携带对应章节 URL 或 `https://www.60ti.com/` Referer 后响应为 `image/*`。不把网络结果写入仓库。

- [ ] **Step 3: 运行全部本地检查**

Run: `$checks = Get-ChildItem tools -Filter 'check-*.js'; foreach ($check in $checks) { node $check.FullName; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE } }`

Expected: 所有 JavaScript 检查退出码 0。

- [ ] **Step 4: 运行 Android 测试和 Release 构建**

Run: `.\gradlew.bat :app:testReleaseUnitTest :app:assembleRelease`

Expected: `BUILD SUCCESSFUL`，APK 生成在 `app/build/outputs/apk/release/app-release.apk`。

- [ ] **Step 5: 检查提交范围**

Run: `git status --short` 和 `git diff --check HEAD~2..HEAD`

Expected: 本任务提交只包含计划、两个 Java 文件、`MainActivity.java`、检查脚本和四个 fixture；`.gradle/` 与 `release/` 不在提交中。

- [ ] **Step 6: 对最终差异执行代码审查**

重点检查 source ID 隔离、分类快照线程安全、搜索非分页、失败语义、所有注册分支和缓存写入前 Content-Type 校验。发现问题时先新增或加强检查，再做最小修复并重新执行 Step 3-5。
