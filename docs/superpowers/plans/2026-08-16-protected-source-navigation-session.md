# Protected Source Navigation Session Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让18漫画和禁漫天堂在同一个 WebView 中直接加载目标页，只在真实挑战发生时显示一次验证，并恢复禁漫分类。

**Architecture:** `CloudflareWebViewSession` 不再先验证再 `fetch`。每个请求直接导航到目标 URL，用小型页面状态机决定等待、显示验证或捕获 DOM，再通过现有 JavaScript bridge 返回完整页面。

**Tech Stack:** Android Java、平台 WebView/CookieManager、JUnit 4、Android Gradle Plugin 7.4.2、腾讯云 COS。

---

### Task 1: 锁定页面状态机

**Files:**
- Modify: `app/src/test/java/com/xxcomic/CloudflareWebViewSessionTest.java`
- Create: `tools/check-protected-source-session.js`

- [ ] **Step 1: 写失败单元测试**

为普通页面、首次挑战、持续挑战和验证完成分别断言 `CAPTURE`、`SHOW_VERIFICATION`、`KEEP_VERIFYING`、`CAPTURE`。

- [ ] **Step 2: 写失败源码契约**

```js
check("loads the requested URL directly", source.includes("webView.loadUrl(request.url)"));
check("captures the current DOM", source.includes("document.documentElement.outerHTML"));
check("does not issue a second fetch", !source.includes("fetch(url"));
```

- [ ] **Step 3: 运行测试并确认失败**

Run: `./gradlew.bat :app:testDebugUnitTest --tests com.xxcomic.CloudflareWebViewSessionTest --no-daemon`

Expected: FAIL，因为页面动作 API 和目标页直达尚不存在。

### Task 2: 改为目标页直达

**Files:**
- Modify: `app/src/main/java/com/xxcomic/CloudflareWebViewSession.java`
- Modify: `app/src/main/java/com/xxcomic/MainActivity.java`

- [ ] **Step 1: 实现最小页面动作**

```java
static PageAction pageAction(boolean verifying, boolean challenge, boolean ready) {
    if (challenge) return verifying ? PageAction.KEEP_VERIFYING : PageAction.SHOW_VERIFICATION;
    return ready ? PageAction.CAPTURE : PageAction.WAIT;
}
```

- [ ] **Step 2: 直接导航并捕获 DOM**

`startRequest()` 调用 `webView.loadUrl(request.url)`；`onPageFinished()` 检查当前页面，普通页面通过 bridge 返回 `document.documentElement.outerHTML`。删除固定验证 URL、`browserReady`、验证次数和页面内 `fetch()`。

- [ ] **Step 3: 运行聚焦测试**

Run: `./gradlew.bat :app:testDebugUnitTest --tests com.xxcomic.CloudflareWebViewSessionTest --tests com.xxcomic.source.JmComicSourceTest --no-daemon`

Expected: PASS。

### Task 3: 发布 1.0.29

**Files:**
- Modify: `app/build.gradle`
- Modify: `tools/check-cuimh-source.js`
- Modify: `tools/check-detail-release.js`
- Modify: `tools/check-rem-visual-contract.js`
- Publish: `release/xx-comic-1.0.29.apk`
- Publish: `release/android-release.json`

- [ ] **Step 1: 设置版本**

将 `versionCode` 改为 `29`，`versionName` 改为 `1.0.29`，同步三个版本契约。

- [ ] **Step 2: 完整验证和构建**

Run: `./gradlew.bat :app:testDebugUnitTest :app:assembleRelease --no-daemon`

Expected: BUILD SUCCESSFUL。

- [ ] **Step 3: 校验并提交**

用 `aapt` 和 `apksigner` 校验包名、版本和签名，计算大小及 SHA-256。只暂存本计划列出的源码、测试和契约文件，提交并推送 `master`。

- [ ] **Step 4: 发布并回下载**

上传同一 APK 到 COS `apk/xx-comic/xx-comic.bin` 与服务器备用路径，更新公开元数据；从两个公网地址回下载，要求大小和 SHA-256 与本地完全一致。
