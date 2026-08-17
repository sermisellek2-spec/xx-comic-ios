# 18漫画列表验证恢复 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 18漫画首次 Cloudflare 验证能在后台完整视口中完成，并在验证后顺序加载列表与分类。

**Architecture:** 复用现有 `CloudflareWebViewSession`，以向后兼容的构造函数参数只为 18漫画开启离屏完整视口。复用现有 `categoriesFollowInitialList` 策略串行化 18漫画首屏请求，禁漫天堂调用与行为不变。

**Tech Stack:** Android Java、WebView、JUnit 4、Gradle、腾讯云 COS。

---

### Task 1: 锁定 18漫画独立行为

**Files:**
- Modify: `app/src/test/java/com/xxcomic/CloudflareWebViewSessionTest.java`
- Modify: `app/src/test/java/com/xxcomic/ProtectedSourceUiTest.java`

- [ ] 增加失败测试：完整视口配置返回 `MATCH_PARENT`，默认配置仍返回 `1`。
- [ ] 增加失败测试：`categoriesFollowInitialList("mh18")` 为真，禁漫天堂现有断言保持不变。
- [ ] 运行两个测试类，确认因缺少新行为而失败。

### Task 2: 最小实现后台视口与顺序加载

**Files:**
- Modify: `app/src/main/java/com/xxcomic/CloudflareWebViewSession.java`
- Modify: `app/src/main/java/com/xxcomic/MainActivity.java`

- [ ] 保留旧构造函数并委托到新增的完整构造函数，默认关闭完整视口。
- [ ] 仅为 18漫画传入完整视口参数；禁漫天堂构造调用不变。
- [ ] 后台状态使用配置后的尺寸并在完整视口模式下移出屏幕；交互验证时恢复到屏幕内。
- [ ] 将 18漫画加入首屏列表后加载分类策略。
- [ ] 运行目标测试、完整 JVM 测试和源码契约。

### Task 3: 发布

**Files:**
- Modify: `app/build.gradle`
- Modify: existing release version contract scripts under `tools/`
- Generate outside Git: `release/` artifacts

- [ ] 将版本升级为 `1.0.37 (37)` 并同步现有版本契约。
- [ ] 构建 Release APK，核对包名、版本、签名与 SHA-256。
- [ ] 提交并推送 `master`。
- [ ] 按现有脚本上传 `apk/xx-comic/xx-comic.bin`，从 COS 公网地址回下载并核对 SHA-256。
