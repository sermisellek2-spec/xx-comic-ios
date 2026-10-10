# iOS 移植验证记录

> 2026-10-10：以下结果是各历史版本的实际记录，不能证明当前交付版本验收。新增2.0.40任务以[执行方案](../docs/IOS_2_0_40_GEMINI_PLAN.md)与[阶段报告模板](../docs/ios-parity-2.0.40/STAGE_REPORT_TEMPLATE.md)收集当前版本证据；保留这些失败与修复记录，尤其重跑外链UIAlertController回归和iPad检查。

日期：2026-09-20。工作区 `.worktrees/ios-port`，分支 `codex/ios-port`。

## 实际执行

- 2026-09-21 第二轮 UI 结果（`iOS-test-results (1).zip`）：17 个用例中 16 个通过，仅外链安全用例出现 2 次失败。App 日志明确记录 `NSInternalInconsistencyException: The presentation controller of an alert controller presenting as an alert must not have its delegate modified`，调用栈为 `confirmExternal` → `presentPanel` → UIKit `setDelegate:`。已让 `presentPanel` 保留 UIAlertController 的系统 delegate，普通目录/排版面板仍监听交互关闭；警告框沿用已有 action 回调更新遮罩状态。保留原有外链确认与取消返回断言作为回归测试。此次修正尚待 macOS UI 重跑，未宣称通过。

- 2026-09-21 UI 测试结果包排查（`iOS-test-results.zip`，`UITests.xcresult`）：该轮 Core 646 项通过、模拟器编译通过；UI 17 项中 5 个用例共 7 次断言失败，尚未通过全部验收。解压 Zstandard 数据后直接核对 XCTest 无障碍树：字号步进器实际是 `epub.fontSize-Increment` / `Decrement` 按钮；DRM 导入项在可滚动菜单可视区域下方；禁用脚本后的 javascript 链接实际暴露为静态文字。已按实际元素调整测试，保留字号修改/重启持久化、DRM 拒绝、安全脚本不执行和外链确认断言。各 EPUB/Kindle 场景使用独立 UUID 数据目录和偏好域，同一场景重启复用 UUID，避免前序用例保存的章节进度污染后续用例；切节竞态测试增加初始“第1章，第1节”断言。此次修改尚待 macOS 重跑，Windows 无 Swift/Apple SDK 且 Docker daemon 不可用，不能据此宣称 UI 已通过或 IPA 已生成。

- 下载安全加固、文件下载Worker、本机HTTP测试服务与动态站源消费（2026-09-20 深夜）：全量 638 项测试通过（2 项 Apple 条件跳过，0 失败，137.464 秒）；全量 XXComic Swift 语法前端解析 0 错误；Android 254 个基准文件 SHA-256 严格一致。
  1. 【本机真实 HTTP 测试服务实现与验证】`LocalTestHTTPServer.swift`（基于纯 Swift POSIX TCP socket），提供真实 `127.0.0.1:0` HTTP/1.1 服务，测试 `LocalTestHTTPServerTests`（2/2 通过）。
  2. 【文件下载 Worker 落地与完整验证】`FileDownloadWorker.swift` 支持 Strong ETag、Range/If-Range、200/206/416 状态码处理、失效链接刷新回调、保留旧版本以及真实格式探测（PDF/EPUB/MOBI/CBZ/ZIP），测试 `FileDownloadWorkerTests`（11/11 通过）。
  3. 【图片下载加固与流式体积校验】`DefaultDownloadImageFetcher` 在数据流式读取过程中硬限制 128MiB，拦截 HTML/JSON 误码响应，漫蛙 AES-CBC 解密，魔数解码校验（PNG/JPEG/GIF/WebP），支持中途取消，测试 `DefaultDownloadImageFetcherTests`（9/9 通过）。
  4. 【动态站源配置消费接通】包子（Baozi）、漫画160（Mh160）、G社（Gmh）、漫客栈（Mkzhan）、漫蛙（Manwa）、18漫画（Mh18）全量接入消费导入的 `routes`、`filters`、`baseUrl`、`referer`，测试 `SourcePreferencesTests.testImportedConfigUpdatesSourceEndpointsAndHeaders` 通过。
  5. 【网络状态监听接入下载运行时】`SystemNetworkMonitor` 接入 `AppEnvironment`，通过 `updateNetworkStatus` 动态更新仅 Wi-Fi 模式与断网自动暂停/网络恢复恢复下载。
  6. 【CI 与构建脚本触发条件说明明确】`.github/workflows/ios.yml` 为 `workflow_dispatch` 手动触发（非推送触发）；`build.sh` 仅在环境变量 `$IOS_TEST_DESTINATION` 非空时执行 UI 测试；在真实 Xcode 与物理设备运行前，UIKit、Files、WebKit 严格标记为未经验收。

- 综合对账核实与业务闭环补齐（2026-09-20 晚）：相关新写和修复测试全部通过（ErrorLogStoreTests 5 项、SourcePreferencesTests 4 项、AppUpdateCheckerTests 1 项、LibraryStoreTests 7 项全部通过）；ComicCore 全量 615 项测试全部通过（2 项 Apple 条件跳过，0 失败，126.262 秒）；全量 XXComic 与 XXComicUITests Swift 语法检查 0 错误；Android 254 个基准文件 SHA-256 绝对一致（0 mismatches）。
  1. 【脱敏错误日志全链路接通】`ErrorLogSanitizer` 自动拦截并脱敏 URL query 敏感 key、Bearer 令牌与 Cookie；在 `ErrorLogStore.append` 自动脱敏并截断；在 `ReaderViewController`（章节与目录加载失败）、`DetailViewController`（详情与目录加载失败）、`BatchImportWorker`（批量导入单项失败）、`DownloadRuntime`（下载异常与 HTTP 失败）中全面调用埋点。
  2. 【下载离线损坏检测与修复接通】`DownloadRuntime.localChapter` 校验本地页面真实存在性、大小与 SHA-256 哈希，损坏或不全时抛出明确 `DownloadError.corruptedData("本章下载文件需要修复")`；`ReaderViewController` 不再使用 `try?` 吞掉损坏静默走网络，而是精准捕获离线损坏，展示“本章下载文件需要修复”卡片，提供“到下载中心重新下载本章”入口并记录日志，完成闭环。
  3. 【站源配置导入导出与可用性检测接通】建立 `SourceConfigModels.swift`，完全对齐 Android `xx-comic.sources` v2 schema（schema、version、exportedAt、sourceOrder、sources 等结构与校验）；在 `SourcePreferences` 落地 `exportConfig` 与 `importConfig`；在 `SourceSettingsViewController` 提供“更多”ActionSheet（“测试站源可用性”、“导入站源配置”、“导出站源配置”、“恢复默认排序”）；实现 `healthCheck` 机制（带代次取消、测速延迟显示于副标题）。
  4. 【iOS 版本更新逻辑落地】实现 `AppRelease` 与 `AppUpdateChecker`，从远程元数据获取更新、对齐 Android `versionCode` 比对逻辑；在 `SettingsViewController` 接入真实的更新检查闭环（进度弹窗、新版本提示与更新日志、打开下载/发行页外链、已经是最新版本、检查失败带重试）。
  5. 【历史删除原子清理】`LibraryStore` 删除历史严格清空阅读记录、图片与文字位置，保留收藏状态；断开本地墓碑关联；写入失败内存回滚保护。

- 设置管理与本地运维（阶段 F）：相关 7 项核心测试全部通过（ErrorLogStoreTests 4 项、StorageCalculatorTests 3 项，0 失败，0.135 秒）；全量 610 项核心测试全部通过（2 项 Apple 条件跳过，0 失败，121.09 秒）。完成 `ErrorLogStore`（线程安全、时间戳与标题格式对齐、错误信息与堆栈持久化、100,000 字符边界自动截断、清空与单条/全量获取）；完成 `StorageCalculator`（递归目录体积统计、Darwin 与 Linux 跨平台可用存储空间检测、多级单位 B/KB/MB/GB 格式化）；重构 `SettingsViewController` 为 InsetGrouped 三段式 Section（“阅读与外观”、“站源与本地数据”、“App”）；接入阅读历史入口至 `BookshelfViewController(historyOnly: true)`；完成本地存储管理 `LocalStorageViewController`（仅 Wi-Fi 开关、存储空间统计：导入/下载/缓存/剩余空间、已存漫画勾选列表、清理缓存、删除副本弹窗确认）；完成缓存清理 `CacheCleanupViewController`（将被清理 vs 始终保留分组、重新计算大小、立即清理确认并保留收藏与进度）；完成错误日志 `ErrorLogsViewController` 与详情 `ErrorLogDetailViewController`（列表卡片、蕾姆空状态、等宽代码块展示、长按复制与系统分享导出、清空确认）；完成关于 App `AboutAppViewController`（蕾姆头像、说明文案、版本与本地信息列表）。全量 UIKit 语法检查通过（XXComic 与 UITests 全部 0 错误），Android 254 文件基准绝对一致。真实系统分享与 iOS 设备视觉手势未验收。

- 下载离线与队列协调（阶段 E）：相关 24 项核心测试全部通过（DownloadIdentityTests 3 项、DownloadCoordinatorTests 11 项、DownloadStoreTests 6 项、DownloadRuntimeTests 4 项，0 失败，0.146 秒）；全量 603 项核心测试通过（2 项 Apple 条件跳过，0 失败，128.799 秒）。完成 `DownloadModels`（确定性长度分隔 SHA-256 身份隔离、JM `scramble_id` 保留而剔除临时鉴权 query、纯 Swift FIPS 180-4 SHA-256 引擎）；完成 `DownloadCoordinator`（代次租约与取消防竞态、FIFO 严格保序与去重入队、并发限制最大 2 个活跃 worker、仅 Wi-Fi/移动网络模式判定、指数退避 2s/5s/15s 与同源 429 Retry-After 延迟协调、验证等待隔离）；完成 `DownloadStore`（版本化原子 JSON 快照、16MiB 边界超限保护、更新保留 FIFO rowid 语义、多页面与目录快照持久化与崩溃恢复）；完成 `DownloadRuntime`（多 worker 后台并发调度、断点续传跳过已有校验通过页面、临时 `.part` 文件校验后原子重命名至 `.img`、失败重试与 403 权限暂停、`localChapter` 优先离线阅读路由）；完成 76% 高度下载选择抽屉 `DownloadSelectionViewController`（本章/全选/清空/区间/倒序快捷芯片、已下载状态互斥与置灰、多选批量入队）；完成下载中心 `DownloadCenterViewController`（作品分组卡片、实时进度条、状态提示、全部暂停/继续、单项暂停/恢复/重试/取消、滑动删除、蕾姆横幅与点击已完成直接跳转阅读器）；在 `DetailViewController` 增加“下载章节”与右上角“下载中心”入口；在 `ReaderViewController` 接入 `localChapter` 优先无缝离线阅读；在 `SettingsViewController` 增加“下载中心”行。全量 UIKit 语法检查通过，Android 254 文件基准严格一致。真实网络环境与 iOS 设备手势视觉未验收。

- 批量导入执行、Files 授权与卷管理交互（阶段 D）：相关 6 项核心测试全部通过（BatchImportWorkerTests 6 项，0 失败，0.274 秒）；全量 579 项核心测试通过（2 项 Apple 条件跳过，0 失败，129.563 秒）。完成 `BatchImportWorker` 批量任务执行器（安全作用域授权、Darwin `NSFileCoordinator` 同步读取协调、`.minimalBookmark` 往返生成与解析、多卷候选自动合并为单一系列、支持已有系列追加新卷、单项失败隔离继续后续项、失败项单独重试、任务代次取消与临时 staging 目录即时清理）；完成 72% 高度分卷管理抽屉 `VolumeManagerViewController`（分卷列表、拖动手柄交互排序、落手原子提交、3.5 秒撤销删除条、超时/关闭/二次删除原子提交、追加新分卷）；完成批量导入确认抽屉 `BatchImportConfirmationViewController`（展示建议分组、提供“合并为一部漫画”开关、各组标题重命名）；在 `DetailViewController` 中接入“管理分卷”抽屉、重命名作品、删除 App 副本提示（提示原文件不受影响，若日后重新导入进度自动恢复）；在 `ComicGridViewController` 中放开多选，选定多文件自动唤起批量确认抽屉，并接入本地漫画长按管理菜单（管理分卷、重命名、删除副本）。全量 UIKit 语法检查通过，Android 254 文件基准严格一致。Apple 原生环境与实机视觉手势尚未验收。

- 系列阅读路由与 UI 消费者（阶段 C）：相关 8 项核心测试全部通过（LocalReadingRoutingTests 8 项，0 失败，0.217 秒）；全量 573 项核心测试通过（2 项 Apple 条件跳过，0 失败，126.951 秒）。完成跨卷连续章节列表拼接、稳定章节 ID 与连续 slot 计算；实现 `LocalReadingTarget` 精确映射全局章节索引到物理卷、卷内章节索引与阅读器类型（`.comic` vs `.text`）；支持混合格式系列（ZIP 图片卷 + 文字 EPUB 卷 + PDF 卷）；支持分卷重排后章节位置动态找回；实现 `TextLocator` 系列身份与物理卷本地身份双向转换；完成 `DetailViewController`、`ReaderViewController` 与 `EpubTextReaderViewController` 在跨卷阅读时的双向原地平级切换（不堆叠导航栈，保留详情返回路径）；保留入口意图（章首/章末/续读恢复）；本地书架列表适配系列摘要展示；已删除本地书历史提供明确“重新导入相同内容即可恢复”提示。UIKit 语法检查与 Android 254 文件基准一致。Apple 原生环境与设备未验收。

- 本地合集、身份、去重与删除恢复（阶段 B）：相关 18 项核心测试全部通过（LocalCatalogTests 9 项、LocalSeriesLifecycleTests 9 项，0 失败，0.247 秒）；全量 565 项核心测试通过（2 项 Apple 条件跳过，0 失败，127.221 秒）。完成原子版本化 JSON 快照（16MiB 边界、写失败回滚、损坏/非法版本保护）、单实例 actor 串行写入；物理卷与系列身份解耦，旧单卷隐式系列兼容；发布前同指纹去重（普通导入返回已存在系列，显式追加冲突抛出 `alreadyImported`）；墓碑机制完整记录系列 ID、卷 ID、用户标题，重新导入同一内容时恢复原有身份与标题；安全卷删除（末卷整删/首卷删除保留系列）、全排列严格重排、Android trim 重命名，启动孤儿回收（未提交卷与遗留暂存安全回收）。UIKit 语法检查与 Android 254 文件基准一致。Apple 原生环境与设备未验收。

- 真实导入指纹与格式元数据（Task 45）：相关 109 项测试全部通过（1 项 Apple 条件跳过，0 失败，68.482 秒）。完成图片、文件夹、ZIP、CBZ、EPUB、PDF、Kindle 拥有的副本指纹与格式计算及元数据校验；文件夹保留剥离前的原相对路径映射，改变原路径导致指纹变化；ZIP/CBZ 先复制为暂存 `source.archive`，再从中解析解压并保留原包（双份实际占用）；EPUB/PDF/Kindle 对各自拥有的原包进行散列；Node crypto 独立固定测试预期替换自证哈希；重开验证声明的拥有包及 64 位小写哈希；旧无字段 JSON 保持兼容；暂存取消与符号链接校验修复。全量 UIKit 语法检查与 Android 254 文件基准一致。Apple 原生环境、真实 Files 授权与设备未验收。

- 本地准备/发布分离（ba575ef、6335cfc）独立审查及修复复审通过：图片、文件夹、ZIP、EPUB、PDF、Kindle共用暂存生命周期；误删未知文件/空目录及同名替换回归先3项13失败后通过。相关87项检查发现EPUB探测文件复用回归后修复，最终重跑51项、1项Apple跳过、0失败（2026-09-20 09:21:30 UTC，49.179秒）；其余36项此前通过，未重复。未知项冲突时保留暂存内容并报错，不声称已清理。Android254文件基准一致。Apple目录发布/APFS/真实PDF未运行；尚未接批量UI、去重和合集。

- 流式内容指纹（11a684f）独立审查通过：12/12（2026-09-20 08:25:28 UTC，1.735秒）；行为RED为42断言失败。独立Node SHA-256向量、真实文件路径/符号链接/读错误/中途取消/截断增长测试通过；256KiB分块、原相对路径清单。仅Linux OpenSSL验证，Apple CryptoKit未运行；去重、墓碑和导入发布尚待整合。

- 批次持久化状态（38133cb）独立审查通过：14/14（2026-09-20 08:12:49 UTC，0.831秒），主要行为RED为12项23失败。真实文件覆盖重开、取消/重试、旧任务ID隔离、精确16MiB上限和系统原子写失败回滚；URI仅保存为元数据，尚未接实际worker/系统书签/UI，Apple未验收。

- 批量分组与卷序规划（015ae3d）独立审查通过：19项行为测试先出现79个预期断言失败，最终19/19通过（2026-09-20 07:49:16 UTC，0.315秒）；复用自然排序/搜索trim的11项测试通过。覆盖精确十进制、稳定卷序、Java Unicode身份与组内去重；Java原方法独立oracle核对。此项不包含实际批量导入、确认UI或Apple验收。

| 检查 | 结果 | 能证明的范围 |
| --- | --- | --- |
| Docker Swift 5.10 `swift test`（拷贝修复、响应头及ZIP导入后） | 238 项通过，0 失败；拷贝专项24/24、本地图片/文件夹13/13、ZIP/CBZ16/16 | 14站适配器fixture、POST取消与字符集、收藏历史、阅读会话、习惯状态机、点击区域、白边、自然排序、本地图片/文件夹/ZIP导入、站源开关排序及基础规则；不代表真实站点和设备验收 |
| Docker Swift 5.10 `swift test`（18漫画适配器与纯验证规则后） | 271/271通过；18漫画定向31/31；后续浏览器地址限制修复定向3/3 | 包含252章、浏览器协议分流、验证判定与取消；不代表WKWebView会话已交付或真实站点验证成功 |
| Docker Swift 5.10 `swift test -j 2`（阅读错误状态、JM图片分片后） | 284/284通过，0失败，20.740秒 | 新增阅读请求错误顺序3项、验证attempt3项、JM公式/行范围6项；Apple条件测试未执行，浏览器审查修复仍在进行 |
| Docker Swift 5.10 `swift test -j 2`（18漫画浏览器修复后） | 287/287通过，0失败，20.887秒，2026-09-20 02:31:18 UTC | 新增Cookie交错更新/删除屏障2项和终态迟到导航1项；生产WK规则Apple编译测试被条件排除，未执行 |
| Docker Swift 5.10 `swift test -j 2`（漫画柜初版后） | 306/306通过，0失败，42.472秒，2026-09-20 02:57 UTC | 漫画柜初版19项含完整LZ29图、拷贝既有24项通过；后续三项审查修复的证据见下一行，不把本次全量冒充后续改动回归 |
| 漫画柜修复定向 `ManhuaguiTests\|CopyMangaTests/testLiteral` | 25/25通过，0失败，28.226秒，2026-09-20 03:11:14 UTC；三项复审均ADDRESSED | 漫画柜23项与Copy strict字面量2项；前置JS字符串不污染配置定位，扫描有预算且取消用例0.101秒，清理后空标题正确回退；未重复不相关全量 |
| 四站分类互斥 `SourceFilterSelectionTests` | 4/4通过，0失败，2026-09-20 03:21:41 UTC；独立审查通过 | 真实RED四站各一断言失败；生产UIKit action已接线，原生高亮/确认/关闭未验收，未重跑全量 |
| 七源搜索trim兼容 `SourceSearchTrimTests` | 9/9通过（03:41:01 UTC），既有七源99/99通过（03:41:36 UTC）；独立审查通过 | 七处复用Java trim语义，特殊空格保留；真实RED9断言失败；固定请求fixture，不代表真实网络或iOS验收 |
| AES及漫蛙图片解码审查 | 两项范围审查均通过；AES固定向量4/4 | Linux OpenSSL路径；CommonCrypto仍未由Xcode编译或运行 |
| 自动主题边界测试 | 1 项通过 | 08:00/18:00 边界、手动昼夜模式 |
| `swiftc -frontend -parse XXComic/*.swift XXComicUITests/*.swift` | 通过 | Swift 语法，不包含 UIKit 类型检查和链接 |
| `bash -n ios/scripts/build.sh` | 通过 | shell 语法，不代表 Xcode 构建运行成功 |
| `node ios/scripts/android-baseline.mjs --check` | 254 个文件一致 | Android 基准与独立工作区一致 |
| Gmh 独立审查 | 3 项重要问题修复后复审通过 | 取消传播、错误结构、筛选去重 |
| 在线 UI 独立审查 | 首轮 5 项及新增恢复搜索问题修复通过 | 点击坐标、切章数组一致性、主题恢复、长图采样、隐藏页面请求取消 |
| 在线 UI 范围复审 | 搜索恢复和分类抽屉通过 | UIKit静态检查，不代表设备结果 |
| 本地导入独立复审 | 大图导入限制和重复导航两项修复通过 | 大图拒绝测试先出现断言失败再通过，本地专项4/4 |

首次测试在核心 target 为空时失败，属于缺失实现导致的构建失败，不将其称为所有行为测试都完成了断言级 red-green。后续翻页数值映射、旧按钮模式回退测试均实际出现断言失败，修复后通过。

## 尚未执行与平台限制

- 真实 macOS / Xcode 编译（XcodeGen 工程生成、Xcode 模拟器与 iPhone 真机架构编译、UIKit/CoreGraphics/WebKit 类型检查与链接）。
- iOS 模拟器/真机原生 UI 测试运行：`build.sh` 中明确要求在环境变量 `$IOS_TEST_DESTINATION` 非空（如指定设备 UDID）时才执行 UI 测试；在非 macOS 或未设目标的环境下将自动跳过 UI 测试。
- GitHub Actions workflow 限制：`.github/workflows/ios.yml` 设定为 `workflow_dispatch`（纯手动触发），不存在 push 自动触发构建；在没有配置 GitHub 仓库与手动运行前，无云端构建制品。
- UIKit、Files 安全作用域授权、WebKit 会话在真机上的手势、视觉与网络验收；在获得 Xcode 构建与设备运行证据前，严格不标记为已验证。
- `LocalImageProbeTests` 两项 Apple 专用测试（真实图片/截断图片、符号链接、大小和取消；Linux 缺少 ImageIO，未执行）。
- ZIP/CBZ 的 Apple 真实图片探测测试、ComicZlib 系统库在 Apple SDK 的编译链接、ZIP/CBZ 文件选择器实机操作。
- IPA 签名、用户 iPhone 安装、视觉/手势/性能验收。

## 阶段验证记录

以下按各阶段当时的实现范围记录，旧条目的“尚未接入”不覆盖后续成果；当前功能状态以 `PARITY.md` 为准。

- 批量预览的电子书元数据扫描（df616eb）独立审查通过：真实ZIP/PDB初始16项96失败后实现；Unicode ID与CRLF属性分词分别新增RED后修复，最终18/18（2026-09-20 07:34:25 UTC），0失败。只读取container/OPF各≤1MiB，未读取正文/封面/nav/encryption；通过故意损坏非元数据CRC的fixture验证边界。未改共用parser/detector；这不是正文/DRM或批量UI验收，Apple尚未运行。

- Kindle导入与恢复（fb3aead、6942eb1）独立复审通过：原包/派生同staging发布，接入文件选择、封面与原阅读器，缺失派生可重建且历史/章ID不变。相关122项中121通过、1项Apple PDF跳过、0失败。复审发现最后目录校验与发布间的替换窗口，真实生产路径RED4断言后以目录fd相对发布修复；最终定向15/15（2026-09-20 07:19:38 UTC），0失败。UIKit语法检查通过；4项新增Kindle UI加既有9项共13项原生场景未运行，Darwin/APFS、Files授权及Apple编译/设备验收仍开放。

- Kindle真实EPUB转换（e0e77f6）独立审查通过：检测21项+转换24项共45/45，2026-09-20 06:46:51 UTC，0失败、无警告。真实PDB→ZIP→EPUB解析覆盖章节、图片/封面、跨记录解压、取消回收及既有目标保护；UTF16代理对与完整XHTML容量回归先失败后通过。单篇完整XHTML限8MiB，HTML扫描共享2秒预算，超限明确失败。此阶段尚无Kindle导入入口；Apple编译、ImageIO、WK显示和设备性能未验收。

- Kindle检测/PalmDOC核心（92a5830）独立审查通过：真实二进制检测和解压初始18项117失败→GREEN，自查Java标题码元比较新增回归1失败后修正；最终Kindle21+SearchRules8共29/29（2026-09-20 06:17:38 UTC），0失败。覆盖容器/DRM/record边界、标题/EXTH、输出限制和运行中取消。这一阶段没有转换、导入或用户入口，Apple未验收。

- PDF（6275fa4）实现与独立审查通过：原包副本、50000页导入/重开、安全逻辑页URL、取消清理及原生渲染/阅读器入口。相关65项中64通过、1项Apple条件跳过；空端口攻击实际RED1失败后修复，最终定向11项中10通过、1跳过、0失败。全UIKit语法检查与Android254文件基准检查通过。Apple真实PDF两项条件测试未运行，CoreGraphics/ImageIO类型检查、像素、Files权限和设备性能尚未验收；Linux注入尺寸测试只证明存储边界。

- 完整EPUB阅读与导入接线（47f9247、efc50ac、68eb46d）两轮修复后独立复审通过。Core真实导航RED3项8失败→GREEN，相关47/47（2026-09-20 05:17 UTC）。复审修复无ID正文误存应用锚点、fragment编码与空锚点回归；生产JS在真实Edge DOM验证最终6/6，Foundation fragment4/4，均保留失败→成功证据。全UIKit语法检查通过，9条原生UI场景未运行；Edge不是WK验收。EPUB导入按钮及文字/混合/图片路由现已接入代码，Xcode类型检查、WebKit规则/脚本/资源隔离、实际Files授权及设备性能仍待验收。

- EPUB图片接线和正文资源地址（0b9a69d）独立审查通过：资源真实RED7项71失败，相关GREEN49/49（资源7＋解析26＋本地导入16）；空端口追加RED1后修复，最终资源8/8。路径单次解码、跨书/authority校验、图片后台读取/取消及Cell重试复用均已实现。UIKit全文件仅语法检查通过，真实ImageIO/复用/晚回调和Apple类型检查未验收；尚未开放EPUB导入入口。

- 文字设置与位置记录（05e5541）独立审查通过：真实RED9项64失败，GREEN21/21（文字9、书架5、阅读设置4、站源设置3，2026-09-20 04:43 UTC）。默认18/1.75/深色/连续，旧JSON兼容、漫画与文字位置隔离、收藏保留、原子写失败不改内存均覆盖。尚未接文字UI；父代理全UIKit语法、构建脚本语法及Android254文件基准检查通过，不代表Apple类型检查。

- EPUB持久化与按需资源（482ef92、2f10f46）独立复审通过：初版相关69/69（新导入14+解析26+旧本地/文件夹/ZIP29）；复审发现manifest导入/重开上限不一致，真实RED2项3失败后修复并运行导入16/16。50000项可重开、50001项发布前拒绝；原包保留、staging清理、混合旧书架、大文件复制/验证和安全页URL均覆盖。仅完成Core，原生文件授权/ImageIO与EPUB用户入口尚未验收。

- EPUB解析核心（46a6f2a、8b198c4）独立复审通过：EPUB26/26（2026-09-20 04:12 UTC），原ZIP回归16/16（04:00 UTC，ZIP代码未变）。覆盖spine/目录/封面/DRM、XML/路径/CRC/读取预算；异常wrapper匹配的运行中取消与耗时预算先RED2项4断言再GREEN。500ms为单调时钟回调检查预算，低性能设备可能拒绝异常文件，Apple回调频率未验收。FoundationXML已条件导入；目前只是核心，不是EPUB可导入/阅读交付。

- 已实现并测试：Gmh站源、取消与错误传播、收藏/历史/章节位置原子存储、阅读会话、白边检测、定时主题核心规则及原有搜索/设置规则。
- 已编写但未经过 iOS 类型检查和编译：真实书架/发现/详情/按需目录/阅读器、独立主题、图像缩放与显示处理、原版角色素材、分类右侧抽屉、目录55%/92%底部抽屉。
- 包子、漫画160、漫客栈、漫画栈、比卡、HiperDEX、悦看、tapmanga、漫本、G社、催漫画、六漫画、拷贝漫画、漫蛙、18漫画和漫画柜已通过静态独立复审并接入；其余2个默认站源、其他验证码会话、电子书/PDF、下载和恢复、完整视觉和设备手势验收仍未完成。
- 漫画柜以固定Android工具中完整LZ字典/29图及目录样本核对；保留Copy默认strict数据解析。三项审查发现（前置脚本干扰、未受限候选扫描、清理前标题回退）修复后复审通过。按Android相对顺序注册在HiperDEX之后，实际站点/Apple网络未验收。
- 18漫画适配器、纯验证规则、WK会话和发现/分类/详情/目录/阅读验证入口已通过独立复审，按安卓版相对顺序在G社之后注册。规则正则分支/路径大小写、成功后迟到导航、Cookie旧快照提前释放四项问题修复后均复审通过。不能把静态审查和核心测试当作验证码可用或iOS编译成功。
- 验证错误消费者已完成复审：目录验证失败不会被后到的章节成功吞掉；章节失败仍优先。会话主动取消但页面Task未取消时退出加载并保留重试，不弹失败。重置结束会话和在途请求、保留站点Cookie；真实WebKit和Cookie行为仍待设备验收。
- JM正文图片还原核心和显示接线已通过复审，Apple MD5Digest的成员类型问题已修正；条件色条像素测试、CryptoKit/CoreGraphics编译、实际峰值内存未验收。此结果不代表JM站源或浏览器已可用。
- 阅读习惯生命周期修复、换源筛选抽屉、站源配置变化后的全站选择保持均已通过静态复审。文件夹导入的复制进行中取消和章节manifest分区完整性修复已通过测试和范围复审。
- 本地图片导入和共用阅读器已接线；128MiB单图限制按安卓对齐，在发布前、复制中和阅读时执行，新增边界测试先失败再通过。目录原子发布、失败不改原文件。本地其他格式尚未接入。
- 本地条目预算包含目录：真实50000项允许、50001项拒绝，RED1项3断言失败后本地13/13通过；独立审查通过。单图与文件夹共用ImageIO真解码探测，原生验证仍待Mac。
- ZIP/CBZ核心与界面入口已通过独立审查。ZIPFoundation固定0.9.20并打包MIT许可；针对已复现的Linux压缩长度跨读问题，deflate使用系统zlib薄封装，校验真实输入长度、流尾、CRC和输出预算。支持中文编码、常见ZIP64/data descriptor、自然分章、坏首图跳过、取消/失败回收，原包只读；扩展ZIP格式尚未验收，不支持RAR/7z。首次全量暴露的Linux系统错误桥接差异已修复后重新全量通过。
- 目录关闭后允许请求完成并缓存；离开详情页面才取消，按 Android 业务约定处理。
- 图像去白边作用于显示副本，不改原文件；原始位图保留，开关不会重新发网络请求。长条正文以24M解码像素预算限制内存，实际性能仍待设备测试。

新站源测试先行阶段会暂时出现缺少适配器的编译失败；记录只代表所述代码状态，后续实现变化须重新验证。详细未完成范围见 `PARITY.md`。

当前不能称为 1:1 复刻完成，也没有可供用户安装的已验证 IPA。
