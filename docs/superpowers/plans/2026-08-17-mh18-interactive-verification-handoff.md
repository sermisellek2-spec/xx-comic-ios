# 18漫画交互验证接管 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 18漫画自动列表请求在 Cloudflare 必须人工勾选时展示一次验证页，并在交互提交后立即回到 App、后台完成验证和原请求。

**Architecture:** 扩展现有 `CloudflareWebViewSession` 的配置和纯状态判断，不创建新会话或验证队列。只有 18漫画开启自动请求交互接管；同一个 WebView 观察 Turnstile 响应或新 `cf_clearance` 后隐藏，最终业务页完成后沿用现有 DOM 捕获路径。

**Tech Stack:** Android Java、平台 WebView/CookieManager、JUnit 4、Node.js 源码契约、Gradle、腾讯云 COS。

---

### Task 1: 锁定交互接管策略

**Files:**
- Modify: `app/src/test/java/com/xxcomic/CloudflareWebViewSessionTest.java`
- Modify: `tools/check-protected-source-session.js`

- [ ] **Step 1: 写自动请求交互与立即隐藏的失败测试**

在 `CloudflareWebViewSessionTest` 增加纯策略断言：显式交互始终允许；普通会话的自动请求不允许；开启自动接管的 18漫画允许；只有验证 UI 已显示且 Turnstile 已提交或 `cf_clearance` 已变化时才隐藏。

- [ ] **Step 2: 执行目标测试并确认 RED**

Run: `./gradlew.bat :app:testDebugUnitTest --tests com.xxcomic.CloudflareWebViewSessionTest --rerun-tasks --console=plain`

Expected: FAIL，提示缺少自动接管或交互完成策略方法。

- [ ] **Step 3: 扩充源码隔离契约并确认 RED**

要求 18漫画构造显式开启新配置、禁漫天堂构造不启用，并要求页面检查读取 `cf-turnstile-response`。执行 `node tools/check-protected-source-session.js`，预期因生产代码尚未实现而失败。

### Task 2: 最小实现 18漫画交互验证接管

**Files:**
- Modify: `app/src/main/java/com/xxcomic/CloudflareWebViewSession.java`
- Modify: `app/src/main/java/com/xxcomic/MainActivity.java`

- [ ] **Step 1: 增加向后兼容的会话配置**

保留现有五参数和六参数构造函数，新增完整构造函数接收 `automaticInteractiveFallback`。请求的有效交互权限由显式 `fetchInteractive()` 或该配置共同决定。

- [ ] **Step 2: 读取验证提交信号**

在现有页面检查脚本中增加布尔 `turnstileSolved`，来源是 `cf-turnstile-response` 隐藏字段是否已有值；请求开始时记录 `cf_clearance`，轮询时比较当前值。

- [ ] **Step 3: 验证提交后立即退回后台**

验证页可见且 Turnstile 已提交或 `cf_clearance` 已变化时，立即调用现有后台视图路径并记录本次交互已收起。WebView 不销毁、不停止加载；最终 `CAPTURE` 分支仍以挑战消失且页面完成为成功条件，只在此时提示“验证完成”。

- [ ] **Step 4: 只为 18漫画启用**

`MainActivity` 的 18漫画会话开启完整视口和自动交互接管；禁漫天堂保留原五参数构造。

- [ ] **Step 5: 执行 GREEN 和回归检查**

Run:

```powershell
./gradlew.bat :app:testDebugUnitTest --tests com.xxcomic.CloudflareWebViewSessionTest --rerun-tasks --console=plain
node tools/check-protected-source-session.js
./gradlew.bat :app:testDebugUnitTest --rerun-tasks --console=plain
```

Expected: 全部 PASS。

### Task 3: 版本与发布

**Files:**
- Modify: `app/build.gradle`
- Modify: existing tracked release-version contract files found by `rg "1.0.37|versionCode 37"`
- Generate outside commit scope: `release/xx-comic-1.0.38.apk` and release metadata/scripts

- [ ] **Step 1: 升级版本并验证版本契约**

将 Android 版本升级为 `1.0.38 (38)`，只同步现有测试或契约中的精确版本断言。

- [ ] **Step 2: 构建并核验 Release APK**

Run: `./gradlew.bat :app:assembleRelease --console=plain`

使用 Android build-tools 核对包名、版本、签名，计算文件大小和 SHA-256。

- [ ] **Step 3: 精确提交并推送 master**

只暂存本设计、计划、测试、18漫画验证会话改动和版本文件；不暂存 `.gradle/`、`app/build/` 或既有 `release/` 产物。推送前确认 `origin/master` 未产生新提交。

- [ ] **Step 4: 上传并回下载核验**

将同一个 APK 上传到 COS `apk/xx-comic/xx-comic.bin`，使用 `C:\Users\15361\.ssh\xx-agent-deploy` 同步服务器备用 APK 和更新元数据。从 COS 公网地址和服务器备用地址重新下载，要求两者大小、SHA-256 与本地 APK 完全一致。

## 计划自检

- 需求覆盖：必要时展示、勾选后立即隐藏、后台续接、18漫画独立、构建发布均有对应步骤。
- 范围：不修改禁漫天堂解析或验证行为，不新增依赖。
- 状态一致：交互提交只负责隐藏，最终业务页完成才负责宣告成功和返回 HTML。
