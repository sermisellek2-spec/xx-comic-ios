# 禁漫天堂与 Cloudflare 会话修复实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修复 18漫画验证后页面无法触摸的问题，新增禁漫天堂站源，并发布 Android `1.0.27 (27)`。

**Architecture:** 用一个基于 Activity 内容层的通用 `CloudflareWebViewSession` 替代持久模态 Dialog；18漫画和禁漫天堂各持有独立 WebView 会话并通过共享 `BrowserSession` 接口请求页面。禁漫正文解析页面声明的 `page_arr`、`aid`、`scramble_id` 和 CDN 主机，图片下载后在阅读解码阶段按官方分片规则恢复。

**Tech Stack:** Android Java、平台 WebView/CookieManager、HttpURLConnection、org.json、Android Gradle Plugin 7.4.2、腾讯云 COS、SSH 备用发布服务器。

---

### Task 1: 修复浏览器验证宿主

**Files:**
- Create: `app/src/main/java/com/xxcomic/source/BrowserSession.java`
- Create: `app/src/main/java/com/xxcomic/CloudflareWebViewSession.java`
- Delete: `app/src/main/java/com/xxcomic/Mh18WebViewSession.java`
- Modify: `app/src/main/java/com/xxcomic/source/Mh18ComicSource.java`
- Modify: `app/src/main/java/com/xxcomic/MainActivity.java`

- [ ] **Step 1:** 将 `fetch(String url)` 提取为共享 `BrowserSession` 接口，18漫画改用该接口。
- [ ] **Step 2:** 将 WebView 宿主加入 `android.R.id.content`，验证时全屏显示“正在验证/验证完成”，完成后缩为 `1x1` 并禁用点击。
- [ ] **Step 3:** 保持 WebView、Cookie 和 JS 会话存活；Activity 销毁时移除宿主并销毁 WebView。
- [ ] **Step 4:** 在 `MainActivity` 中用参数化会话初始化 18漫画，验证地址为 `https://18mh.org/manga`。

### Task 2: 新增禁漫天堂站源

**Files:**
- Create: `app/src/main/java/com/xxcomic/source/JmComicSource.java`
- Modify: `app/src/main/java/com/xxcomic/source/SourceConfig.java`
- Modify: `app/src/main/java/com/xxcomic/MainActivity.java`

- [ ] **Step 1:** 增加 `jmcomic` 配置，路由固定为 `/albums?o=mr&page={page}`、`/search/photos`、`/theme/`、`/album/{comicId}` 和 `/photo/{chapterId}`。
- [ ] **Step 2:** 列表仅解析 `/album/{数字}` 卡片，封面优先 `data-original`，标题优先 `title` 和 `alt`。
- [ ] **Step 3:** 详情解析 `#book-name`、封面、作者、分类标签、描述；目录解析 `/photo/{数字}`、`data-album` 和 `.h2_series`。
- [ ] **Step 4:** 正文用 `JSONArray` 解析 `page_arr`，并从页面读取 `aid`、`scramble_id`、`cdnImgHost` 后生成真实图片 URL。
- [ ] **Step 5:** `/theme/` 按 `h4 + ul` 动态生成筛选组，只保留站内 `/search/photos` 与 `/albums` 链接。
- [ ] **Step 6:** 在设置、单站/全站搜索、详情路由、偏好、导入导出、健康检测和图片 Referer 的全部显式注册点增加第 14 个站源。

### Task 3: 恢复禁漫正文图片

**Files:**
- Modify: `app/src/main/java/com/xxcomic/MainActivity.java`

- [ ] **Step 1:** 阅读图片解码接收原始 URL，仅对 `cdn-msp*.18comic.vip/media/photos/` 执行恢复。
- [ ] **Step 2:** `aid < scramble_id` 不处理；旧图使用 10 段，新图按 `MD5(aid + filename)` 最后一位和 8/10 除数计算偶数分片数。
- [ ] **Step 3:** 将纵向分片逆序绘制到新 Bitmap，余数归第一段；封面和其他站源图片保持现状。

### Task 4: 发布 1.0.27

**Files:**
- Modify: `app/build.gradle`
- Modify: `tools/check-release-regressions.js`
- Modify: `tools/check-settings-visual-contract.js`
- Modify: `tools/check-detail-release.js`
- Modify: `tools/check-cuimh-source.js`
- Modify: `tools/check-rem-visual-contract.js`
- Publish outside Git: `release/xx-comic-1.0.27.apk`
- Publish outside Git: `release/android-release.json`

- [ ] **Step 1:** 设置 `versionCode 27`、`versionName "1.0.27"`，同步版本和 14 个站源的源码契约常量。
- [ ] **Step 2:** 按用户要求不运行测试，只执行 `./gradlew.bat :app:assembleRelease --no-daemon`。
- [ ] **Step 3:** 校验包名 `com.xxcomic`、版本 `1.0.27 (27)`、签名、字节数和 SHA-256，生成不可变 APK 与元数据。
- [ ] **Step 4:** 只暂存源码、计划和契约文件，排除 `.gradle`、`app/build` 和既有 `release` 脏文件；提交并推送 `master`。
- [ ] **Step 5:** 上传 COS `apk/xx-comic/xx-comic.bin`，同步服务器 APK 与元数据，回下载两个公网 APK 并要求 SHA-256 与本地一致。
