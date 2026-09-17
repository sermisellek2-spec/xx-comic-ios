# 第一阶段 Codex 验收报告：未通过，需留在第一阶段整改

日期：2026-09-17。审查对象：`9dcf5c8`（实现）和 `c1612df`（报告/计划勾选），分支 `codex/local-library-offline`，对比基线 `a56290b`。

## 结论

暂不进入第二阶段。基础代码与构建已经落地，但重导续读、最低 Android 版本兼容、文件生命周期、解压保护及非阻塞导入存在明确问题。Gemini 报告中部分“测试已覆盖”的描述与测试实际内容不符。

本次没有修改 App 源码，没有安装到用户手机，没有运行会 seed 数据的 Android 插桩，没有代替用户真机验收。只复跑构建/单测、读取代码和 SDK API 元数据、运行隔离的 JVM 审查样例，新增这份审查文档。

## 已验证证据

- `:app:testDebugUnitTest :app:assembleDebug :app:assembleDebugAndroidTest` 成功，但该次任务均为 UP-TO-DATE。
- 随后显式运行 `:app:testDebugUnitTest --rerun-tasks --console=plain`，退出码 0；37 个套件、228 项测试、0 failures、0 errors，不能由此推导未覆盖的业务正确。
- 验收 APK 确为 11,511,911 字节，applicationId `com.xxcomic`、versionCode 221、versionName 2.0.21。
- 文件 SHA-256：`3f55868fbacb597a2584253a8209c22b2caa5e3e32e188e7804b892153256634`，与提交报告一致。
- 签名 SHA-256：`131d74720c2565d2e502a474dc31e66a67039e048511a07fdd35d9487c93b72a`。覆盖安装还需设备当前版本码不高于 221、签名相同，不能无条件承诺。
- Android SDK `platforms/android-34/data/api-versions.xml` 明确 `ZipFile(File, Charset)` 从 API 24 提供，项目 minSdk 是 23。
- 隔离样例 `release/local-library-stage-1-review/LocalArchiveReviewProbe.java` 输出：

```text
Signature-only image accepted as pages=1; cover=1.png
Duplicate normalized paths accepted as pages=2
Size budget: accepted declared=16; streamed actual=135266312; configured limit=134217728
Same-file reimport chapter IDs: local_original_ch_0 -> local_reimported_ch_0
Same-file reimport page IDs: local_original_ch_0_p_0 -> local_reimported_ch_0_p_0
```

该样例仅在 release 下创建自制小压缩包，解压数据以小缓冲流式计数，没有操作用户漫画，也没有实际触发设备 OOM。

## 必须整改的发现

### R1 · P1：重导后并没有接回原阅读位置

位置：`LocalImporter.java:94`、`:179`，`MainActivity.java:2870`、`:3342`、`:6795`、`:6800`，`ArchiveIndex.java:210`。

每次导入创建新的 UUID bookId，只把旧 progressKey 存进数据库。MainActivity 没有使用这个 progressKey：章节进度依然 `progress.get(book.id)`，保存时也是新 comicId，页内位置由 comicId + chapterId 拼接；chapterId/pageId 也随新 UUID 全部变化。原记录仍在旧键下，重新导入必然从第 1 章/初始位置开始。数据库测试仅检查一个字段相等，不是实际续读测试。

整改：统一本地读写进度的稳定身份映射，同时解决章节/页身份；续读卡片与历史需能从旧进度身份找到当前实体，不能只替换 savedChapter 一个入口。

验收：导入 2 章多页 → 第 2 章第 3 页中段退出 → 重命名 → 删除 → 重导相同文件 → 重启 App → 从详情、续读、历史分别恢复原章/页/offset；文件夹同样验证。历史应避免重复的旧/新身份记录。

### R2 · P1：API 23 无法使用 ZIP/CBZ 导入

位置：`ArchiveIndex.java:71`，UTF-8 和 GB18030 分支分别在 74、87 行。

无条件调用 API 24 才有的 `new ZipFile(File, Charset)`，与 minSdk 23 不兼容。API 23 会抛 NoSuchMethodError；这里和导入 UI 只捕获 Exception，因此后台 Future 会失败且完成回调不执行，导入弹框可能一直留在等待状态。编译成功无法发现运行平台缺方法。

整改：在保持 minSdk 23 的前提下使用可运行的兼容路径，明确旧平台编码兜底能力；不要通过提高最低版本或简单 catch Throwable 掩盖功能失效。

验收：补 SDK 兼容检查及 API 23 样本验证；设备测试由用户完成时要将该项明确列待测，不再宣称全部平台通过。

### R3 · P1：导入中断/提交失败会留下不可管理的正式文件

位置：`LocalImporter.java:123`、`:133`、`:136`（文件夹对应 203–217）；`LocalLibraryStore.java:313`。

先把 staging 文件移动到 imports，再 commitImport；失败 catch 只删除已经移走的 staging 路径，不删除或登记正式副本与封面。进程在两步间退出也有同样结果。导入前没有持久 staging 记录，recoverOrphanedStates 只删数据库状态行，无法发现这些 imports 孤儿；`cleanStaging()` 在生产路径没有调用。

整改：文件移动前记录可恢复的导入状态/目标路径，建立提交失败和下次启动恢复流程，清理或完成对应文件/封面。恢复 deleting 记录也不能仅删除数据库行，否则丢失可恢复元信息并留下文件。

验收：分别在复制中、生成封面后、移动后/DB 提交前注入故障或结束进程；重启无幽灵书、无无法管理文件、无丢失原文件。数据库写入使用可检查的失败结果/抛错语义，不忽略 insert 失败。

### R4 · P1：删除不能保证清完文件，失败仍报告成功

位置：`LocalDetailView.java:260`，`LocalContentResolver.java:127`。

删除只清 imports 副本和封面，没有删除本书在 derived/pages 下已经解压的正文。`deleteRecursively()` 的返回值被忽略，异常被吞掉，仍移除 DB 索引并 toast “已删除本地漫画”。用户看不到这本书后却可能还有大量文件占用空间；全部递归删除也在主线程执行，大目录会卡住页面。

整改：后台删除本书全部关联文件，先停止/隔离相关读取工作，依据真实结果提交删除状态与空间统计。失败保留重试入口；读取任务晚回调不能重新生成已删除内容。正常缓存清理保持不会触碰原副本。

验收：阅读 ZIP 多页生成衍生文件后删除，对比本书所有目录及占用；模拟删除失败，不能提示完全成功或丢失重试记录；边读边退再删/大图片目录删除不阻塞 UI。

### R5 · P1：解压只检查声明大小，实际读取和缓存没有预算

位置：`ArchiveIndex.java:113`、`LocalContentResolver.java:132`、`LocalImporter.java:499`、`LocalContentResolver.java:167`。

索引阶段信任 ZipEntry.getSize，materializePage 的实际输出没有单条字节上限、可用空间检查、线程取消或缓存容量限制；失败不在 finally 清理 `.writing`。封面读取又把整个条目读入 ByteArrayOutputStream 后再复制成 byte[]，采样发生在全量读取之后。已用样例证实：声明 16 字节的 entry 实际可输出 135,266,312 字节，突破配置的 128MiB。正常大文件也可能导致内存高峰或磁盘被衍生页填满。

整改：在实际写入/读取时执行预算，封面用可重开流的 bounds + 采样解码，不整页无界聚合到堆内存；限制 derived 缓存、保护正在使用页、支持取消并清未提交文件。同页前台读取和预取需协调，避免同时间戳暂存路径冲突或相互删除目标。

验收：伪造小声明/大输出立即限流失败并回收；大图封面不产生全文件双副本内存；磁盘不足、取消、并发同页、读大量页后缓存上限均有行为测试。

### R6 · P1：SAF 文件夹的目标路径未经校验就写入

位置：`LocalImporter.java:247`、`:253`。

将 DocumentsProvider 提供的 DISPLAY_NAME 直接传入 `new File(targetDir, name)` 并 mkdir/打开 FileOutputStream，没有在写入前检查 canonical 路径或限制名称为单段。自定义提供者返回 `../...` 时可以逃出本次 staging，事后读取时的 assertPathInsideRoot 无法补救已经发生的越界写入。文件夹递归也缺少条目数/深度/单文件预算，与 ZIP 的限制不一致。

整改：对文件夹名和文件名统一做单段校验及根内路径检查，然后才创建/打开；拒绝重复目标、越界和循环/超深目录，在复制实际数据时执行数量与大小预算。

验收：受控 DocumentsProvider 输入越界名/重复名/循环目录，目标目录外没有任何文件改变，失败清理仅针对本次导入路径。

### R7 · P2：导入阻塞其他页面，取消也不贯穿整个任务

位置：`MainActivity.java:663`、`:728`，`LocalImporter.java:258`、`:309`。

两个入口都创建 `.setCancelable(false)` 的模态 AlertDialog，用户只能等待或取消，无法切换书架/发现/设置；不是设计中的非阻塞状态。文件夹复制单文件的 while 内无取消检查，后续哈希/索引/封面/提交也无取消校验，点击取消之后任务仍可能入库。共享 boolean[] 也没有跨线程可见性保证。

整改：使用主题内联导入状态或可收起的非阻塞任务 UI，任务与页面生命周期分开；使用线程安全取消信号，复制、哈希、解析、提交前检查并一致清理，避免 Activity 销毁后弹框。

验收：导入大目录时切到其他页面再回来；在复制/哈希/解析分别取消，任务无新书提交、无临时文件残留。部分成功的批量导入需要同时列明失败项，不能只显示成功数量。

### R8 · P2：无效图片被当作正文，书名/封面兜底不符合约定

位置：`ArchiveIndex.java:147`、`:257`，`LocalImporter.java:51`、`:152`、`:115`。

图片只核验前几个魔数字节，8 字节 PNG 文件头已被实测接受为 1 页，之后生成 ready 作品却无法阅读；不是“实际有效图片”。封面只尝试所选第一条目，首图坏但下一张可用时不会继续选。DISPLAY_NAME 为空时先替换为 comic.zip/comic_folder，后续“未命名漫画 N”分支因此不触发。规范化后重复路径也被接受成两页。

整改：入库前确认存在实际可解码正文，区分局部坏页与全书不可读；封面沿阅读顺序找第一张实际有效图片，默认图仅在确实没有可用封面时使用。无名使用约定编号，重复规范化条目明确拒绝。

验收：只有图片头的压缩包拒绝入可读库；坏首图+正常第二图封面用第二图且正文规则明确；无名文件与文件夹显示未命名编号；重命名与重导保持名称。

### R9 · P2：剩余空间计算重复扣掉已复制数据

位置：`LocalImporter.java:74`、`:262`，`LocalStorageManager.java:151`。

复制已经写入后读取当前 usable，再减去累计 bytesCopied。当前剩余空间已经扣过复制的字节，相当于要求接近两倍空间。例如可用 2GiB、导入 1GiB 文件，实际完成后仍有 1GiB，逻辑却会在约 896MiB 时因额外扣减而报空间不足。

整改：区分复制前的预估需求与复制中的当前剩余空间，仅从当前 usable 扣除仍未写入的必要预算；未知大小使用动态余量，不减累计量。

验收：注入可控空间读数，分别测刚好足够、余量不足、未知长度与文件夹累计大小。

### R10 · P2：本地详情没有复用约定目录抽屉，交互样式未对齐

位置：`LocalDetailView.java:149`、`:169`、`:173`、`:222`、`:252`。

本地详情把全部章节逐个加入 ScrollView 中的 LinearLayout，没有 76% 目录抽屉入口，报告中“本地详情 76% 目录”的描述不成立。重命名、删除使用默认系统 AlertDialog/Toast，未接现有蕾姆主题确认。大量章节一次性创建 View 也会明显拖慢详情。

整改：复用现有详情/阅读目录的样式和 76% 抽屉，列表按需创建；删除/重命名沿用主题控件，去掉与现有详情不一致的重复布局。

验收：浅深色对比现有详情页，打开目录检查宽度、排序、当前章和滚动；大章节目录不一次创建全部行，长标题与大字体仍可操作。

### R11 · P2：重命名后的当前详情和第一章阅读状态显示不正确

位置：`MainActivity.java:2899` 附近 `onBookRenamed`，`LocalDetailView.java:143`、`:198`。

重命名只更新 details Map 并刷新背后的书架，当前 LocalDetailView 的标题与点击监听闭包仍使用旧 book/detail；继续阅读的工具栏也可能带旧书名。按钮用 savedChapterIndex > 0 判断是否读过：读到第一章中段仍显示“开始阅读”，未读书却把第一章标成“上次读到”。

整改：重命名后刷新当前展示模型与操作闭包，并同步 summary；通过是否存在实际历史判断开始/继续和上次章节，不用章节索引是否大于 0 判断。

验收：新书无“上次读到”；第 1 章中段退出后显示继续；当前详情重命名立即更新，直接阅读/回书架/历史均显示新名。

### R12 · P2：切换回本地书架会丢失滚动位置

位置：`MainActivity.java:1603`、`:1789`。

每次切到本地页调用 refreshLocalBookshelf，直接移除旧 ScrollView 并新建，没有保存/恢复 scrollY。与独立保持滚动状态的报告和设计不符。书架标题只设 minimumHeight、两侧文本 wrap-content，也不能由代码认定固定行高/窄屏绝不跳动。

整改：未变更数据时复用已有本地视图；确需重建时记录并恢复状态。标题宽度和大小变化以真实布局校准。

验收：本地书架滚动到下方 → 切我的书架 → 再切回，原位置保持；长标题/大字体/连续点击录屏由用户验收。

## 测试与报告必须同步纠正（R13）

- `LocalImporterTest` 实际只测目录指纹、两种章节划分；没有执行 importArchiveUri/importFolderUri、取消或真实去重事务。
- `LocalContentResolverTest` 只测字符串 URL 构造/识别；没有打开页面流或验证 ZipFile 关闭。
- `LocalStorageManagerTest` 没有测试剩余空间数值策略，无法支撑“256MiB 余量检查通过”。
- `LocalLibraryChecks` 仅检查数据库字段/手工构造数据，不测试 UI 阅读恢复、真实磁盘原子性、进程中断恢复；插桩 APK 编译成功不等于插桩执行成功。
- 阶段报告没有设备型号/API、插桩运行输出或实际视觉截图证据。用户已明确由自己做真机验收，应把设备/视觉项标为待用户验证，而不是在方案清单中全勾选。
- 构建存在既有 AGP/compileSdk 警告，报告“无任何告警”不准确；无需借此升级工具链，只需如实记录。

Gemini 应为每个已修复问题增加对应行为回归，补足源码问题所涉及的真实链路；不会跑的设备项目明确列出，不用源码字符串测试伪装端到端验证。

## 给 Gemini 的整改指令

```text
第一阶段 Codex 验收未通过，先不要进入第二阶段。
完整阅读 docs/superpowers/reports/local-library-stage-1-codex-review.md。
在 codex/local-library-offline 上逐项核实并修复 R1–R12；若有异议，提供具体代码/运行证据，不得直接忽略。
优先修复 P1：稳定续读身份、API 23 ZIP 兼容、导入/删除恢复、解压与内存保护、SAF 目标路径安全。
随后修复导入非阻塞与取消、名字/封面/有效正文识别、空间计算、主题目录和交互状态。
按 R13 纠正报告与计划勾选，新增真实行为测试，不得把未执行的设备测试写成通过。
不改与整改无关的在线站源，不覆盖已有用户改动，不进入下载/电子书阶段。
修复后提交整改代码，更新阶段报告，提供新的独立验收 APK、哈希及人工复现清单，然后停止。
Codex 重新验收，我负责真机验收。不要自动推送、合并 master、升正式版本或发布 COS。
```

审查复现辅助文件位于忽略目录 release，仅供复现，不必提交到生产源码；Gemini 应把必要的独立样例转成规范回归测试。
