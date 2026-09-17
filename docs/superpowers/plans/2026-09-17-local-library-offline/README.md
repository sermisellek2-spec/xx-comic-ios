# 本地书架与离线下载分阶段实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task when available. Gemini 没有该技能时直接遵循本文及阶段任务；无需安装技能。用户指定 Gemini 执行，Codex 与用户验收，不自动启用子代理或连续跨阶段。

**Goal:** 在专用分支逐阶段增加本地阅读、离线下载及电子书/文件站源能力，保持已有在线功能兼容。

**Architecture:** 本地内容与缓存分离，图片阅读沿用现有阅读器，以本地解析入口提供持久资源。独立下载队列产出同一内容模型；电子书按格式逐阶段接入，保持稳定作品身份和进度。

**Tech Stack:** Java、Android 原生 View、SAF、ZipFile、SQLite、现有 Gradle 与 JUnit；电子书库按样本评估后选择。

**Spec:** `docs/superpowers/specs/2026-09-17-local-library-offline-design.md`

## Global Constraints

- 仅分支 `codex/local-library-offline`，基线 `9cb04f4` / 2.0.21 / 221；开始执行时重新检查真实 HEAD 与工作区。
- 保留 Java/native Android UI、minSdk 23、compileSdk/targetSdk 34，不整体重写 MainActivity，不顺手改其他站源。
- 文件只保存在手机本机；导入复制副本，删除和清缓存遵循设计中的数据边界。
- 主题使用现有 UIHelpers 和蕾姆资源；浅深色与旧功能均为验收内容。
- 每阶段：Gemini 实施、自检、本地提交、报告 → Codex 验收 → 用户真机验收 → 用户明确启动下一阶段。
- 不自动合并 master、推送、正式升版或发布 COS；验收 APK 单独归档。
- 当前已有被跟踪的构建输出改动及无关 `%SystemDrive%/`，不要 reset、删除、提交或藏入本功能提交。

## 阶段与可交付结果

| 阶段 | 执行文件 | 本阶段验收结果 |
| --- | --- | --- |
| 1 | [01-local-library.md](01-local-library.md) | 图片文件夹 / ZIP / CBZ 从导入到阅读、续读、删除的完整闭环 |
| 2 | [02-offline-downloads.md](02-offline-downloads.md) | 单章/多章/全章下载，持久任务，断网可读，存储管理 |
| 3 | [03-epub-comics.md](03-epub-comics.md) | 按 EPUB 真实阅读顺序阅读图片漫画与已验证固定版式 |
| 4 | [04-epub-text.md](04-epub-text.md) | EPUB 文字/图文混排，字号/行距与稳定续读 |
| 5A / 5B | [05-kindle-formats.md](05-kindle-formats.md) | 先兼容报告，单独验收后实现明确支持的 MOBI/AZW 变体 |
| 6 | [06-file-sources.md](06-file-sources.md) | 可选文件源能力、整文件下载、解析入库和阅读，使用受控示例验收 |

阶段 1 已包含必要的本地存储底座，不另外开一个只有空类的“架构阶段”。阶段 2 包含存储管理和下载完整性。阶段 5A 也是停点，未经确认不进入 5B。

## 给 Gemini 的总指令（首次发送）

```text
你是 XX Comic 的本地阅读与离线下载实现者。项目在 F:\softForCode\codex-project\xx-comic。
工作分支是 codex/local-library-offline，已经由 Codex 创建；先核对分支、HEAD、工作区及 AGENTS.md。
先完整阅读：
1. docs/superpowers/specs/2026-09-17-local-library-offline-design.md
2. docs/superpowers/plans/2026-09-17-local-library-offline/README.md
3. docs/superpowers/plans/2026-09-17-local-library-offline/REPORT-TEMPLATE.md
仅执行我明确指定的阶段，不能一次实现所有阶段。
沿用现有主题、浅深色、蕾姆元素与阅读交互，按设计保护原收藏、历史、验证信息和缓存边界。
使用现有平台与依赖优先；格式库需要先给兼容性、许可、体积证据。不做全项目重构。
保留他人未提交修改；构建输出、APK、凭证和本机配置不提交。
每阶段先给短实施清单，再逐任务实现和验证，提交本阶段代码与阶段报告，停止等待。
报告必须区分已测试/未测试，列出基线和提交、文件、命令、输出、设备、截图、APK 及 SHA-256、人工验收路径和风险。
Gemini 自检通过不等于用户验收；等 Codex 验收和用户真机验收均通过，我明确通知后才能继续。
不要自动合并 master、推送、发布 COS 或改正式版本号。
```

## 开始第一阶段（紧接总指令发送）

```text
只开始阶段 1。
阅读 docs/superpowers/plans/2026-09-17-local-library-offline/01-local-library.md。
完成图片文件夹、ZIP/CBZ 导入、本地书架、本地详情、现有阅读器复用、续读和安全删除。
先保全工作区并记录回归基线。第一阶段不实现下载、EPUB、MOBI/AZW，也不要放不可用下载按钮。
完成自检、生成阶段报告和独立验收 APK 后停止，等 Codex 和我验收。
```

其余阶段指令放在各自文件末尾。用户未明确授权下一阶段时，Gemini 只处理当前阶段验收问题。

## 共同验证命令与约束

PowerShell 中使用已安装 JDK 17；路径不匹配时先查实际安装，不修改系统环境变量永久值。

```powershell
$env:JAVA_HOME='C:/Users/15361/.jdks/corretto-17.0.12'
./gradlew.bat :app:testDebugUnitTest :app:assembleDebug :app:assembleDebugAndroidTest --console=plain
git diff --check
```

有授权测试设备时安装 debug/app-test 包，沿用现有测试入口：

```powershell
adb devices
adb install -r app/build/outputs/apk/debug/app-debug.apk
adb install -r app/build/outputs/apk/androidTest/debug/app-debug-androidTest.apk
adb shell am instrument -w com.xxcomic.test/com.xxcomic.ReaderInstrumentation
```

现有 instrumentation 会 seed 测试数据，只能使用测试设备或事先备份的测试环境，不能在用户日常书架直接执行。没有设备则列明待真机检查；真实站点访问失败需区分网络、验证和代码问题。

发布给用户覆盖安装的验收包需检查 applicationId、签名和设备当前 versionCode，不能默认安装版本低于设备的包可覆盖；不通过卸载绕过此问题。若需提高测试包版本号，先由用户决定，保留正式 COS 元数据。

每阶段新增的业务测试应先复现失败后修复，已有测试通过后只重复与后续变更相关的检查。不要用字符串匹配源码替代行为测试，不为了测试增加全局危险开关。

## 每阶段共同回归清单

- [ ] 当前基线已有单元测试及新增行为测试；记录实际数量，不沿用旧报告数字。
- [ ] 在线发现的站源、分类、搜索、分页；详情目录、排序、站源切换与返回。
- [ ] 收藏、更新蓝星、历史、续读及现有设置保存。
- [ ] JM / 18mh 验证信息隔离、手动验证入口不受新任务影响。
- [ ] 图片阅读：条漫/单页 × 左/右手 × 触碰/按钮/手势，章边界、缩放、沉浸和控制层。
- [ ] 浅色/深色、窄屏/大字号、长标题、重复点击、返回、旋转后状态。
- [ ] 关闭网络后本地操作不发网络请求；缓存清理不误删本地内容。
- [ ] 原设置中的升级检查、下载更新和安装流程未被漫画下载挤占或错误替换。

## 接力验收

Gemini 报告归档为 `docs/superpowers/reports/local-library-stage-N.md`，5A/5B 分开。
用户把报告路径和阶段提交交给 Codex，Codex 审核 diff、运行必要检查、按严重度给结论。修复仍在当前阶段完成，不滚入下阶段。
用户真机验收通过后，在报告的独立验收记录追加实际结论；Gemini 不代填 Codex/用户结论。

阶段验收包和截图放 `release/local-library-stage-N/`（已忽略），报告给绝对路径和哈希。全程不把测试成功称为零风险保证。
