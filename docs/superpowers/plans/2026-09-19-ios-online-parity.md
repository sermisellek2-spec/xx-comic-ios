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

### Task 7: 漫画160

完整迁移 Mh160ComicSource 搜索、动态筛选、详情、目录、Base64章节图片与CDN迁移阈值；共享已存在的HTML4解码器，避免复制映射。保留合法空列表/目录，但空章节正文应与Android一样报错。以确定性fixture验证错误壳、编码、去重、旧ID与顺序。集成后按包子、漫画160、G社的默认相对顺序展示；只为该源原有的 `auto.mangafiles.com` 图片域设置HTTP例外，不放开全局ATS。

### Task 8: 阅读习惯与启动书架

按 Android reader/ReadingHabitTracker.java 及 ReadingHabitTrackerTest.java 移植本地状态机，新增 ComicCore/ReadingHabitTracker.swift 和对应测试。保持60秒可读有效时间加主动操作、120秒空闲截止、后台超过300秒新会话、30天最近10次且至少5次和70%阈值；不足阈值保留旧偏好，每会话一票，手动模式不学习，重置及持久化行为对齐。时钟可注入，持续时间使用单调时钟、样本使用墙钟。不得上传统计。

接入 AppEnvironment、AppDelegate、Bookshelf、Reader、RemoteImageView（如需要图片成功回调）、Settings：首次书架选择采用解析结果，手动切换保存；设置提供自动/固定我的/固定本地、当前偏好、确认后重置；真实图片可读后才开始计时，用户主动阅读操作才激活，覆盖层/后台暂停，离开阅读器结束，跨章不重复计票。对照 Android MainActivity 的调用位置与文案。避免定时器循环持有页面及通知泄漏。

先运行失败测试再实现；Docker核心测试、UIKit语法检查。新增状态机/持久化测试需覆盖阈值前后、空闲、覆盖层、短/长后台、同书/换书、重置和重新加载。不得把语法检查报告成 iOS 编译通过。仅修改 iOS 文件，代理不暂存不提交，主代理统一提交并独立审查。

### Task 9: 漫画栈和比卡漫画

对照 FiveUmComicSource.java、SourceConfig.fiveUm 和 SourceFilters，新增单一 FiveUmComicSource 适配器，通过两份默认配置支持 manhuazhan/漫画栈/https://www.60ti.com 与 bbyin/比卡漫画/https://bbyin.com。复用 ComicSource、HTTPTransport、HTML4EntityDecoder。迁移最新分页、仅第一页搜索（Java表单URL编码）、动态题材/状态、详情作者/封面/标签/简介/最新章但返回空目录、独立目录顺序和URL去重、仅正文comic-image图片及懒加载属性优先级。ID含站源前缀，支持旧详情URL输入。

测试请求URL/请求头、双站隔离、筛选文档顺序/全部项/重复标签、详情不暴露目录、章节顺序/去重/正文范围、HTML实体、HTTP失败和取消。遵循现有约定，合法空列表可以为空，错误HTML壳不冒充搜索无结果，缺标题/筛选/正文必须报中文错误。不增加第三方依赖。注册放在习惯任务完成后，由主代理按安卓相对顺序接线以免AppEnvironment冲突；只改iOS，Windows测试不替代设备验证。

### Task 10: 漫客栈

对照 MkzhanComicSource.java 和 SourceConfig.mkzhan，新增 MkzhanComicSource.swift 及测试。保留 latest不强加is_free而category筛选默认is_free=1 的区别；搜索仅第一页、Java表单编码；动态四组筛选和参数顺序；限定列表容器、封面/标题/更新文本回退和去重；详情携带同次HTML中目录、data-hreflink章节顺序及“开始阅读”排除。章节调用comic.mkzcdn.com既有公开API，从data.page提取图片去重、http升级https，保留章节ID为comic/chapter及url规范化。保留请求头和可取消HTTP契约。错误响应不能冒充正常内容；合法空列表/目录仍可返回。测试先行，固定fixture对照URL及解析，不访问账号、不新增依赖、不修改Android。主代理注册，不与其他实现者同时写AppEnvironment。

### Task 11: HiperDEX、悦看漫画、tapmanga搬运

一组同类 HTML 站源移植：新增 HiperdexComicSource、D5d6ComicSource、AntbywComicSource 和各自 fixture 测试，严格对照同名Android源码及SourceConfig默认配置，复用现有ComicSource/HTTPTransport/HTML4EntityDecoder。逐源移植latest/search/page行为、筛选键值/顺序、详情元数据与目录按需契约、章节ID与排序去重、正文图匹配及相对URL/实体解码。源特有区域/状态回退按原代码，不把三站归并成通用猜测解析器。

允许提取被这三站实际共同使用的小型文本/URL函数，不提前设计爬虫框架。HTTP失败和取消必须传播，错误壳不冒充正常空内容；保留合法空列表/目录。先写测试观察缺实现失败，再实现并运行聚焦测试，最后全量一次；报告具体URL、解析和错误覆盖。仅改对应iOS源/测试及必要共享helper，不修改Android、不注册AppEnvironment、不提交不暂存、不访问账号。注册由主代理按安卓默认相对顺序完成；独立复审后才记为已接入。

### Task 12: 本地文件夹章节导入

按Android LocalImporter.indexFolder/buildFolderChapters/findCommonFolderWrapper移植图片目录：忽略元数据、最多5层，递归自然排序，剥离共同包装目录，有子目录时根图为“未分章”且各第一层目录为章，无子目录时为“正文”。保持图片副本和原子发布、取消/失败回收，不改原文件。LocalBook兼容已有pages JSON，新增可选章节信息，旧单章URL仍能续读；文件存储仍为受控扁平命名，不能由manifest路径越界。通过LocalComicSource目录和章节API接共用阅读器。

系统文件选择增加图片文件夹入口，安全范围访问包住整个导入任务；ImageIO过滤无效图片，扫描/复制均在后台且可取消。测试旧数据兼容、共同包装目录、多章/根图顺序、重复文件名、非图/符号链接/过深目录/取消不发布及重新打开目录阅读。当前40MiB单图保护保留并明确不是Android128MiB上限一致性验收；批量分书、分卷编辑、指纹去重恢复后续任务，不宣称完整本地复刻。

### Task 13: 站源开关和排序

对照SourceOrder.java/tests及MainActivity站源开关保存，新增SourcePreferences小型本地存储：稳定ID排序、无效/重复/退役ID清理、新源按默认相对顺序追加、禁用仍保留排序位置、默认全开、支持全关、恢复默认排序不改开关。测试重启持久化/错误JSON/旧版本增减源。无服务端同步。

AppEnvironment保留完整适配器列表，并向发现页提供已启用有序列表，收藏/历史仍可通过完整列表读取。设置加入站源管理页、开关、拖动排序和恢复默认排序。发现页配置变化后按ID保留选中源；选中源禁用后回退到首个可用源并清空不适用筛选；取消旧请求、空列表禁用筛选，防越界与旧结果污染。只为已实现适配器提供开关，不把未移植源列成可用。暂不含自定义路由配置/导入导出/测速和日志，后续补齐；UI仍需截图对照。

### Task 14: 站源筛选抽屉统一

按MainActivity.showFilterDrawer(0/1)把源名按钮的即时菜单换成已有右侧抽屉的站源列表入口；分类按钮进入分类页。抽屉内选源只改草稿并重置该源筛选，确认后才提交源和筛选；关闭/点外部丢弃。选源后普通源加载分类，mh18/jmcomic保留源列表直到确认（categoriesFollowInitialList）。取消旧分类请求，禁止旧结果覆盖新选源；关闭抽屉取消分类请求。复用现有三列布局和抽屉宽度，不额外添加页面。UIKit验收需Mac，Windows只记录语法和静态审查。

### Task 15: 漫本与表单 POST

**Files:** 新增 `ios/ComicCore/Sources/ComicCore/ManbenComicSource.swift`、`ios/ComicCore/Tests/ComicCoreTests/ManbenSourceTests.swift`；修改 `ios/ComicCore/Sources/ComicCore/ComicSource.swift` 和 `ios/ComicCore/Tests/ComicCoreTests/GmhSourceTests.swift` 中已有 URLProtocol transport 测试。注册由主代理在审查后修改 `ios/XXComic/AppEnvironment.swift`。

**Interfaces:** 沿用 `ComicSource`；`ManbenComicSource(transport: any HTTPTransport = URLSessionHTTPTransport())`，默认 ID `manben`、名称 `漫本`、baseURL `https://www.manben.com`、Referer 带尾斜杠。给 `HTTPTransport` 增加 `post(_ url: URL, headers: [String:String], body: Data) async throws -> HTTPResponse`；协议扩展默认实现抛出明确 unsupported-method 错误以兼容既有只读 fixture，URLSession 实现必须真实 POST。GET/POST 共用现有取消发送逻辑，不复制网络栈、不新增依赖。

- [ ] 读取 Android `ManbenComicSource.java`、`SourceConfig.manben`、`ManbenComicSourceTest.java`。先在新测试文件创建记录 method/URL/headers/body 的 actor transport，POST 分类合法空响应 fixture 为 `[]`。添加首个行为测试并运行，确认缺少适配器或POST接口导致失败：

```swift
func testLatestUsesPostCategoryPageAndDefaults() async throws {
    let transport = ManbenFixtureTransport(response: "[]")
    let source = ManbenComicSource(transport: transport)
    let items = try await source.latest(page: 2)
    XCTAssertTrue(items.isEmpty)
    let recorded = await transport.lastRequest()
    let request = try XCTUnwrap(recorded)
    XCTAssertEqual(request.method, "POST")
    XCTAssertEqual(request.url.absoluteString, "https://www.manben.com/mh-list/pagerdata.ashx")
    XCTAssertEqual(request.fields["pageindex"], "2")
    XCTAssertEqual(request.fields["t"], "2")
    XCTAssertEqual(request.fields["sc"], "1")
    XCTAssertEqual(request.fields["tsort"], "2")
    XCTAssertEqual(request.fields["tnm"], "")
}
```

测试代码的 await 结果先存局部变量再传 XCTest autoclosure；fixture 记录字段解析自实际表单 body，不能复用生产编码逻辑生成期望值。

- [ ] 移植分类默认字段 `t=2,pageindex=max(1,page),sc=1,tsort=2,tagid=0,tst=0,tarea=0,tgroup=0,tnm=`，筛选映射 state/tag/audience/region/letter 到 tst/tagid/tgroup/tarea/tnm，all转换按Android。验证POST编码及取消；不改变现有GET fixture行为。
- [ ] 搜索 `/search?page={page}&title={keyword}&language=1` 使用Java表单编码，保留分页；动态筛选按网页顺序、tagClick参数、中文标签映射。详情保留评分嵌套span剥离、作者长链接回归、简介/封面/状态/最新章、目录为空的按需契约。章节仅取chapterlistload，保留站点分组sectionSlot，组内按数值ID升序、去重和连续chapterSlot；不要扫推荐区。
- [ ] 正文先解析章节标题和被屏蔽状态，再按 `/imageshow.ashx?cid={chapterId}&page={page}&showtype=1&ispre=0` 顺序取页，Referer为章节URL。解析chapterimage JSON的ImagePix/Images/IsEnd，只保留ImagePix范围内图片，去重；两次连续无新增报错、最多1000次、未正常结束报错、空正文报错。fixture覆盖正常两页、重复图片、终止空数据/错误壳、无新增循环、取消中断零后续请求。保留HTTP失败，不吞取消。
- [ ] 聚焦执行 `docker run --rm --mount 'type=bind,source=F:\softForCode\codex-project\xx-comic\.worktrees\ios-port\ios\ComicCore,target=/work' -w /work swift:5.10-jammy swift test --filter 'ManbenSourceTests|GmhSourceTests'`，再全量一次确认POST接口未破坏已有源。报告实际测试名称/数量、RED/GREEN、未覆盖平台编码差异。仅主代理提交和接线；独立审查后更新矩阵，不把fixture通过当作站点或设备验收。

### Task 16: 站源 AES-CBC 平台解码

**Files:** 新增 `ios/ComicCore/Sources/ComicCore/SourceAES.swift`、`ios/ComicCore/Tests/ComicCoreTests/SourceAESTests.swift`。不改现有站源或UIKit；随后催漫画/六漫画/拷贝/漫蛙直接调用。

**Interface:** internal `SourceAES.decrypt(_ ciphertext: Data, key: Data, iv: Data) throws -> Data`；对应 Android `AES/CBC/PKCS5Padding`，AES块大小16时等于PKCS7。接受16/24/32字节密钥、16字节IV、正数且16整除密文；坏输入/填充必须报错。返回字节，不做站源JSON/图片语义验证，后者由消费者负责。

- [ ] 新增固定已知密文测试：Android CuimhComicSourceTest.decryptsChapterImagesWithNativeAes 的 Base64 样本首16字节是IV，密钥为该源码 AES_KEY。解密JSON images必须为 `["https://img.example/1.webp","/static/2.webp"]`。先跑 `swift test --filter SourceAESTests` 观察缺实现失败；同时补24/32字节密钥固定向量和坏长度/坏padding回归。
- [ ] Apple端 `import CommonCrypto` 调用 CCCrypt(kCCDecrypt,kCCAlgorithmAES,kCCOptionPKCS7Padding,...)，不写AES算法、不增加Swift依赖。Linux仅用于核心测试，使用已安装 `/usr/bin/openssl enc -d -aes-{128|192|256}-cbc` 的独立进程，参数数组不经过shell；临时目录保存输入输出并defer清理，避免管道阻塞，不打印站源公开格式密钥。调用前后检查取消；Apple分支需Xcode单独验收，Linux通过不能替代。
- [ ] 再跑同聚焦测试，校验已知明文、三种密钥长度、错误填充/输入及预取消。记录Linux后端差异和命令；独立审查，不以抽象层测试替代后续源集成测试。

### Task 17: 催漫画与六漫画

**Files:** 新增 `ios/ComicCore/Sources/ComicCore/CuimhComicSource.swift`、`LiumanhuaComicSource.swift` 及 `ios/ComicCore/Tests/ComicCoreTests/CuimhSourceTests.swift`、`LiumanhuaSourceTests.swift`。修改 `ComicSource.swift` 仅增加 `var supportsSearch: Bool { get }` 和协议扩展默认true。两源返回false，search直接抛中文“不支持搜索”，不能请求网络。主代理在审查后注册及接发现页搜索能力过滤。

**Interfaces:** public可默认初始化的两源适配器，HTTPTransport注入、模型沿用ComicSource；用Task16内部SourceAES解密，HTML4EntityDecoder清文本，不复制AES实现、不引入依赖。默认配置以Android SourceConfig.cuimh/liumanhua为准。先完整读两源Android源码及对应Tests，必须分别移植，不把细微不同归并猜测。

- [ ] 先移植Android现有明文/加密fixture成失败测试（`swift test --filter 'CuimhSourceTests|LiumanhuaSourceTests'`），验证最新和分类、动态分组、详情同次携带目录、目录顺序去重、ID和相对URL。错误壳须有站点结构检查，不能单凭h1认正常详情；Cuimh单独目录无章应报错。
- [ ] Cuimh分类顺序 `classification,subject,type,quality,region,copyright,state` 对应 `/list/,/tags/,/theme/,/quality/,/city/,/copyright/,/finish/`，只接受匹配键前缀；默认/category和/category/共用缓存键。5分钟TTL、LRU最多8页、每次网络开始间隔至少1秒；403本地冷却30分钟，冷却优先于缓存，禁止自动绕过/重试。Swift actor的await可重入，必须保持安卓synchronized fetch的串行性，不能让并发请求跳过间隔。时钟/等待可注入以快速测试TTL边界、LRU、冷却和取消；不要让真实测试睡30分钟。
- [ ] Cuimh固定Base64 payload沿用Android测试，首16字节IV，AES公钥沿用原源码；解密JSON必须host精确www.cuimh.com，缺images报错；相对图片前缀https://img1.baipiaoguai.org，保持顺序去重。
- [ ] Liumanhua分别保留自己的categoryPath筛选限制、目录URL模式和无目录时“在线阅读”fallback条件；普通20秒、章页30秒。解密JSON验证comic_down、source_id、host、comic_id/comicId/chapter_id/chapterId与请求一致性，以及非空HTTP(S)图片；不把Cuimh的相对地址规则用于六漫画。测试Android原本的所有拒绝场景，替换为固定密文时由独立Java/OpenSSL生成并记录来源。
- [ ] 聚焦成功后全量一次，记录真实数量和未执行Xcode情况；代理不暂存不提交不注册，不运行真实站点请求。主代理提交并独立复审；修复通过后主代理按Android enabledSearchSources规则排除不支持搜索的源（它们仍能分类/收藏/阅读），单站输入也给清晰中文提示，不伪造空结果。

### Task 18: 漫蛙图片解码与显示接线

**Files:** 新增 `ios/ComicCore/Sources/ComicCore/ManwaImageDecoder.swift`、`ios/ComicCore/Tests/ComicCoreTests/ManwaImageDecoderTests.swift`；修改 `ios/XXComic/RemoteImageView.swift` 的后台图像解码入口。

- [ ] public `ManwaImageDecoder.usesImageHost(_ text: String) -> Bool` 和 `decode(_ data: Data, publicKey: String = ...) throws -> Data`。默认公钥逐字使用Android SourceConfig.manwa.route(imageKey)，是站点公开图片格式的一部分，非账号凭证。测试直接使用Android ManwaImageDecoderTest内.NET生成的一像素PNG和密文常量，先观察新API失败；验证明文不改、密文精确还原、截断/HTML/错误key拒绝、主域/子域匹配且相似域不匹配。
- [ ] 仅识别 `mwtuwu.cc,mwzu.cc,mhttu.cc,manwace.cc` 主域及点分子域；至少16字节，JPEG/PNG/GIF8/RIFF+WEBP头透传，其他数据首16字节IV、32字节UTF8密钥调用SourceAES，然后再次检查图片头。错误不允许进入图片缓存。
- [ ] RemoteImageView后台ImageIO之前按原请求URL域名决定是否解码；所有来源和本地文件仍沿用既有展示/裁边/缓存，明文与加密图片都走同一显示通路，不在主线程解码。保持取消/代次检查和onFailure。当前无下载队列，后续下载必须复用同decoder，不能把显示接线称为离线实现。
- [ ] 聚焦 `swift test --filter ManwaImageDecoderTests`，UIKit全文件syntax parse；不把Linux通过称为CommonCrypto/Xcode通过。报告/独立审查后才算此范围实现完成，漫蛙站源API另项继续。

### Task 19: 漫蛙 API 站源

**Files:** 新增 `ios/ComicCore/Sources/ComicCore/ManwaComicSource.swift`、`ios/ComicCore/Tests/ComicCoreTests/ManwaSourceTests.swift`。仅这两个文件及必要的测试fixture，不改网络协议/UI，不暂存提交、不派子代理。主代理审查后注册。

**Contract:** 完整阅读 Android `ManwaComicSource.java`、`ManwaComicSourceTest.java`、`SourceConfig.manwa` 和 `app/src/test/resources/manwa/`；以该基准精确移植路由、筛选、列表、详情、目录和正文。复用现有HTTPTransport POST与模型、HTML4EntityDecoder，不新建网络层或依赖。默认base `https://manwace.cc`、imageSource `https://tu.mwzu.cc`、25秒读取；连接15秒的独立限制URLSession不能等价表达，要在报告披露。16MiB响应上限若只能取回后检查也须披露，不称增量防护一致。

- [ ] 先写 Android 样本驱动的失败测试并实际运行，后实现。GET搜索 `/api/search?type=mh&page={page}&pageSize=20&keyword={keyword}`；分类JSON POST `/api/cate{tagSuffix}`，7组顺序level/type/tag/region/state/day/sort，完整标签slug/数值默认对照Android，不缩减选项。分类Referer `/cate{tagSuffix}`，Origin base，Content-Type `application/json; charset=UTF-8`；Cookie只在该请求设置`typeId=N`（all为0），不能污染后续搜索。tag通过URL后缀起效，未知slug报错。列表data.list必须存在，对象类型错误报错，numeric ID、去重、text标题、cover回退pic、author和分隔标签；非空原列表解析无结果报错，明确空列表合法。
- [ ] 详情HTML必须有page-title；comic-cover按data-src/data-original-cover/src；作者中文逗号空白、tagsContainer、comic-desc、状态和最新章，详情不预取目录。目录 `/api/comic/{id}/chapters` 使用全部列表，按sortId Double稳定排序（含1.5番外），每项合法正数字ID，排序后去重、连续chapterSlot；878条测试证明不受HTML20条截断。
- [ ] 正文URL严格 `/comic/{comicId}/{chapterId}`；先info `/api/comic/chapter/info/{chapterId}` 校验data.current comicId/id，再图片API `/api/comic/image/{chapterId}?page={page}&page_size=100&image_source={encoded}`。images和pagination必需；total>0、total_pages 1...500、current_page正确且后页总量不变，每页非空、图片URL为HTTP(S)或合法相对地址，重复图片必须报错，最终计数等于total才可返回，不可吞错返回半章。chapterId为完整规范章URL、nextPageUrl空。
- [ ] HTTP401/403及JSON code401/403明确访问受限，不绕过账号/付费；其他HTTP非2xx及code非200报错；每次请求前后检查取消。覆盖分类实际method/body/headers与搜索无Cookie、各筛选映射、合法空/错误壳、详情按需、长目录小数稳定次序、多页/重复/错页/总量变化/不完整/取消零后续请求。
- [ ] 聚焦 `swift test --filter ManwaSourceTests`，最后全量一次；与主代理协调共享target。报告RED/GREEN实际数量、URL与结构验证、网络/Apple未验收。图片显示已独立接ManwaImageDecoder，无需重复解密实现，也不假称已有离线下载。

### Task 20: 本地图片大小边界对齐

对照Android LocalImporter.MAX_SINGLE_FILE_BYTES和复制循环，把LocalLibrary单图上限由临时40MiB对齐128MiB；保留256KiB流式复制、20GiB总上限、取消/失败回收、系统ImageIO验证和24M解码像素预算。测试128MiB恰好允许、128MiB+1拒绝且不发布、不改原文件。测试使用临时稀疏文件，只验证核心文件大小边界，不声称它们是有效图片。RemoteImageView本地读取复用同一上限，用Foundation mappedIfSafe避免可映射文件的额外整份堆拷贝；在线图片上限不在此任务修改。先观察大小边界测试失败再修正。设备峰值内存和大图渲染仍需iPhone验收。

### Task 21: 拷贝漫画当前 API 与分类字面量

**Files:** 新增 `ios/ComicCore/Sources/ComicCore/CopyMangaComicSource.swift`、必要 `CopyMangaLiteral.swift`、对应测试和从Android复制的Fixtures/copy4000。测试资源只在Package.swift注册。主代理审查后注册，代理不暂存提交、不派子代理。不修改Android、网络协议或UIKit。默认ID `copy4000`、名称 `拷贝漫画`、base `https://www.copy4000.com`，referer尾斜杠。

完整读Android CopyMangaComicSource.java、CopyMangaLiteral.java、SourceConfig.copy4000以及CopyMangaComicSourceTest/CopyMangaApiTest/CopyMangaConnectionTest。此任务只移植当前公开ComicSource调用的网络路径：章节/目录用API，不添加不可达的旧HTML加密目录/阅读回退（Android保留的parseReader/decrypt并非当前chapter实现）；固定旧URL重定向仍保留。测试按实际调用契约，不为未使用兼容函数写代码。

- [ ] 搜索空白直接空、page<1抛错，limit12和offset=(page-1)*12；分类limit50及offset，ordering默认-datetime_updated并仅允许±datetime_updated/±popular；theme/region/status固定顺序、all略去、region/status限0/1/2；表单编码空格必须%20。/filter动态题材去数量后缀、去重，排序/题材/地区/状态4组，默认值与Android相同。
- [ ] 类别exemptComic-box的list属性是数据字面量。优先考虑系统JSON，但实际有单引号、True/False/None、尾逗号及\x/\u转义，不能用全局替换破坏字符串或执行JS；若需最小递归解析器按Android64层深度、仅字符串键、有限合法数字、拒绝表达式和尾部垃圾。复用HTML4EntityDecoder，覆盖引号/转义/Unicode和注入拒绝。search JSON code200/results.list，列表每项path_word/name必需，作者用 ` / `，去重并允许合法空列表；详情依赖指定结构，目录按需。
- [ ] 默认API `https://api.manga2026.xyz`，备选依次 `https://mapi.elfgjfghkk.club`、`https://mapi.fgjfghkkcenter.club`。路径detail `/api/v3/comic2/{comicId}?platform=3`，groups章节 `/api/v3/comic/{comicId}/group/{group}/chapters?limit=100&offset={offset}`，正文 `/api/v3/comic/{comicId}/chapter/{chapterId}?platform=3`。API header COPY/3.0.9、Accept application/json、platform3/version3.0.9/region1/webp1、Referer；普通网络保留Chrome140 UA和JSON优先Accept；不发送dnts。默认普通20s/API12s读取，不能独立表达15s/8s连接限制要披露。
- [ ] API仅连接失败可按3个origin尝试并记住最近返回code200/results对象的线路；网络变化时仍可从该线路回退其他。HTTP失败、JSON错误/占位null、证书验证失败、取消均不得换线；不能放松TLS。保留原path/query；全部连接失败给含尝试host的中文错误。不新增自动无限重试。可注入transport和明确API origin/fallback列表用于契约测试；显式自定义API主域不落回内置备用域。
- [ ] 目录先校验comic.path_word，groups全部遍历，不信count（0也取）。每组分页limit100、offset必须匹配、total>=0、list必需，每项comic/group归属以及uuid/name必需，跨组chapterID去重，sectionSlot按组、chapterSlot=offset+i；只要没到total的空页、重复整页、最多1000页未结束须失败，不能返回半目录。保持JSON分组原有顺序；Foundation Dictionary无稳定输入顺序保证，须选用最小保序解析方案或专门扫描groups键序，不悄悄排序改原行为。
- [ ] 正文旧域URL提取comic/uuid并解码，规范为当前域；校验results非空且is_lock非true、comic/uuid/归属一致，contents非空且size等于数组长度，保留原图顺序（不用words字段重排），每图HTTP(S)，空nextPageUrl。拒绝被锁内容，不绕过访问限制。
- [ ] 先失败测试后实现，复制使用Android记录样本：搜索两页各12、分类50、分类组题材含COLOR、目录190、正文86；失败目录/正文、连接回退/证书/取消及URL/header边界。响应16MiB只后验限制必须披露。聚焦测试结束后与主代理协调一次全量，报告真实结果和平台未验收。输出task-21-report.md。

### Task 22: 本地导入条目计数与真实图片探测

对照Android LocalImporter.copyDocumentTreeNative与AndroidImageProbe，修改LocalFolderIndex：忽略metadata后，所有目录与文件都计入50000项预算，保留5层深度、单图128MiB、总20GiB和取消。真实临时目录回归：49999个空目录和1张图恰好允许，再加1个目录失败；失败不发布新书、不动原图，metadata仍不计数。不要为测试给生产类加可变限制。

新增仅Apple可用的ComicCore LocalImageProbe.isReadable(_:) throws -> Bool，使用原生ImageIO缩略图解码，文件必须普通文件、非符号链接、<=128MiB，前后检查取消。不只接受有效图片头。单图和文件夹UIKit入口共用；单图失败报错，文件夹坏图继续跳过，后台/安全作用域/发布流程不变。条件Apple测试覆盖有效PNG、只有头的截断PNG、非图片、大小超限及预取消。Windows不能运行ImageIO，明确这些测试未执行，不称完整TDD或Xcode验证；跨平台计数必须观察RED/GREEN。仅修改本地相关文件，不改Task21所有权文件。

### Task 23: ZIP/CBZ 导入核心及接线

完整对照Android ArchiveIndex.java、LocalImporter.java及ArchiveIndexTest；先读本计划账本目录archive-research.md。依赖标准库无ZIP解压器，采用固定ZIPFoundation0.9.20（MIT，保留许可）而不自写解压算法。等待Task21释放Package.swift，再新增依赖并保留其fixture资源。仅ZIP/CBZ，电子书/批量/分卷管理后续继续，不能称本地全量完成。

核心LocalLibrary.importArchive(title:archive:isReadableImage:)流式解压到受控临时目录，成功后单次rename发布，失败/取消清理，原文件不变。不要解压后调用importFolder：ZIP无5层限制，避免再次复制整份数据。仅提取供图片页使用的受控扁平目标名，复用现有自然分章及manifest发布逻辑，不建通用导入框架。

所有条目（含目录和metadata）<=50000；每条声明<=128MiB，声明总量<=20GiB。非目录先拒绝绝对路径/盘符/越界路径，再规范化、拒绝重复，最后跳过metadata；拒绝符号链接。名称先尝试全部UTF8，失败全局GB18030（保留UTF8 flag强制UTF8规则）。Library序列可能静默截断，须最小EOCD/ZIP64计数校验，声明与实际数量必须匹配；多磁盘、加密、不支持或损坏后部条目不能静默导入部分书籍。流式consumer检查取消、实际单条/累计预算、最终长度和CRC，禁止只相信中央目录；坏图片跳过，压缩流完整性损坏应失败。真解码探测复用Task22 ImageIO路径，坏首图不能成为封面。深目录、自然顺序、wrapper剥离、未分章/正文规则同Android。

测试先失败后实现：存储/deflate、中文UTF8和GB18030、chapter自然顺序、深度>5、跳坏首图、越界/绝对/盘符/规范化重复/metadata重复、声明预算与50001条、损坏CRC/截断/后部加密条目/ZIP64计数、取消清理、重开阅读。测试fixture用确定性ZIP字节或库创建后定点破坏，不引入运行时shell。UIKit新增压缩包选择与清晰中文状态，保持安全作用域直至任务完成；parse不是Xcode验收。依赖、核心、UI分清验证，独立审查后更新矩阵。
