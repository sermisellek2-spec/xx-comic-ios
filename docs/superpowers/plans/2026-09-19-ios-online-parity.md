# iOS 在线阅读与数据闭环实施计划

**Goal:** 从已测试的基础规则推进到真实站源、书架、详情、目录、阅读及本地保存的完整闭环，然后继续扩展全部安卓版功能。
**Spec:** docs/superpowers/specs/2026-09-19-ios-parity-baseline.md
**Architecture:** ComicCore 实现可注入网络的站源和可测试存储；UIKit 持有请求 Task、展示状态和阅读交互；Swift 5.9 / iOS 16。

## Global Constraints

- Android 2.0.29 为基准；不得修改 Android 源码。
- 业务结果、默认行为、视觉素材按 Android 对照；无后台统计、账号或云同步。
- 不将占位页面或空数据称为功能完成；错误、空结果和验证要求分开。
- 所有网络工作可取消，旧请求不能更新新页面；书架删除收藏保留历史。
- Linux 测试不等于 Xcode 或 iPhone 验证；不公开仓库或推送。

### Task 1: G社站源及公共网络契约

所有修改限于 `ios/ComicCore/Sources/ComicCore/ComicModels.swift`、新增 `ComicSource.swift`、`GmhComicSource.swift`、`SourceHTML.swift`（确有复用需要时），以及对应 `Tests/ComicCoreTests/GmhSourceTests.swift`。

逐项读取 Android `source/GmhComicSource.java`、`SourceConfig.gmh`、`GmhComicSourceTest`。移植搜索、分类/筛选、详情、目录、章节图片、host 迁移和混淆解码；保留广告章节回退规则、顺序、去重、请求头和配置默认值。

共享接口：
- `public protocol ComicSource: Sendable { var id: String { get }; var name: String { get }; var referer: String { get }; func latest(page: Int) async throws -> [ComicSummary]; func search(keyword: String, page: Int) async throws -> [ComicSummary]; func detail(comicId: String) async throws -> ComicDetail; func chapters(comicId: String) async throws -> [Chapter]; func chapter(url: String) async throws -> ChapterPage; func filterGroups() async throws -> [SourceFilterGroup]; func category(filters: [String:String], page: Int) async throws -> [ComicSummary] }`
- `public actor GmhComicSource: ComicSource`，可用 `GmhComicSource()` 初始化；标识属性 nonisolated。
- `ComicDetail` 字段 `summary:ComicSummary, author/status/description/latestChapter:String, chapters:[Chapter]`；`ChapterPage` 字段 `chapterId/title/nextPageUrl:String, imageUrls:[String]`；提供 public 初始化器。
- `SourceFilterGroup(key:String,label:String,options:[SourceFilterOption])`，`SourceFilterOption(label:String,value:String)`。
- 网络使用可注入的 `HTTPTransport`，协议签名由实现者给出；URLSession 默认实现支持 FoundationNetworking。测试使用固定响应，不真实依赖站点。

步骤：先写捕捉响应解析、加密图片还原、目录广告过滤和 HTTP 失败的行为测试，运行 red；实现后针对性测试 green；完整测试一次并提交本任务文件。测试命令：Docker swift:5.10-jammy，绑定 ComicCore 到 /work，`swift test --filter GmhSourceTests`。实际站点探测仅作为补充，无法访问必须如实记录。

### Task 2: 本地收藏和阅读数据

新增 `LibraryStore.swift` 及 `LibraryStoreTests.swift`。模型 Codable，使用明确的 sourceId/comicId 组合身份，收藏时间/最后阅读时间排序；取消收藏不删除作品缓存或阅读位置；位置按作品与章节保存；JSON 原子写入；损坏文件报告错误而不是覆盖。用临时目录重开存储验证、同名不同站源区分、收藏移除保留历史、目录缩短由 ReaderPosition clamp。先写测试并运行，再实现。

### Task 3: 在线页面与阅读器

替换 `AppDelegate` 中占位书架、发现页。新增应用共享环境、封面网格、可取消图片加载、详情与按需章节抽屉、在线阅读器、收藏/历史页面。书架三列、卡片仅封面/标题；详情不主动请求章节；搜索键提交而非每字请求。复用已有中文和图片资源，支持真实加载/错误重试/空态。

阅读器支持条漫和单页、缩放、逻辑页序和左右手、按钮/触碰/滑动模式、跨章、进度恢复及持久化；阅读主题独立，控制栏/抽屉同步；进出页面取消网络任务。先建立独立可测阅读会话模型覆盖跨章和单次动作，再接 UIKit。未接入的去白边等能力明确留在功能矩阵，不能宣称全量完成。

### Task 4: 复核与后续

Docker 核心测试、UIKit 语法检查、Android 基准检查。独立审查代码与 Android 约定差异，修复明确问题。更新 `ios/VALIDATION.md` 和功能矩阵，继续站源验证/全部站源、本地漫画/电子书/PDF、下载和完整视觉；Xcode 构建等待用户提供 GitHub 环境。

### Task 5: 包子站源

按 Android BaoziComicSource 完整迁移列表、搜索、分类 API、详情、目录与图片，保留 nextPageUrl 是下一章的契约。固定 fixture 验证请求与解析，HTML 错误页与合法空容器分开，中文/HTML实体解码一致。实现与审查限定 Baozi 源及测试。

### Task 6: 本地图片导入闭环

先对照 Android NaturalPathOrder 迁移自然排序（分路径、数字块、大整数、前导零、大小写），再实现图片文件副本导入、元数据和本地 source 适配器。导入失败/取消不发布不完整书籍，不动原始文件；原子目录发布，拒绝路径逃逸。以临时目录测试重开、排序、副本、失败保留及 source 阅读接线；接 UIKit 文件选择、本地书架和共用阅读器。此步骤只完成图片格式，文件夹/ZIP/EPUB/MOBI/PDF、分卷管理与恢复另行继续，不得宣称全量本地库完成。
