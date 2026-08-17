# 18漫画严格可见验证 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 18漫画在 Cloudflare 挑战真正完成后才关闭验证页，并发布 Android `1.0.40 (40)`。

**Architecture:** 复用现有单 WebView 会话和页面轮询。把自动交互模式作为“必须等到目标页捕获”的严格模式，仅阻止 Turnstile token 或 clearance 变化触发提前交回；最终成功仍由现有 `CAPTURE` 分支判定。

**Tech Stack:** Android Java、平台 WebView、JUnit 4、Node.js 源码契约、Gradle、腾讯云 COS。

---

### Task 1: 锁定严格验证判定

**Files:**
- Modify: `app/src/test/java/com/xxcomic/CloudflareWebViewSessionTest.java`
- Modify: `app/src/main/java/com/xxcomic/CloudflareWebViewSession.java`
- Modify: `tools/check-protected-source-session.js`

- [ ] **Step 1: 写失败测试**

给 `shouldHandOffInteractive` 增加 `keepVisibleUntilPageReady` 输入，新增断言：该输入为 `true` 时，即使 Turnstile token 已生成或 clearance 已变化也返回 `false`；输入为 `false` 时保留现有行为。

- [ ] **Step 2: 运行 RED**

```powershell
./gradlew.bat :app:testDebugUnitTest --tests com.xxcomic.CloudflareWebViewSessionTest --rerun-tasks --console=plain
```

Expected: 测试编译因新方法签名尚不存在而失败。

- [ ] **Step 3: 最小实现**

`shouldHandOffInteractive` 在 `keepVisibleUntilPageReady=true` 时直接返回 `false`。调用处传入 `automaticInteractiveFallback`；删除不再可达的“放到 App 下层继续验证”视图状态，非严格模式仍调用 `showBackgroundView()`。

- [ ] **Step 4: 更新源码契约并运行 GREEN**

源码契约要求自动交互参数参与提前交回判定，并禁止重新出现 `showCompletingBehindApp`。运行聚焦 JVM 测试和 `node tools/check-protected-source-session.js`，预期全部通过。

### Task 2: 发布 1.0.40

**Files:**
- Modify: `app/build.gradle`
- Modify: `tools/check-cuimh-source.js`
- Modify: `tools/check-detail-release.js`
- Modify: `tools/check-rem-visual-contract.js`
- Generate outside Git: `release/xx-comic-1.0.40.apk`、发布元数据和上传辅助文件

- [ ] **Step 1: 递增版本**

设置 `versionCode 40`、`versionName "1.0.40"`，同步三个当前版本契约。

- [ ] **Step 2: 完整验证和构建**

```powershell
./gradlew.bat :app:testDebugUnitTest --rerun-tasks --console=plain
node tools/check-protected-source-session.js
node tools/check-release-regressions.js
node tools/check-detail-release.js
node tools/check-cuimh-source.js
node tools/check-rem-visual-contract.js
./gradlew.bat :app:assembleRelease --console=plain
git diff --check
```

Expected: 所有命令退出码为 0，并生成 `app/build/outputs/apk/release/app-release.apk`。

- [ ] **Step 3: 核验、提交和推送**

使用 Android build-tools 核对包名 `com.xxcomic`、版本 `1.0.40 (40)` 和签名；精确暂存本计划中的源码、测试、文档和版本契约，排除 `.gradle/`、`.gradle-codex/`、`app/build/`、`release/`，提交并推送 `master`。

- [ ] **Step 4: 发布并回下载核对**

上传同一 APK 到 COS `apk/xx-comic/xx-comic.bin`，同步服务器备用 APK 和公开元数据。从 COS 与服务器地址回下载，要求大小、SHA-256 与本地 `release/xx-comic-1.0.40.apk` 完全一致。

## 计划自检

- 覆盖用户确认的严格可见交互、18漫画限定范围和完整发布流程。
- 不包含 UA、Cookie 或解析器调整，避免一次改变多个变量。
- 无占位步骤，版本和验证命令明确。
