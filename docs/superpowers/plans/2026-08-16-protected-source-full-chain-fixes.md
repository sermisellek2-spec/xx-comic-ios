# Protected Source Full-Chain Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修复 18漫画和禁漫天堂搜索、详情、目录、阅读及验证会话的已确认问题，并发布 Android `1.0.30 (30)`。

**Architecture:** 保留现有站源与 WebView 会话边界，增加少量可测试纯函数，在调用点修正分页终止、请求匹配和解析范围。目录仍按需异步加载，受保护站源共享各自持久验证会话。

**Tech Stack:** Android Java、平台 WebView、JUnit 4、Android Gradle Plugin 7.4.2、腾讯云 COS、SSH 备用服务器。

---

### Task 1: 锁定分页与站源 URL 行为

**Files:**
- Create: `app/src/test/java/com/xxcomic/SearchPagingTest.java`
- Create: `app/src/test/java/com/xxcomic/source/Mh18ComicSourceTest.java`
- Modify: `app/src/main/java/com/xxcomic/MainActivity.java`
- Modify: `app/src/main/java/com/xxcomic/source/Mh18ComicSource.java`

- [ ] 写分页重复 ID、向下滚动条件与 18漫画第二页 URL 的失败测试。
- [ ] 运行聚焦测试，确认因当前行为失败。
- [ ] 最小实现向下滚动门槛、追加页去重和 18漫画分页 URL。
- [ ] 运行聚焦测试，确认通过。

### Task 2: 锁定详情、目录和正文解析

**Files:**
- Modify: `app/src/test/java/com/xxcomic/source/Mh18ComicSourceTest.java`
- Modify: `app/src/test/java/com/xxcomic/source/JmComicSourceTest.java`
- Modify: `app/src/test/java/com/xxcomic/JmImageSlicesTest.java`
- Modify: `app/src/main/java/com/xxcomic/source/Mh18ComicSource.java`
- Modify: `app/src/main/java/com/xxcomic/source/JmComicSource.java`
- Modify: `app/src/main/java/com/xxcomic/MainActivity.java`

- [ ] 写 JSON-LD/meta 容错、禁漫目录排除推荐链接和 `1114754/00010.webp` 四分片的失败测试。
- [ ] 运行聚焦测试，确认因当前解析逻辑失败。
- [ ] 最小修正解析范围、解扰公式与详情后台刷新逻辑。
- [ ] 运行聚焦测试，确认通过。

### Task 3: 锁定 WebView 请求匹配和超时

**Files:**
- Modify: `app/src/test/java/com/xxcomic/CloudflareWebViewSessionTest.java`
- Modify: `app/src/main/java/com/xxcomic/CloudflareWebViewSession.java`
- Modify: `app/src/main/java/com/xxcomic/MainActivity.java`

- [ ] 写最终 URL 不匹配、主文档 HTTP 错误和受保护站源全站搜索超时的失败测试。
- [ ] 运行聚焦测试，确认失败。
- [ ] 增加最终 URL/状态判定，并把受保护站源超时调整为 185 秒。
- [ ] 运行聚焦测试，确认通过。

### Task 4: 版本、验证与发布

**Files:**
- Modify: `app/build.gradle`
- Modify: `tools/check-cuimh-source.js`
- Modify: `tools/check-detail-release.js`
- Modify: `tools/check-rem-visual-contract.js`
- Publish: `release/xx-comic-1.0.30.apk`
- Publish: `release/android-release.json`

- [ ] 将版本及源码契约同步为 `1.0.30 (30)`。
- [ ] 运行完整 JVM 测试、源码契约和 `git diff --check`。
- [ ] 构建 Release APK，校验包名、版本、签名、大小和 SHA-256。
- [ ] 精确暂存源码、测试、文档与版本契约，排除既有构建脏文件，提交并推送 `master`。
- [ ] 上传 COS 与服务器备用地址，回下载两个公开 APK 并核对 SHA-256。
