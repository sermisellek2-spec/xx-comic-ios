# 第一阶段 Codex 接管交付 · 2026-09-17

状态：本轮源码整改、桌面测试和打包完成，待用户真机验收。没有原生设备运行和 UI 截图证据，不代表整阶段验收通过。本报告替代旧报告的当前结论和产物信息。

## 基线与提交

- 分支：`codex/local-library-offline`；接管基线为 Gemini `365db97`。
- 本轮代码：`28d065098155b0fe9186eb26a49c1d0deb320018`，`fix(local): coordinate import recovery and safe offline reads`。
- 报告/计划另行提交，避免自引用哈希。
- 接管时已有被跟踪的 `.gradle/`、`app/build/` 构建改动，保留且不提交。阶段计划中取消“真实数据库实测完成”的修改已保留。
- 历史审查见 `local-library-stage-1-codex-review.md`、`local-library-stage-1-codex-rereview.md`。旧报告的测试名、预算和“全部彻底修复”声明不作为本轮证据。

Gemini 已实现本地书架、SAF 文件夹/ZIP/CBZ 导入、详情、76% 目录、阅读器接入及稳定续读身份。其最后一轮修正了目录首次填充、后台任务入口和部分删除失败处理。本轮继续修复中断恢复、并发文件操作和验证证据。

## 范围对照

| 范围 | 本轮处理 | 验证边界 |
| --- | --- | --- |
| 导入发布 | 文件移动前写 staging 记录，移动后提交 ready；失败清理，未清成功保留记录；ready 提交才清旧身份墓碑 | 原生 SQLite 故障检查已编译，未执行 |
| 启动恢复 | MainActivity 跨实例复用 Store/存储锁；恢复与导入同一队列，恢复前限制本地入口；销毁时取消本次导入 | 源码检查，旋转/杀进程待真机 |
| 删除/读取 | 文件发布、解码、删除、缓存清理共享锁；删除先标记，只准 ready 新读；失败保留重试；检查墓碑写入结果 | JVM 并发读图、删除中发布、清缓存等待测试通过 |
| 数据库 | WAL + 非独占事务；读查询不再等待整个 Store Java 写锁；重命名移后台并处理失败 | Android 编译通过，大库性能待真机 |
| 预算/取消 | 单条统一 128MiB，缓存预留新页预算；写前保留 256MiB 空间；有界流响应取消、允许精确上限 EOF | 超限、低空间、取消解码测试通过 |
| SAF | 拒绝重复路径、空流、目录查询失败；过深目录明确报错；50,000 条目限制包含目录/文件 | Provider 选择/撤权待真机 |
| 图片校验 | 原生 BitmapFactory 有界采样，移除生产代码的桌面 ImageIO fallback；桌面 codec 仅在测试 fixture | JVM 索引测试不等于 Android 解码实测 |
| 资源/界面 | 非 ready 禁读、文件夹缺页报错、ZIP 按页缓存、封面兜底采样；更多菜单收纳重命名/删除；导入可查看/取消、进度回调节流 | 文件行为测试通过，界面仅编译 |

主要文件：`MainActivity.java`；`local/LocalImporter.java`、`ArchiveIndex.java`、`AndroidImageProbe.java`、`LocalContentResolver.java`、`LocalStorageManager.java`、`LocalLibraryStore.java`、`LocalDetailView.java` 及相应测试。未改站源解析、JM/18mh 验证实现及阅读手势规则。

## 页面与数据影响

书架保留“我的书架 | 本地书架”，本地有导入与当前任务入口；详情保留封面、格式/大小、续读与 76% 目录，右上更多菜单提供重命名/删除。没有下载中心或电子书空入口。浅深色/窄屏/大字体截图与动画录屏待真机提供。

SQLite schema 仍 v1，未迁移旧在线数据。数据库及 library 位于 App no-backup 私有目录，WAL 在同一数据库目录。原文件只读；副本在 imports、暂存在 staging、衍生文件在 derived。普通缓存仅清本地 derived/pages，不删副本；删除漫画清副本/封面/页缓存，保留身份墓碑及原阅读记录。旧收藏、历史和验证缓存清理策略保留。

## 验证命令与结果

Windows / PowerShell，Corretto 17.0.12，Android build-tools 34.0.0。旧 app/build 的 SourceConfig.dex 曾被 Windows 映射占用，D8 失败；未删除旧目录或杀未知进程，改用独立 buildDir 后成功。

本机忽略脚本 `release/local-library-stage-1-codex-build.gradle`：

```groovy
gradle.beforeProject { project ->
    if (project.path == ':app') {
        project.buildDir = new File(project.rootProject.projectDir, 'release/local-library-stage-1-codex-build/app')
    }
}
```

最终源码执行：

```powershell
$env:JAVA_HOME='C:/Users/15361/.jdks/corretto-17.0.12'
./gradlew.bat --no-daemon -I release/local-library-stage-1-codex-build.gradle :app:testDebugUnitTest :app:assembleDebug :app:assembleDebugAndroidTest --console=plain
```

退出码 0，BUILD SUCCESSFUL in 22s，61 tasks（10 executed / 51 up-to-date）；修改后的生产/测试 Java、单测、App 打包实际执行。此前全新隔离目录构建为 61 executed。

最终 XML 汇总：**37 套件、257 测试，0 failures / 0 errors / 0 skipped**，位于 `release/local-library-stage-1-codex-build/app/test-results/testDebugUnitTest/`。

关键行为测试：

- LocalImporterTest：`boundedStreamAcceptsExactLimitAndRejectsOneByteMore`、`cancellationInterruptsDecoderReadsEvenWhenDecoderSwallowsIOException`。
- LocalContentResolverTest：`pendingBookCannotBeOpenedEvenWhenItsArchiveExists`、`deletionDuringMaterializationCannotPublishPage`、`materializationRechecksFreeSpaceDuringCopy`、`concurrentRequestsPublishOnlyOneCompletePage`、`clearingCacheWaitsUntilPageConsumerFinishes`。
- LocalStorageManagerTest：`rejectsImportRootAsBookPath`、`bookDeletionReportsDerivedFailure`。

新增 `LocalImportRecoveryChecks.java` 并接入 LocalLibraryChecks：原生坏图/小 GIF、真实 importer 去重、重命名/重导身份、SQLite 重开恢复、删除失败重试、ready 提交失败回滚。**仅编译，未执行**；Uri.fromFile fixture 不等于真实 SAF Provider，重开数据库不等于已执行系统杀进程实验。

同一隔离脚本执行 `:app:lintDebug --console=plain`，退出码 1：**7 errors、60 warnings**。错误为旧 PagedReaderView 的 position 捕获、FavoriteUpdateCoordinator 四处 Map.compute、MainActivity 的 Bitmap.Config.HARDWARE 与 Map.getOrDefault。上一轮本地 Resolver 的 API 24 computeIfAbsent 错误已消除；没有为全 Lint 绿扩大改动范围。

`git diff --cached --check` 通过；`adb devices` 无设备。未安装 App 或执行会 seed 数据的 ReaderInstrumentation。仍有 AGP 7.4.2/compileSdk 34、过时 API 和签名 META-INF 元数据等旧工具链警告。

## 独立验收 APK

- 路径：`F:/softForCode/codex-project/xx-comic/release/local-library-stage-1/xx-comic-local-stage-1-28d0650.apk`
- 大小：11,383,636 字节。
- 文件 SHA-256：`7FB784602913E0E0515A2C19A4D3F00DA56C6F1F841ED48558629B3D52E90134`。
- 包名 com.xxcomic，versionName 2.0.21，versionCode 221，minSdk 23，targetSdk 34。
- apksigner verify 成功；Debug 签名 SHA-256：`131d74720c2565d2e502a474dc31e66a67039e048511a07fdd35d9487c93b72a`。
- 覆盖前提：设备包签名相同、versionCode 不高于 221。未升正式版，不用卸载绕过版本/签名冲突。

## 用户真机验收

准备自制/有权使用的平铺图片文件夹、双章节 CBZ、大文件、空 ZIP、坏首图后有好图的包。

1. 本地书架 → 导入：核对单章/多章、1/2/10 排序；重复文件一本，同名不同内容两本。
2. 大文件导入 → 后台运行 → 发现/设置 → 返回本地查看并取消，无残缺可读书，再次导入可完成；系统选择取消/撤权可恢复操作。
3. 详情目录首次即有章节，排序/重开正常；更多 → 重命名，空白拒绝、书架/详情同步。
4. 读到第二章中段退出重进；覆盖条漫/单页、左右手、触碰/按钮/手势、缩放、沉浸和章边界。
5. 飞行模式读本地 → 清缓存 → 仍可读；删除用户原文件后 App 副本仍可读。
6. 删除先取消再确认，保留原文件和历史；重导恢复名称/章节/位置。
7. 复制/解析时旋转、退出、结束进程再启动，无可读空书，不误删有效书；观察低空间、大量图片时的响应和重试。
8. 浅深色/窄屏/大字体/长标题截图与切换录屏，核对书架滚动位置。
9. 回归在线搜索、详情/站源切换、收藏、历史、阅读、JM/18mh 验证和版本更新安装。当前无这些真机回归证据。

## 限制、回退、结论

- 仅文件夹与 ZIP/CBZ；不支持加密压缩包、RAR、EPUB、MOBI/AZW。API 23 中文 ZIP 编码回退待实机样本验证。
- 文件夹最多 5 层，超深明确拒绝；50,000 条目；单图 128MiB；ZIP 声明/文件夹实际复制预算 20GiB；页缓存目标 200MiB；预留空间 256MiB。
- 文件操作共享锁优先确保一致性，大型漫画延迟待真机观察。短 SQLite 查询仍有 UI 调用点，本轮消除整段 Java 写锁等待，不承诺海量书库无延迟。
- Activity 销毁取消本次导入；不承诺跨进程继续复制，下次回收未完成状态后重新选择文件。
- 回退本轮使用普通 revert `28d0650`，先保全工作区和数据、解决冲突并验证；不 reset 仓库或删除数据库/原文件。Gemini 旧代码仍有已记录缺陷，回退不代表可发布。
- Gemini 实施至 365db97；Codex 本轮源码整改及桌面验证完成。**原生/UI 整阶段验收与用户真机验收待完成。**
- 已停在第一阶段：保留分支，未推送、未合并 master、未发布 COS、未进入第二阶段。
