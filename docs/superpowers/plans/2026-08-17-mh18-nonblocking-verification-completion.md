# 18漫画非阻塞验证完成 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 18漫画 Turnstile 提交后恢复可操作的 App 主界面，同时保持 WebView 的前台运行条件直到 Cloudflare 真正完成验证。

**Architecture:** 复用现有单 WebView 会话和页面轮询，只新增一个介于“交互验证”和“离屏后台”之间的视图状态。该状态不改变 WebView 几何、透明度或生命周期，仅把 App 根内容提升到其上方；最终成功仍由挑战 DOM 消失、目标 URL 和页面完成共同判定。

**Tech Stack:** Android Java、平台 WebView/ViewGroup、JUnit 4、Node.js 源码契约、Gradle、腾讯云 COS。

---

### Task 1: 锁定验证提交后的视图语义

**Files:**
- Modify: `app/src/test/java/com/xxcomic/CloudflareWebViewSessionTest.java`
- Modify: `tools/check-protected-source-session.js`

- [ ] **Step 1: 写失败的状态策略测试**

将旧 `shouldDismissInteractive` 断言替换为 `shouldHandOffInteractive`：只有验证 UI 已显示且 Turnstile 已提交或 `cf_clearance` 已变化时才把控制权交还 App。方法名明确该信号不是最终验证成功。

- [ ] **Step 2: 写失败的视图契约**

在源码契约中要求提交路径调用 `showCompletingBehindApp()`；该方法必须使用 `verificationLayoutParams()`、`translationX=0`、`alpha=1`，并把已记录的 App 根内容 `bringToFront()`。该方法不得调用 `showBackgroundView()`。

- [ ] **Step 3: 执行 RED**

Run:

```powershell
./gradlew.bat :app:testDebugUnitTest --tests com.xxcomic.CloudflareWebViewSessionTest --rerun-tasks --console=plain
node tools/check-protected-source-session.js
```

Expected: JUnit 因 `shouldHandOffInteractive` 不存在而失败；源码契约因 `showCompletingBehindApp` 不存在而失败。

### Task 2: 最小实现非阻塞完成状态

**Files:**
- Modify: `app/src/main/java/com/xxcomic/CloudflareWebViewSession.java`

- [ ] **Step 1: 记录 App 根内容**

`ensureViews()` 在向 `android.R.id.content` 添加 WebView host 前记录其第一个既有子 View，作为 App 根内容。关闭会话时清除引用。

- [ ] **Step 2: 实现完成阶段视图**

新增 `showCompletingBehindApp()`：host 保持全尺寸和屏幕内，WebView 保持 `alpha=1`，host/WebView 均不接收点击，状态卡隐藏，最后调用 App 根内容的 `bringToFront()`。方法不停止或重新加载 WebView。

- [ ] **Step 3: 替换过早后台化**

Turnstile 响应或凭证变化时将 `interactiveVisible=false`，提示“正在完成验证”，调用 `showCompletingBehindApp()`。最终 `CAPTURE` 和请求结束仍调用原 `showBackgroundView()`。

- [ ] **Step 4: 执行 GREEN 与完整回归**

Run:

```powershell
./gradlew.bat :app:testDebugUnitTest --tests com.xxcomic.CloudflareWebViewSessionTest --rerun-tasks --console=plain
node tools/check-protected-source-session.js
./gradlew.bat :app:testDebugUnitTest --rerun-tasks --console=plain
node tools/check-release-regressions.js
```

Expected: 全部 PASS。

### Task 3: 发布 1.0.39

**Files:**
- Modify: `app/build.gradle`
- Modify: `tools/check-cuimh-source.js`
- Modify: `tools/check-detail-release.js`
- Modify: `tools/check-rem-visual-contract.js`
- Generate outside Git: `release/xx-comic-1.0.39.apk` and matching metadata/publish scripts

- [ ] **Step 1: 升级版本契约**

将版本升级为 `1.0.39 (39)`，同步三个现有精确版本检查，不改历史设计文档。

- [ ] **Step 2: 构建并核验 APK**

Run: `./gradlew.bat :app:assembleRelease --console=plain`

使用 SDK build-tools 核对包名、版本、v1/v2 签名、文件大小和 SHA-256。

- [ ] **Step 3: 精确提交并推送 master**

只暂存本次文档、会话实现、测试、源码契约和版本文件；不暂存 `.gradle/`、`app/build/`、`.gradle-codex/` 或 `release/` 产物。推送前 fetch 并确认远端没有新提交。

- [ ] **Step 4: 发布并回下载核验**

使用 `C:\Users\15361\.ssh\xx-agent-deploy` 将同一 APK 上传到 COS `apk/xx-comic/xx-comic.bin`，并原子替换服务器备用 APK 与元数据。从 COS 和服务器公网地址重新下载，要求两份文件与本地 APK 的大小、SHA-256 完全一致。

## 计划自检

- 需求覆盖：勾选、立即恢复 App、WebView 持续活跃、非阻塞切换、最终成功判定、发布均有对应步骤。
- 状态边界：交互提交与验证成功保持为两个不同状态。
- 范围：不修改禁漫天堂、解析器、线程池或全局页面路由。
