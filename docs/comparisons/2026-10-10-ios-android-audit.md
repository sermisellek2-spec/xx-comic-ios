# iOS 与 Android 当前代码整体对比

核对日期：2026-10-10。结论基于当前工作区实际源码、固定基线哈希、已有验证记录和本次重新执行的 Swift 核心测试。

**整体判断：iOS 已具备相当完整的核心业务实现，但尚未与当前 Android 2.0.40 对齐。主要差距来自移植基线停在 2.0.29、应用层接线不完整、原生界面重建与后续 Android 功能未同步。不能将“核心模块已有代码”直接等同于“用户已经能从界面完整使用”。**

**1. 对比对象和证据边界**

| 项目 | Android | iOS |
| --- | --- | --- |
| 工作区 | `F:/softForCode/codex-project/xx-comic` | `F:/softForCode/codex-project/xx-comic/.worktrees/ios-port` |
| 分支 / HEAD | `master` / `0a90d299` | `codex/ios-port` / `409601a1` |
| 工程版本 | `2.0.40` / versionCode `340` | `0.1.0` / build `1` |
| 行为基线 | 当前源码 | `ios/android-baseline.json` 仍记录 Android `2.0.29`，commit `e800a06e` |
| 技术实现 | Java + Android View，部分 C++/JNI | Swift + UIKit，独立 ComicCore Swift Package |
| 系统目标 | minSdk 23，compile/targetSdk 34 | iOS 16，iPhone + iPad |

固定基线的 254 个文件中，当前 Android 有 **157 个文件内容变化、2 个路径已不存在**。这是基线漂移证据，不是功能缺失数量，也不能用于推算完成百分比。详情见[基线漂移清单](F:/softForCode/codex-project/xx-comic/docs/comparisons/2026-10-10-baseline-drift.json)。

本次做了源码和调用链对照；检查了 Android 已有界面截图；校验了双方共用 PNG；重新运行了 ComicCore 全量测试。没有在当前 Windows 环境运行 iOS UIKit、iPad 或两端同场景截图，因此下面的视觉结论以布局、颜色、素材和组件代码为依据，不能当作像素差分结果。站源数量是代码目录数量，未测当前网站在线率。

工程参数证据：[Android 构建配置](F:/softForCode/codex-project/xx-comic/app/build.gradle:1)、[iOS 工程配置](F:/softForCode/codex-project/xx-comic/.worktrees/ios-port/ios/project.yml:1)、[iOS 固定基线](F:/softForCode/codex-project/xx-comic/.worktrees/ios-port/ios/android-baseline.json:1)。

**2. 纯视觉与页面构成**

| 维度 | Android 当前实现 | iOS 当前实现 | 对比结论 |
| --- | --- | --- | --- |
| 主导航 | 自绘页面标题和底部导航，项目自己的矢量图标与动效 | UITabBarController + UINavigationController，SF Symbols：`books.vertical` / `safari` / `gearshape` | 页面职责相同；标题、图标、系统栏、选中反馈和转场明显不同 |
| 基础配色 | 完整 BG、SURFACE、CARD、TEXT1–4、BORDER、ACCENT、GREEN、状态色等 token | Palette 只有 background/card/text/secondaryText/accent/border 六组主色 | 主蓝色、背景、卡片和主文字颜色基本同源；次级层次、状态色覆盖不足 |
| 边框颜色 | 日间 `#CFE5F3`，夜间 `#2F465B` | 日间 `#DDE6EE`，夜间 `#27394D` | 可明确定位的色值差异 |
| 字体与字号 | UIHelpers 的字号最低 12sp，Android Typeface 与统一触控封装 | 部分使用 Dynamic Type，部分固定 UIKit 字号；封面标题 13pt medium | 字体度量、行高、字重和放大行为不同；不能只比较数值是否相等 |
| 封面网格 | CoverLayoutHelper 按内容宽度动态算列数；封面 3:4 | 所有 ComicGrid 固定三列，宽度 `(bounds.width - 48) / 3`；封面同为 3:4 | 手机上结构接近；iPad 和横屏仍固定三列，封面密度明显不同 |
| 书架 | 分组胶囊栏、分组抽屉、网格/列表切换、徽标、本地悬浮导入按钮 | “我的书架/本地书架”系统分段控件、三列网格、顶部“导入/历史”文本按钮 | 书架视觉与信息密度差异大 |
| 发现页 | 自定义大标题、搜索框、模式按钮、站源分组、筛选与结果头部 | UISearchBar + UISegmentedControl + 普通按钮 + 横向源标签 | 业务入口近似，控件形态、间距、层次和布局并未复刻 |
| 详情页 | 自适应 hero 封面、项目风格操作区及错误/续读提示 | 垂直 UIStackView，封面固定 280pt，描述与一组文本按钮 | 内容排列和封面尺度明显不同，缺少当前 Android 的完整详情表现 |
| 目录 | 自绘 ChapterDrawerSheet、快速滚动和目录导航 | UITableView 的章节列表，55% / 92% 系统 sheet，勾选当前章 | 抽屉高度意图接近；行样式、快速操作和导航能力不同 |
| 阅读控制条 | 矢量按钮、漫画进度预览、换源、状态信息和增强控制 | 四个文本按钮“上一页/章、目录、设置、下一页/章”，页码和时间徽标 | 控件体系与信息量差异大 |
| 设置 | 自定义分区卡片、图标、标签、开关/抽屉 | UITableView insetGrouped，系统 UISwitch / UISegmentedControl | 设置项有大量对应关系，视觉表现仍偏系统原生 |
| 错误与空状态 | 项目统一错误恢复、对话框、提示和素材组合 | 部分共用蕾姆图，部分底部状态按钮或系统 UIAlertController | 同一素材不意味着同一错误/加载布局 |
| 应用图标 | 已有 mipmap 密度图、前景图和启动图标配置 | 当前 iOS 源目录及 project.yml 未见 AppIcon 资产目录或对应配置 | 当前 Android 启动图标尚未在 iOS 工程中对应落实 |

**共用素材已确认一致：**`rem_empty`、`rem_error`、`rem_in_bookshelf`、`rem_loading`、`rem_no_image`、`rem_not_in_bookshelf`、`rem_reader_boundary`、`rem_reader_resume` 共 8 张 PNG，SHA-256 完全相同。它们是最明确的视觉一致部分。

证据：[Android 主题 token](F:/softForCode/codex-project/xx-comic/app/src/main/java/com/xxcomic/UIHelpers.java:109)、[iOS Palette](F:/softForCode/codex-project/xx-comic/.worktrees/ios-port/ios/XXComic/Palette.swift:1)、[iOS 导航](F:/softForCode/codex-project/xx-comic/.worktrees/ios-port/ios/XXComic/AppDelegate.swift:25)、[Android 封面适配](F:/softForCode/codex-project/xx-comic/app/src/main/java/com/xxcomic/CoverLayoutHelper.java:1)、[iOS 三列网格](F:/softForCode/codex-project/xx-comic/.worktrees/ios-port/ios/XXComic/ComicGridViewController.swift:81)、[iOS 详情布局](F:/softForCode/codex-project/xx-comic/.worktrees/ios-port/ios/XXComic/DetailViewController.swift:36)。

**3. 交互与功能矩阵**

“已实现”指找到真实代码和应用调用；“核心已有、界面未接通”表示不能视为用户流程已经完成。未运行的设备交互均保留验收边界。

| 能力 | iOS 当前情况 | 与当前 Android 的差异 |
| --- | --- | --- |
| 三大页面、书架默认入口 | 已接通 | 主导航样式不同 |
| 收藏、取消收藏、继续阅读、历史 | 已接通，位置和收藏分开保存，有移出收藏撤销 | 当前 Android 的书架管理、批量/分组动作和视觉尚未对应 |
| 启动书架习惯与手动固定 | 已有 ReadingHabitTracker，并接到设置与阅读器 | iOS 生命周期和弹层计时仍需设备核验 |
| 书架分组、分组管理 | 未见对应实现 | Android 有在线/本地分组数据与胶囊栏、抽屉 |
| 网格/列表布局切换 | 未见对应实现 | iOS 只提供固定三列网格 |
| 收藏更新检查与更新徽标 | 未见 Android FavoriteUpdateCoordinator 的对应流程 | iOS LibraryStore 的 updatedAt 是阅读更新时间，不能当作追更检查 |
| 本地悬浮导入按钮 | 未实现对应组件 | iOS 使用顶部“导入”按钮 |
| 单站搜索与分页 | 已接通，按 comicId 去重 | iOS 翻页后 reloadData；Android 已有追加结果和滚动锚点优化，行为需同场景核验 |
| 全站搜索 | 已接通，每源第一页、严格 trim 同名优先、红点、结果代次隔离 | 核心规则接近；并发组织与视觉不同 |
| 发现页站源分组 | 未见对应管理层 | Android 有 SourceGroupStore 和发现分组入口 |
| 分类筛选 | 已有右侧抽屉、草稿与确认/取消机制 | UIKit 抽屉宽度最多 320pt；与 Android 自定义筛选层仍需视觉对照 |
| 详情和按需目录 | 已接通；目录按钮触发请求，续读可从已保存章节开始 | 当前详情布局和最新恢复交互尚未完整对齐 |
| 当前章定位与正/倒序 | 已接通 | iOS 目录未见 Android 的快速滚动和完整目录导航控件 |
| 详情/阅读换源 | 未见对应用户入口 | Android 有 DetailSourceSearch、SourceSwitchSheet、章节匹配和最新章节信息 |
| 条漫/单页、跨章、左右手 | 已接通 | 当前 Android 使用卷轴/普通/漫画阅读模式卡片；iOS 分为布局、翻页方式和左手开关 |
| 卷轴防误翻 | 未对齐当前 Android | iOS 条漫仍允许侧边点按或横滑触发换章，见后文问题清单 |
| 双指/双击缩放 | 已接通 | 真实手势竞争、旋转和超长图仍需 iPad 验收 |
| 图内位置与横竖屏恢复 | 已有 ReaderPosition、恢复逻辑与旋转回调 | 核心测试不能证明 UIKit 实际视觉位置完全一致 |
| 漫画进度拖动预览 | 未见对应组件 | Android 有 ReaderSeekBar / ReaderSeekSession；iOS 漫画阅读器只有页码徽标。文字阅读器另有 UISlider，不能混为一项 |
| 时间/电量信息 | 漫画徽标包含页码和时间 | 未见电量接线；时间更新方式也不是 Android 的状态条体系 |
| 阅读主题、墨水屏、禁止动画、去白边 | 已实现并接通 | 平台图像处理和刷新路径不同；大图裁剪会建立完整 RGBA 缓冲，峰值内存需实测 |
| 本地增强、AI 2x 超分、原图对照 | 未见对应实现 | Android 已有 ReaderEnhancementEngine / ImageEnhancer / ncnn Vulkan GPU 超分与对照设置 |
| 图片、文件夹、ZIP/CBZ 导入 | 已有真实导入与界面入口 | iOS 以 App 拥有副本为主，未复刻 Android SAF 零复制直接索引 |
| EPUB、PDF、MOBI/AZW | 已有真实解析、导入与阅读路由 | README 仍写未完成，已经落后于实际源码；两端都不等于支持所有 Kindle 格式 |
| Kindle 边界 | 与 Android 同样拒绝 DRM、KFX、Topaz、纯 KF8/AZW3、HUFF/CDIC 等不支持情况 | 不应把选择器里能选 AZW3 理解为正文已经支持 |
| 本地合集、分卷、重排、删除撤销 | 已有 LocalCatalog 与 VolumeManager，混合格式可切换阅读器 | 核心范围较完整，但文件授权、竞态、混合卷和视觉仍需实机 |
| 批量导入 | 分组确认与执行已接通 | resumeSession/retryFailed 核心 API 存在，未找到 UIKit 调用，重启恢复和失败重试闭环未完成 |
| 文件夹持续同步 | 未见对应实现 | Android 已有 LocalFolderMonitor / LocalFolderSync 自动同步、授权恢复与目录协调 |
| 漫画图片下载 | 队列、暂停、重试、Wi-Fi 限制、损坏恢复已有接线 | 下载完成与本地书架汇总尚未接通，后台能力也不同 |
| EPUB/ZIP 等文件下载 | FileDownloadWorker 核心已有实现和测试 | 当前 App 未提供对应文件站源、fileSourceResolver 或 enqueueFiles 用户入口，不算端到端完成 |
| 本地存储与缓存清理 | 已有存储统计、勾选删除、缓存清理 | iOS Downloads/Local 在沙盒内；Android 有自定义下载位置与可读目录名 |
| 错误日志 | 已有持久化、脱敏、查看/清理/分享 | 系统分享和错误界面与 Android 不同，iPad 分享呈现还需检查 |
| 可选使用统计 | iOS 未见统计上传模块或开关 | Android 默认启用 UsageStatsClient，并有设置开关；这是产品政策差异，是否移植需要单独决定 |
| 检查更新 | 已有 iOS 元数据地址和外链按钮 | Android 可下载 APK 并调用安装；iOS 当前跳转外部更新地址，不能复刻 APK 自安装 |

阅读和书架证据：[iOS 阅读器](F:/softForCode/codex-project/xx-comic/.worktrees/ios-port/ios/XXComic/ReaderViewController.swift:62)、[iOS 阅读规则](F:/softForCode/codex-project/xx-comic/.worktrees/ios-port/ios/ComicCore/Sources/ComicCore/ReadingRules.swift:44)、[Android 主流程](F:/softForCode/codex-project/xx-comic/app/src/main/java/com/xxcomic/MainActivity.java:1232)、[Android 阅读设置](F:/softForCode/codex-project/xx-comic/app/src/main/java/com/xxcomic/reader/ReaderSettingsSheet.java:1)、[Android 图像增强](F:/softForCode/codex-project/xx-comic/app/src/main/java/com/xxcomic/reader/ReaderEnhancementEngine.java:1)。

**4. 站源、解析与配置**

| 统计口径 | Android | iOS |
| --- | --- | --- |
| 专用适配器站点 | 当前启用目录支持 22 个 | AppEnvironment 创建 16 个站点实例 |
| 公共配置驱动站点 | public-sources.json 有 29 个 available=true 配置 | 没有对应公共配置注册器 |
| 可选目录总数 | 51；其中毒牙漫画默认关闭，不能说默认 51 个都开启 | 16 个创建实例，默认启用流程实际只能匹配 14 个 |
| 已退役包子 | 用 RetiredBaoziComicSource 保留旧记录，不进入新搜索目录 | 仍默认创建 BaoziComicSource，默认域名为 cn.dzmanga.com |
| 网站真实可用性 | 本次未探测 | 本次未探测 |

**当前共同存在的 15 个站点适配器：**漫画160、G社漫画、18漫画、漫客栈、HiperDEX、漫画柜、悦看漫画、漫本、漫画栈、比卡漫画、tapmanga 搬运、催漫画、六漫画、拷贝漫画、漫蛙。iOS 中漫画栈和拷贝漫画因为 ID 接线问题，不能进入正常启用列表；所以“共同有适配器”和“当前默认流程能选择”是不同口径。

**Android 专用站源中 iOS 尚缺的 7 个：**禁漫天堂/JM、Hanman18、顶漫画、动漫啦、新漫画-A、再漫画、瓜子漫画。iOS 有 JM 图片分片还原工具和测试，但没有 JM 站源及会话接线，不能算 JM 已接入。

**Android 公共配置驱动的 29 个站源全部未对应移植：**动漫屋、极速漫画、漫画人、咚漫、漫画狗、思思漫画、漫小肆、乐乐韩漫、图库漫画、异次元漫画、喵趣漫画、艾米漫画、毒牙漫画、羞羞漫画、歪歪漫画、250漫画、土豪漫画、漫士多、读漫屋、次元漫、W漫画、阿吧漫画、51漫画、D漫画、360漫画、喜漫漫画、天天看漫画、来漫画、L漫画。该目录里本身包含搜索限制、免费章节限制和网络提示；新增时需要连这些能力边界一起同步。

配置和验证进一步差异：

- 两端都使用 `xx-comic.sources` v2 导入/导出结构。但 iOS 只接受 defaultIDs 中认识的 ID；不识别的站源会跳过，`custom` 也没有接入执行层，所以不能认为 Android 导出的配置可以完整互通。
- iOS 的包子、漫画160、G社、18漫画、漫客栈、漫蛙 6 个适配器从 SourcePreferences 消费动态配置；其他适配器在 AppEnvironment 中直接默认构造，导入 baseUrl/routes/filters 不会自动改变这些实际请求。
- iOS 的导入是系统 alert 的单行文本框粘贴 JSON，导出复制剪贴板并系统分享；大量配置的编辑、文件导入和长文本展示体验与 Android 不同。
- iOS 已有 18漫画 WKWebView 验证、Cookie 同步、手动验证和重置入口；Android 同时有 JM 等受保护站源的专用会话。CommonCrypto、CoreGraphics 与 WebKit 原生分支仍需 Apple 平台验证。
- 即便源名和 URL 相同，Java/Jsoup 与 Swift 解析器是独立实现。Android 基线之后的修复没有自动同步到 Swift，不能以名称相同断言解析完全一致。
- Android 网络安全配置包含多个精确 HTTP 图片/页面例外与 bzcdn 信任配置；iOS Info.plist 当前仅列 auto.mangafiles.com 的 HTTP 例外。后续补站源时需要逐域重新评估，不能只搬解析器。

站源证据：[Android 站源目录](F:/softForCode/codex-project/xx-comic/app/src/main/java/com/xxcomic/MainActivity.java:5442)、[公共站源注册器](F:/softForCode/codex-project/xx-comic/app/src/main/java/com/xxcomic/source/PublicSourceRegistry.java:1)、[29 源配置](F:/softForCode/codex-project/xx-comic/app/src/main/resources/public-sources.json)、[iOS 注册和启用流程](F:/softForCode/codex-project/xx-comic/.worktrees/ios-port/ios/XXComic/AppEnvironment.swift:20)、[iOS 配置导入](F:/softForCode/codex-project/xx-comic/.worktrees/ios-port/ios/ComicCore/Sources/ComicCore/SourcePreferences.swift:103)。

**5. 组件与工程情况**

| 子系统 | Android | iOS | 含义 |
| --- | --- | --- | --- |
| 页面组织 | MainActivity 承担大量主流程，UIHelpers + 多个专用 View/Sheet | 多个独立 UIViewController，AppEnvironment 统一依赖，ComicCore 放核心逻辑 | iOS 分层更明确，但分层模块存在不代表页面已接通 |
| UI 依赖 | RecyclerView、ViewPager2、Shimmer、自定义矢量和绘制 | UIKit Collection/Table/Stack、SF Symbols、系统 Sheet/Alert | 相同页面名称下的实际组件组合不同 |
| 网络/HTML | HttpURLConnection、Jsoup、专用 WebView 会话 | URLSession、Swift 解析函数、WKWebView | 错误、超时、Cookie、重定向和取消语义需分别验证 |
| 图片显示/处理 | Bitmap、自定义 drawable、白边检测、Java 增强、JNI/ncnn Vulkan | UIImage/ImageIO、CoreGraphics/CoreImage、白边检测 | iOS 当前没有 Android GPU 超分模块；Apple 图像分支无法由 Linux 证明 |
| 文字电子书 | Android WebView / 本地 Publication | WKWebView + 自定义资源 scheme + EpubTextSession | iOS 有外链确认、网络隔离与脚本限制；历史 UI 验证发现过系统 alert 委托异常 |
| PDF | Android 原生 PDF 渲染 | Apple CoreGraphics/PDF 相关原生分支 | 平台分支测试必须分别运行 |
| 数据持久化 | SharedPreferences、业务 JSON / 映射文件等 | UserDefaults、LibraryStore、LocalCatalogStore、DownloadStore 原子 JSON | 没有完整跨端收藏/历史/书库迁移入口；站源配置互通不是用户数据同步 |
| 外部文件访问 | SAF 授权与直接索引、下载位置映射、目录监控 | UIDocumentPicker、安全作用域、书签/NSFileCoordinator、拥有副本 | 文件夹零复制和持续同步是待设计/实现项，不能当作平台绝对不能做 |
| 下载生命周期 | DownloadService 前台服务及通知 | 当前普通 Task/URLSession，未见后台 URLSession、BGTask 或后台模式配置 | iOS 当前没有与 Android 前台下载等效的后台接线，不能保证切后台持续下载 |
| 构建 | Gradle、Android SDK/NDK、CMake；release 当前使用 debug signingConfig | XcodeGen、Swift Package、Xcode；脚本产出未签名 IPA | 正式签名和发布渠道需要分别管理 |
| CI | 项目 Android 构建工具与验证 | ios.yml 使用 macos-14，手动及 codex/ios-port push 触发，选择 iPhone 模拟器运行 UI | 旧文档“只手动触发”已不符合当前 workflow；iPad 未纳入该 UI 设备选择 |
| 更新 | Android 安装包下载/校验和安装流程 | `ios-release.json` 元数据与外部更新地址 | 两端更新源与分发方式分开，不应共用 Android versionCode 判定 |

工程和生命周期证据：[iOS 下载运行时](F:/softForCode/codex-project/xx-comic/.worktrees/ios-port/ios/ComicCore/Sources/ComicCore/DownloadRuntime.swift:254)、[Android 下载服务](F:/softForCode/codex-project/xx-comic/app/src/main/java/com/xxcomic/download/DownloadService.java:1)、[iOS Info.plist](F:/softForCode/codex-project/xx-comic/.worktrees/ios-port/ios/XXComic/Info.plist:1)、[iOS CI](F:/softForCode/codex-project/xx-comic/.worktrees/ios-port/.github/workflows/ios.yml:1)。

**6. 本次确认的问题与接线缺口**

优先级表示建议修复顺序。下面没有把尚未实测的风险写成已经复现的崩溃。

| 优先级 | 问题 | 源码事实与用户影响 | 建议 |
| --- | --- | --- | --- |
| P1 | 两个站源 ID 不一致 | defaultIDs 使用 `five_um` / `copymanga`；适配器返回 `manhuazhan` / `copy4000`。启用源用严格 ID compactMap，因此两源丢失；站源管理对应项也取不到名称 | 统一 ID，迁移旧偏好；加覆盖实际 AppEnvironment 的注册与启用集成断言 |
| P1 | 卷轴模式仍会侧边点按/横滑切章 | ReaderNavigation.tapAction 对 strip + tap 返回 move；ReaderViewController.move 在 strip 中直接 changeChapter；pan 判断也未限制 paged | 同步 Android 2.0.32/2.0.36 后的卷轴防误翻规则，并验收多指、缩放、取消和边缘手势 |
| P1 | iPad 多处弹出层未设置锚点 | 导入菜单有 barButtonItem 锚点，但 SourceSettings 的更多 ActionSheet/分享、本地长按删除、详情管理/删除等未见对应 popover 锚点 | 优先补齐 sourceView/sourceRect/barButtonItem；在用户已有 iPad 上验收。当前属于明确代码缺口和运行风险，未在本次复现异常 |
| P1 | 下载完成未汇入本地书架 | 本地书架仅查询 localLibrary.series；Downloads 是另一目录；onTaskCompleted 在 App 未赋值。本地书架文案承诺“收进本地书架”但当前接线不支持 | 增加统一书架条目/下载书目录桥接；保留下载中心离线阅读入口；验收源停用和断网场景 |
| P1 | 批量导入恢复/重试没有用户闭环 | Worker 有 resumeSession/retryFailed，UIKit 未调用；书架执行后仅显示成功/失败数 | 启动检测未完成批次，提供恢复/重选授权/失败项重试，保留已完成卷 |
| P2 | “跟随系统”与自动主题实际行为矛盾 | iOS Settings 写跟随系统；AppTheme.isDark 用小时小于8或大于等于18。当前 Android 自动主题读取系统 uiMode | 统一为用户期望的系统主题，或明确改文案并提供独立时间自动模式 |
| P2 | 下载中心 Wi-Fi 切换不持久化 | toggleWifiOnly 只改 runtime；LocalStorage 的同类开关才写 downloads.wifiOnly；下次启动重新读 defaults | 两处使用统一设置入口，立即同步并落盘 |
| P2 | 多数站源动态配置未消费 | 仅6源传 config；其余直接默认构造；不认识的 ID 和 custom 被跳过 | 明示导入成功/跳过数，按适配器能力补齐动态消费和跨端互通 |
| P2 | 文件下载只完成核心层 | Worker/协议/队列存在，但当前 App 未接文件站源和 enqueueFiles 入口 | 接入实际 FileSourceCapability、刷新链接和本地打开路由后再标记完整 |
| P2 | iPad/横屏固定三列与固定详情封面 | 不是 Android 当前动态列数/hero 尺寸 | 引入共享设计规格，按尺寸和内容宽度计算；同场景截图验收 |

问题关键证据：[ID 列表与启用映射](F:/softForCode/codex-project/xx-comic/.worktrees/ios-port/ios/XXComic/AppEnvironment.swift:49)、[漫画栈真实 ID](F:/softForCode/codex-project/xx-comic/.worktrees/ios-port/ios/ComicCore/Sources/ComicCore/FiveUmComicSource.swift:11)、[拷贝真实 ID](F:/softForCode/codex-project/xx-comic/.worktrees/ios-port/ios/ComicCore/Sources/ComicCore/CopyMangaComicSource.swift:4)、[卷轴 move](F:/softForCode/codex-project/xx-comic/.worktrees/ios-port/ios/XXComic/ReaderViewController.swift:411)、[横滑条件](F:/softForCode/codex-project/xx-comic/.worktrees/ios-port/ios/XXComic/ReaderViewController.swift:470)、[书架数据来源](F:/softForCode/codex-project/xx-comic/.worktrees/ios-port/ios/XXComic/ComicGridViewController.swift:132)、[批量导入接线](F:/softForCode/codex-project/xx-comic/.worktrees/ios-port/ios/XXComic/ComicGridViewController.swift:246)、[下载网络开关](F:/softForCode/codex-project/xx-comic/.worktrees/ios-port/ios/XXComic/DownloadCenterViewController.swift:55)、[时间自动主题](F:/softForCode/codex-project/xx-comic/.worktrees/ios-port/ios/ComicCore/Sources/ComicCore/AppTheme.swift:1)。

**7. 验证结果与文档可信度**

本次在 Windows Docker 的 Swift 5.10 Linux 环境运行：

```text
docker run --rm --mount type=bind,source=<ComicCore目录>,target=/work -w /work swift:5.10-jammy swift test -j 2
Executed 639 tests, with 2 tests skipped and 0 failures
耗时：129.549 秒；退出码：0
```

两项跳过的是 Apple 原生 PDF 渲染相关场景。通过结果证明本次执行到的 ComicCore Linux 路径没有测试失败；不证明 UIKit、WKWebView、CommonCrypto/CoreGraphics 条件分支、Files 授权、iPad popover 或真实网站均可用。[本次完整日志](F:/softForCode/codex-project/xx-comic/docs/comparisons/2026-10-10-ios-core-tests.log)。

已有 VALIDATION 记录显示：2026-09-21 曾有 Core 646 项通过、模拟器编译通过；后一轮 UI 17 个用例中16个通过，外链安全场景仍因 UIKit alert 委托异常失败。当前 HEAD 修复了该问题，但本次没有重新运行 macOS UI 测试，不能声称最新完整 UI 已通过。历史记录与本次639项使用不同平台和条件测试口径，不能直接当成测试减少或退步。[历史验证记录](F:/softForCode/codex-project/xx-comic/.worktrees/ios-port/ios/VALIDATION.md:7)。

以下文档已落后于代码，需要更新：

- 根 README 只介绍早期几个站源，还把漫画屋列为内置源；无法代表当前 Android 注册目录。
- iOS README 仍写13/18源、EPUB/PDF/下载未完成、未连接GitHub；当前代码已有这些核心实现和 GitHub remote。
- iOS PARITY 仍写文件下载 Worker 未完成、动态路由不消费、只有手动 CI；当前代码与最新 VALIDATION 已部分推翻这些结论。
- 同样，文档里写“16/18站源注册”也不能替代调用链检查；本次发现实际启用流程只有14个能匹配。

**8. 建议补齐顺序**

1. 先修实际使用问题：两个站源 ID、iPad 弹出层、卷轴误切章、下载书架汇总、导入恢复/重试、网络偏好持久化与主题规则。
2. 再以 Android 2.0.40 建立新对齐清单，补书架/站源分组、网格/列表、追更徽标、详情/阅读换源、漫画进度预览和目录快速导航。
3. 按真实优先级同步7个专用站源与29个公共配置站源，并先处理包子退役策略、动态配置与网络例外；逐站验证搜索/分类/详情/目录/图片/验证/下载能力。
4. 单列文件系统和增强工作：外部文件夹直接索引、持续同步、自定义下载目录、后台下载策略、iOS 本地图像增强/AI 超分。这些需要适合 iOS 的实现，不能只翻译 Java。
5. 完成视觉规格：项目图标、完整颜色与尺寸 token、导航、书架/详情/阅读控制条、提示层；按 iPhone/iPad × 横竖屏 × 深浅色做同场景截图，并验证大字体、键盘和安全区。
6. 更新 README/PARITY/VALIDATION 与固定基线，使“已写代码、已接页面、已通过核心、已通过原生构建、已通过设备验收”分别可追踪。

本次产物：[代码数量和素材校验事实](F:/softForCode/codex-project/xx-comic/docs/comparisons/2026-10-10-code-facts.json)、[基线漂移](F:/softForCode/codex-project/xx-comic/docs/comparisons/2026-10-10-baseline-drift.json)、[核心测试日志](F:/softForCode/codex-project/xx-comic/docs/comparisons/2026-10-10-ios-core-tests.log)。本次仅生成对比报告和核验产物，没有修改 Android/iOS 业务代码，也没有提交或推送。

