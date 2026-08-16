# Protected Source Cache And VPN Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 恢复 18漫画和禁漫天堂列表，建立可清理的原生验证缓存，并在站源管理中提供 VPN 标记和手动验证入口。

**Architecture:** 保留每个受保护站源一个 `CloudflareWebViewSession` 的现有边界，由 Android `CookieManager` 持久化且按域隔离验证 Cookie。状态机仅在未处于验证流程时把主文档 HTTP 错误判为失败；缓存清理统一清 Cookie、WebStorage 和两个 WebView 页面缓存。

**Tech Stack:** Android Java、WebView/CookieManager/WebStorage、JUnit 4、Node 源码契约、Gradle、腾讯云 COS。

---

### Task 1: 修复验证后列表被旧 403 拒绝

**Files:**
- Modify: `app/src/test/java/com/xxcomic/CloudflareWebViewSessionTest.java`
- Modify: `app/src/main/java/com/xxcomic/CloudflareWebViewSession.java`

- [ ] **Step 1: 写失败测试**

```java
@Test
public void completedVerificationIgnoresChallengeResponseStatus() {
    assertEquals(CloudflareWebViewSession.PageAction.CAPTURE,
            CloudflareWebViewSession.pageAction(true, false, true, 403));
}
```

- [ ] **Step 2: 运行聚焦测试并确认失败**

Run: `.\gradlew.bat testDebugUnitTest --tests com.xxcomic.CloudflareWebViewSessionTest --no-daemon`

Expected: FAIL，实际值为 `FAIL`。

- [ ] **Step 3: 最小修正状态机**

```java
if (statusCode >= 400 && !verifying) return PageAction.FAIL;
```

- [ ] **Step 4: 重跑聚焦测试并确认通过**

Run: `.\gradlew.bat testDebugUnitTest --tests com.xxcomic.CloudflareWebViewSessionTest --no-daemon`

Expected: PASS。

### Task 2: 把验证数据纳入缓存清理

**Files:**
- Modify: `app/src/main/java/com/xxcomic/CloudflareWebViewSession.java`
- Modify: `app/src/main/java/com/xxcomic/MainActivity.java`
- Modify: `tools/check-protected-source-session.js`
- Modify: `tools/check-android-source.js`

- [ ] **Step 1: 在源码契约中要求原生验证缓存可被清理**

要求契约检查 `CookieManager.removeAllCookies`、`WebStorage.getInstance().deleteAllData()`、两个会话的 `clearCache()`，并确认清理文案包含验证缓存。

- [ ] **Step 2: 运行契约并确认失败**

Run: `node tools/check-protected-source-session.js` 和 `node tools/check-android-source.js`

Expected: FAIL，提示缺少验证缓存清理。

- [ ] **Step 3: 增加会话和全局缓存清理**

```java
void clearCache() {
    main.post(() -> {
        if (webView != null) {
            webView.clearCache(true);
            webView.clearHistory();
        }
    });
}
```

`MainActivity.clearAppCache()` 调用两个会话的 `clearCache()`，再调用 `CookieManager.removeAllCookies`、`flush` 与 `WebStorage.deleteAllData()`；不清站源配置、收藏、历史和进度。

- [ ] **Step 4: 重跑契约并确认通过**

Run: `node tools/check-protected-source-session.js` 和 `node tools/check-android-source.js`

Expected: PASS。

### Task 3: 增加 VPN 标记和手动验证

**Files:**
- Create: `app/src/test/java/com/xxcomic/ProtectedSourceUiTest.java`
- Modify: `app/src/main/java/com/xxcomic/MainActivity.java`
- Modify: `tools/check-settings-visual-contract.js`

- [ ] **Step 1: 写站源能力失败测试**

```java
@Test public void vpnSourcesAreExplicit() {
    assertTrue(MainActivity.requiresVpn("mh18"));
    assertTrue(MainActivity.requiresVpn("jmcomic"));
    assertTrue(MainActivity.requiresVpn("hiperdex"));
    assertTrue(MainActivity.requiresVpn("hanman18"));
    assertTrue(MainActivity.requiresVpn("manhuagui"));
    assertFalse(MainActivity.requiresVpn("baozimh"));
}

@Test public void onlyProtectedSourcesCanBeVerifiedManually() {
    assertTrue(MainActivity.supportsManualVerification("mh18"));
    assertTrue(MainActivity.supportsManualVerification("jmcomic"));
    assertFalse(MainActivity.supportsManualVerification("hiperdex"));
}
```

- [ ] **Step 2: 运行测试和 UI 契约并确认失败**

Run: `.\gradlew.bat testDebugUnitTest --tests com.xxcomic.ProtectedSourceUiTest --no-daemon` 和 `node tools/check-settings-visual-contract.js`

Expected: FAIL，能力方法与验证按钮尚不存在。

- [ ] **Step 3: 最小实现卡片能力和验证动作**

将 `sourceCard` 改为接收 `SourceConfig`。五个指定站源在标题旁显示无边框 `VPN` 文本；18漫画和禁漫天堂在开关左侧显示无边框“验证”按钮。点击后在 `sourceHealthIo` 中调用对应 `client.latest(1)`，列表非空显示“验证完成”，异常或空列表显示轻量失败提示。

- [ ] **Step 4: 重跑测试和契约并确认通过**

Run: `.\gradlew.bat testDebugUnitTest --tests com.xxcomic.ProtectedSourceUiTest --no-daemon` 和 `node tools/check-settings-visual-contract.js`

Expected: PASS。

### Task 4: 版本、完整验证和发布

**Files:**
- Modify: `app/build.gradle`
- Modify: `tools/check-cuimh-source.js`
- Modify: `tools/check-detail-release.js`
- Modify: `tools/check-rem-visual-contract.js`
- Publish: `release/xx-comic-1.0.31.apk`
- Publish: `release/android-release.json`

- [ ] **Step 1: 升级到 `1.0.31 (31)` 并同步三个版本契约**

把 `app/build.gradle` 的 `versionCode/versionName` 改为 `31/1.0.31`，并把三个脚本中的旧版本断言同步为新版本。

- [ ] **Step 2: 运行完整 JVM 测试、受影响源码契约和空白检查**

Run: `.\gradlew.bat test --no-daemon --rerun-tasks`；逐个运行本计划涉及的 Node 脚本；运行 `git diff --check`。

Expected: 所有命令退出码为 0，JUnit 无 failure/error。

- [ ] **Step 3: 构建并核验 Release APK**

Run: `.\gradlew.bat assembleRelease --no-daemon --rerun-tasks`，随后使用 SDK 34 的 `aapt.exe`、`apksigner.bat` 和 `Get-FileHash` 检查 APK。

Expected: `com.xxcomic`、`1.0.31 (31)`、v1/v2 签名有效，并记录大小与 SHA-256。

- [ ] **Step 4: 精确提交并推送**

只暂存本计划列出的源码、测试、文档和契约文件；确认 `.gradle/`、`app/build/`、`.gradle-codex/`、`release/` 未进入暂存区。提交后运行 `git push origin master`。

- [ ] **Step 5: 发布并回下载验证**

把 APK 上传到 COS `apk/xx-comic/xx-comic.bin`，同步 `/var/lib/xx-comic/releases/android/xx-comic.apk` 和 `/var/lib/xx-comic/releases/android-release.json`。从 COS 与 `https://weifeng.cloud/xx-comic/releases/xx-comic.apk` 回下载，要求二者大小和 SHA-256 与本地发布包完全一致。
