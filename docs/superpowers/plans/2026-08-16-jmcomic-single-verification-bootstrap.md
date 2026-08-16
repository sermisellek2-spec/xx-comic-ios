# 禁漫天堂单次验证与基础浏览 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让禁漫天堂首次访问只完成一次 Cloudflare 验证，随后先展示漫画列表，再展示 7 组分类；凭证失效前不重复验证。

**Architecture:** 保留现有 `CloudflareWebViewSession` 和 Android `CookieManager`。共享会话只修复挑战状态与验证页可见性；`JmComicSource` 增加不依赖漫画解析的访问探测；`MainActivity` 仅对 `jmcomic` 延后分类请求，直到第一页列表已经成功渲染。

**Tech Stack:** Java 8、Android WebView/CookieManager、JUnit 4、现有 Node 源码契约脚本

---

## 文件边界

- `app/src/main/java/com/xxcomic/source/JmComicSource.java`：禁漫页面哨兵、列表解析和独立访问探测。
- `app/src/test/java/com/xxcomic/source/JmComicSourceTest.java`：当前列表与分类最小 HTML fixture。
- `app/src/main/java/com/xxcomic/CloudflareWebViewSession.java`：challenge 生命周期、单活动请求和可交互验证页。
- `app/src/test/java/com/xxcomic/CloudflareWebViewSessionTest.java`：旧 403 不得覆盖正常 DOM 的状态机测试。
- `app/src/main/java/com/xxcomic/MainActivity.java`：手动验证、列表优先启动顺序、分类错误重试入口。
- `app/src/test/java/com/xxcomic/ProtectedSourceUiTest.java`：禁漫分类延后策略的纯逻辑测试。
- `tools/check-jmcomic-bootstrap.js`：验证 UI 调度和手动探测没有退回旧实现。

不创建新的站源框架，不修改 `Mh18ComicSource`，不修改详情、目录、正文和图片解扰代码。

### Task 1: 用当前站点结构固定列表和分类解析

**Files:**
- Modify: `app/src/test/java/com/xxcomic/source/JmComicSourceTest.java`
- Modify: `app/src/main/java/com/xxcomic/source/JmComicSource.java:55-125`
- Modify: `app/src/main/java/com/xxcomic/source/JmComicSource.java:218-232`

- [ ] **Step 1: 添加当前列表 fixture 的失败测试**

在 `JmComicSourceTest` 中增加最小页面，只保留两个真实卡片结构、一个无标题的导航链接和一个广告链接：

```java
@Test
public void currentCatalogCardsParseFromSlugLinksAndSrcCovers() throws Exception {
    String html = "<a href=\"/album/209225\"><img src=\"/paper_box.svg\"></a>"
            + "<a href=\"/album/1462132/current-title\">"
            + "<img src=\"https://cdn-msp3.18comic.vip/media/albums/1462132_3x4.jpg?u=1\" "
            + "title=\"漫画甲\" alt=\"漫画甲\"></a>"
            + "<a href=\"/album/1247117/second-title\">"
            + "<img data-original=\"https://cdn-msp3.18comic.vip/media/albums/1247117_3x4.jpg\" "
            + "alt=\"漫画乙\"></a>"
            + "<a href=\"/advert/1\"><img title=\"广告\"></a>";
    BrowserSession session = url -> html;
    JmComicSource source = new JmComicSource(SourceConfig.jmcomic(true), session);

    List<ComicModels.ComicSummary> result = source.latest(1);

    assertEquals(2, result.size());
    assertEquals("jmcomic:1462132", result.get(0).comicId);
    assertEquals("漫画甲", result.get(0).title);
    assertEquals("https://cdn-msp3.18comic.vip/media/albums/1247117_3x4.jpg",
            result.get(1).coverUrl);
}
```

- [ ] **Step 2: 添加访问探测与空列表的失败测试**

```java
@Test
public void verificationProbeChecksBusinessPageWithoutParsingCards() throws Exception {
    java.util.concurrent.atomic.AtomicReference<String> requested =
            new java.util.concurrent.atomic.AtomicReference<>();
    BrowserSession session = url -> {
        requested.set(url);
        return "<html><a href=\"/album/123/title\"><img src=\"cover.jpg\"></a></html>";
    };
    JmComicSource source = new JmComicSource(SourceConfig.jmcomic(true), session);

    source.verifyAccess();

    assertTrue(requested.get().contains("/albums?o=mr"));
    assertTrue(requested.get().contains("page=1"));
}

@Test(expected = java.io.IOException.class)
public void latestRejectsACompletedPageWithoutCatalogCards() throws Exception {
    JmComicSource source = new JmComicSource(SourceConfig.jmcomic(true),
            url -> "<html><title>禁漫天堂</title><body>广告</body></html>");
    source.latest(1);
}
```

- [ ] **Step 3: 运行测试并确认失败**

Run:

```powershell
.\gradlew.bat :app:testDebugUnitTest --tests com.xxcomic.source.JmComicSourceTest --rerun-tasks --console=plain
```

Expected: 编译失败，提示 `verifyAccess()` 尚不存在，或空列表测试未抛出异常。

- [ ] **Step 4: 增加最小页面哨兵和访问探测**

在 `JmComicSource` 增加：

```java
public void verifyAccess() throws IOException {
    String html = fetch(pageUrl(absolute(config.route("latest")), 1));
    if (!hasCatalogMarker(html)) throw new IOException(config.name + " 页面未就绪");
}

static boolean hasCatalogMarker(String html) {
    Matcher links = ALBUM_LINK.matcher(html == null ? "" : html);
    while (links.find()) {
        if (IMAGE_TAG.matcher(links.group(5)).find()) return true;
    }
    return false;
}

private List<ComicModels.ComicSummary> requireCatalogCards(String html) throws IOException {
    List<ComicModels.ComicSummary> result = parseCards(html);
    if (result.isEmpty()) throw new IOException(config.name + " 漫画列表解析失败");
    return result;
}
```

只把 `latest(int page)` 改为：

```java
@Override
public List<ComicModels.ComicSummary> latest(int page) throws IOException {
    return requireCatalogCards(fetch(pageUrl(absolute(config.route("latest")), page)));
}
```

搜索和有筛选条件的分类允许合法空结果，暂不改为强制非空。

- [ ] **Step 5: 扩充分类 fixture**

在现有 7 组分类测试的“类别”组加入 `/albums/another/sub/cosplay` 和 `/blog_library/`，断言前者保留、后者过滤：

```java
assertTrue(groups.get(1).options.stream()
        .anyMatch(option -> option.value.contains("/albums/another/sub/cosplay")));
assertTrue(groups.stream().flatMap(group -> group.options.stream())
        .noneMatch(option -> option.value.contains("blog_library")));
```

- [ ] **Step 6: 运行测试并提交**

Run:

```powershell
.\gradlew.bat :app:testDebugUnitTest --tests com.xxcomic.source.JmComicSourceTest --rerun-tasks --console=plain
```

Expected: `BUILD SUCCESSFUL`。

Commit:

```powershell
git add app/src/main/java/com/xxcomic/source/JmComicSource.java app/src/test/java/com/xxcomic/source/JmComicSourceTest.java
git commit -m "test: lock jmcomic catalog page contracts"
```

### Task 2: 修复 challenge 状态残留并显示真实验证页

**Files:**
- Modify: `app/src/test/java/com/xxcomic/CloudflareWebViewSessionTest.java`
- Modify: `app/src/main/java/com/xxcomic/CloudflareWebViewSession.java:229-275`
- Modify: `app/src/main/java/com/xxcomic/CloudflareWebViewSession.java:314-348`
- Modify: `app/src/main/java/com/xxcomic/CloudflareWebViewSession.java:380-405`

- [ ] **Step 1: 添加旧 challenge 响应不得覆盖正常 DOM 的失败测试**

```java
@Test
public void verifiedBusinessDomIgnoresTheOldChallengeResponse() {
    assertFalse(CloudflareWebViewSession.isChallenge(
            "https://18comic.vip/albums?o=mr&page=1",
            "最新的 Comics - 禁漫天堂",
            "<a href='/album/123'><img src='cover.jpg'></a>",
            403, "challenge", true));
}

@Test
public void firstChallengeResponseStillStartsVerification() {
    assertTrue(CloudflareWebViewSession.isChallenge(
            "https://18comic.vip/albums?o=mr&page=1",
            "Just a moment...", "", 403, "challenge", false));
}
```

- [ ] **Step 2: 运行状态机测试并确认失败**

Run:

```powershell
.\gradlew.bat :app:testDebugUnitTest --tests com.xxcomic.CloudflareWebViewSessionTest --rerun-tasks --console=plain
```

Expected: 编译失败，因为 `isChallenge` 尚未接收 `verifying` 参数。

- [ ] **Step 3: 让旧响应头只负责首次进入验证**

把 `inspectPage()` 调用改为：

```java
boolean challenge = isChallenge(page.optString("url"), page.optString("title"),
        page.optString("text") + " " + page.optString("html"),
        request.statusCode, request.mitigated, request.verifying);
```

把 `isChallenge` 改为：

```java
static boolean isChallenge(String url, String title, String body, int statusCode,
                           String mitigated, boolean verifying) {
    String content = ((url == null ? "" : url) + " " + (title == null ? "" : title)
            + " " + (body == null ? "" : body)).toLowerCase(Locale.US);
    boolean responseChallenge = statusCode == 403 && "challenge".equalsIgnoreCase(mitigated);
    boolean domChallenge = content.contains("/orchestrate/chl_page/")
            || content.contains("cf-chl-widget")
            || content.contains("cf-turnstile-response")
            || content.contains("just a moment")
            || content.contains("attention required")
            || content.contains("checking your browser")
            || content.contains("performing security verification")
            || content.contains("verify you are human")
            || content.contains("请稍候")
            || content.contains("正在验证")
            || content.contains("安全验证");
    return domChallenge || (!verifying && responseChallenge);
}
```

更新现有测试调用，最后一个参数按场景传入 `false`。

- [ ] **Step 4: 自动验证先保持轻提示，需要等待时再展示真实页面**

增加短暂的自动验证窗口：

```java
private static final long INTERACTIVE_DELAY_MS = 1200L;
```

首次识别 challenge 时先展开状态层但保持网页透明；1.2 秒后仍未完成，才展示可操作网页：

```java
if (action == PageAction.SHOW_VERIFICATION) {
    request.verifying = true;
    showVerificationView(false);
    browser.postDelayed(() -> {
        if (isActive(request) && request.verifying) showVerificationView(true);
    }, INTERACTIVE_DELAY_MS);
}
```

保留后台状态的 `0.01f`，按 `interactive` 决定验证页面是否可见：

```java
private void showVerificationView(boolean interactive) {
    if (host == null) return;
    host.setLayoutParams(verificationLayoutParams());
    host.setBackgroundColor(Color.argb(42, 18, 39, 56));
    host.setClickable(true);
    host.setFocusable(true);
    if (webView != null) {
        webView.setAlpha(interactive ? 1f : 0.01f);
        webView.setClickable(interactive);
    }
    if (statusCard != null) statusCard.setVisibility(View.VISIBLE);
    showVerifyingState();
    host.bringToFront();
}

private void showBackgroundView() {
    if (host == null) return;
    host.setLayoutParams(backgroundLayoutParams());
    host.setBackgroundColor(Color.TRANSPARENT);
    host.setClickable(false);
    host.setFocusable(false);
    if (webView != null) {
        webView.setAlpha(0.01f);
        webView.setClickable(false);
    }
    if (statusCard != null) statusCard.setVisibility(View.GONE);
}
```

创建 `statusCard` 时使用顶部居中布局，避免遮住 Turnstile 主区域：

```java
FrameLayout.LayoutParams statusParams = new FrameLayout.LayoutParams(
        ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT,
        Gravity.TOP | Gravity.CENTER_HORIZONTAL);
statusParams.topMargin = UIHelpers.dp(activity, 18);
page.addView(card, statusParams);
```

- [ ] **Step 5: 在失败信息中保留安全的请求上下文**

给 `FetchRequest` 增加不含 Cookie 的诊断字段，并在每次 DOM 检查时更新：

```java
volatile String currentUrl = "";
volatile boolean challengeDom;
volatile boolean pageReady;
```

```java
request.currentUrl = page.optString("url");
request.challengeDom = challenge;
request.pageReady = ready;
```

统一生成安全诊断后缀，验证超时与普通请求超时使用不同文案：

```java
private String requestDiagnostic(FetchRequest request) {
    return " [url=" + request.currentUrl + ", status=" + request.statusCode
            + ", verifying=" + request.verifying + ", challenge="
            + request.challengeDom + ", ready=" + request.pageReady + "]";
}

private String timeoutError(FetchRequest request) {
    return sourceName + (request.verifying ? "验证超时" : "请求超时")
            + requestDiagnostic(request);
}
```

超时、异常路径和 HTTP 失败使用该上下文；不得写入 Cookie、页面正文或完整 HTML。

- [ ] **Step 6: 运行测试并提交**

Run:

```powershell
.\gradlew.bat :app:testDebugUnitTest --tests com.xxcomic.CloudflareWebViewSessionTest --rerun-tasks --console=plain
```

Expected: `BUILD SUCCESSFUL`。

Commit:

```powershell
git add app/src/main/java/com/xxcomic/CloudflareWebViewSession.java app/src/test/java/com/xxcomic/CloudflareWebViewSessionTest.java
git commit -m "fix: complete jmcomic challenge navigation"
```

### Task 3: 将禁漫手动验证与列表解析分离

**Files:**
- Modify: `app/src/main/java/com/xxcomic/MainActivity.java:165-172`
- Modify: `app/src/main/java/com/xxcomic/MainActivity.java:2254-2270`
- Create: `tools/check-jmcomic-bootstrap.js`

- [ ] **Step 1: 创建手动验证契约并确认失败**

创建 `tools/check-jmcomic-bootstrap.js`：

```javascript
const fs = require("fs");
const main = fs.readFileSync("app/src/main/java/com/xxcomic/MainActivity.java", "utf8");
const session = fs.readFileSync("app/src/main/java/com/xxcomic/CloudflareWebViewSession.java", "utf8");

function check(name, condition) {
  if (!condition) throw new Error("FAIL " + name);
  console.log("PASS " + name);
}

check("jmcomic uses its dedicated access probe",
  main.includes("jmcomicClient.verifyAccess()"));
check("verification webview becomes visible only during challenge",
  session.includes("showVerificationView(false)")
  && session.includes("showVerificationView(true)")
  && session.includes("interactive ? 1f : 0.01f"));
check("old challenge response is ignored after verification",
  session.includes("!verifying && responseChallenge"));
check("protected requests remain single active navigation",
  session.includes("synchronized (requestLock)")
  && session.includes("activeRequest != null && !activeRequest.completed"));
check("manual verification keeps useful failure classes",
  main.includes('" 验证超时"') && main.includes('" 页面验证失败"')
  && main.includes('" 连接失败，请检查 VPN"'));
```

Run:

```powershell
node tools/check-jmcomic-bootstrap.js
```

Expected: `FAIL jmcomic uses its dedicated access probe`。

- [ ] **Step 2: 保留禁漫具体类型并调用访问探测**

把字段类型从 `ComicSource` 改为 `JmComicSource`：

```java
private JmComicSource jmcomicClient;
```

在 `verifyProtectedSource()` 中只对禁漫走独立探测，18漫画保持现状；结果保留具体失败类型：

```java
String resultMessage;
try {
    if ("jmcomic".equals(sourceId)) {
        jmcomicClient.verifyAccess();
        resultMessage = client.name() + " 验证完成";
    } else {
        resultMessage = client.name() + (!client.latest(1).isEmpty()
                ? " 验证完成" : " 验证失败");
    }
} catch (Exception error) {
    String reason = clean(error.getMessage(), "连接失败");
    resultMessage = client.name() + (reason.contains("超时")
            ? " 验证超时" : reason.contains("页面") || reason.contains("解析")
            ? " 页面验证失败" : " 连接失败，请检查 VPN");
}
String message = resultMessage;
postMainIfAlive(() -> {
    verifyingProtectedSourceIds.remove(sourceId);
    showRemToast(message);
});
```

不增加自动重试；同一按钮仍由 `verifyingProtectedSourceIds` 防止重复点击。

- [ ] **Step 3: 运行契约和相关测试并提交**

Run:

```powershell
node tools/check-jmcomic-bootstrap.js
.\gradlew.bat :app:testDebugUnitTest --tests com.xxcomic.ProtectedSourceUiTest --tests com.xxcomic.source.JmComicSourceTest --rerun-tasks --console=plain
```

Expected: 契约全部 `PASS`，Gradle `BUILD SUCCESSFUL`。

Commit:

```powershell
git add app/src/main/java/com/xxcomic/MainActivity.java tools/check-jmcomic-bootstrap.js
git commit -m "fix: separate jmcomic verification from parsing"
```

### Task 4: 固定先列表后分类并提供分类重试

**Files:**
- Modify: `app/src/test/java/com/xxcomic/ProtectedSourceUiTest.java`
- Modify: `app/src/main/java/com/xxcomic/MainActivity.java:707-755`
- Modify: `app/src/main/java/com/xxcomic/MainActivity.java:2915-3011`
- Modify: `app/src/main/java/com/xxcomic/MainActivity.java:3392-3413`
- Modify: `app/src/main/java/com/xxcomic/MainActivity.java:4463-4610`
- Modify: `app/src/main/java/com/xxcomic/MainActivity.java:4650-4667`
- Modify: `tools/check-jmcomic-bootstrap.js`

- [ ] **Step 1: 添加分类延后策略的失败测试**

在 `ProtectedSourceUiTest` 增加：

```java
@Test
public void jmcomicCategoriesWaitForTheFirstCatalogPage() {
    assertTrue(MainActivity.categoriesFollowInitialList("jmcomic"));
    assertFalse(MainActivity.categoriesFollowInitialList("mh18"));
    assertFalse(MainActivity.categoriesFollowInitialList("baozimh"));
}
```

Run:

```powershell
.\gradlew.bat :app:testDebugUnitTest --tests com.xxcomic.ProtectedSourceUiTest --rerun-tasks --console=plain
```

Expected: 编译失败，提示 `categoriesFollowInitialList` 不存在。

- [ ] **Step 2: 增加唯一的禁漫顺序判定**

在 `MainActivity` 增加：

```java
static boolean categoriesFollowInitialList(String sourceId) {
    return "jmcomic".equals(sourceId);
}
```

进入发现页、确认站源、旧站源选择器和导入配置后，只有非禁漫站源可以立即调用 `loadSourceCategories()`：

```java
if (!categoriesFollowInitialList(selectedSourceId) && sourceFilterGroups.isEmpty()) {
    loadSourceCategories();
}
```

在站源抽屉点选禁漫时不预加载分类，并保留在站源选择页等待“确认”；其他站源维持当前自动切到分类页的行为：

```java
sourceFilterGroups.clear();
if (categoriesFollowInitialList(sid)) {
    filterTab[0] = 0;
} else {
    loadSourceCategories();
    filterTab[0] = 1;
}
fill[0].run();
```

- [ ] **Step 3: 在第一页列表渲染后启动分类请求**

在 `loadSearchPage()` 成功回调进入 UI 前计算：

```java
boolean loadCategoriesAfterList = categoriesFollowInitialList(requestSourceId)
        && categoryMode && page == 1 && !append && sourceFilterGroups.isEmpty();
```

先执行现有列表写入和 `showTab(1, false)`，然后再启动分类：

```java
if (currentTab == 1) {
    if (append && searchResultsContent != null) {
        appendSearchResults(additions);
    } else {
        showTab(1, false);
    }
}
if (loadCategoriesAfterList) loadSourceCategories();
persistComicCachesAsync();
```

这保证真实列表已经进入 `searchResults` 并完成一次渲染，分类请求才进入同一浏览器会话。

- [ ] **Step 4: 将分类异常从静默失败改为可重试状态**

增加字段：

```java
private boolean sourceCategoriesFailed;
```

`loadSourceCategories()` 开始时清除旧状态；成功时保持 `false`；异常时仅对当前站源和 generation 生效：

```java
} catch (Exception error) {
    main.post(() -> {
        if (generation != categoryGeneration || !TextUtils.equals(sourceId, selectedSourceId)) return;
        sourceCategoriesFailed = true;
        appendErrorLog("分类加载失败", error);
        if (currentTab == 1) showTab(1, false);
    });
}
```

在发现页筛选行位置增加无边框轻量重试入口：

```java
if (sourceCategoriesFailed && categoriesFollowInitialList(selectedSourceId)) {
    TextView retryCategories = UIHelpers.text(
            this, "分类加载失败，重试", 12, UIHelpers.ACCENT, Typeface.BOLD);
    retryCategories.setGravity(Gravity.CENTER_VERTICAL);
    retryCategories.setBackgroundColor(Color.TRANSPARENT);
    retryCategories.setOnClickListener(v -> {
        sourceCategoriesFailed = false;
        showTab(1, false);
        loadSourceCategories();
    });
    page.addView(retryCategories,
            UIHelpers.marginBottom(-2, UIHelpers.dp(this, 6)));
}
```

切换站源时把 `sourceCategoriesFailed` 重置为 `false`。分类失败不得清空 `searchResults`。

- [ ] **Step 5: 扩充启动顺序契约**

追加到 `tools/check-jmcomic-bootstrap.js`：

```javascript
check("jmcomic defers categories until the first list",
  main.includes('return "jmcomic".equals(sourceId);')
  && main.includes("if (loadCategoriesAfterList) loadSourceCategories()"));
check("category failures are visible and retryable",
  main.includes('appendErrorLog("分类加载失败", error)')
  && main.includes('"分类加载失败，重试"'));
check("category failure never clears catalog results",
  !/catch \(Exception error\)[\s\S]{0,500}分类加载失败[\s\S]{0,300}searchResults\.clear\(\)/.test(main));
```

- [ ] **Step 6: 运行测试和契约并提交**

Run:

```powershell
node tools/check-jmcomic-bootstrap.js
.\gradlew.bat :app:testDebugUnitTest --tests com.xxcomic.ProtectedSourceUiTest --tests com.xxcomic.source.JmComicSourceTest --tests com.xxcomic.CloudflareWebViewSessionTest --rerun-tasks --console=plain
```

Expected: 契约全部 `PASS`，Gradle `BUILD SUCCESSFUL`。

Commit:

```powershell
git add app/src/main/java/com/xxcomic/MainActivity.java app/src/test/java/com/xxcomic/ProtectedSourceUiTest.java tools/check-jmcomic-bootstrap.js
git commit -m "fix: load jmcomic catalog before categories"
```

### Task 5: 完整回归与真机验收准备

**Files:**
- None. This task only verifies the committed implementation.

- [ ] **Step 1: 运行完整 JVM 测试**

Run:

```powershell
.\gradlew.bat testDebugUnitTest testReleaseUnitTest --rerun-tasks --console=plain
```

Expected: `BUILD SUCCESSFUL`，Debug 和 Release 单元测试均无失败。

- [ ] **Step 2: 运行本次相关源码契约**

Run:

```powershell
node tools/check-jmcomic-bootstrap.js
node tools/check-protected-source-session.js
node tools/check-settings-visual-contract.js
node tools/check-release-regressions.js
```

Expected: 四组脚本全部退出码 `0`。

- [ ] **Step 3: 构建可安装的 Debug APK**

Run:

```powershell
.\gradlew.bat assembleDebug --rerun-tasks --console=plain
```

Expected: `BUILD SUCCESSFUL`，生成 `app/build/outputs/apk/debug/app-debug.apk`。

- [ ] **Step 4: 真机执行第一阶段验收**

按顺序执行并记录结果：

1. 开启 VPN，清理 App 缓存。
2. 进入禁漫天堂，确认验证层只出现一次；需要操作时真实网页可见可点。
3. 确认验证后先出现漫画列表，再出现 7 组分类。
4. 切换分类、翻页、刷新，确认不再次验证。
5. 重启 App，确认 Cookie 有效时不再次验证。
6. 清理缓存后再次进入，确认只重新验证一次。
7. 关闭 VPN，确认出现连接失败提示而不是循环验证。

- [ ] **Step 5: 检查提交范围**

Run:

```powershell
git diff --check
git status --short
git log --oneline -5
```

Expected: 没有未提交的本次源码改动；`.gradle/`、`app/build/`、`release/` 仍不进入提交。

第一阶段验收完成后停止。详情、目录和阅读另开设计与实施计划，不在本计划继续修改。
