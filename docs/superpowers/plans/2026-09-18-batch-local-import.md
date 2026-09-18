# 批量本地导入与多卷合集 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为大量 EPUB/MOBI 本地文件提供快速扫描、确认分组、后台增量导入和多卷合集阅读能力。

**Architecture:** 在现有本地库之上增加来源无关的 series/volume 逻辑模型。快速扫描只产出轻量元数据，后台导入按卷提交；旧单文件 Book 通过默认卷兼容，不改变现有阅读器的外部入口。

**Tech Stack:** Java、Android 原生 View、SQLite、现有 EPUB/MOBI 解析器、JUnit。

**Spec:** `docs/superpowers/specs/2026-09-18-batch-local-import-design.md`

## Global Constraints

- 保留 Java/native Android UI、minSdk 23、compileSdk/targetSdk 34。
- 不拼接或重新打包 EPUB/MOBI，不引入新格式库。
- 不按标题自动合并不同来源；无来源文件必须有明确合集确认。
- 后台导入最多 2 个文件并发；页面图片默认按需解码。
- 不删除用户原文件；普通缓存清理不得删除本地导入和下载。

---

### Task 1: 快速扫描与分组纯逻辑

**Files:**
- Create: `app/src/main/java/com/xxcomic/local/BatchImportModels.java`
- Create: `app/src/main/java/com/xxcomic/local/BatchImportPlanner.java`
- Test: `app/src/test/java/com/xxcomic/local/BatchImportPlannerTest.java`

- [ ] 写失败测试：卷号解析、标题规范化、同一合集候选分组、来源隔离、排序优先级、重复内容识别。
- [ ] 运行该测试确认因类/方法不存在而失败。
- [ ] 实现无 Android 依赖的 `FileCandidate`、`ImportGroup`、`VolumePlan` 和 `BatchImportPlanner`。
- [ ] 运行测试通过。
- [x] 提交 `feat(local): add fast batch import planning`。

### Task 2: 本地合集与卷索引

**Files:**
- Modify: `app/src/main/java/com/xxcomic/local/LocalModels.java`
- Modify: `app/src/main/java/com/xxcomic/local/LocalLibraryStore.java`
- Modify: `app/src/main/java/com/xxcomic/local/LocalContentResolver.java`
- Test: `app/src/test/java/com/xxcomic/local/LocalLibraryStoreTest.java`

- [ ] 写失败测试：同一合集多卷计数、卷级排序、单卷删除、旧 Book 默认卷兼容。
- [ ] 运行测试确认失败。
- [ ] 增加最小 `Series`/`Volume` 模型和 SQLite 迁移；章节、页面保存卷归属。
- [ ] 让内容解析根据页面的卷归属打开对应文件。
- [ ] 运行相关测试和已有本地测试。
- [ ] 提交 `feat(local): persist multi-volume local series`。

### Task 3: 快速 EPUB/MOBI 元数据读取

**Files:**
- Create: `app/src/main/java/com/xxcomic/ebook/QuickPublicationInfo.java`
- Modify: `app/src/main/java/com/xxcomic/ebook/EpubParser.java`
- Modify: `app/src/main/java/com/xxcomic/ebook/KindleFormatDetector.java`
- Test: `app/src/test/java/com/xxcomic/ebook/QuickPublicationInfoTest.java`

- [ ] 写失败测试：读取 EPUB 标题/系列/卷号/封面入口，不遍历或解码全部页面；读取 MOBI 头部标题。
- [ ] 运行测试确认失败。
- [ ] 实现快速读取接口，结构错误返回可展示的文件级错误。
- [ ] 运行测试通过。
- [ ] 提交 `feat(ebook): add lightweight publication scan`。

### Task 4: 批量后台导入会话

**Files:**
- Create: `app/src/main/java/com/xxcomic/local/BatchImportSession.java`
- Modify: `app/src/main/java/com/xxcomic/local/LocalImporter.java`
- Modify: `app/src/main/java/com/xxcomic/download/DownloadRuntime.java`
- Test: `app/src/test/java/com/xxcomic/local/BatchImportSessionTest.java`

- [ ] 写失败测试：最多两个并发槽、单卷失败不阻塞、完成一卷即可发布、取消不发布半成品。
- [ ] 运行测试确认失败。
- [ ] 实现持久会话状态、卷级 staging 和增量提交；复用现有解析器与校验。
- [ ] 为 EPUB 快速模式跳过全量图片预解码，阅读时仍使用现有完整错误处理。
- [ ] 运行测试通过。
- [x] 接入现有导入入口，提交 `feat(local): process batch imports incrementally`。

### Task 5: 导入确认与本地书架聚合 UI

**Files:**
- Modify: `app/src/main/java/com/xxcomic/MainActivity.java`
- Modify: `app/src/main/java/com/xxcomic/local/LocalLibraryView.java`
- Modify: `app/src/main/java/com/xxcomic/local/LocalDetailView.java`
- Test: `app/src/test/java/com/xxcomic/local/BatchImportUiStateTest.java`

- [ ] 写失败测试：扫描中、待确认、处理中、部分完成、失败和完成状态文案/操作。
- [ ] 运行测试确认失败。
- [ ] 增加紧凑导入状态、分组确认、卷级目录和合集删除入口，沿用现有浅深色主题。
- [ ] 运行测试通过并检查现有在线书架路由不变。
- [ ] 提交 `feat(local): expose batch import and volume grouping`。

### Task 6: 回归与交付

**Files:**
- Modify: `docs/superpowers/reports/local-batch-import.md`
- Test: existing local/ebook/download tests

- [ ] 运行完整 JVM 测试和 lint/build。
- [ ] 编译 AndroidTest；有设备时执行批量导入入口，否则如实记录未运行。
- [ ] 检查 `git diff --check`、线程、目录路径和普通缓存清理边界。
- [ ] 更新报告、提交并输出分支和验收包信息。
