# iOS 移植交接：供 Gemini 继续开发

更新：2026-09-20。用户已要求 Codex 停止开发，转交 Gemini。本文是剩余方案与执行流程，不表示功能已完成。

## 1. 先看这里

- **实际开发目录**：`F:\softForCode\codex-project\xx-comic\.worktrees\ios-port`。不要在外层 Android 主工作区误改。
- **分支**：`codex/ios-port`。
- **最后已提交状态**：`e800a06`，文档提交；对应最近功能提交 `ba575ef`、安全修复 `6335cfc`，均已完成任务范围独立审查。
- **Android 对照基准**：2.0.29 / versionCode 229；基准提交 `0d41c22f6917fb471e663fc3dbb40c2c39ed6d9c`；254 文件哈希基准。不得修改 Android 来迁就 iOS。
- **技术栈**：Swift 5.9 / iOS 16，UIKit + ComicCore，已有 ZIPFoundation、系统 zlib、WebKit、PDF 原生渲染等，优先复用。
- **用户范围**：先补齐安卓版功能；暂停新增站源，jmcomic、hanman18 后续由用户处理。已有站源的管理、验证与下载接线仍在范围内。
- **环境**：Windows + Docker；没有已配置的 Mac/Xcode 构建环境，也没有已验证可安装 IPA。不要宣称 1:1 已完成或绝对无 bug。
- **停止时状态**：实现代理已中断，Docker 容器列表为空。以下 3 个未完成文件已保留，未提交、未回退。

### 未提交工作，必须首先处理

| 文件 | 实际状态 | 接手动作 |
| --- | --- | --- |
| `ios/ComicCore/Sources/ComicCore/LocalLibrary.swift` | 仅增加 `LocalImportFormat`、LocalBook 的可选 `importFormat/fingerprint` 及初始化器默认参数 | 保留并完成实际导入/验证接线，不能把字段存在当作功能完成 |
| `ios/ComicCore/Tests/ComicCoreTests/ContentFingerprintTests.swift` | 增加扁平拥有文件与原路径映射的测试 | 它调用的内部 `folder(root, files:)` 尚未实现，因此当前工作树可能无法编译测试 |
| `ios/ComicCore/Tests/ComicCoreTests/LocalImportFingerprintTests.swift` | 新增未跟踪的整合测试草稿 | 必须一并保留；部分期望仍由被测 ContentFingerprint 计算，需要改为独立 Node crypto 固定预期；覆盖仍不完整 |

Task45 没有完整落盘报告、没有最终 GREEN，也没有独立审查通过。此前实现代理口头报告过行为 RED，但交接不将其当作完整可复核测试证据。接手时重新确认本任务基线即可，不必重做 Tasks1–44。

不要运行 `git reset --hard`、`git clean -fdx`，也不要自动丢弃这些文件。`git diff` 不显示未跟踪文件内容，须单独打开新测试文件。

## 2. 可靠资料与优先级

1. Android 实际源码与基准行为是业务依据。
2. `ios/PARITY.md`：当前逐项完成/欠缺矩阵。
3. `ios/VALIDATION.md`：历史验证证据和平台限制。
4. `docs/superpowers/specs/2026-09-19-ios-parity-baseline.md`：迁移基准。
5. `docs/superpowers/specs/2026-09-20-ios-local-library-lifecycle.md`：已确定的本地批量、合集、恢复设计。
6. `docs/superpowers/plans/2026-09-19-ios-online-parity.md`：Tasks1–45；**从 Task45 继续**。后续任务尚未全部写成实施任务，不要误认为总计划已覆盖全部剩余功能。

本机还保留 `.superpowers/sdd/2026-09-19-ios-online-parity/` 下的 `progress.md`、任务报告、review diff，以及 `local-management-research.md`、`download-research.md`、`management-research.md`。它是 **Git 忽略目录**，换机器/只克隆仓库不会带过去；本文已收录关键约束，仍需按具体任务读 Android 源码。

`ios/README.md` 的早期“13/18站源、其他格式未接”等描述落后于实际代码，不能据此重新实现。以 PARITY、实际代码和最新验证记录为准。Gemini 无须安装或采用 Codex 的代理技能；普通串行实现加审查即可。

## 3. 已有能力，不要重写

- 16/18 个默认站源已注册并经过任务范围审查；真实网络、Apple 平台仍需验收。剩余两源暂停。
- 在线发现/搜索、收藏与历史持久化、详情/按需目录、分类抽屉、图片阅读器、主题、白边、墨水屏、阅读习惯等已有实现或接线，差异见 PARITY。
- 本地图片、文件夹、ZIP/CBZ、EPUB、PDF、MOBI/AZW 导入及既有阅读入口已实现。EPUB 已有全文、目录、排版与续读；Kindle 已有 MOBI7/PalmDOC/兼容组合文件转换及缺派生文件恢复。
- 与 Android 支持边界一致：不要假称纯 KF8/KFX/Topaz、DRM 已支持。
- 批量基础：`QuickPublicationInfo`、`BatchImportPlanner`、`BatchImportSession`、`ContentFingerprint` 已有实现与审查。元数据扫描不代表文件可读；持久 URL 字符串不代表文件权限。
- Task44 六格式共用准备/发布已完成。最近误删未知文件问题已修复：按名字和 device/inode 登记；未知项、链接或同名替换时保留暂存并报错。**不要退回“枚举所有子项然后删除”。**

最近证据：Task44 修复回归先 3 测试/13 断言失败；修复中发现 EPUB probe 复用问题并解决；最终重跑 51 项、1 项 Apple 条件跳过、0 失败，另 36 项相关格式测试此前通过。独立复审 Spec/Quality 均 PASS。Android 254 文件基准一致。此证据对应已提交状态，不覆盖 Task45 草稿。

## 4. 总体剩余量与执行顺序

剩余 **5 大块**，不是仅剩打包：

| 大块 | 尚缺内容 | 下列执行阶段 |
| --- | --- | --- |
| 本地批量与分卷 | 实际 worker、授权恢复、分组确认、合集、混合格式跨卷阅读、卷管理界面 | A、B、C、D |
| 去重及删除重导恢复 | 指纹接线、稳定身份、墓碑、删除事务/重试、重命名 | A、B |
| 下载与离线 | 队列、图片/文件 worker、恢复、下载中心、离线优先阅读 | E、F、G |
| 管理功能 | 历史、存储、缓存、站源配置、可用性、日志、关于 | H、I |
| Apple 与一致性验收 | Xcode 编译、原生测试、签名安装、iPhone 行为/视觉/性能 | J，构建应尽早尝试 |

这不是工时或百分比估计。建议一次交付一个可验证的用户流程，不再无限铺核心模块而不接 UI。B/C/D 可拆小提交，但以“多文件导入→合并→阅读→重排→删除→重导恢复”作为整块验收。

## A. 完成当前 Task45：真实导入指纹与格式

权威详细任务见总计划 Task45。预计修改：LocalLibrary、LocalFolderIndex、LocalEpubLibrary、LocalPdfLibrary、ContentFingerprint、LocalImportPreparation 及两组指纹测试；不要改解析器、Android、站源或 UI。

1. LocalBook 的两个可选字段默认 nil；旧 JSON 缺字段仍可读。新格式枚举为 images/folder/zip/cbz/epub/pdf/mobi/azw/azw3。
2. 文件指纹来自**本次拥有的副本**：EPUB `content.epub`；PDF `content.pdf`；Kindle `source.kindle`，不能散列派生 EPUB 冒充原包。
3. ZIP/CBZ 先限量复制为暂存 `source.archive`，再从同一副本解压、校验和散列；发布后保留原包。外部源在 probe 回调中改变不得影响导入结果。实际磁盘占用包含原包和展开图片两份。
4. 文件夹保留扫描时的原相对路径（共同 wrapper 剥离前），与平铺拥有图片一一对应。不要用生成的 `0.png/1.png` 作为原路径身份。
5. 新增内部 `ContentFingerprint.folder(_ root: URL, files: [(relativePath: String, ownedFile: URL)]) throws -> String`；公开旧接口复用同一管线。原路径 UTF-8 唯一、自然序；ownedFile 必须在 root 内且逐级无链接；保留 50000 项、128MiB 单图、20GiB 总量与取消限制。
6. 多选独立图片是 `.images`，指纹 nil，不伪造文件夹身份。旧 ZIP/文件夹缺原包/路径也不补造指纹。
7. 元数据在准备完成、book.json 写入之前一次算好。验证合法格式组合及 64 位小写 ASCII 十六进制指纹；新 ZIP 声明格式时，准备和重开均要求拥有的普通 `source.archive`。不要重开书架就重新散列全部大文件。
8. 现 `prepareLocalImport` build 是 `(String, URL, LocalImportDirectory) throws -> LocalBook`；新增文件用 `copy/copyEbook(..., didCreateFile: owned.recordFile)` 登记。不要绕过 Task44 的所有权检查。

验收：真实格式 fixture；Node crypto 独立固定 hash；旧 JSON；原始外部字节保护；改变原路径导致文件夹指纹变化；非法格式/hash、source.archive 缺失/链接、越界和中途取消。当前草稿用被测函数生成期望的问题必须修正。ZIP fixture 要固定时间戳或固定原包字节，不能硬编码不稳定 ZIP 的 hash。

## B. 合集、身份、去重与删除恢复

对照 `app/src/main/java/com/xxcomic/local/LocalLibraryStore.java`、`LocalImporter.java`、`LocalModels.java`、`LocalStorageManager.java` 及对应测试。遵循本地生命周期 spec，新增文件名可按职责调整，不必机械套编号。

### 存储设计

- 保留现有 UUID 物理卷目录、book.json 和格式资源，**不搬全库、不把多个 EPUB 伪装成单份 EPUB**。
- 作品/系列 ID 与物理卷 ID 分开；旧单卷默认同 UUID 的隐式系列，首次合并保留已有作品/章节身份。
- 用一个版本化、有读取/写入大小上限的原子 JSON catalog 保存显式系列、有序卷引用、删除状态和指纹墓碑；单一 actor 串行变更，不加 SQLite/新数据库依赖。
- 落盘成功后才更新内存；损坏/不支持版本/超限不能当空库覆盖。通过实际文件写失败验证回滚。
- 系列只有引用已提交才对书架可见。新物理卷元数据带归属，先隐藏发布、再提交 catalog；失败留下的明确孤儿仅在启动且没有活跃 worker 时恢复/清理，不运行中扫掉全部 `.import-*`。

### 操作与身份

- 同指纹普通导入返回已有作品；显式追加不同作品报“已导入”，不悄悄搬卷。文件名相同不是内容相同。
- 准备结果的临时 ID 和正式恢复 ID 必须在发布前处理。当前 storage.id 同时用作暂存令牌与正式 ID，后续需显式拆开；修改最终 book.id 时同步更新稳定章节 ID、归属、manifest 字节长度与拥有记录。不能先可见再改 ID。
- EPUB 校验按物理 book.id 生成 `_ch_index`；无显式章节的图片书用 book.id 作章 ID。恢复必须保持这些规则。
- 墓碑至少能恢复旧作品/卷身份、章节身份和用户标题。旧身份仍被现存作品/目录占用时不得覆盖，应按 Android 冲突规则处理；读取原方法，不凭猜测按标题合并。
- 重命名使用 Android trim，拒绝空标题；失败保留输入。卷重排必须是全部现有卷的完整排列，章 ID 不变。
- 删除先持久化 deleting，再清精确拥有副本，最后原子完成删除/墓碑；失败保留可重试状态。删首卷不删系列身份；删最后卷等同整书删除。
- 保留收藏、历史、原始用户文件。仅明确删除历史时清相应阅读位置与恢复关联。
- 写入保留至少 256MiB 可用空间；未知总大小也逐块检查。原包、展开文件、派生缓存、下载占用分开统计。

验收：两个导入竞争同内容只出现一个结果；追加中删除目标后迟到结果不能复活；重排不丢进度；删首卷/末卷；删除失败重试；同内容重导恢复标题和历史；原路径/其他卷/未知文件不受损；坏 catalog 不覆盖；发布成功但 catalog 失败后的启动恢复。

## C. 系列阅读路由与 UI 消费者

涉及现有 `LocalComicSource.swift`、`EpubTextSession.swift`、`LibraryStore.swift`，以及 `DetailViewController.swift`、`ReaderViewController.swift`、`EpubTextReaderViewController.swift`、`EpubBookSchemeHandler.swift`。

- 建立明确 readingTarget：系列 ID + 稳定章节 ID → 物理卷 ID + 卷内章/spine + 全局章序。
- 图片/PDF 走现有漫画阅读器；文字/图文 EPUB 走现有文字阅读器。目录跳转、下一章、上一章跨类型均可用，不停留于 requiresTextReader 错误页。
- 换 reader 替换当前导航项，保留详情返回路径，不连续 push 堆栈。
- 保留入口意图：续读/目录可以恢复保存位置；主动跨章从章首进入，上一章从章末进入。不要把全部跳转都当续读。
- 文字 session 可以保持物理卷内部定位；保存/恢复时转换为系列历史身份及全局章节序。正文内部链接、上一/下一节同样可能跨章节，不能只适配目录按钮。
- WK 资源授权始终绑定当前物理卷，不因系列有多卷放开跨卷文件访问。
- 重排后按稳定章 ID 定位；删除当前章只使该章失效，不清其他章位置。被删书的历史显示标题及“重新导入”提示，不让列表整体报错。

验收：图片→文字→PDF→文字双向跨卷；拖动卷后续读；正文内部链接；多个 EPUB 有重复 href；无效资源隔离；旧单卷及旧历史 JSON 全部保持可用。

## D. 实际批量导入、Files 授权与卷管理界面

复用已完成 Planner/Session/Metadata/Fingerprint，不重写它们。Android 对照 `BatchImportPlanner.java`、`BatchImportSession.java`、`VolumeManagerSheet.java`、`LocalDetailView.java` 与 MainActivity 导入入口。

- 当前 picker 只有 images 多选，其他格式只消费 `urls.first`。需要完整多选→扫描→建议分组→确认→串行发布→进度/重试链路，不能只打开多选开关。
- 本地同名仅建议合并，需确认；远程元数据按原作品身份分组。用户可独立导入或合并；卷序复用既有精确排序。
- 安全作用域覆盖扫描和复制，start/stop 成对；外部 Files 读取用 NSFileCoordinator。系统文件提供器需 Apple 真机测试。
- iOS 持久书签使用 `.minimalBookmark` 创建、默认 resolvingBookmarkData 解析，处理 stale/撤销权限；不要使用仅 macOS 支持的 `.withSecurityScope` 创建/解析选项。
- 批次 URL 字符串不是授权。重开授权失败时保留状态并提示重新选择，不能假装空文件或导入成功。
- 已完成/跳过不重跑；失败不挡后项；重试前确认旧 worker 停止；取消保留已完成、丢弃未完成，代次校验阻止迟到回调。
- 分卷抽屉按 Android 72% 高度；拖动落手只保存一次；删除 3500ms 撤销；下次删除/关闭/离开先提交待删项；忙时不能丢掉已承诺删除。
- 详情显示真实格式/大小/卷数、重命名、添加卷、删除错误重试，明确仅删除 App 副本。

验收：多文件混合格式导入、分开/合并、取消/重开/权限撤销、单项失败继续、重试不重复、拖动与删除忙态、撤销/离开提交。

## E. 下载队列与持久状态

Android 依据在 `app/src/main/java/com/xxcomic/download/`：DownloadModels、DownloadCoordinator、DownloadStore、DownloadRuntime、DownloadService 及 `app/src/test/java/com/xxcomic/download/`。实现前定向读原文件，研究摘要不替代代码。

- 身份来自 source/comic/chapter 或 source/comic/fileId，不能用标题或带签名 URL。保留在线作品与章节身份，离线阅读不能创建另一份历史/收藏。
- 状态包括 QUEUED、RESOLVING、DOWNLOADING、VERIFYING、COMPLETED、PAUSED_USER、WAITING_NETWORK、WAITING_VERIFICATION、FAILED、CANCELLED、DELETING。
- FIFO、总并发最多 2，默认 Wi-Fi only；使用 generation/lease 阻止暂停、取消、删除重建后的旧回调发布。actor 遇 await 会重入，发布前必须再次核验。
- 重开 active→queued；完成记录须校验内容；删除中任务继续清理。暂停/继续/取消/重试要真实落盘，写失败不能显示成功。
- 自动失败退避对照 2s/5s/15s；Retry-After 上限 15 分钟、429 至少 60s；验证失败区分 WAITING_VERIFICATION 并影响同源相关任务。
- 不持久化短期签名 URL、Cookie、Authorization。恢复时重新解析。
- iOS 后台遵循系统调度；先保证可恢复，不照抄 Android 常驻服务、wakelock，也不承诺用户强退后持续下载。

验收：FIFO/并发上限、断网/Wi-Fi、迟到结果、重开、同任务去重、验证等待、失败重试和删除恢复。真实磁盘持久化测试，不仅内存 mock。

## F. 图片与文件下载 worker

### 图片章节

- 读取真实章节图片，不能把 Baozi 的 nextPageUrl 当同章下一页无限追下去。
- `.part` 按代次隔离；校验响应、实际长度、128MiB 限额、真实图片解码与全文件 hash 后才发布。失败/取消回收自己的部分文件。
- 重用已完成且身份/hash 匹配的整页，**不是图片字节 Range 续传**。
- 对已有混淆图片保留正确解码后的字节或所需变换元数据，不重编码 JPEG 损伤内容；JM 新站源暂停，不因此阻塞通用下载，但不能丢掉现有变换契约。

### 文件资源

- 可选文件源能力单独建最小协议；当前图片源不伪装支持文件。先做通用框架与测试，不新增站源适配。
- 仅 matching revision/hash + strong quoted ETag 可 Range/If-Range 续传。
- 200 从头截断；206 校验起止/总量/ETag/实际长度；416 清旧续传状态再重试。过期或 401/403 最多重新解析一次。
- HTTP(S) 无 userinfo、禁止 HTTPS 降级；跨 origin 清源敏感 headers；防 CR/LF、覆盖 Host/Range 等头。重定向预算按原版 5 次。
- 文件上限 20GiB，空数据/HTML 拒绝；校验容器实际格式、已知长度和可选 hash。
- 新版本发布成功并持久索引后才删旧版；新下载取消不能破坏原来可读版本。

验收：本机 HTTP 服务器提供正常、截断、错误 HTML、206/200/416、ETag 改变、重定向、取消、刷新失败样例；真实文件验证旧版本保留。

## G. 下载中心与离线阅读接线

涉及 AppEnvironment、详情、阅读路由、设置；复用本地存储，避免另造不兼容书库。

- 下载选择面板约 76% 高度；本章/全选/清空/区间/倒序，区间按当前显示序 1-based inclusive，倒序不改原章节身份。
- 下载中心按作品展示队列，支持暂停、继续、重试、取消、清理、验证入口、完成后阅读及确认后重新下载。
- COMPLETED 时优先校验本地内容；坏内容显示“下载文件需要修复”并提供修复入口，不静默走网络掩盖损坏。
- 未下载且断网与已下载损坏应显示不同提示；成功/失败都检查当前阅读请求代次。
- 删除下载书由 download runtime 统一清任务与存储，不能只删 LocalLibrary 文件夹。

验收：在线下载→飞行模式启动→续读→跨章；坏文件修复；下载中删书；重下保留原阅读进度与在线收藏。

## H. 历史、存储、缓存、日志和关于

- 历史单条删除/清空：明确确认，清阅读记录、图片位置和文字位置，保留收藏。明确删历史后清相应本地墓碑关联；普通删书则保留历史。
- 已删除本地书保留可辨识历史行及重导提示，不能打开不存在内容导致全列表失败。
- 存储分类统计导入、下载、缓存及可用空间，真实遍历计量并处理错误，不把 ZIP 原包+图片只计一份。
- 缓存清理按具体目录/缓存对象列白名单：URL/WK、图片内存/磁盘、裁剪、章节/搜索、派生页；保留原包、下载内容、历史、收藏和设置。禁止递归清 Application Support 根。
- 设置增加下载中心、存储、历史、缓存清理、错误日志、关于/版本。日志脱敏 URL/token/cookie/authorization，不增加后台分析或账号系统。
- Android APK 自更新不移植成 iOS 假安装入口；版本信息与更新方式须符合实际分发方式。

验收：清缓存后所有导入/离线书和续读仍可用；清历史后收藏仍在；低空间真实错误可重试；大小统计与磁盘实际占用对应；无敏感日志。

## I. 已有站源的配置管理与验证回归

- 已有开关/排序/恢复默认不要重做。补配置导入导出、自定义参数及实际消费者。
- Android 配置 schema `xx-comic.sources`、version 2，包含 sourceOrder、sources、custom；内含 routes/filters/baseUrl/referer 等。完整解析校验后原子替换，不半成功。
- 目前很多 Swift source 仅构造 baseURL/name，尚未消费完整 routes/filters。不能做一个 JSON picker 却忽略字段就称兼容。
- healthCheck 是可用性检测，界面不要冒称网络测速；可取消且旧结果不更新新页面。
- 18漫画等验证会话需 Apple WebKit/Cookie 实际回归；不能将 parser fixture 当验证码登录验收。新增两个站源仍不做。

## J. Apple 构建、视觉和最终交付

**尽早并行解决 Apple 编译环境，不必等所有功能写完才第一次编译。** Windows Docker 不能运行 iOS SDK、UIKit 类型检查或 iPhone 模拟器。

- 已有 `ios/project.yml`、`ios/scripts/build.sh`、`.github/workflows/ios.yml`。脚本：Core tests → XcodeGen → simulator build → 可选 UI tests → device unsigned build → 未签名 IPA。
- 当前 workflow 使用 macos-14；接手时确认该 runner 仍可用、Xcode/iOS16目标兼容，按平台实际情况更新。没有成功云构建证据。
- 可以由用户在 GitHub 注册免费账号并创建私有仓库，明确同意上传后运行手动 workflow；私有仓库免费额度有限，不承诺无限免费。不要擅自公开或上传现有源码。
- 未签名 IPA 不可直接安装。用户后续自行选择签名/分发方式；Apple 账号、证书和密码不能写进源码或日志。
- 必测 Apple 分支：CryptoKit/CommonCrypto、zlib 链接、ImageIO、PDF 原生像素、WebKit 脚本/资源隔离、Files/书签/NSFileCoordinator、Darwin rename/link/APFS、真实异步与内存。
- Android/iOS 使用相同 fixture、页面状态、主题与内容逐页对照：书架、发现/搜索、详情、分类/目录抽屉、两种阅读器、批量与卷管理、下载、设置与错误态。系统手势/安全区等平台差异单独记录。
- 实机覆盖后台/前台、旋转/字号、弱网、长图/大文件、内存峰值、权限撤销、安装/升级后旧数据。不能只比正常路径截图。

最终交付必须包含：完整差异表、Xcode 构建日志、测试结果、签名安装说明、可复核的设备验收记录。Apple 环境拿不到时，明确列为未验收，不改成“全部完成”。

## 5. 建议的开发节奏

1. 进入正确 worktree，读本文件、PARITY、对应 spec；查看 git status，保留当前未提交工作。
2. 首先完成 A/Task45，只跑需要的测试；完成后再处理 B。后续按 B→C→D→E→F→G→H→I，J 的构建检查尽早插入。
3. 每个小任务先读具体 Android 方法及现有 iOS 调用者，列出输入、输出、默认值、失败与取消结果；只实现当前任务，不新增未来框架。
4. 为高风险逻辑建立可复现行为测试，再实现。格式支持使用真实 fixture；文件与队列用真实临时文件/本机 HTTP；简单 UI 文案无需为凑数量加测试。
5. 每个模块都落实实际消费者和错误 UI；阶段验收跑完整用户流程。核心通过、UI 接线、Apple 编译、真机验证分别记录，不能混写。
6. 一个 worktree 同时只允许一个实现者和一个 Core 构建，避免文件/缓存冲突。可以另做只读审查，但不强制代理工具。
7. 自查 diff，必要时独立代码审查；修具体问题后只重跑影响范围。不要每个小改都重复全库重测，也不能以检查语法替代测试。
8. 每个通过的独立功能做本地小提交，更新 PARITY/VALIDATION；不要 push、发布、删除用户数据或扩大站源范围，除非用户明确要求。

## 6. 可直接用的命令

PowerShell，先进入实际 worktree：

```powershell
Set-Location 'F:\softForCode\codex-project\xx-comic\.worktrees\ios-port'
git status --short
git log -5 --oneline
git diff --check
node ios/scripts/android-baseline.mjs --check
```

Task45 完成后的相关测试（当前草稿缺 API，不保证此刻能编译）：

```powershell
docker run --rm --mount 'type=bind,source=F:\softForCode\codex-project\xx-comic\.worktrees\ios-port\ios\ComicCore,target=/work' -w /work swift:5.10-jammy swift test -j 2 --filter 'LocalImportFingerprintTests|ContentFingerprintTests|LocalImportPreparationTests|LocalLibraryTests|LocalFolderTests|LocalArchiveTests|LocalEpubLibraryTests|LocalPdfLibraryTests|LocalKindleLibraryTests'
```

UIKit 语法及构建脚本语法检查，**不等于 Apple 编译**：

```powershell
docker run --rm --mount 'type=bind,source=F:\softForCode\codex-project\xx-comic\.worktrees\ios-port\ios,target=/work' -w /work swift:5.10-jammy bash -c 'swiftc -frontend -parse XXComic/*.swift XXComicUITests/*.swift && bash -n scripts/build.sh'
```

在真实 macOS、安装 Xcode/XcodeGen 后，在仓库根执行：

```sh
bash ios/scripts/build.sh
# 需要运行原生 UI tests 时，将 UDID 替换为 xcrun simctl list devices available 中的真实设备值：
IOS_TEST_DESTINATION='platform=iOS Simulator,id=真实UDID' bash ios/scripts/build.sh
```

## 7. 可直接复制给 Gemini 的接手指令

> 请接手现有 Android→iOS 移植，先完整阅读 `docs/IOS_GEMINI_HANDOFF.md`、`ios/PARITY.md` 和本地生命周期 spec。实际目录是 `F:\softForCode\codex-project\xx-comic\.worktrees\ios-port`，分支 `codex/ios-port`，最后提交 e800a06；有 3 个未提交 Task45 文件，必须保留并检查。用户要求先补齐功能，暂停新增站源，不修改 Android、不公开/推送代码。
>
> 不要重写已有模块。先完成 Task45 的真实拥有副本指纹与原格式信息，修正测试草稿中的自证 hash 和缺失映射 API，再依次完成合集/删除恢复、混合卷阅读、批量导入与卷管理、下载离线、设置管理。按本文验收条件接通 UI，避免只写核心层。Apple 编译应尽早安排，但不得擅自上传仓库；拿不到 Apple 环境如实保留验收缺口。
>
> 每个阶段给出实际改动、测试命令/结果和剩余项，使用简体中文。保护现有改动与用户文件，优先标准库/系统能力/已有依赖，少写框架。不要反复问是否继续；如果遇到确实需要账号、签名或用户选择的阻塞，具体说明。不要用代码量、测试数量或主观百分比宣称 1:1 完成，也不要保证绝对无错。
