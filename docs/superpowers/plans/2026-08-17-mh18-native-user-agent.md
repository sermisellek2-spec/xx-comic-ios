# 18漫画原生浏览器指纹 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 18漫画验证请求使用一致的真机 WebView 指纹，并发布 Android `1.0.41 (41)`。

**Architecture:** 给共享 Cloudflare 会话增加显式的 `useNativeUserAgent` 构造参数。18漫画开启后，WebView 保持平台默认 UA，HTTP 使用启动时读取的同一 UA；禁漫天堂沿用现有固定 UA。

**Tech Stack:** Android Java、WebView/WebSettings、JUnit 4、Node.js 源码契约、Gradle、腾讯云 COS。

---

### Task 1: 原生 UA 选择

**Files:**
- Modify: `app/src/test/java/com/xxcomic/CloudflareWebViewSessionTest.java`
- Modify: `app/src/main/java/com/xxcomic/CloudflareWebViewSession.java`
- Modify: `app/src/main/java/com/xxcomic/MainActivity.java`
- Modify: `tools/check-protected-source-session.js`

- [ ] **Step 1: 写失败测试**

新增 `selectedUserAgent(boolean, String)` 行为断言：原生模式返回传入的真实 UA；非原生模式与原生 UA 不同；原生 UA 为空时回退固定 UA。

- [ ] **Step 2: 运行 RED**

```powershell
./gradlew.bat :app:testDebugUnitTest --tests com.xxcomic.CloudflareWebViewSessionTest --rerun-tasks --console=plain
```

Expected: 因 `selectedUserAgent` 尚不存在而编译失败。

- [ ] **Step 3: 最小实现**

新增显式 `useNativeUserAgent` 参数和已选 UA 字段。18漫画构造传 `true`，其他构造默认 `false`；HTTP 使用字段值，原生 WebView 跳过 `setUserAgentString`。

- [ ] **Step 4: 运行 GREEN**

运行聚焦 JVM 测试和 `node tools/check-protected-source-session.js`，预期通过。

### Task 2: 发布 1.0.41

**Files:**
- Modify: `app/build.gradle`
- Modify: `tools/check-cuimh-source.js`
- Modify: `tools/check-detail-release.js`
- Modify: `tools/check-rem-visual-contract.js`
- Generate outside Git: `release/xx-comic-1.0.41.apk`、元数据和发布辅助文件

- [ ] **Step 1: 设置版本 `1.0.41 (41)` 并同步三个版本契约。**
- [ ] **Step 2: 运行完整 JVM 测试、源码契约、`git diff --check` 和 `:app:assembleRelease`。**
- [ ] **Step 3: 核对包名、版本、签名、大小和 SHA-256，精确提交并推送 `master`。**
- [ ] **Step 4: 上传 COS 和服务器备用包，从两个公网地址回下载并要求 SHA-256 与本地一致。**

## 计划自检

- 只解决 UA/Client Hints 一致性，不同时调整 UI、Cookie、超时或解析。
- 原生模式显式限定到 18漫画，禁漫天堂构造路径不变。
- 无占位步骤，测试和发布目标明确。
