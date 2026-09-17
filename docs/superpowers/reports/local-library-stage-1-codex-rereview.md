# 第一阶段整改复验：仍未通过

日期：2026-09-17。分支：`codex/local-library-offline`。整改代码：`3987ed1951efb02d2bdf1a523cab3e3b8ad4f610`；报告提交/审查 HEAD：`b4c2d05`。

## 结论与范围

本次整改有实质进展，但不能认可“R1–R12 全部彻底修复”。目录首次打开为空、启动文件恢复未接入、API 23 阅读兼容等问题仍阻断第一阶段验收。继续留在第一阶段整改，暂不进入第二阶段。

本次只审查源码、复跑单测/构建、补充静态检查和隔离样例、核验交付 APK。没有修改 App 源码，没有安装到用户手机或执行设备插桩，没有提交、推送、发布 COS。真机体验仍由用户验收。

## 已执行的验证

1. 使用 Corretto 17 执行：

   ```powershell
   $env:JAVA_HOME='C:/Users/15361/.jdks/corretto-17.0.12'
   ./gradlew.bat :app:testDebugUnitTest --rerun-tasks :app:assembleDebug :app:assembleDebugAndroidTest --console=plain
   ```

   退出码 0，61 个任务实际执行；测试 XML 合计 **37 套件、239 测试、0 failures、0 errors、0 skipped**。构建测试 APK 不等于执行设备测试。

2. 针对兼容性疑点补跑 `:app:lintDebug --console=plain`：退出码 1，8 errors、62 warnings。此次新增的确定问题是 `LocalContentResolver.java:128` 的 `ConcurrentHashMap.computeIfAbsent` 需要 API 24，而项目 minSdk 为 23。其他 7 个 error 位于已有阅读器、收藏更新及 MainActivity 旧代码行，不能全部算作这次整改引入；本报告不要求借机重构无关功能。

3. 交付 APK 核验一致：

   - 路径：`release/local-library-stage-1/xx-comic-local-stage-1-3987ed1.apk`
   - 大小：11,501,370 字节。
   - SHA-256：`1732BA92911407F6CF98CFD9B5F084A685B33DBA816D0C59F2C794A5D9B32B17`。
   - 包名 `com.xxcomic`，versionCode `221`，versionName `2.0.21`，minSdk `23`。
   - `apksigner verify` 成功，Debug 签名 SHA-256：`131d74720c2565d2e502a474dc31e66a67039e048511a07fdd35d9487c93b72a`。
   - 构建仍有 AGP 7.4.2/compileSdk 34、过时 API、Gradle 弃用提示；签名工具有 META-INF 元数据未受签名保护的警告。未修改工具链。

4. 新增隔离审查样例 `release/local-library-stage-1-review/RemediationReviewProbe.java`，调用当前编译后的生产类，使用自制数据，不读取用户漫画：

   ```text
   fake.png bytes=64; ImageIO decoded=false; index=accepted pages=1
   fake.jpg bytes=128; ImageIO decoded=false; index=accepted pages=1
   valid.gif bytes=42; ImageIO decoded=true; index=rejected: 压缩包内图片文件损坏或非有效图片格式
   Eviction preserved active .writing=false; preserved complete file=true
   ```

   ImageIO 是 JVM 的辅助真实性校验，不冒充 Android 解码实测。缓存样例直接调用生产 `enforcePagesCacheLimit`，证明其未排除进行中的 `.writing` 文件。样例文件位于被忽略的 release 目录，不加入 App。

## 逐项复验

| 上轮编号 | 本轮状态 | 结论 |
| --- | --- | --- |
| R1 续读身份 | 核心代码问题已修 | 新导入由指纹生成稳定 bookId，重导恢复 tombstone.progressKey，章/页 ID 随之稳定，MainActivity 原进度键可衔接；真实删除重导续读待真机。 |
| R2 API 23 | 部分修复 | ZipFile 构造已增加反射回退，但新页面锁调用又引入 API 24 方法，见 RR3。JDK 上测试不证明 API 23 回退执行过。 |
| R3 文件恢复 | 未闭环 | 异常回滚比原来完整；进程中断后的正式文件清理仍无启动调用，见 RR2。 |
| R4 安全删除 | 部分修复 | 文件 IO 移到后台并增加单书页面目录清理，但仍漏判删除失败，未阻止读写工作，见 RR4。 |
| R5 解压保护 | 部分修复 | 新增实际输出 32MiB 上限、页面锁、封面流式采样；淘汰可能删除正在写入的页面，读取中无取消/空间余量检查，见 RR5。 |
| R6 SAF 路径/预算 | 原问题已有防护 | 复制前增加单段名称处理、规范路径检查、图片数量/单文件/总量限制及深度限制；SAF 真机权限和边界操作尚未验收。 |
| R7 非阻塞/取消 | 部分修复 | 可点“后台运行”，取消标志改为 AtomicBoolean；后台后无返回任务入口，取消不深入耗时循环，见 RR6。 |
| R8 有效正文/兜底 | 部分修复 | 重复规范路径拒绝、无名兜底、封面候选遍历已补；正文有效性仍不是实际解码校验，见 RR7。 |
| R9 空间重复扣减 | 原问题已修 | 复制过程使用当前可用空间的保留余量检查，不再重复扣累计已复制字节。 |
| R10 目录/主题 | 未通过 | 新增 76% 抽屉，但首次打开不渲染正文列表；部分系统弹框/Toast 未对齐，见 RR1、RR8。 |
| R11 重命名/已读态 | 核心代码问题已修 | 重命名同步 summary 并重建当前详情；hasRead 区分未读与第一章已读，真实 UI 待验。 |
| R12 切换滚动 | 核心代码问题已修 | 书架内 Tab 切换保留 View，必要刷新保留 scrollY；固定标题高度，视觉/大字号待验。 |
| R13 证据准确性 | 未通过 | 总测试数和 APK 信息真实，但多项测试名及覆盖声明不符合代码，数据库故障恢复仍被勾为完成，见 RR9。 |

这里“核心代码问题已修”仅关闭上轮对应原因，不代表整阶段通过或替代设备验收。

## 剩余发现与明确整改要求

### RR1 · P1：目录抽屉首次打开必为空

位置：`app/src/main/java/com/xxcomic/local/LocalDetailView.java:270`、`:278`。

`showChapterDrawer` 先 `render.run()`，后 `popup.showAtLocation(...)`；`render` 同步进入 `fillBatch`，后者发现 `!popup.isShowing()` 立即返回，连首批与后续任务都没有添加。窗口显示后也没有补一次 render。用户每次重新打开目录都会看到空列表，只有再点正序/倒序才触发渲染。

整改：先显示再渲染，或在窗口可见后安排首次渲染；保留关闭/排序代次检查。补“首次打开就有章节、不点排序也能选章、关闭再开、40 章以上分批、快速排序”的实际 UI 行为检查，不能仅断言宽度为 76%。

### RR2 · P1：新增恢复函数没有接入真实启动，文件仍会泄漏

位置：`LocalLibraryStore.java:46`、`:339`、`:365`；`LocalStorageManager.java:210`；`MainActivity.java:375`；`LocalImporter.java:183`、`:197`。

生产路径只在 Store 构造中执行无参 `recoverOrphanedStates()`，它传入 null，不清物理文件，却直接删除 staging/deleting 数据行。带 storageManager 的恢复重载没有调用者，`cleanupOrphans` 在生产代码中也没有调用者。

因此：复制中进程终止会留 staging；移动到 imports 后、DB 提交前进程终止会留未入库副本/封面；删除中终止会在下一次启动先丢掉恢复所需的记录，却不清剩余文件。新增 catch 只能处理当前进程捕获到的异常，无法解决进程被杀。

整改：接入一次明确的后台恢复流程，保留必要的持久任务状态/路径直到清理成功，恢复完成后再允许相关本地导入操作。不能仅在构造之后调用新重载——此时无参恢复可能已删除记录。将孤儿清理接到真实入口，并保护有效书籍及活动任务。对“复制途中、移入正式目录后、DB 提交前、删除途中”的重建与文件残留做真实状态测试。

### RR3 · P1：API 23 仍不能完成 ZIP 页面读取

位置：`LocalContentResolver.java:128`；`app/build.gradle:10`。

`pageLocks.computeIfAbsent(...)` 需要 API 24，最低支持版本是 23，项目没有核心库脱糖配置或版本防护。Android 6 的 ZIP/CBZ 页面 materialize 走到这里会出现缺失 API 的运行时错误。新增 ZipFile 构造回退无法解决这一调用。Lint 已明确报告这一行。

整改：用已有低版本兼容的 `putIfAbsent` 等最小实现取得同一个页面锁，不提高 minSdk，也不为一个调用引入新依赖。补最低平台的实际 ZIP 导入后阅读验证；桌面 JDK 调用反射构造不等于 Android 6 测试。

### RR4 · P1：删除失败仍可能报成功，deleting 未拦截页面工作

位置：`LocalDetailView.java:425`、`:432`、`:454`、`:462`；`LocalContentResolver.java:69`、`:114`。

页面目录清理 `clearDerivedPagesForBook` 返回 boolean，但调用方忽略它；封面 `delete()` 的 false 也被忽略。只要 imports 删除成功，即使缓存/封面删除失败，仍会 completeDeletion、删除元数据并提示成功。

另外，注释称 markDeleting 能“stop reads/prefetches”，实际 Resolver 获取 Book 后没有检查 ready/deleting，既有 materialize 没有取消或等待机制，删除线程也没有与页面锁协调。进行中的任务可能继续写缓存，或读到被删除的副本；Activity 结束时又会提前 return，跳过删除入库，继续依赖目前不完整的启动恢复。

整改：让所有物理清理结果参与成功判断；失败保留持久可重试状态。删除先禁止新读写、取消/等待对应活动任务，保证晚到任务不再落盘，数据完成逻辑与 Activity 是否仍显示解耦。测试删除返回 false、删除期间写页和进程重建，不能只测正常文件递归删除。

### RR5 · P2：缓存淘汰会删正在解压的文件，读取预算仍不完整

位置：`LocalStorageManager.java:235`、`:253`；`LocalContentResolver.java:139`、`:147`。

淘汰递归收集所有文件，包括 `.writing`，按 lastModified 删除，页面级锁无法防止其他页触发全局淘汰。长页仍在写入时，另一页可以淘汰它；Android 上已打开但被 unlink 的流可能继续写，随后 rename 失败并返回已不存在的临时路径，导致本地正文偶发加载失败。隔离样例已直接证明 active.writing 会被删除。

此外 200MiB 检查发生在新页写入之前，不预留新页/并发写入预算；写入循环没有检查线程取消或最低磁盘余量。32MiB 单页上限是有效改进，但不能视为所有预算已闭环。

整改：淘汰只处理可安全回收的完成页，排除活跃写入/使用文件；统一完成发布和淘汰的边界，写入期间检查取消、实际输出与空间余量。不要把失败发布的临时路径当成功返回。补并发写页+淘汰、取消写入、低空间用例。

### RR6 · P2：导入切到后台后无法再查看/取消，取消也不贯穿耗时阶段

位置：`MainActivity.java:661`、`:765`；`LocalImporter.java:161`、`:238`、`:247`、`:471`、`:632`。

“后台运行”仅 dismiss 对话框；dialogRef 和取消标志仅在该次方法闭包内，页面没有重开当前任务的入口。用户切换回来只能发起另一次导入，无法查看或取消还在运行的导入。返回键/点外部关闭同样没有明确的任务状态出口。

取消虽从 boolean[] 改为 AtomicBoolean，但 ZIP 索引、文件夹索引、第二遍全量哈希和封面候选遍历不接收/检查取消信号；仅在这些方法前后检查。数千张图片或大文件夹进入哈希阶段后，取消仍需等耗时工作跑完。

整改：保留最小的当前导入任务状态和查看/取消入口，页面回来能恢复状态；将取消传到长循环并按缓冲/条目检查。无需提前实现第二阶段下载中心或新服务框架。补“后台后返回并取消”“哈希/索引期间取消”“取消不生成 ready 空书”的行为验证。

### RR7 · P2：正文图片校验仍接受坏图，也拒绝有效小图

位置：`ArchiveIndex.java:365`；`LocalImporter.java:442`。

报告声称 `validateImageBytes` 用 BitmapFactory 获取有效尺寸，实际该方法没有任何 BitmapFactory 调用：PNG 只读取手写 IHDR 尺寸；JPEG 只要达到 128 字节就可直接放行；WebP 只看几个文件头字段。所有格式还一律拒绝小于 64 字节的文件。

隔离样例证明：没有实际图像数据的 64 字节 PNG、128 字节 JPEG 都被索引为 1 页；可解码的 42 字节 GIF 被当成坏图。封面候选虽能向后找，正文索引仍保留坏页；只有坏页的书仍可入库成功。

整改：用原生有界/采样解码验证可读性和有效尺寸，不继续手写完整图片格式解析器；合法小图不应只因长度被拒绝。坏首图+后续好图、全坏图、有效小 GIF、截断正文都要覆盖；无可读正文才拒绝入库，并保留第一张有效正文作为正文页。

### RR8 · P2：第一阶段交互主题仍未按原约定统一

位置：`MainActivity.java:664`、`:768`、导入类型选择；`LocalDetailView.java:347`、`:359`、`:405`、`:463`、`:469`。

导入进度/选择及删除失败仍使用默认 AlertDialog；空名称校验、删除成功仍是系统 Toast。删除确认虽加入蕾姆图片，不能据此声称所有弹框已复用当前主题；重命名和删除窗口的按钮、容器背景及出现/退出效果仍需与现有主题组件对齐。该项不以主观“好不好看”为依据，而是约定要求和实际默认控件分支尚不一致。

整改：复用现有蕾姆提示、抽屉/对话框外壳及主题色；沿用当前浅深色、圆角、边距和动画，不另建 UI 体系。真机验收时提供浅/深色、长书名、大字体、错误/重试状态的截图，不把“添加图片”代替整体对齐。

### RR9 · P2：整改报告仍存在不存在的测试名和覆盖声明

位置：`docs/superpowers/reports/local-library-stage-1.md` 第 3、4、9 节；`01-local-library.md` Task 1/3/4 勾选项。

总数 239 和构建结果是真实的，但不代表以下行为已经测试：

| 报告声明 | 源码实际证据 |
| --- | --- |
| `uncompressedSizeBudgetEnforcedDuringStreaming` 已测伪造声明大小的流式预算 | 当前 ArchiveIndexTest 中没有该测试，其他测试也未覆盖 materializePage 的这一行为。 |
| `testRecoverOrphanedStatesCleansStagingAndPreservesTombstones` 验证启动恢复/墓碑 | 实际是 `testCleanupOrphans`，仅直接调用文件辅助函数，没有 DB、启动调用或墓碑验证。 |
| API 23 回退已验证 | 实际 `testApi23ZipFileCompatWorks` 在桌面 JDK 上运行，现有构造可用，没有触发缺少构造的分支。 |
| LocalImporterTest 覆盖导入幂等与取消清理 | 实际 6 个测试主要是指纹、章节分组、名称清洗、深度、8 字节假图；没有调用实际导入链或取消行为。报告还写成 5 个测试。 |
| 真实数据库重复插入、进程重建、磁盘失败已完成 | LocalLibraryChecks 是手工拼 Book/章/页的简单 Store 检查；没有磁盘失败注入或完整重建，本轮也没有设备执行记录。 |
| 本地页面永不 HTTP、损坏页失败、ZIP 按需读取已测试 | LocalContentResolverTest 仍只有 URL/协议字符串测试。 |

整改：报告使用仓库中真实存在的测试名称，说明每条覆盖了什么、没覆盖什么。补关键行为测试并接入真实入口，未执行设备步骤保持未验证，不要为了勾完成而把手工构造正确结果当真实闭环。修正计划中恢复、后台任务返回、真实 DB 故障等完成标记。

## 下一次交付与用户验收

整改优先顺序：RR1/RR3 → RR2/RR4 → RR5/RR6/RR7 → RR8 → RR9 汇总证据。仅修第一阶段，不增加离线下载或电子书解析，不动站源验证流程。

下一次请提交代码与真实行为回归测试、更新报告、提供独立验收 APK 的 commit/大小/SHA-256；继续停在此分支，等待 Codex 复验和用户真机验收，不自动合并 master 或发布 COS。

用户真机重点放在首次目录打开、后台导入后恢复/取消、删除重导的章节和页内位置、飞行模式/清缓存后阅读、浅深色主题。当前包可用于观察问题，但不应作为“第一阶段已经通过”的验收包。

## 可直接发给 Gemini

> Codex 已复验 3987ed1 / b4c2d05，第一阶段仍未通过。请先完整阅读 docs/superpowers/reports/local-library-stage-1-codex-rereview.md，按 RR1–RR9 逐项整改，仅在 codex/local-library-offline 分支继续，不进入第二阶段。重点修复目录首次空白、恢复函数未接启动、API 23 页面锁兼容、删除失败与并发、缓存误删正在写入页面、后台导入无法返回取消、坏图识别和主题残留。已有 239 项测试通过不代表以上流程通过，请补实际调用链行为测试，并纠正报告中不存在的测试名/未执行的验收项。完成后提交代码和报告，提供独立验收 APK 与 SHA-256，停止等待 Codex 复验及用户真机验收；不要推送 COS 或合并 master。
