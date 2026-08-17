# 18漫画混合会话与内容链路 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 18漫画首次挑战静默验证一次，随后快速加载列表、分类、详情、真实异步目录和正文，并发布 Android `1.0.36 (36)`。

**Architecture:** 复用现有 `CloudflareWebViewSession` 的 HTTP 优先混合会话，不修改禁漫天堂。`Mh18ComicSource` 从页面唯一数据容器读取可信 API 主机和数字参数，再请求站点真实异步接口；所有声明主机都限制为 HTTPS 的 `18mh.org` 或其子域。

**Tech Stack:** Android Java、平台 WebView/CookieManager、HttpURLConnection、org.json、JUnit 4、Node.js 源码契约、Android Gradle Plugin 7.4.2、腾讯云 COS、SSH 备用发布服务器。

---

## 文件边界

- `app/src/main/java/com/xxcomic/MainActivity.java`：仅把 18漫画会话切到 HTTP 优先；禁漫天堂初始化不变。
- `app/src/main/java/com/xxcomic/source/Mh18ComicSource.java`：解析目录/正文数据容器、校验 API 主机并请求真实异步接口。
- `app/src/test/java/com/xxcomic/source/Mh18ComicSourceTest.java`：18漫画目录、正文、主机白名单和交互验证回归测试。
- `tools/check-protected-source-session.js`：锁定两个受保护站源的独立会话及 18漫画 HTTP 优先配置。
- `app/build.gradle`、`tools/check-detail-release.js`、`tools/check-cuimh-source.js`、`tools/check-rem-visual-contract.js`：发布版本 `1.0.36 (36)`。
- `release/`：生成 APK、元数据和远端发布辅助文件；该目录维持现有未跟踪发布产物策略，不纳入 Git。

### Task 1: 让 18漫画复用 HTTP 优先混合会话

**Files:**
- Modify: `tools/check-protected-source-session.js`
- Modify: `app/src/main/java/com/xxcomic/MainActivity.java:348-353`

- [ ] **Step 1: 增加失败的源码契约**

在 `tools/check-protected-source-session.js` 读取 `main` 后增加会话初始化片段，并添加断言：

```javascript
const mh18Session = main.slice(
  main.indexOf("mh18BrowserSession = new CloudflareWebViewSession("),
  main.indexOf("jmcomicBrowserSession = new CloudflareWebViewSession("),
);

check("18mh uses the HTTP-first hybrid session",
  mh18Session.includes("mh18Config.name, true, this::showRemToast"));
```

- [ ] **Step 2: 运行契约并确认 RED**

```powershell
node tools/check-protected-source-session.js
```

Expected: `FAIL 18mh uses the HTTP-first hybrid session`，因为当前构造参数是 `false`。

- [ ] **Step 3: 写最小实现**

在 `MainActivity.onCreate()` 中只改 18漫画构造参数：

```java
mh18BrowserSession = new CloudflareWebViewSession(
        this, main, mh18Config.name, true, this::showRemToast);
```

保留禁漫天堂现有构造、CookieManager、缓存清理和手动验证代码不变。

- [ ] **Step 4: 运行契约并确认 GREEN**

```powershell
node tools/check-protected-source-session.js
```

Expected: 脚本退出码为 0，最后输出 `Protected source session contract holds.`。

- [ ] **Step 5: 提交会话边界**

```powershell
git add app/src/main/java/com/xxcomic/MainActivity.java tools/check-protected-source-session.js
git commit -m "fix: reuse hybrid session for 18mh"
```

### Task 2: 对接 18漫画真实异步目录接口

**Files:**
- Modify: `app/src/test/java/com/xxcomic/source/Mh18ComicSourceTest.java`
- Modify: `app/src/main/java/com/xxcomic/source/Mh18ComicSource.java:149-167,304-327`

- [ ] **Step 1: 增加目录接口与主机白名单失败测试**

在 `Mh18ComicSourceTest` 增加 `IOException`、`ArrayList`、`LinkedHashMap`、`Map` 和 `fail` 导入，再添加：

```java
@Test
public void catalogParsesCurrentCardsAndFilterGroups() throws Exception {
    String html = "<a href=\"/manga/meilixinshijie\"><img data-src=\"cover.webp\">"
            + "<h3 class=\"cardtitle\">美麗新世界</h3></a>"
            + "<a href=\"/manga-genre/hanman\"><button>韓漫</button></a>"
            + "<a href=\"/manga-tag/juchang\"><button>#劇情</button></a>";
    Mh18ComicSource source = new Mh18ComicSource(
            SourceConfig.mh18(true), url -> html);

    assertEquals("美麗新世界", source.latest(1).get(0).title);
    List<ComicModels.FilterGroup> groups = source.filterGroups();
    assertEquals(2, groups.size());
    assertEquals("漫画类型", groups.get(0).label);
    assertEquals("hanman", groups.get(0).options.get(1).value);
    assertEquals("热门标签", groups.get(1).label);
    assertEquals("juchang", groups.get(1).options.get(1).value);
}

@Test
public void chaptersLoadTheAsyncApiDeclaredByTheCatalogPage() throws Exception {
    String catalogUrl = "https://18mh.org/chapterlist/meilixinshijie";
    String apiUrl = "https://18mh.org/manga/get?mid=28&mode=all";
    Map<String, String> pages = new LinkedHashMap<>();
    pages.put(catalogUrl, "<div id='allchapters' data-mid='28' "
            + "data-host='https://18mh.org'>Loading...</div>");
    StringBuilder directory = new StringBuilder();
    for (int index = 0; index < 252; index++) {
        directory.append("<a href='/manga/meilixinshijie/28-")
                .append(9821 + index).append('-').append(index)
                .append("' data-ms='28' data-cs='").append(33999 + index)
                .append("' data-ct='第").append(index + 1).append("話'></a>");
    }
    directory.append("<a href='/manga/other/99-1-0' data-ms='99' data-cs='1' ")
            .append("data-ct='错误章节'></a>");
    pages.put(apiUrl, directory.toString());
    List<String> requests = new ArrayList<>();
    BrowserSession session = url -> {
        requests.add(url);
        String page = pages.get(url);
        if (page == null) throw new IOException("unexpected url: " + url);
        return page;
    };

    List<ComicModels.Chapter> chapters = new Mh18ComicSource(
            SourceConfig.mh18(true), session).chapters("mh18:meilixinshijie");

    assertEquals(java.util.Arrays.asList(catalogUrl, apiUrl), requests);
    assertEquals(252, chapters.size());
    assertEquals("33999", chapters.get(0).chapterId);
    assertEquals("第252話", chapters.get(251).title);
}

@Test
public void chaptersRejectAnApiHostOutside18mhBeforeFetchingIt() throws Exception {
    List<String> requests = new ArrayList<>();
    BrowserSession session = url -> {
        requests.add(url);
        return "<div id='allchapters' data-mid='28' data-host='https://evil.example'></div>"
                + "<a href='/manga/meilixinshijie/28-9821-0' data-cs='33999' "
                + "data-ct='第1話'></a>";
    };

    try {
        new Mh18ComicSource(SourceConfig.mh18(true), session)
                .chapters("mh18:meilixinshijie");
        fail("untrusted API host must be rejected");
    } catch (IOException error) {
        assertTrue(error.getMessage().contains("目录参数解析失败"));
    }
    assertEquals(1, requests.size());
}
```

- [ ] **Step 2: 运行目录测试并确认 RED**

```powershell
.\gradlew.bat :app:testDebugUnitTest --tests com.xxcomic.source.Mh18ComicSourceTest.chaptersLoadTheAsyncApiDeclaredByTheCatalogPage --tests com.xxcomic.source.Mh18ComicSourceTest.chaptersRejectAnApiHostOutside18mhBeforeFetchingIt --rerun-tasks --console=plain
```

Expected: 第一个测试因当前只解析 `Loading...` 页面而报“目录解析失败”；第二个测试因当前错误接受页面里的章节链接而未抛异常。

- [ ] **Step 3: 增加唯一的 API 主机校验方法**

在 `Mh18ComicSource` 增加：

```java
private String trustedApiBase(String tag, String errorMessage) throws IOException {
    try {
        URL url = new URL(attribute(tag, "data-host"));
        String host = url.getHost().toLowerCase(java.util.Locale.US);
        String domain = config.domain.toLowerCase(java.util.Locale.US);
        boolean trusted = host.equals(domain) || host.endsWith("." + domain);
        boolean defaultPort = url.getPort() == -1 || url.getPort() == 443;
        if (!"https".equalsIgnoreCase(url.getProtocol()) || !trusted || !defaultPort) {
            throw new IllegalArgumentException();
        }
        return "https://" + host;
    } catch (Exception error) {
        throw new IOException(errorMessage, error);
    }
}
```

该方法只复用 `java.net.URL`，不增加依赖，也不接受用户信息、自定义端口、HTTP 或站外主机。

- [ ] **Step 4: 先取目录容器，再请求真实目录接口**

将 `chapters()` 的开头改成：

```java
String rawId = rawComicId(comicId);
String catalog = fetch(absolute("/chapterlist/" + rawId));
String holder = tagWithAttribute(catalog, "id", "allchapters");
String mangaId = attribute(holder, "data-mid");
if (!mangaId.matches("\\d+")) throw new IOException("18漫画目录参数解析失败");
String apiBase = trustedApiBase(holder, "18漫画目录参数解析失败");
String html = fetch(apiBase + "/manga/get?mid=" + mangaId + "&mode=all");
```

保留现有锚点解析和去重逻辑，但继续要求链接属于当前 `rawId`、`data-cs` 与 `data-ct` 均非空。

- [ ] **Step 5: 运行整个 18漫画测试类并确认 GREEN**

```powershell
.\gradlew.bat :app:testDebugUnitTest --tests com.xxcomic.source.Mh18ComicSourceTest --rerun-tasks --console=plain
```

Expected: `BUILD SUCCESSFUL`，目录接口、恶意主机、搜索分页、详情结构化数据、正文图片和手动验证测试全部通过。

- [ ] **Step 6: 提交目录链路**

```powershell
git add app/src/main/java/com/xxcomic/source/Mh18ComicSource.java app/src/test/java/com/xxcomic/source/Mh18ComicSourceTest.java
git commit -m "fix: load 18mh chapters from async endpoint"
```

### Task 3: 对接 18漫画真实正文接口

**Files:**
- Modify: `app/src/test/java/com/xxcomic/source/Mh18ComicSourceTest.java`
- Modify: `app/src/main/java/com/xxcomic/source/Mh18ComicSource.java:169-183`

- [ ] **Step 1: 增加正文接口与主机白名单失败测试**

```java
@Test
public void chapterLoadsImagesFromTheApiDeclaredByTheChapterPage() throws Exception {
    String chapterUrl = "https://18mh.org/manga/meilixinshijie/28-9821-0";
    String apiUrl = "https://api.18mh.org/chapter/getcontent?m=28&c=33999";
    Map<String, String> pages = new LinkedHashMap<>();
    pages.put(chapterUrl, "<div id='chapterContent' data-ms='28' data-cs='33999' "
            + "data-ct='第1話' data-host='https://api.18mh.org'></div>");
    pages.put(apiUrl, "<img data-src='https://s3.mangabuddy.in/0.webp'>"
            + "<img src='data:image/gif;base64,transparent'>"
            + "<img src='https://s3.mangabuddy.in/1.webp'>");
    List<String> requests = new ArrayList<>();
    BrowserSession session = url -> {
        requests.add(url);
        String page = pages.get(url);
        if (page == null) throw new IOException("unexpected url: " + url);
        return page;
    };

    ComicModels.ChapterPage page = new Mh18ComicSource(
            SourceConfig.mh18(true), session).chapter(chapterUrl);

    assertEquals(java.util.Arrays.asList(chapterUrl, apiUrl), requests);
    assertEquals("第1話", page.title);
    assertEquals(2, page.imageUrls.size());
    assertEquals("https://s3.mangabuddy.in/1.webp", page.imageUrls.get(1));
}

@Test
public void chapterRejectsAnApiHostOutside18mh() throws Exception {
    BrowserSession session = url -> {
        if (url.contains("chapter/getcontent")) {
            return "<img src='https://s3.mangabuddy.in/incorrect.webp'>";
        }
        return "<div id='chapterContent' data-ms='28' data-cs='33999' "
                + "data-ct='第1話' data-host='https://evil.example'></div>";
    };

    try {
        new Mh18ComicSource(SourceConfig.mh18(true), session)
                .chapter("https://18mh.org/manga/meilixinshijie/28-9821-0");
        fail("untrusted API host must be rejected");
    } catch (IOException error) {
        assertTrue(error.getMessage().contains("章节参数解析失败"));
    }
}
```

- [ ] **Step 2: 运行正文测试并确认 RED**

```powershell
.\gradlew.bat :app:testDebugUnitTest --tests com.xxcomic.source.Mh18ComicSourceTest.chapterLoadsImagesFromTheApiDeclaredByTheChapterPage --tests com.xxcomic.source.Mh18ComicSourceTest.chapterRejectsAnApiHostOutside18mh --rerun-tasks --console=plain
```

Expected: 第一个测试因当前请求固定 `https://18mh.org/chapter/getcontent` 而失败；第二个测试因当前忽略 `data-host` 而错误成功。

- [ ] **Step 3: 使用已验证的正文 API 主机**

将 `chapter()` 中正文请求改为：

```java
String contentTag = tagWithAttribute(html, "id", "chapterContent");
String mangaId = attribute(contentTag, "data-ms");
String chapterId = attribute(contentTag, "data-cs");
String title = clean(attribute(contentTag, "data-ct"));
if (!mangaId.matches("\\d+") || !chapterId.matches("\\d+")) {
    throw new IOException("18漫画章节参数解析失败");
}
String apiBase = trustedApiBase(contentTag, "18漫画章节参数解析失败");
String content = fetch(apiBase + "/chapter/getcontent?m=" + mangaId + "&c=" + chapterId);
```

保留 `parseChapterImages()` 的现有顺序：优先 `data-src`，再取 `src`，只接受绝对 HTTP(S) 图片并去重。

- [ ] **Step 4: 运行 18漫画与共享会话测试并确认 GREEN**

```powershell
.\gradlew.bat :app:testDebugUnitTest --tests com.xxcomic.source.Mh18ComicSourceTest --tests com.xxcomic.CloudflareWebViewSessionTest --rerun-tasks --console=plain
```

Expected: `BUILD SUCCESSFUL`，两个测试类无失败。

- [ ] **Step 5: 提交正文链路**

```powershell
git add app/src/main/java/com/xxcomic/source/Mh18ComicSource.java app/src/test/java/com/xxcomic/source/Mh18ComicSourceTest.java
git commit -m "fix: load 18mh pages from declared endpoint"
```

### Task 4: 升级发布版本并锁定契约

**Files:**
- Modify: `app/build.gradle`
- Modify: `tools/check-detail-release.js`
- Modify: `tools/check-cuimh-source.js`
- Modify: `tools/check-rem-visual-contract.js`

- [ ] **Step 1: 更新 Android 版本**

```groovy
versionCode 36
versionName "1.0.36"
```

- [ ] **Step 2: 同步三个现有发布断言**

将三个脚本中的 `1.0.35`/`35` 精确替换为 `1.0.36`/`36`，不改其他契约。

- [ ] **Step 3: 运行版本和受保护站源契约**

```powershell
node tools/check-protected-source-session.js
node tools/check-detail-release.js
node tools/check-cuimh-source.js
node tools/check-rem-visual-contract.js
```

Expected: 四个脚本均退出码为 0，各自打印最终 contract-success 行。

- [ ] **Step 4: 提交发布版本**

```powershell
git add app/build.gradle tools/check-detail-release.js tools/check-cuimh-source.js tools/check-rem-visual-contract.js
git commit -m "chore: release android 1.0.36"
```

### Task 5: 完整验证与 Release 构建

**Files:**
- No tracked source changes expected.

- [ ] **Step 1: 运行完整 JVM 测试**

```powershell
.\gradlew.bat testDebugUnitTest testReleaseUnitTest --rerun-tasks --console=plain
```

Expected: `BUILD SUCCESSFUL`，无失败测试。

- [ ] **Step 2: 运行关键源码契约**

```powershell
node tools/check-protected-source-session.js
node tools/check-jmcomic-bootstrap.js
node tools/check-detail-release.js
node tools/check-cuimh-source.js
node tools/check-rem-visual-contract.js
node tools/check-release-regressions.js
```

Expected: 六个脚本均以退出码 0 完成。禁漫天堂契约通过证明本轮未产生行为回归。

- [ ] **Step 3: 构建 Release APK**

```powershell
.\gradlew.bat assembleRelease --rerun-tasks --console=plain
```

Expected: `BUILD SUCCESSFUL`，生成 `app/build/outputs/apk/release/app-release.apk`。

- [ ] **Step 4: 校验 APK 身份与签名**

```powershell
& 'C:\Users\15361\xx-android-sdk\build-tools\34.0.0\aapt.exe' dump badging app\build\outputs\apk\release\app-release.apk
& 'C:\Users\15361\xx-android-sdk\build-tools\34.0.0\apksigner.bat' verify --verbose --print-certs app\build\outputs\apk\release\app-release.apk
```

Expected: 包名 `com.xxcomic`、`versionCode='36'`、`versionName='1.0.36'`，签名验证成功。

- [ ] **Step 5: 检查提交范围并推送 master**

```powershell
git diff --check
git status --short
git log --oneline -6
git push origin master
```

Expected: 只有既有 `.gradle/`、`app/build/`、`.gradle-codex/`、`release/` 产物保持未提交；`master` 推送成功。

### Task 6: 生成发布物并更新 COS/服务器备用包

**Files:**
- Generate outside Git: `release/xx-comic-1.0.36.apk`
- Generate outside Git: `release/android-release.json`
- Generate outside Git: `release/android-release-1.0.36.json`
- Generate outside Git: `release/publish-cos-1.0.36.js`
- Generate outside Git: `release/run-publish-cos-1.0.36.js`
- Generate outside Git: `release/publish-server-1.0.36.sh`

- [ ] **Step 1: 复制 APK 并生成精确元数据**

```powershell
Copy-Item -LiteralPath 'app\build\outputs\apk\release\app-release.apk' -Destination 'release\xx-comic-1.0.36.apk'
$releaseHash = (Get-FileHash -Algorithm SHA256 -LiteralPath 'release\xx-comic-1.0.36.apk').Hash.ToLowerInvariant()
$releaseSize = (Get-Item -LiteralPath 'release\xx-comic-1.0.36.apk').Length
```

用实际哈希和大小机械生成两份相同元数据：

```powershell
$releaseMetadata = [ordered]@{
    versionName = '1.0.36'
    versionCode = 36
    size = [long]$releaseSize
    sha256 = $releaseHash
} | ConvertTo-Json
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Resolve-Path 'release').Path + '\android-release.json', $releaseMetadata + "`n", $utf8NoBom)
[System.IO.File]::WriteAllText((Resolve-Path 'release').Path + '\android-release-1.0.36.json', $releaseMetadata + "`n", $utf8NoBom)
```

- [ ] **Step 2: 生成 COS 发布脚本**

`release/publish-cos-1.0.36.js`：

```javascript
const fs = require("fs");
const COS = require("/opt/xtra/gateway/node_modules/cos-nodejs-sdk-v5");

const apkPath = "/tmp/xx-comic-1.0.36.apk";
const cos = new COS({
  SecretId: process.env.COS_SECRET_ID,
  SecretKey: process.env.COS_SECRET_KEY,
});

cos.putObject({
  Bucket: process.env.COS_BUCKET,
  Region: process.env.COS_REGION,
  Key: "apk/xx-comic/xx-comic.bin",
  Body: fs.createReadStream(apkPath),
  ContentLength: fs.statSync(apkPath).size,
  ContentType: "application/octet-stream",
  CacheControl: "no-cache",
}, (error, data) => {
  if (error) {
    console.error(error.message || error);
    process.exitCode = 1;
    return;
  }
  console.log(JSON.stringify({ statusCode: data.statusCode, location: data.Location }));
});
```

`release/run-publish-cos-1.0.36.js`：

```javascript
const fs = require("fs");
const { execFileSync } = require("child_process");

const pid = execFileSync("systemctl", [
  "show", "xx-agent.service", "-p", "MainPID", "--value",
], { encoding: "utf8" }).trim();

for (const entry of fs.readFileSync(`/proc/${pid}/environ`, "utf8").split("\0")) {
  const separator = entry.indexOf("=");
  if (separator > 0 && entry.startsWith("COS_")) {
    process.env[entry.slice(0, separator)] = entry.slice(separator + 1);
  }
}

require("/tmp/publish-cos-1.0.36.js");
```

- [ ] **Step 3: 生成服务器原子发布脚本**

`release/publish-server-1.0.36.sh`：

```bash
#!/usr/bin/env bash
set -euo pipefail

apk=/tmp/xx-comic-1.0.36.apk
metadata=/tmp/android-release-1.0.36.json
release_root=/var/lib/xx-comic/releases

expected=$(node - "$metadata" "$apk" <<'NODE'
const fs = require("fs");
const release = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
const size = fs.statSync(process.argv[3]).size;
if (release.versionName !== "1.0.36"
    || release.versionCode !== 36
    || release.size !== size
    || !/^[a-f0-9]{64}$/.test(release.sha256)) {
  throw new Error("release metadata mismatch");
}
process.stdout.write(release.sha256);
NODE
)

printf '%s  %s\n' "$expected" "$apk" | sha256sum -c - >/dev/null
if [[ ! -e "$release_root/android/xx-comic.apk.bak-1.0.35" ]]; then
  cp -p -- "$release_root/android/xx-comic.apk" \
    "$release_root/android/xx-comic.apk.bak-1.0.35"
fi
if [[ ! -e "$release_root/android-release.json.bak-1.0.35" ]]; then
  cp -p -- "$release_root/android-release.json" \
    "$release_root/android-release.json.bak-1.0.35"
fi

install -m 0644 -- "$apk" "$release_root/android/xx-comic.apk.tmp"
install -m 0644 -- "$metadata" "$release_root/android-release.json.tmp"
mv -f -- "$release_root/android/xx-comic.apk.tmp" "$release_root/android/xx-comic.apk"
mv -f -- "$release_root/android-release.json.tmp" "$release_root/android-release.json"

printf '%s  %s\n' "$expected" "$release_root/android/xx-comic.apk" \
  | sha256sum -c - >/dev/null
cmp -s -- "$metadata" "$release_root/android-release.json"
```

- [ ] **Step 4: 上传临时文件并执行两个发布动作**

```powershell
scp release\xx-comic-1.0.36.apk root@123.207.35.196:/tmp/xx-comic-1.0.36.apk
scp release\android-release-1.0.36.json root@123.207.35.196:/tmp/android-release-1.0.36.json
scp release\publish-cos-1.0.36.js root@123.207.35.196:/tmp/publish-cos-1.0.36.js
scp release\run-publish-cos-1.0.36.js root@123.207.35.196:/tmp/run-publish-cos-1.0.36.js
scp release\publish-server-1.0.36.sh root@123.207.35.196:/tmp/publish-server-1.0.36.sh
ssh root@123.207.35.196 "node /tmp/run-publish-cos-1.0.36.js"
ssh root@123.207.35.196 "bash /tmp/publish-server-1.0.36.sh"
```

Expected: COS 返回成功状态；服务器脚本退出码为 0。

- [ ] **Step 5: 从两个公网地址回下载并核对**

```powershell
Invoke-WebRequest -Uri 'https://xx-1321588235.cos.ap-guangzhou.myqcloud.com/apk/xx-comic/xx-comic.bin' -OutFile 'release\verify-cos-1.0.36.tmp.apk'
Invoke-WebRequest -Uri 'https://weifeng.cloud/xx-comic/releases/xx-comic.apk' -OutFile 'release\verify-server-1.0.36.tmp.apk'
Invoke-WebRequest -Uri 'https://weifeng.cloud/xx-comic/releases/android-release.json' -OutFile 'release\verify-metadata-1.0.36.tmp.json'
Get-FileHash -Algorithm SHA256 release\xx-comic-1.0.36.apk,release\verify-cos-1.0.36.tmp.apk,release\verify-server-1.0.36.tmp.apk
Get-Content -Raw release\verify-metadata-1.0.36.tmp.json
```

Expected: 三个 APK 的 SHA-256 完全一致；公开元数据为 `1.0.36 (36)`，大小和小写 SHA-256 与本地一致。

- [ ] **Step 6: 最终 Git 与公开发布状态检查**

```powershell
git status --short --branch
git rev-parse HEAD
git rev-parse origin/master
```

Expected: `HEAD` 等于 `origin/master`；未跟踪/已修改内容仍仅为构建和发布产物，没有遗漏源文件。
