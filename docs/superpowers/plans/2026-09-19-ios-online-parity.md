# iOS 在线阅读与数据闭环实施计划

**Goal:** 从已测试的基础规则推进到真实站源、书架、详情、目录、阅读及本地保存的完整闭环，然后继续扩展全部安卓版功能。
**Spec:** docs/superpowers/specs/2026-09-19-ios-parity-baseline.md
**本地批量/分卷后续设计:** docs/superpowers/specs/2026-09-20-ios-local-library-lifecycle.md（Tasks40–43之后的持久化、导入协调和阅读路由边界；尚未实现）
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

实施验证补充：已复现ZIPFoundation0.9.20 Linux解压跨越声明compressedSize且接受截断条目（RED1测试3失败），其底层decode对短输入块还使用bufferSize而非实际chunk.count。不得保留该风险。继续用ZIPFoundation解析/枚举ZIP，deflate分支使用系统zlib最小薄封装（非自写算法），Apple/Linux共用；新增ComicZlib systemLibrary避免与依赖内部CZLib重名，最小shim/modulemap链接z。受限输入、实际avail_in、256KiB输出、取消、CRC、完整消费压缩长度及Z_STREAM_END验证，defer释放原生流。覆盖>256KiB含短尾数据、截断/提前流尾/额外尾部，Apple链接仍需Xcode验收。UTF8 flag/边界/支持方法由最小中央目录顺序校验补齐，不扩成通用ZIP实现。

测试先失败后实现：存储/deflate、中文UTF8和GB18030、chapter自然顺序、深度>5、跳坏首图、越界/绝对/盘符/规范化重复/metadata重复、声明预算与50001条、损坏CRC/截断/后部加密条目/ZIP64计数、取消清理、重开阅读。测试fixture用确定性ZIP字节或库创建后定点破坏，不引入运行时shell。UIKit新增压缩包选择与清晰中文状态，保持安全作用域直至任务完成；parse不是Xcode验收。依赖、核心、UI分清验证，独立审查后更新矩阵。

### Task 24: 18漫画适配器与验证判定规则

先读同计划账本目录mh18-research.md，再完整读Android Mh18ComicSource.java、Mh18ComicSourceTest、Mh18WebViewSession.java静态规则837..991及Mh18WebViewSessionTest。新增Mh18ComicSource.swift、Mh18VerificationRules.swift、ComicBrowserSession.swift及对应测试；ComicSource.swift只允许向HTTPResponse增加默认空响应header字典与URLSession返回头，保留既有初始化调用兼容。真实URLProtocol测试验证cf-mitigated字段传输及大小写无关查询，不能只测手造响应。

ComicBrowserSession: Sendable，async throws fetch(_ url: URL) -> String / fetchInteractive(_ url: URL) -> String。适配器可注入browserSession与HTTPTransport，默认id mh18、名称18漫画、base/referer https://18mh.org[/]。当前任务不注册：先保留可测试的浏览器会话边界，Task25实现真实WK消费者再注册。非交互挑战抛typed verificationRequired，不弹窗口、不自动破解。verifyAccess明确调用interactive并要求hasCatalogMarker。

请求/解析以Android当前公开路径逐项移植：搜索Java form编码和/page/N，分类tag优先genre/all及动态两组；cardtitle结构、去重、slug标题回退；JSON-LD ComicSeries含@graph、数组@type及meta属性顺序无关的fallback，作者/状态/标签，详情不预取目录。目录/chapterlist/{id}读取allchapters data-mid/data-host，再/manga/get?mid=N&mode=all；章节chapterContent data-ms/data-cs/data-ct，再/chapter/getcontent?m=N&c=N。data-host只HTTPS配置根/点分子域与默认443，不请求外域；有效252章完整测试、data-src优先src、图片HTTP(S)顺序去重；无目录/正文清晰报错。直接网络UAChrome124 desktop、15s请求限制，对10s独立连接差异披露。配置session时主域及子域请求进入session（包括API）；返回仍检查取消。错误壳不伪装合法空结果。

Mh18VerificationRules移植HTTP/interactive/page/probe判定、挑战marker（排除普通precursor）、期望/manga路径/同协议根子域、Cloudflare挑战导航白名单、deadline120s/代次及成功条件。测试按Android现有18个会话案例扩展host相似域/错误协议/过期导航；避免仅测getter常量。所有核心测试先RED再GREEN；共享target与Task23串行，输出task-24-report.md并独立审查。该范围只实现adapter与规则，不能冒称WK验证可用。

### Task 25: 18漫画 WKWebView 会话、Cookie 与手动验证接线

使用系统WebKit，在UIKit新增Mh18BrowserSession及验证弹层，复用Task24协议/判定；MainActor管理WebView、continuations、定时/导航代次。AppEnvironment持有session并注入Mh18适配器，按Android默认相对顺序注册；SourceSettings增加该源验证入口与状态，用户主动进入，其他源无多余验证按钮。必须完整对照AndroidMh18WebViewSession及MainActivity站源验证调用，先读mh18-research.md完整研究再实施，不以简单Cookie复制替代浏览器网络上下文。

对照MainActivity.verificationRequiredState/showReaderVerificationRequired：发现单站/全站、详情、目录及阅读请求遇到typed verificationRequired时显示“需要验证/去验证”，点击到站源管理，不能只给网络重试或静默空页。全站错误需要保留验证状态类型，不能从中文字符串猜测。普通HTTP错误仍重试；取消不弹失败。验证成功后能从原错误页面重新请求，保留选中站源/关键词/章节位置，不能让旧请求覆盖新页面。当前没有下载队列，成功唤醒下载的消费者留待下载模块实现，不虚构已接线。

初始普通请求用HTTP+Cookie，同一session串行；首次/失效挑战仅返回需要验证。手动验证先HTTP预检，有有效漫画目录直接成功；只有挑战打开浏览器，普通失败留重试/关闭。固定UA/Accept-Language按Android，会话生命周期保持Cookie，平台第三方Cookie限制必须披露。WKWebView配置默认持久dataStore；URLSession收到的Cookie同步到WKHTTPCookieStore，WK新Cookie能供HTTP预检/图片请求使用（仅按真实URL域规则发送，不把某站Cookie污染其他源）。返回URL与协议/host验证，严禁关闭TLS校验。

信任边界补充：Task24纯规则为了对照保留Android sameSite的祖先域宽松语义及CF例外协议行为，UIKit不能单独依赖它。请求、导航与返回地址先约束到配置HTTPS根18mh.org或点分子域、443/默认端口、无userInfo；Cloudflare例外仅HTTPS/443的challenges.cloudflare.com及点分子域，且限既有挑战路径。拒绝org等祖先域、相似域、FTP/HTTP/自定义scheme和非默认端口。Cookie同样按实际域隔离。只收紧原逻辑在非业务地址上的信任，不改变正常本站跳转。

显式验证绝对单调120s deadline从创建开始，自动probe reload最多2次且不续期；DOM检查600ms、成功延迟600ms，过程中可关闭取消，用户重新加载创建新请求。浏览器DOM在当前/manga有真实card marker后，通过同一WebView网络fetch(credentials include/cache no-store/redirect follow)再验证目录；都成功才保留WebView并切后续请求到browser context。使用callAsyncJavaScript参数传值或同等安全方式，不拼接未转义URL/执行源站提供脚本代码作为解码器。请求取消中止网络，过期request/attempt/navigation不能完成新页面；失败/timeout停止探测但保留手动重试/关闭，不自动操作验证码。retained context失效返回需要验证，不悄悄无限循环。关闭/缓存清理/进程终止完成所有continuation并释放UI。

状态机与协调可用注入driver/clock测试实际并发、取消、超时、陈旧probe、两次恢复和手动重试；不为UIKit包装每个系统方法建框架。UI测试验证进入/关闭/错误重试入口并明确Windows未运行。至少原生代码syntax parse，真实WebKit网络/Cookie/验证、Apple类型检查与设备验收始终单列未完成，不能把Linux状态机GREEN称为站点可用。独立审查后再更新矩阵。

### Task 26: JM图片分片还原核心与原生图像接线

对照完整JmImageTransform.java及JmImageSlicesTest.java，MainActivity.decodeReaderImage/restoreJmReaderImage。最小JmImageTransform Swift实现官方公开图片格式：URL仅HTTP(S)的cdn-msp*.18comic.vip域与/media/photos/{aid}/{filename}，且scramble_id为非负Int64；低于scramble不还原，aid<268850固定10片，否则MD5(aid+不含末尾扩展名的filename)的最后一个小写十六进制字符ASCII值%divisor*2+2，aid>=421926 divisor8否则10，不能用十六进制数值替代字符。利用Apple原生CryptoKit/Linux已安装OpenSSL，不新写MD5算法/新增依赖。边界高度小于片数保持原样；分片余数放目标首片，源行逆序且每片内部不倒置。

先跨平台RED/GREEN：Android1114754/220980/00010.webp与jpg均4片、阈值、ASCII字符公式、1499/14全源与全目标覆盖、不重叠、不丢行、非法或无关URL/端口/凭据不改图、取消。Apple CoreGraphics还原复用同一bounds，在RemoteImageView正文缩略解码后、白边/墨水屏前运行（Android亦先缩放再还原），不更改文件与网络数据；分配/裁片失败明确失败不能把乱序图显示为成功。Apple条件像素测试验证带余数色条的行重排，但Windows明确未执行。JM站源/浏览器尚未注册，本任务不冒称JM阅读完整可用；离线transformation元数据接线留待下载模块。与Task25源/会话文件不重叠，核心构建协调串行，审查独立。

### Task 27: 漫画柜解析与站源移植

先完整读本账本manhuagui-research.md及Android ManhuaguiComicSource.java、SourceConfig.manhuagui、tools/check-manhuagui-parser.js。Java是逻辑基准，JS内已有真实压缩字典和可重复fixtures可复用，不把旧sim或mock脚本的简化逻辑当权威。新增ManhuaguiComicSource.swift、最小packed/LZ数据解析及tests，不执行站点代码，不引入WebView/eval/新依赖。已有CopyMangaLiteral保序数据解析可重用，但其现有严格默认不能变宽；如明确loose模式支持漫画柜裸键/标识符值，须覆盖默认仍拒绝表达式以及引号内文本不被改写，不能全局regex替换字符串内容。避免重复造通用JS解释器。

默认漫画柜/idmanhuagui/https://www.manhuagui.com，referer结尾slash；/list及/comic/id不带尾slash，分类segment按region/genre/audience/year/letter/state顺序以hyphen连接，page>1/index_pN.html；搜索/s/{Java表单编码keyword}.html只第一页。六类动态筛选、bcover属性顺序/title→imgalt/data-src→data-original→src、ID去重和空列表错误；详情h1/author/status/intro-cut/latest及多级cover最终cf.mhgui.com/cpic/b/id.jpg，详情不预取目录。目录只同bookID、href去重、title属性优先、numericchapterID顺序与Int32溢出fallbackindex。

正文优先嵌套packer最多depth4，然后SMH.imgData/两种bracket形式，最后对象形状fallback。保留Java实际字典选择顺序：raw→LZdecoded，给定sep→pipe→comma，先达到count否则最多项；真实dictionary长度大于declaredcount也须使用，base62 ASCII tokens单次替换，不对replacement再次替换。括号/引号/反斜杠边界按data读取；数字溢出、不合法radix、截断LZ和递归/展开预算清晰失败，不能卡死或无限分配。标准库与现有依赖无LZString，可最小UTF16按位字典解码；输入/展开及累计字典上限每类32MiB、字典条目<=262144、深度4，循环检查取消。限制在报告披露，正常fixture不得削减。

最终图像固定eu2.hamreus.com，path逐段JavaURLEncoder再+→%20，files顺序去重，e/m签名值按原格式；只发布有效HTTP(S)完整列表。保留普通Chrome150导航请求头和正文30s/普通15s超时（独立15/10s连接限制平台差异披露）；URLSession负责gzip，响应已有headers可手动处理未跟随的Location并最多5次，主站HTTP重定向规范为HTTPS。不得关闭TLS。真实平台自动重定向限制与站点可用性单列，不以fixtures冒称网络通过。

RED→GREEN覆盖工具原样3cards、111/112章节、封面fallback、direct/loose/bracket、无效token跳过再有效、多层/双引号packer、稀疏count2但index197字典、LZ样本完整29图和精确第三图URL、百分号中文路径、输入顺序fallback、坏参数/展开预算/取消，以及源网络header/path/分页/归属。必要fixtures从本地工具静态提取并保留为测试资源，不抓取真实受限内容。单任务报告task-27-report.md；完成后父代理独立审查再注册，保护Android与所有既有测试。

### Task 28: JM站源解析与验证判定

**Files:** 新增 `ios/ComicCore/Sources/ComicCore/JmComicSource.swift`、`JmVerificationRules.swift`，对应 `JmSourceTests.swift`、`JmVerificationRulesTests.swift`；不修改UIKit、Mh18生产端、图片还原或注册。完整读同计划账本 `jm-research.md`、Android `JmComicSource.java`、`JmComicSourceTest.java`、`JmComicWebViewSession.java`、`JmComicWebViewSessionTest.java` 和 `SourceConfig.jmcomic`。

**Interfaces:** 复用现有 `ComicSource`、`ComicBrowserSession` 和 `HTTPTransport`。`public actor JmComicSource: ComicSource`，nonisolated id/name/referer；init默认 `baseURL:URL=https://18comic.vip`、`name:String=禁漫天堂`、`transport:any HTTPTransport=URLSessionHTTPTransport(timeoutInterval:25)`、`browserSession:(any ComicBrowserSession)?=nil`。提供 `public func verifyAccess() async throws`、`public static func hasCatalogMarker(_ html:String)->Bool`。`JmSourceError` 是Equatable/Sendable/LocalizedError，case verificationRequired、invalidResponse(String)，不能复用Mh18站名错误。`JmVerificationRules` 提供 `HTTPAction { returnBody,verificationRequired,fail }`、`httpAction(statusCode:mitigated:body:)`、`isChallenge(url:title:body:statusCode:mitigated:)`、`isExpectedPage(requested:URL,actual:URL)`、`verificationComplete(browserCatalog:probeCatalog:)`、`probeCanComplete(activeAttempt:probeRunning:stopped:capturedNavigation:currentNavigation:)`、`requiresCredentialReset(storedFingerprint:String?,currentFingerprint:String?)->Bool`。纯规则保留Android结果；真实WK信任边界另行接入。

- [ ] 先建真实fixture行为测试和必要接口骨架，运行断言级RED；不要将只有缺失类型的编译失败称为行为RED。
- [ ] 逐项移植列表、搜索、分类、详情、目录和正文。latest `/albums?o=mr&page=1`，search `/search/photos?main_tag=0&search_query={Java表单编码}&page=N`，theme `/theme/`，detail `/album/{id}`。page至少1，删除原数字page参数后追加，保留其他query。UA desktopChrome124、Referer根slash、Language zh-CN,zh;q=0.9；session注入只走根/点分子域，interactive明确调用fetchInteractive。取消前后检查、HTTP错误传播，挑战typed错误与普通错误分开。不加入真实网络依赖。
- [ ] 卡片slug数字ID，title→alt，data-original→data-src→src，保持Java先seen再校验title的行为；hasCatalogMarker只需album链接内部img，与有效卡片列表不同。latest任何页空拒绝，defaultcategory第一页空拒绝，filteredcategory/search/后页defaultcategory允许空。theme h4与其后1600字符内btnmg，七组规范label按Android；成功组缓存，失败不缓存。分类取有效theme选项：UI原本互斥，因此正常只一个；同时传多个时按theme数字索引选第一个，避免Swift Dictionary随机顺序，记录与原LinkedHashMap外部构造顺序的差异。
- [ ] detail和chapters共用最后一个非空详情HTML缓存，保持不同作品隔离；actor重入时同作品并发合并为一个在途读取或明确测试请求行为，不能跨作品错用。标题book-name→og:title，作者main_tag=2、标签search/photos及完结/连载，范围book-name至episode排除推荐；封面仅当前albumID匹配，album_photo_cover优先；目录懒加载。episode div平衡范围内href数字photo且data-album相等、h3.h2_series标题、去重保序；无目录时仅read-block明确开始/继续阅读按钮回退第1话，排除read_mode与推荐。
- [ ] 正文aid/scramble_id/cdnImgHost/page_arr无需尾分号。图片按数组保序，保留重复项、跳空字符串，绝对HTTP(S)项保留，否则cdn/media/photos/aid/file；追加scramble_id时正确使用?或&，不得丢失已存在query。复用已有数据字面量解析（数组单双引号等AndroidJSON可接受行为），不执行JS；拒绝不能安全表达的URL/整数溢出/非法数组，报告边界。不要新增图片还原算法。
- [ ] 纯规则照AndroidJM列表移植，不能直接调用Mh18的额外challenge markers：JM不含 `_cf_chl_opt` 和 `challenge-error-text`。/albums原始路径、尾slash规范；sameSite纯helper保留祖先/端口语义但注释不是安全边界。fingerprint null current不重置，stored nil视空；同chrome124-v1不重置。
- [ ] GREEN覆盖Android完整源/会话fixtures，补互斥多值确定顺序、详情缓存隔离、真实请求头/path、错误/取消、重复图片和已有query、编码路径不得被解码成/albums。示例断言：`XCTAssertEqual(page.imageUrls[0], "https://cdn-msp2.18comic.vip/media/photos/1114754/00010.webp?scramble_id=220980")`；主题七组按热门/类别/排行榜/主题/角色/特殊/其他。测试使用真实适配器+捕获transport/session，禁止镜像生产实现的假解析器。
- [ ] 在固定 `/work` Docker挂载运行 `swift test -j 2 --filter 'JmSourceTests|JmVerificationRulesTests'`，最后一次全量并diffcheck，报告 `task-28-report.md` 给父代理提交与独立审查。不称JM可用、不注册；原生JM会话后续单独实现。

### Task 29: 四站分类选项互斥

**Files:** 新增 `ios/ComicCore/Sources/ComicCore/SourceFilterSelection.swift` 与 `Tests/ComicCoreTests/SourceFilterSelectionTests.swift`；修改 `ios/XXComic/DiscoverViewController.swift` 的FilterViewController option action。完整对照Android MainActivity.java 9028附近点击选项分支及8730附近选项初始化。

**Interface:** `public enum SourceFilterSelection`，`public static func select(sourceID:String,key:String,value:String,groupKeys:[String],in selection:inout [String:String])`，仅集中一个实际生产规则，无状态机/新依赖。代码先写 `selection[key] = value`，若 `value != "all" && ["mh160","gmh","mh18","jmcomic"].contains(sourceID)`，遍历groupKeys中非当前key设为all。普通源保持其他筛选，选all不清其他，旧未知key按Android保留。UIKit点击直接调用此函数并render；草稿/确认/关闭/换源不变。

- [ ] 测试先写：四个源从genre=a切tag=b得到genre=all/tag=b；选all只改单键；普通源多组选项共存；换同组不破坏未知key。以旧仅改单键行为为RED，明确错误断言输出。
- [ ] 实现最少函数并真实接到现有按钮action，GREEN定向SourceFilterSelectionTests；Core不与其他任务共享构建并发。UIKit全文件syntaxparse，报告原生交互未执行。
- [ ] 报告task-29-report.md，父代理提交/独立审查；同步PARITY的分类互斥修复与Apple待验收，不将helper测试当UIKit交互通过。

### Task 30: 已接入站源搜索首尾字符语义

**Files:** `CopyMangaComicSource.swift`、`D5d6ComicSource.swift`、`GmhComicSource.swift`、`AntbywComicSource.swift`、`Mh160ComicSource.swift`、`HiperdexComicSource.swift`、`Mh18ComicSource.swift` 内keyword规范化一行；新增 `ios/ComicCore/Tests/ComicCoreTests/SourceSearchTrimTests.swift`。漫画柜由Task27负责同项，不混入此任务。

**Contract:** Android这些源对keyword使用Java String.trim，只去UTF16<=0x20，Swift Foundation.whitespacesAndNewlines额外去NBSP/全角空格。使用已有 `SearchRules.trim(keyword)` 替换恰好七处keyword规范化，不改标题/HTML/Cookie/host清理、路由、编码函数或其他行为；不新增通用trim或新依赖。完整对照这七个Androidsearch方法及现有Swifttests的transport注入方式。

- [ ] 捕获真实适配器HTTP请求，先RED再改代码：`" \t\u{00A0}词\u{3000}\r\n"` 结果只去ASCII边界，URL仍含 `%C2%A0%E8%AF%8D%E3%80%80`；Copy还验证只含NBSP时仍发请求，而全ASCII空白返回空且不请求。HTML/JSON返回可用最小各站fixture，不真实联网；不能只测试SearchRules函数或复制编码实现当oracle。
- [ ] 改七处一行，定向 `swift test -j 2 --filter SourceSearchTrimTests` GREEN；随后既有七源相关测试覆盖返回行为，不重复不相关全量。保持原URLEncoder与HiperDEX空格%20差异。
- [ ] 报告task-30-report.md，父代理提交/范围审查，登记无新功能只是已有Android业务对齐。

### Task 31: EPUB 解析与目录核心（暂停新增站源后的首项功能）

**Files:** 新增 `ios/ComicCore/Sources/ComicCore/EpubPublication.swift`（值模型/章节边界）、`EpubParser.swift`（OPF/nav/NCX/XML解析）、`EpubArchive.swift`（只读按需ZIP资源访问），新增 `Tests/ComicCoreTests/EpubParserTests.swift`。复用现有 ZIPFoundation、ZIPDirectory、ZIPDeflate，不修改现有漫画ZIP导入逻辑、UIKit、LocalLibrary持久化格式或站源。完整读取 Android `ebook/EpubParser.java`、`Publication.java` 和 `EpubParserTest.java`；本计划账本 `ebook-pdf-research.md` 为背景，源码为准。

**Interfaces:** `public enum EpubParser { public static func parse(archive: URL) throws -> EpubPublication }`。`EpubPublication: Codable, Equatable, Sendable` 含 title/author/description/language/opfPath:String、coverEntry:String?、有序manifest:[ManifestItem]、spine:[SpineItem]、navItems:[NavItem]、isFixedLayout/isPurePictureEpub/isReflowableText/hasDrm/hasFontObfuscation:Bool、unsupportedReason:String?。嵌套值类型字段逐项对应Java（id/href/mediaType/properties；idref/fullZipPath/mediaType/linear/resolvedImageEntry；title/href/spineIndex/children）。公开 `chapterRanges(overrideTitle:String? = nil) throws -> [ChapterRange]`，ChapterRange的title:String、startIndex/endIndex:Int（半开区间），只负责Publication边界规则，不制造文件或页面URL。`EpubError: Error, LocalizedError` 提供清晰中文原因；取消原样传播。

**资源与安全裁定:** EpubArchive内部只读，现有ZIPDirectory校验条目数量/大小/中央目录；按UTF8与全局GB18030回退规则找条目，拒绝重复规范路径、符号链接、绝对/越界/NUL路径；使用ZIPDeflate和Archive.extract校验真实输出大小/CRC。不要一次加载整本书或提取全包。单次XML读取最多8MiB，XHTML单图检查仅保留首1MiB但流式校验完整条目CRC，单条128MiB/总包20GiB/50000项继承现有限制，累计解析读取预算256MiB（重复读取也计入）。XML使用FoundationXML.XMLParser，禁用外部实体；拒绝DOCTYPE/ENTITY（覆盖UTF8/16/32编码），节点数最多100000、嵌套最多128并检查取消。损坏encryption.xml明确失败，不沿用Android吞掉加密声明错误。此项比Android对异常文件更严格，记录兼容性边界，不宣称完全相同。

- [ ] 先用最小可执行接口骨架和真实临时EPUB ZIP文件建立断言级RED（不是缺类型编译错误）。复用现有ZIPFixture或ZIPFoundation创建fixtures，不手写解析器当oracle。至少先验证spine顺序和文本分类。
- [ ] 实现container/rootfile选择（首个非空，后续匹配media-type覆盖）、OPF元数据/有序manifest/非空spine/id唯一及缺失引用错误。资源href使用Java URLDecoder的加号变空格语义，再去fragment和规范路径；使用现有SearchRules.trim；禁止路径逃出包。linear=no仍保留。单图wrapper兼容img和SVG image，仅一个图片且条目存在时归类图片。分类/封面顺序和固定布局标记逐项按Java，字体混淆与DRM区分，hasDrm可返回元数据但chapterRanges拒绝阅读。
- [ ] EPUB3 nav优先，空/普通XML格式错误则回退NCX；取消、预算或不安全XML错误必须传播，不静默fallback。嵌套目录保留，映射到第一个匹配spine索引，无法映射为-1。chapterRanges展平有效导航、稳定按spine排序、去同边界；伪页目录折叠；前置未映射正文补“封面与序言”；无目录默认书名或“全 1 卷”；显式overrideTitle优先。

```swift
let publication = try EpubParser.parse(archive: fixture)
XCTAssertEqual(publication.spine.map(\.fullZipPath), ["OEBPS/text/01.xhtml", "OEBPS/text/02.xhtml", "OEBPS/text/10.xhtml"])
XCTAssertEqual(try publication.chapterRanges().map(\.startIndex), [0, 2])
XCTAssertFalse(publication.spine[1].linear) // still present in reading order
```

- [ ] GREEN覆盖Android完整fixtures：spine非文件名顺序、NCX/nav、SVG/direct image、封面优先级、字体混淆/DRM、纯文本/混合、缺container/spine、UTF8 BOM、路径越界、XXE不读外部内容。补：linear=no、重复id/无效idref、伪页折叠/序言/override、nav损坏回退、坏encryption失败、Unicode空格/加号与percent路径、实际deflate/CRC坏包、取消、XML预算/嵌套上限。应断言业务结果，不仅“不崩溃”。CRC/取消不得被wrapper可选解析吞掉。
- [ ] 固定/work Docker运行 `swift test -j 2 --filter EpubParserTests`，涉及包读取的现有 `LocalArchiveTests` 回归一次；不重复不相关全量。报告 `task-31-report.md` 含真实RED/GREEN与限制。父代理提交、独立审查。此交付仅解析核心，不称用户已能导入/阅读EPUB；下一项需扩展旧manifest兼容的正文类型、导入与阅读接线。

### Task 32: EPUB 本地导入、旧书架兼容与按需资源

**Files:** 修改 `ios/ComicCore/Sources/ComicCore/LocalLibrary.swift`、`LocalComicSource.swift`，必要时最小扩展 `EpubArchive.swift` 的流式资源写入接口（复用同一CRC/预算/取消逻辑，不复制解压器）；新增 `LocalEpubLibrary.swift`、`Tests/ComicCoreTests/LocalEpubLibraryTests.swift`。消费Task31复审后的EpubParser/EpubPublication/EpubArchive，不修改UIKit或站源。本任务是持久化/资源读取层，用户入口与原生阅读在下一任务接入，不先展示不可读导入入口。

**Archive预算衔接:** Task31解析器的每实例累计256MiB默认值保留。导入逐图验证可能合法超过256MiB，可给内部EpubArchive.init增加默认256MiB的累计读取上限参数，仅导入验证实例使用20GiB；流式write与read共用同一计数/CRC/取消循环。避免每张图重开扫描整个ZIP形成平方工作量。重复资源先验证一次（spine token仍保留重复位置），封面优先复用已验证候选结果或在读取预算内再读；预算耗尽必须明确失败而非吞掉。单项128MiB和ZIP声明总量20GiB限制不放宽。

**Interfaces:** LocalBook增加可选 `epub:EpubPublication?`、`coverName:String?`，公开init参数默认nil，旧book.json无需迁移。新增LocalLibrary方法 `importEpub(title:String,archive:URL,isReadableImage:(URL)throws->Bool) throws -> LocalBook`、`epubResource(bookID:String,path:String,maximumBytes:Int) throws -> Data`、`epubImageData(pageURL:URL) throws -> Data`。仅EPUB书使用生成的 `spine-0`、`spine-1` 等唯一逻辑页token（同一资源重复出现在spine时仍是两页），原图片书pages仍是原有唯一叶子文件名；chapters仍严格分区pages。资源原文件固定为书目录 `content.epub`，封面候选验证后可保存固定 `cover.bin`，不从manifest接受任意文件系统路径。安全页URL为 `xxcomic-epub://page/<bookUUID>/<spineIndex>`：精确scheme/host、无userinfo/port/query/fragment、路径恰好UUID与非负十进制索引，拒绝编码绕过和越界；生成/解析生产逻辑集中一处。

- [ ] 先写真实ZIP临时文件的RED：导入并重开仍按spine顺序、chapterRanges映射准确、原包不改；图片token→真实资源字节；旧图片book.json缺新增key仍能读。使用Task31测试fixture构建方式，不重新实现测试解析器。
- [ ] 导入到 `.import-UUID`：分块取消可控复制原包（总20GiB，非单图128MiB），解析的是复制副本；拒绝DRM/空spine，逐项验证图片或文本资源存在。图片流式写一个临时probe文件调用实际注入probe，不全书常驻Data；坏图片使整次导入失败（与图片ZIP可跳过不同）。可最小扩展现有copy helper的单文件上限参数，旧调用默认128MiB；不复制整段copy实现。封面顺序按Publication：有效显式封面→第一个有效正文图→首个manifest图片；无有效图片保留nil供原生生成文字封面。清理probe文件后，写manifest并在最终取消检查后目录rename发布；失败/取消只清理本次staging，已有书与外部原包不改。
- [ ] books/book/pageURLs/summary分支验证EPUB元数据与逻辑token、spine数量/章节分区/封面叶子路径及owned content文件（拒绝符号链接逃逸）；旧图片路径校验不放宽。summary用已保存coverName，无封面空URL不伪造图片。LocalComicSource详情显示作者/简介/EPUB类型，目录使用导入chapterRanges；全图片章节返回安全页URL，含文本章节明确抛出需要文字阅读器的类型错误，由后续原生路由消费，禁止把HTML交给图片解码器。
- [ ] 按需资源只能读取指定已验证本地EPUB内规范路径；每个worker独立EpubArchive实例，不跨线程共享ZIPFoundation。Data输出受调用上限和包上限约束，CRC/取消原样传播，不返回半截正文。`epubImageData`检查token索引和resolvedImageEntry存在；文字页URL不能伪装成图片读取。后续native图片加载将在后台调用该方法。

```swift
let imported = try library.importEpub(title: "文件名标题", archive: fixture, isReadableImage: { _ in true })
let reopened = try LocalLibrary(directory: library.directory)
XCTAssertEqual(try reopened.book(id: imported.id), imported)
XCTAssertEqual(imported.pages, ["spine-0", "spine-1"])
XCTAssertEqual(try Data(contentsOf: fixture), originalBytes)
XCTAssertThrowsError(try reopened.epubImageData(pageURL: URL(string: "xxcomic-epub://page/invalid/0")!))
```

- [ ] GREEN覆盖新旧混合书架、正文重复资源、真实按需字节/非图片拒绝、缺资源/坏图/DRM、取消复制及取消probe不发布、损坏manifest/路径和符号链接逃逸、原包保留、无图文本书合法导入。测试注入probe仅替代ImageIO边界，不能用假解析器。运行LocalEpubLibraryTests与现有LocalLibraryTests/LocalFolderTests/LocalArchiveTests相关回归，报告task-32-report.md；父代理提交/独立审查。Apple probe/文件授权及最终UI仍未验收。

### Task 33: 文字排版设置和独立阅读位置持久化

**Files:** 新增 `ios/ComicCore/Sources/ComicCore/TextReaderPreferences.swift`、`TextLocator.swift`、`Tests/ComicCoreTests/TextReadingTests.swift`；修改 `LibraryStore.swift`。不修改UIKit、站源或Task32导入实现。原版对照 `app/src/main/java/com/xxcomic/ebook/TextLocator.java`、`TextReaderSettingsSheet.java`、`TextReaderView.java:setSettings`、`app/src/test/java/com/xxcomic/ebook/TextLocatorTest.java`。

**Interfaces:** `TextReaderTheme:Int,CaseIterable,Sendable` 为light=0/sepia=1/dark=2；`TextReaderPreferences:Equatable,Sendable` 有fontSize:Int、lineHeight:Double、theme:TextReaderTheme、pagedMode:Bool，默认18/1.75/dark/false。`TextReaderPreferencesStore(defaults:UserDefaults = .standard)` 提供load()/save(_:)；键前缀 `text.reader.`，后接fontSize/lineHeight/theme/pagedMode，不覆盖漫画设置。`TextLocator:Codable,Equatable,Sendable` 有bookID:String、chapterIndex:Int、spineIndex:Int、resourceHref:String、anchorID:String、scrollPercentage:Double、charOffset:Int，公开完整init，anchorID/scrollPercentage/charOffset默认空/0/0；属性let。`LibraryEntry` 添加可选 `textPositions:[String:TextLocator]?` 保持旧JSON兼容。`LibraryStore.textPosition(for:ComicSummary,chapterID:String)->TextLocator?` 和 `saveTextReading(_:ComicSummary,chapter:Chapter,chapterIndex:Int,locator:TextLocator,now:TimeInterval=Date().timeIntervalSince1970)throws`。一次原子写更新历史ReadingRecord及文字位置；历史兼容ReaderPosition取默认零位置，绝不能把正文spine索引误当漫画图片位置或覆盖原positions。原有saveReading不删除文字位置。

- [ ] 先真实RED验证默认值/设置重开/旧书架JSON解码、独立文字位置保存后重新打开及favorite取消保留文字记录。使用临时UserDefaults suite与真实临时文件。

```swift
let initial = TextReaderPreferencesStore(defaults: defaults).load()
XCTAssertEqual(initial.fontSize, 18)
XCTAssertEqual(initial.lineHeight, 1.75)
XCTAssertEqual(initial.theme, .dark)
XCTAssertFalse(initial.pagedMode)
let locator = TextLocator(bookID: comic.comicId, chapterIndex: 2, spineIndex: 5,
    resourceHref: "OEBPS/chapter2.xhtml", anchorID: "section_1", scrollPercentage: 0.45, charOffset: 120)
try store.saveTextReading(comic, chapter: chapter, chapterIndex: 2, locator: locator, now: 123)
XCTAssertEqual(try LibraryStore(directory: directory).textPosition(for: comic, chapterID: chapter.chapterId), locator)
```

- [ ] 最小实现：load/save统一字号12...32，行距1.2...2.5（UI下一任务只提供1.5/1.75/2），非有限行距回默认1.75，未知主题回dark。文字位置init和decode均将负索引/offset归0、百分比夹0...1，非有限百分比归0；decode缺字段走空/0，与原版缺字段语义一致；类型损坏抛解码错误。Codable键沿用Android bookId/anchorId等拼写。保存拒绝comic.sourceId不是local、bookID不匹配comic.comicId、locator.chapterIndex与有效chapterIndex不一致、空resourceHref；中文typed错误，不能默默存错书。资源安全/本书spine范围由消费层使用Task32书籍校验，位置模型不发明路径解析。
- [ ] 复用LibraryStore.persist原子保存，内存更新发生在落盘成功之后；保持favoriteAt、漫画positions和其他章textPositions。JSON坏数据不能重建空库覆盖原文件。不另建文字历史数据库/计时器/缓存。
- [ ] GREEN覆盖负值/越界/非有限数、JSON缺键和roundtrip、两章位置、旧数据兼容、写入失败内存不变、错误bookID拒绝、漫画与文字设置/记录互不覆盖；运行TextReadingTests和既有LibraryStore/ReaderPreferences相关回归（先rg确认实际测试名）。报告task-33-report.md，父代理提交/独立审查。此任务没有文字UI，不能称阅读器已完成。

### Task 34: EPUB 图片阅读接线及文字显示资源边界

**Files:** 新增 `ios/ComicCore/Sources/ComicCore/EpubReaderResource.swift`、`Tests/ComicCoreTests/EpubReaderResourceTests.swift`；修改 `ios/XXComic/RemoteImageView.swift`、`ReaderViewController.swift`。本任务不提前开放EPUB导入按钮；Task35原生文字阅读完成后统一开放。复用Task32资源API，不增加解压库/HTML解析库。

**Interfaces:** `EpubReaderResource` 公开静态 `url(bookID:String,path:String,fragment:String?=nil)throws->URL`、`path(from:URL,bookID:String)throws->String`、`mimeType(path:String,publication:EpubPublication)->String`。正文资源使用独立scheme `xxcomic-book://<UUID小写>/<按路径组件编码的ZIP路径>`；不与图片页URL混用。url生成前验证UUID与非空规范路径；path解析要求精确scheme、匹配bookUUID小写host、无userinfo/port/query、单次percent解码，允许fragment但不计入资源路径；拒绝NUL、反斜线、绝对/空路径、点/父段、空段、编码分隔符、编码点段。加号是路径文字，不用Java URLDecoder再次解码已经规范的ZIP路径。literal `%20` 文件名生成 `%2520` 后必须恢复成literal `%20`，不能双解码。MIME优先按manifest规范路径匹配，其次只支持已知扩展html/xhtml/css/jpg/jpeg/png/gif/webp/svg/ttf/otf/woff/woff2，未知为application/octet-stream；manifestMIME不直接拼进HTML。

- [ ] 真实RED覆盖同书URL与中文/空格/加号/百分号路径roundtrip、fragment、外书UUID、host欺骗（包括percent编码host，用percentEncodedHost核对原始host）、userinfo/port/query、编码斜杠/点段/反斜线/双解码案例。资源契约只定位包内条目，不自动请求网络。

```swift
let id = "A2DA4DA0-271B-4B86-86E4-814D4DD6249B"
let url = try EpubReaderResource.url(bookID: id, path: "OEBPS/文+字%20.xhtml", fragment: "引言")
XCTAssertEqual(try EpubReaderResource.path(from: url, bookID: id), "OEBPS/文+字%20.xhtml")
XCTAssertThrowsError(try EpubReaderResource.path(from: URL(string: "xxcomic-book://a2da4da0-271b-4b86-86e4-814d4dd6249b/OEBPS/%2e%2e/a")!, bookID: id))
```

- [ ] RemoteImageView.load增加默认nil的 `epubImage: (@Sendable (URL)throws->Data)?` 参数，只在精确 `xxcomic-epub` scheme时调用该resolver；没有resolver走明确失败，不交URLSession。后台Task读取，withTaskCancellationHandler转发取消到worker；generation继续保护缓存/尺寸/失败回调。HTTP/file既有行为保持，单图上限仍128MiB、解码沿现有ImageIO。ReaderViewController仅local源注入捕获Sendable LocalLibrary副本的epubImageData；ReaderImageCell.configure→retry保存并传递resolver，prepareForReuse清理。不能扩大file路径白名单或全局注册URLProtocol。
- [ ] Core GREEN后仅做相关回归，UIKit全文件syntax parse与静态接线审查；不能把syntaxparse称Apple类型检查。写task-34-report.md，父代理提交/独立审查。UI入口仍未开放，后续Task35消费此正文resourceURL契约并添加安全WK渲染。

### Task 35: EPUB 全正文导航与原生文字阅读、导入入口

**Files:** 新增 `ios/ComicCore/Sources/ComicCore/EpubTextSession.swift`、`Tests/ComicCoreTests/EpubTextSessionTests.swift`；新增 `ios/XXComic/EpubTextReaderViewController.swift`（导航/位置/工具栏）、`EpubTextContentView.swift`（WK隔离文档/样式）、`EpubBookSchemeHandler.swift`（只读WK资源队列/取消/预算）、`TextReaderSettingsViewController.swift`（设置）、`TextBookCover.swift`（UIKit绘制封面）、`EpubUITestFixtures.swift`（仅同时启用--ui-testing与--epub-fixtures时生成真实EPUB并导入UITest隔离目录，重启保留身份和位置）；修改 `ComicGridViewController.swift`、`DetailViewController.swift`、`RemoteImageView.swift`、`AppEnvironment.swift` 接入口/默认文字封面/设置实例；在 `ios/XXComicUITests/EpubReadingUITests.swift` 添加原生验收用例。复用Task32–34最终审查接口，只有完成本任务才显示EPUB导入按钮。不要拆成占位页面交付。

**Core interface:** `EpubTextSession:Sendable` 持有已结构验证的LocalBook，公开只读chapterIndex/spineIndex和当前entry:EpubPublication.SpineItem；`init(book:LocalBook,chapterIndex:Int,locator:TextLocator?) throws`、`mutating selectChapter(_ index:Int)throws`、`mutating moveSpine(delta:Int)->Bool`、`mutating navigate(path:String)->Bool`、`locator(anchorID:String="",percent:Double,charOffset:Int=0)->TextLocator`。章节来自book.chapters的pages token→book.pages索引，不重新按目录名排序；初始化章节越界夹合法范围，错误分区/无EPUB/DRM/空spine拒绝。恢复位置必须bookID/章节/资源路径/spine索引都对应当前章，失效回本章首spine；同路径重复出现以locator索引恢复，内部链接优先本次spine否则首匹配。moveSpine只接受±1，按完整spine顺序跨章，每次恰好一步，边界false不改状态。navigate仅接受本书spine内规范路径。文字/混合书按全部spine可读，保留图片条目；纯图片书仍共用漫画阅读器。

**Fixture dependency:** 允许修改`ios/project.yml`给app显式连接已安装的ZIPFoundation product，URL与ComicCore一致且固定`exact 0.9.20`，不得改为from范围或新增ZIP实现。仅双参数隔离fixture生成真实EPUB使用；Apple工程生成/包解析未运行需报告，不以YAML静态检查代替。

- [ ] RED核心覆盖一章多正文/同href重复出现/混合图片/跨章/旧位置不匹配与越界，使用真实EPUB fixture解析并importEpub得到book，不手造不成立模型。GREEN后才原生接线。

```swift
var session = try EpubTextSession(book: book, chapterIndex: 0, locator: nil)
XCTAssertEqual(session.spineIndex, 0)
XCTAssertTrue(session.moveSpine(delta: 1))
XCTAssertEqual(session.spineIndex, 1) // 一章包含两个正文时，第二个不能丢失
XCTAssertEqual(session.chapterIndex, 0)
```

- [ ] 原生文字view使用非持久WKWebsiteDataStore、每书专属WKURLSchemeHandler，只读Task34 `xxcomic-book` 本书资源。正文8MiB，资源128MiB，单次文档累计256MiB/1024请求/最多2个资源读取并行，超限明确失败；后台读取每次独立Archive，取消转发且stopURLSchemeTask后不得回调。页面切换/退出撤销所有旧worker和脚本回调，用generation与对应WK实例隔离；不得把上一正文的迟到scroll写进新位置。
- [ ] WK配置 `defaultWebpagePreferences.allowsContentJavaScript = false`，正文自己的script/eventhandler不能执行。自己的滚动/位置脚本在独立WKContentWorld中运行，使用callAsyncJavaScript arguments传anchor/percent/样式，禁止拼接书籍字符串进代码；脚本message handler弱引用并退出移除。编译并安装WKContentRuleList阻止http/https/ws/wss/ftp/file资源，编译失败不能展示正文。主文档开始处强制CSP default-src 'none'、script-src 'none'、img-src本书scheme与data、style-src本书scheme与unsafe-inline、font-src本书scheme、frame-src/object-src/connect-src 'none'、base-uri 'none'、form-action 'none'；规则与主导航delegate共同执行，不能只regex删除script。scheme handler只接受匹配书ID的路径，不允许任意file/网络委托。未知MIME不当HTML执行，明文text/plain需HTML转义，直接图片spine用转义URL的img文档承载。新窗口/重定向/非主框架导航默认拒绝；用户点击http/https外链弹确认再系统浏览器，其他scheme拒绝；书内链接用session.navigate+fragment或当前anchor。
- [ ] 样式按Android TextReaderView.generateCss对照：18px/1.75默认、字号12...32；浅FAFAFA/23272E/4C78A8、护眼F5EEDB/3F3222/8C6239、深12161F/C8D0E0/5E81AC；正文padding22px18px90px18px、段首2em、段间.9em、图片max-width100%/margin14px/radius4。排版变更立即保存并更新当前文档，保留位置；字体变化/旋转后恢复当前anchor优先，否则percent。120ms延迟恢复必须校验generation。进度上报最多每100ms，退出/后台同步保存最后有效位置；只有当前document成功可读才更新历史/阅读习惯，不把加载失败当已读。
- [ ] 工具栏上一章/下一章、进度0...100、目录/详情/排版/主题，主题循环0→1→2；目录复用55%/92%抽屉且选中真实chapter。一章多spine提供上一节/下一节与序号，确保全部内容可达（相较Android只读首正文的缺陷，账本已裁定修正）；进度代表当前正文。排版面板字号±1、行距紧凑1.5/标准1.75/宽松2、浅白/护眼/夜空、连续滚动/点击翻页，默认值由Task33读取。中央32%...68%单击切换控制条；边缘仅paged模式滚动0.88视口，多指/取消/拖动/链接点击不能误翻；仍可系统返回。接现有ReadingHabitTracker的enter/readable/user/overlay/tick/exit，面板时不累计阅读。
- [ ] Bookshelf添加EPUB文件选择和导入说明，标题默认文件名，原security-scoped后台worker及取消保留，调用Task32 importEpub+LocalImageProbe。不改已发布manifest来生成封面；无图片封面的本地书在grid/detail显示UIKit绘制600×900蓝渐变243B55→141E30、EPUB电子书徽标和书名作者，布局按AndroidgenerateTextCover；不生成AI图片。Detail.openReader针对本地非纯图片EPUB转文字reader，纯图片走Task34已接resolver的漫画reader。加载/损坏/取消分别展示，重试保留目标章，不把HTML传图片decode。
- [ ] 续读入口传入的chapters可能只有saved.chapter一个元素且index=0、incomplete=true，不能把这个临时索引当本地书真实chapterIndex。文字路由先后台读取本书完整章节，按传入目标chapterId匹配真实索引，再取该章textPosition创建session；目标章已失效则夹保存的真实reading.chapterIndex或回首章，并明确使用有效章locator校验。UIKit测试要实际从第二章退出后点“继续阅读”，验证回到第二章同一正文，不仅直接初始化Core章节2。
- [ ] 验证：EpubTextSessionTests真实核心RED/GREEN；UIKit全文件syntaxparse；原生UI用例覆盖导入文本/图文/纯图片、设置重启保存、正文跨页/目录/位置恢复、外链确认和退出（当前Windows不能运行，标记未验收）。为WK隔离/同书资源/旧回调编写可执行Apple测试或现有原生测试靶可承载的fixture场景，严禁静态字符串断言冒充WebKit行为测试。报告task-35-report.md，父代理提交/独立审查；Apple编译/WK规则和JS隔离/性能验收没有环境则明确列出，不能称完全1:1完成。

### Task 36: PDF 本地导入与按需原生渲染

**Files:** 新增Core `PdfPublication.swift`（页面尺寸/绘制尺寸规则）、`LocalPdfLibrary.swift`（持久化/受限页URL）、`PdfRenderer.swift`（条件CoreGraphics+ImageIO实现）、`Tests/ComicCoreTests/LocalPdfLibraryTests.swift`、`PdfRendererTests.swift`；修改 `LocalLibrary.swift`、`LocalComicSource.swift`、原生 `ComicGridViewController.swift`、`ReaderViewController.swift`、`RemoteImageView.swift`；若提取共有的本地页URL编码/解码，仅合并EPUB/PDF完全相同的规则，保留既有EPUB契约和回归。先完整读取Android `app/src/main/java/com/xxcomic/pdf/PdfParser.java`、`app/src/test/java/com/xxcomic/pdf/PdfParserTest.java` 和LocalContentResolver的PDF分支。无需新依赖/手写PDF解析器。

**Interfaces:** `PdfPublication:Codable,Equatable,Sendable` 包含有序pages:[PageSize]，PageSize公开width/height:Double与init；仅有限正尺寸、1...50000页合法。`PdfPublication.renderSize(width:Double,height:Double,maximumDimension:Int=2048)throws->PageSize` 实现Android min(2.5,max(1,targetMax/max(w,h)))并四舍五入，异常尺寸拒绝；在正常公式超过24M像素时额外等比缩小至24M（记录平台安全差异，不能无限分配）。LocalBook新增pdf:PdfPublication?默认nil，与epub互斥；旧JSON兼容。`LocalLibrary.importPdf(title:String,file:URL,inspect:(URL)throws->PdfPublication,renderCover:(URL)throws->Data?)throws->LocalBook`；`pdfPageData(pageURL:URL,render:(URL,Int)throws->Data)throws->Data`。固定owned `content.pdf`、可选`cover.bin`，逻辑页`pdf-0`等，单章“全本”，安全页 `xxcomic-pdf://page/<UUID>/<index>` 复用EPUB严格host/路径/索引/无query规则。渲染只允许本书范围，不能把任意fileURL传入native renderer。

- [ ] 真实临时源文件+注入平台inspect/render边界先RED：副本持久、页顺序/原包不改、旧JSON、空页/过多页/非法尺寸/双格式元数据拒绝、后台取消/失败只清本次staging、页URL攻击与越界、源/owned文件符号链接拒绝。注入假尺寸只能证明核心持久化，不当成PDF可解析证据。

```swift
let size = try PdfPublication.renderSize(width: 600, height: 800)
XCTAssertEqual(size.width, 1500)
XCTAssertEqual(size.height, 2000) // 最大2.5倍，与Android规则一致
XCTAssertThrowsError(try PdfPublication.renderSize(width: .infinity, height: 800))
```

- [ ] 复用Task32的分块copy（20GiB）、staging/manifest原子发布与ownedFile验证，不复制解压或文件copy。仅解析复制后的content.pdf。保存后验证与重开规则一致，临界值测试防止“导入成功却无法重开”。正文不在导入时全量转图片，只inspect逐页尺寸并渲染封面；图片页历史仍使用已有ReaderPosition，不使用文字locator。
- [ ] `#if canImport(CoreGraphics) && canImport(ImageIO)` 内 `PdfRenderer.inspect(_ url:URL)throws->PdfPublication` 使用CGPDFDocument，拒绝encrypted/isUnlocked不足、空页、损坏页，并逐页取消检查；pageIndex对外0基，CGPDFDocument.page(at:)内部+1。`render(_ url:URL,pageIndex:Int,maximumDimension:Int=2048,quality:Double=0.92)throws->Data` 每worker独立document，白色不透明底，正确应用页面box/rotation绘图变换，JPEG通过ImageIO写Data；cover使用page0/720/0.85，禁止网络或外部命令。取消在打开/尺寸/绘图前后/编码后检查，不承诺中断系统单次同步绘图。
- [ ] 添加真实Apple条件测试：用CGContext生成含白底/彩色定位块的两页PDF，实际inspect/渲染/尺寸/页序/旋转及坏页拒绝；Linux跳过须在报告单列，不能以mock或Swiftparse标记通过。Core尺寸安全及导入/页URL测试在Docker实际RED/GREEN；已有EPUB/图片/ZIP回归按改动范围一次验证。
- [ ] UIDocumentPicker加PDF，security-scoped后台复制照旧；生产inspect/render使用PdfRenderer，图片读取resolver只接受本地EPUB/PDF明确scheme，保留EPUBretry/reuse取消。LocalComicSource详情显示PDF/页数、目录“全本”，阅读共用漫画阅读器按需取页；不让文字书route误吞PDF。原生入口与后台渲染同一任务完成，失败提供明确提示/重试，不显示空白当完成。UIKitsyntaxparse、task-36-report.md、父代理提交/独立审查；PDFKit/CoreGraphics实际Apple编译与像素性能仍需Mac设备。

### Task 37: Kindle 容器识别与有界 PalmDOC 解压核心

**Files:** 新增 `ios/ComicCore/Sources/ComicCore/KindleFormatDetector.swift`、`PalmDoc.swift`、`Tests/ComicCoreTests/KindleFormatTests.swift`。本任务只建立可实际测试的格式边界，不提前开放MOBI导入按钮、不添加DRM解密或KF8重建、不修改Android。完整对照 `ebook/KindleFormatDetector.java`、`KindlePublicationAdapter.java:decompressPalmDoc` 及两份对应Java测试；后续转换层复用本任务结果与既有ZIPFoundation/EPUB存储。

**Interfaces:** `KindleVariant:String,Sendable` 为mobi7/kf8/combo/palmDoc/kfx/topaz/unknown/corrupt；`KindleDRM:String,Sendable` 为none/mobipocket/amazon/kfx；`KindleDetection:Equatable,Sendable` 只读variant/drm/isReadable/unsupportedReason:String?/title/author/compression:Int/encoding:String/recordCount:Int/firstImageRecord:Int/coverRecordIndex:Int/kf8BoundaryRecord:Int。`KindleFormatDetector.detect(_ file:URL)throws->KindleDetection`，正常不支持/坏格式返回typed结果，取消必须抛CancellationError而非转为corrupt；实际I/O失败抛错。`PalmDoc.decompress(_ input:Data,maximumOutputBytes:Int=8*1024*1024)throws->Data`，后续调用方先在16MiB内拼接正文record再调用，不能按record重置回溯字典。不引入新依赖或自写通用二进制框架；FileHandle限量读/seek、普通字节移位即可。

- [ ] RED先建真实PDB二进制fixture（临时文件，不mock检测器）覆盖中文书名/作者、UTF8与Windows-1252标记、MOBI7/COMBO/PalmDOC/KF8、KFX/Topaz/azw1魔数、扩展名伪装、DRM真实偏移和0xffffffff哨兵、空/短文件/乱序/越界record表、HUFF拒绝。PalmDOC用独立字节期望，不用被测算法反向构造oracle：

```swift
XCTAssertEqual(try PalmDoc.decompress(Data([65, 66, 67, 0x80, 0x18])), Data("ABCABC".utf8))
XCTAssertEqual(try PalmDoc.decompress(Data([0xC1]), maximumOutputBytes: 1), Data([32]))
XCTAssertThrowsError(try PalmDoc.decompress(Data([0x80, 0]))) // 距离0
XCTAssertThrowsError(try PalmDoc.decompress(Data([2, 65]))) // literal截断
```

- [ ] 识别严格遵循Java容器次序：小于8字节corrupt；先KFX/Topaz，PDB最少78字节，type BOOK/TEXt或creator MOBI满足其一；recordCount>0，table=78+8*n，offset unsigned32严格递增且在table后/文件内，record0至少16字节。compression仅1/2，其余unknown+明确HUFF说明；无MOBI头回PalmDOC。MOBI长度16...65536且完全在record0；字段偏移按Java而非网上另一版本猜测。仅小块读取表/头/title/EXTH条目，不Data(contentsOf:)读整本书；所有加法/转换先检查边界，记录循环取消检查。
- [ ] 书名先PDB Latin1零终止+SearchRules.trim，fullNameOffset优先record0相对再MOBI相对，长度最多65536；UTF8声明65001，否则书名Latin1，正文encoding标记Windows-1252。EXTH author100（UTF8）、boundary121、cover201，边界完全在record0、条目8...65536；保留Java遇到不合法条目停止解析的行为，EXTH总长度越界corrupt。DRM字段record0+168/172/176（不是188/196），以Int32语义解释负哨兵，encryption=1优先mobipocket，否则非0或有效DRM元数据为amazon。有效boundary优先COMBO，否则version>=8或type248为KF8且isReadable=false；cover索引安全加法并要求0..<recordCount。界面错误中文，对受保护/不支持/损坏区分，不伪称可读。
- [ ] PalmDOC输入最多16MiB、输出最多8MiB，maximumOutputBytes<=0返回空；检查取消（含运行中大输入）。0原样、1...8后续literal、9...127原样、128...191回溯distance/length、192...255空格+异或0x80字符。允许重叠回溯、跨record拼接后回溯；拒绝截断、distance0和超出已输出范围。每一分支都严格遵守输出上限，包括space+char仅剩1字节，不能复制Android该分支超写1字节及接近8MiB提前报错的缺陷。输出达到声明上限后不解析padding垃圾。Data动态增长须保持上限，不按输入*3无条件预分配大buffer。
- [ ] GREEN覆盖全部检测fixture，额外覆盖EXTH边界/标题偏移/索引溢出、PalmDOC声明截断/重叠/跨记录/最大边界/真实运行中取消。只运行本任务测试和实际受影响回归；写task-37-report.md，父代理提交并独立审查。这个阶段尚未转换/导入或接UI，不更新矩阵为Kindle完成。

### Task 38: Kindle 正文及图片转换为真实 EPUB

**Files:** 新增 `ios/ComicCore/Sources/ComicCore/KindlePublicationAdapter.swift`（限量读取与转换编排）、`KindleEpubWriter.swift`（内部HTML处理及ZIP输出）、`Tests/ComicCoreTests/KindlePublicationTests.swift`。只实现可读取的MOBI7/PalmDOC/COMBO→EPUB，不接UIKit/书架或修改Task37已审查规则；如需读取record表共用内部窄接口，须保持检测器行为及测试。原版 `KindlePublicationAdapter.java` 和其完整测试为对照。

**Interface:** `KindlePublicationAdapter.convert(source:URL,to destination:URL)throws->EpubPublication`，成功返回实际 `EpubParser.parse` 验证后的publication，destination必须原先不存在且不能等于source；不删除或覆盖既有文件。后台调用同步throws接口，Task取消始终传递。先检测Task37结果，isReadable=false抛中文错误，不尝试解密/外部转换。原书保留与书架原子发布留给下一整合任务，本任务生成可真实解析的派生文件，不称用户已可导入。

- [ ] RED用真实PDB fixture调用convert后通过既有EpubParser/EpubArchive读实际产物：两章小说、三图以上漫画、含布局空白的漫画、文字与recindex图片混排、指定封面、UTF8/Windows1252、压缩1/2、跨record回溯及声明正文长度。JPEG/PNG用可真实解码的固定微型图片字节，不以伪magic作为后续ImageIO通过证据。可在测试内部复用Task37的fixture builder，但不得变更断言语义。

```swift
let publication = try KindlePublicationAdapter.convert(source: mobi, to: derived)
XCTAssertEqual(publication.spine.count, 2) // fixture含两个pagebreak分开的正文
XCTAssertEqual(try publication.chapterRanges().map(\.title), ["第一章", "第二章"])
let archive = try EpubArchive(url: derived)
let first = try archive.read(publication.spine[0].fullZipPath)
XCTAssertTrue(String(decoding: first, as: UTF8.self).contains("第一章正文"))
XCTAssertEqual(try Data(contentsOf: mobi), originalBytes)
```

- [ ] 使用FileHandle读取并重新验证真实record边界；每正文record<=8MiB，压缩record累计<=16MiB，输出<=8MiB及声明textLength（0或>=Int32.max使用8MiB），压缩2将record拼接后调用PalmDoc。textRecordCount必须<=numRecords-1，COMBO按Java在boundary<textRecordCount时取boundary-1；逐record/块取消。文本UTF8或Windows-1252，保留正文内容，不把乱码静默替换为假正文。
- [ ] 从firstImageRecord扫描至末尾，每条<=16MiB、累计<=512MiB（包括未识别控制record）。JPEG/PNG/GIF/WebP/BMP魔数按原版，relativeIndex=recordIndex-firstImageRecord+1，忽略控制record但保留索引空洞。图片逐条暂存本次转换唯一scratch内，不把512MiB全部留内存；封面优先检测器coverRecord，否则第一张。ZIP图片条目stored，逐块写入并检查取消，原始字节/CRC交给现有ZIPFoundation，不实现第二套ZIP/CRC。
- [ ] 漫画分类：有效图>=3且移除HTML标签及布局空白后的UTF16长度<300；布局空白含Android ASCII正则空白、NBSP/全角空格与nbsp/十进制160/十六进制a0实体。漫画按record图序一图一正文，Page N目录使既有EPUB伪页目录折为一章。文字只按mbp:pagebreak/pagebreak分章（不凭注释增加h2分章），recindex映射本地images，缺图recindex删除；章名取首h1...h4同一行去标签后非空且UTF16<50，否则第 N 章。保留书中原文字/图片，不执行HTML/JS。新opf/ncx元数据逐项XML转义，正文继续由Task35的WK隔离机制显示。
- [ ] 对不可信HTML的正则使用Foundation reportProgress可取消匹配，转换内HTML扫描共享单调时钟2秒预算，超限明确失败，不能在多个replaceAll中重新启动无界扫描；纯线性操作每块/章检查取消。输入正文8MiB、派生manifest<=50000、spine<=100000，与发布/重开边界一致。空正文且无可组成漫画内容明确报错，禁止照搬Android的“正文内容”占位页。mimetype必须首条且stored；META-INF/container.xml、OEBPS/content.opf、toc.ncx及相对图片/正文路径可被真实EpubParser读取，cover-image实际指向所选封面（避免原版fallback封面声明悬空）。
- [ ] 本次转换在destination父目录创建唯一`.kindle-`+UUID工作目录，所有临时图片和derived.epub均在内；既有destination检查后仍以不覆盖的move发布。defer只清理本次明确创建且验证归属的scratch，失败/取消保留source与任何既有destination；不递归清理调用方目录。写完并解析验证、最终取消检查后才发布，无try?吞掉转换错误。最终验证只读产物，不执行内嵌内容。
- [ ] 派生每篇完整XHTML（正文+转义标题+wrapper的UTF8字节）必须≤8MiB，与EpubTextContentView实际读取限制相同；超过明确报错并清理scratch，不截断原文、不擅自拆章。总解压8MiB可通过两个pagebreak章验证，不能单章写出后靠测试提高archive.read上限掩盖不可读。无标签正文允许先线性检查跳过必定无匹配的正则，仍检查取消/共享预算；不移除恶意HTML2秒边界。加完整页超限实际RED/GREEN和多章总输出截断边界。
- [ ] GREEN覆盖实际ZIP元数据/文字/图片原字节/封面、控制record索引空洞、跨record/截断、空正文拒绝、超预算与运行中取消回收、既有target保护、无原包改动、恶意HTML耗时及取消；原Task37定向回归。报告task-38-report.md，父代理提交/独立审查；原生Kindle入口尚未完成。

### Task 39: Kindle 原包保存、派生恢复与完整阅读入口

**Files:** 修改 `ios/ComicCore/Sources/ComicCore/LocalLibrary.swift`、`LocalEpubLibrary.swift`、`LocalComicSource.swift`；新增 `LocalKindleLibrary.swift`、`Tests/ComicCoreTests/LocalKindleLibraryTests.swift`；修改 `ios/XXComic/ComicGridViewController.swift` 与既有EPUB原生UI测试文件接Kindle入口/fixture。派发前读取Task36–38最终接口，保持PDF、EPUB、ZIP/图片行为。不新增阅读器、不改变站源。

**Interfaces:** `LocalKindleFormat:String,Codable,Sendable` 为mobi/azw/azw3；`LocalBook.kindleFormat:LocalKindleFormat?` 为新可选字段且init默认nil，旧书架JSON仍兼容；`LocalLibrary.importKindle(title:String,source:URL,format:LocalKindleFormat,isReadableImage:(URL)throws->Bool)throws->LocalBook`。固定拥有原包`source.kindle`、派生包`content.epub`，现有book.epub描述派生内容，kindleFormat!=nil要求epub!=nil且pdf==nil。format只展示原文件扩展名，不覆盖Task37按字节的实际变体/DRM判断，不承诺AZW3/KF8可读。

**发布裁定（Task39实施核对）：** 派生文件与scratch同一书库卷，最终发布使用Foundation `linkItem`的原子不覆盖语义，成功后本次scratch的defer回收源链接；不依赖moveItem内部先检查目标再rename的潜在竞态。下文“不覆盖move”按这一契约执行。允许对Task38 `KindlePublicationAdapter.swift`最后发布作同样最小修改并回归目标竞争/取消，不改转换规则。仅按NSError domain/code识别Cocoa/POSIX的已存在错误后验证赢家，其余错误继续抛出；不支持硬链接明确失败，不回退可能覆盖的rename。成本是依赖App私有书库所在文件系统支持同卷硬链接，Apple实际执行仍待验收。

**复审补充：** 恢复到既有书目录不能仅路径校验后再按路径`linkItem`，必须把不覆盖发布绑定已打开、验证的目录身份（最小Darwin/Glibc目录fd与`linkat`或等价原语），防止最终校验与发布间目录替换导致写入新/外部目录。必要的本次输出回收也必须相对该句柄，只删除本次创建的链接，不能按替换后的路径清理。允许内部窄发布边界测试钩子确定性复现最后窗口；不增加公共发布框架或不可取消全局锁。Task38转换器的私有scratch发布不扩大转换规则。

- [ ] RED真实MOBI临时文件导入后重开、原包字节保持、派生EPUB正文/图片、历史位置及旧书架兼容。源文件被用户移走后仍从App副本读取；DRM/KF8损坏明确失败，无发布残留。删除App拥有的派生content.epub后实际资源读取重建，不用mock转换器充当格式支持。

```swift
let book = try library.importKindle(title: "小说", source: input, format: .mobi, isReadableImage: probe)
XCTAssertEqual(book.kindleFormat, .mobi)
let opened = try LocalLibrary(directory: directory).book(id: book.id)
XCTAssertEqual(opened.epub, book.epub)
let path = try XCTUnwrap(book.epub?.spine.first?.fullZipPath)
let before = try library.epubResource(bookID: book.id, path: path, maximumBytes: 8 * 1024 * 1024)
try FileManager.default.removeItem(at: directory.appendingPathComponent(book.id).appendingPathComponent("content.epub"))
XCTAssertEqual(try library.epubResource(bookID: book.id, path: path, maximumBytes: 8 * 1024 * 1024), before)
```

- [ ] 最小提取LocalEpubLibrary现有单次staging→完整校验→manifest→原子move流程为共用内部实现；EPUB prepare只复制content.epub，Kindle prepare先限量复制source.kindle再调用Task38 convert到content.epub，之后共用解析、spine校验、ImageIO probe/cover、元数据校验和发布，不能先发布EPUB再补写原包/标记。只从本次拥有副本转换，不在安全域授权结束后再读外部URL；单个原包仍20GiB，转换自身采用Task38更小正文/图预算。取消/错误只回收本次staging，不动原包或已发布书架。
- [ ] 重开校验允许仅Kindle的派生content.epub缺失，但必须有合法kindleFormat、匹配EPUB元数据和拥有的regular非符号链接source.kindle；普通EPUB缺失仍失败。epubResource/epubImageData在实际读取前通过共用内部ownedEPUB获取：content.epub存在则按原校验读取；仅缺失时用原包生成本次唯一scratch，实际EpubParser结果必须等于持久化publication，最终取消检查后不覆盖move到content.epub。不修改book.json/章ID/位置，不遇到普通CRC错误就静默换书。
- [ ] 并发请求使用各自临时目录及非覆盖发布；另一请求先发布时，只有检查取消后验证已存在文件归属且publication与原metadata相等才能复用赢家。其他错误继续抛出。不为了重建创建已被删除的book目录，不保留旧worker输出到新/外书，不增加全局不可取消的转换锁。测试实际两请求缺派生重建、失败/取消不遗留临时文件、原包缺失/符号链接/派生不符拒绝；删除测试仅针对测试拥有目录。
- [ ] Bookshelf增加Kindle文档选择（mobi/azw/azw3，具体UTType按系统可用类型），保持security-scoped worker/取消/导入标题确认；格式错误提示原解析器实际原因。LocalComicSource详情展示MOBI/AZW/AZW3，不把kindleFormat当支持声明。书架封面、纯图片阅读、文字/混合路由、目录/设置/续读均直接复用Task35；无封面沿既有蓝渐变电子书封面。原生fixture覆盖小说/漫画导入后的实际阅读、继续阅读与不支持提示；只在隔离UITest域种子。
- [ ] GREEN核心真实导入/资源/恢复用例，再按修改范围回归EPUB/本地图片/PDF和转换器；UIKit全syntaxparse，Apple实际测试未运行单列。报告task-39-report.md，父代理提交并独立审查。没有Xcode/设备不能声称Kindle原生验收通过。

### Task 40: 批量导入前的轻量电子书元数据扫描

**Files:** 新增 `ios/ComicCore/Sources/ComicCore/QuickPublicationInfo.swift`、`Tests/ComicCoreTests/QuickPublicationInfoTests.swift`。只提供扫描，后续批量UI消费，不改现有导入/全文解析行为。完整对照Android `ebook/QuickPublicationInfo.java`及其测试；复用EpubArchive/EpubXML/Task37检测器，不实现第二套XML/ZIP/PDB解析。

**Interface:** `QuickPublicationInfo:Equatable,Sendable` 公开只读title/seriesTitle/volumeNumber/coverEntry:String、isReadable:Bool、unsupportedReason:String?；`static read(_ file:URL,formatOrFileName:String?=nil)throws->Self`。format默认file.lastPathComponent，取最后点后缀并lowercase；epub读取元数据，mobi/azw/azw3/prc转KindleFormatDetector，其他明确unsupported错误。volumeNumber保留原始十进制字符串，不先Double舍入；本层只提供分组建议数据，不按同名自动合并。

- [ ] 真实RED ZIP fixture：缺失body/cover仍可读metadata、Calibre系列+2.5卷号、EPUB3 collection/refines、literal+和编码空格封面路径、无metadata空字段、DOCTYPE含UTF16/32拒绝、压缩后超1MiB元数据拒绝、非法percent路径报错；真实Kindle头fixture复用Task37检测，MOBI7标题和KF8不支持状态保持。

```swift
let info = try QuickPublicationInfo.read(epub) // fixture声明但不包含body/cover
XCTAssertEqual(info.title, "夏日列车")
XCTAssertEqual(info.seriesTitle, "四季故事")
XCTAssertEqual(info.volumeNumber, "2.5")
XCTAssertEqual(info.coverEntry, "Images/cover art.jpg")
XCTAssertTrue(info.isReadable) // 只代表元数据可扫描，不代表正文/DRM验收
```

- [ ] EPUB只读取container.xml和选中opf，每项最多1MiB、两项累计2MiB，使用现有CRC/取消/DTD禁用/节点深度边界；不调用完整EpubParser、不读取body/cover/encryption/nav资源，更不解码图片。first非空rootfile后优先最后一个media-type=application/oebps-package+xml，与原版一致。封面与rootfile解析保留literal+，仅一次percent解码再使用现有normalized/相对路径机制；不调用EpubArchive.resolve的form+替换行为，不改变全文解析器的既有语义。拒绝空、父路径越界、冒号、NUL/符号链接或绝对包路径，先检查相对关系再规范化；不请求网络。
- [ ] title取首metadata中的首title并SearchRules.trim。Calibre系列/卷号按同metadata的meta顺序后值覆盖；只有series为空才按belongs-to-collection次序寻找id及匹配refines='#id'的collection-type=series/group-position，首匹配series采用其文本及position。避免原Java嵌套扫描二次复杂度：一次索引refines键再顺序匹配，保留同key最后值规则。封面取全局items中第一个properties token含cover-image或id匹配meta cover的href，路径可以不存在，不伪称已解码。
- [ ] Kindle只复用检测结果，title及可读/原因透传，series/volume/cover为空；不转换正文。CancellationError不包装为损坏或不支持。测试加入正文/cover损坏CRC而metadata正常的档案，证明没有读正文；元数据自身CRC损坏必须失败。GREEN只跑新扫描及实际共用受影响回归；报告task-40-report.md，父代理提交/审查。批量导入功能仍需规划、持久队列及多卷UI完成，不能用扫描核心冒充用户入口。

### Task 41: 批量分组建议与精确分卷排序

**Files:** 新增 `ios/ComicCore/Sources/ComicCore/BatchImportPlanner.swift`、`Tests/ComicCoreTests/BatchImportPlannerTests.swift`。完整对照Android `local/BatchImportModels.java`、`BatchImportPlanner.java`、`BatchImportPlannerTest.java`；复用SearchRules.trim与NaturalPathOrder，不读文件、不导入、不提前更新批量功能完成状态。

**Interfaces:** `BatchImportCandidate:Equatable,Sendable` 只读sourceId/remoteComicId/seriesTitle/fileName/fileId/format/fingerprint:String、sourceOrder:String?、selectionIndex:Int；公开throwing初始化，字符串默认空、sourceOrder默认nil、selectionIndex默认0。所有字符串Java trim；空sourceOrder按无元数据处理，非空非法十进制显式报错，selectionIndex夹到0。`BatchImportGroup:Equatable,Sendable` 有key/title:String、requiresConfirmation:Bool、volumes:[BatchImportCandidate]。`BatchImportPlanner.plan(_ candidates:[BatchImportCandidate])->[BatchImportGroup]`、`orderVolumes(_ candidates:[BatchImportCandidate])->[BatchImportCandidate]`、`normalizeTitle(_ fileName:String)->String`、`volumeNumber(_ fileName:String)->Int`。

- [ ] RED移植全部Android用例并增加确定的独立oracle：首次组顺序、跨组相同指纹不去重、同组非空指纹大小写去重保留首项、空指纹保留；不同书名explicit orderVolumes不重新分组；元数据相等后文件名卷号/自然序/selectionIndex依次打破平局，全部相等保留输入序。

```swift
let later = try BatchImportCandidate(seriesTitle: "Series", fileName: "A.epub", sourceOrder: "2.5")
let earlier = try BatchImportCandidate(seriesTitle: "Series", fileName: "Z.epub", sourceOrder: "2.0")
let groups = BatchImportPlanner.plan([later, earlier])
XCTAssertEqual(groups.first?.volumes.map(\.fileName), ["Z.epub", "A.epub"])
XCTAssertEqual(groups.first?.requiresConfirmation, true)
XCTAssertEqual(BatchImportPlanner.normalizeTitle(" 城市猎人 第02卷.epub "), "城市猎人")
XCTAssertThrowsError(try BatchImportCandidate(sourceOrder: "NaN"))
```

- [ ] 分组key按Android字符串组合：sourceId与remoteComicId均非空则`remote:<source>:<comic>`且无需确认；否则`local:<title.lowercased()>`且必须确认。title优先seriesTitle否则normalizeTitle。输出按首次组出现顺序，不靠Dictionary枚举；指纹去重只在组内，不按title/fileId去重。这里只产生建议，不查询或合并既有书架。
- [ ] 分组字典的实际身份比较保持Java字符串语义，不利用Swift String的canonical equality合并组合/分解Unicode文本；最小使用UTF8 Data或UTF16码元键，公开group.key仍为原字符串。加入显示相同但码元不同的本地系列名与remoteComicId两组真实行为断言；不对书名或ID做额外Unicode规范化。仅因Swift字符串默认行为导致的合并会违背同名建议边界。
- [ ] normalizeTitle逐步照原版：Java trim→删末尾ASCII字母数字1...8位扩展→全角空格变空格并trim→删末尾卷号表达式及分隔符→删末尾ASCII空白/_/-并压缩ASCII空白→trim→空值“未命名漫画”。NSRegularExpression中的`\s`/`\d`须显式使用Java默认ASCII范围，不能让ICU默认Unicode语义吞NBSP或全角数字。volumeNumber保留最后一个成功Int32匹配；溢出忽略该匹配而不是覆盖已得到的值。测试中文/vol/v/末尾1...4数字、括号、内部卷号、NBSP、全角数字、溢出与零。
- [ ] sourceOrder按十进制精确比较，不能Double或Foundation Decimal舍入后比较；Decimal不足以覆盖Java BigDecimal超过38位的输入。最小私有比较实现：解析ASCII符号/有效数字串/小数位/可选e/E有符号指数，规范零与前导零，用调整后的十进制位数和有效数字逐位（缺位补0）比较，负数反序，不展开巨大指数为零数组。合法指数及scale遵循Java BigDecimal的Int32范围，计算使用Int64检查；sourceOrder文本受1MiB上限约束，与元数据扫描上限一致。保留原始字符串用于后续持久化，不引入BigInt依赖或通用任意精度运算库。覆盖2.0/2、负数、负零、1e3、1e-3、超过38位且只末位不同、巨大指数、非法数字/指数溢出；测试只验证实际排序和失败，不复制比较算法作oracle。
- [ ] 排序优先：两者sourceOrder均存在则精确非等值优先；仅一方存在则有值优先；其次已识别文件卷号（有值优先）；其次NaturalPathOrder；其次selectionIndex；最后原始输入次序保证稳定。不改变既有NaturalPathOrder和搜索trim的语义。GREEN本任务及实际受影响测试；写task-41-report.md，父代理限定文件提交/独立审查。持久批次、分卷存储、确认UI另行实施，不能将本任务计为用户可用批量导入。

### Task 42: 可恢复批量导入状态持久化

**Files:** 新增 `ios/ComicCore/Sources/ComicCore/BatchImportSession.swift`、`Tests/ComicCoreTests/BatchImportSessionTests.swift`。完整读取Android `local/BatchImportSession.java` 和全部对应测试，复用Foundation Codable/atomic snapshot模式，不引入数据库或任务框架。此任务只建立状态层，不启动实际导入worker或UI；输入文件授权与分卷发布由后续消费者实现。

**Interfaces:** `public actor BatchImportSession` 由App后续持有唯一实例；`init(file:URL)throws` 限量加载旧快照，无文件时为空。嵌套`State:String,Codable,Sendable` 为pending/running/completed/skipped/failed；`Item:Codable,Equatable,Sendable` 为uri/name/format:String、selectionIndex:Int、state:State、error:String；`Group` 为key/title/targetBookId:String、requiresExistingBook:Bool、items:[Item]；`Snapshot` 为version:Int=1、taskId:String(UUID)、groups:[Group]、cancelled:Bool。外部只读值快照：`current()->Snapshot?`、`create(groups:[Group])throws->Snapshot`、`start(taskID:String,group:Int,item:Int)throws`、`complete(taskID:String,group:Int,item:Int,bookID:String)throws`、`fail(taskID:String,group:Int,item:Int,error:String)throws`、`skip(taskID:String,group:Int,item:Int)throws`、`setTargetBookID(taskID:String,group:Int,bookID:String)throws`、`retryFailed(taskID:String)throws`、`cancel(taskID:String)throws`、`pendingGroupIndices()->[Int]`。Item/Group公开初始化，state初始pending/error空；requiresExistingBook默认false，JSON缺此字段仍按false兼容。

- [ ] RED真实临时JSON持久化测试：正在执行项重开回pending，已完成/跳过不重跑，失败不阻后续、错误保留且retry清理，取消保留完成项并跳过所有未完成项；明确targetBookId/requiresExistingBook跨重启保留。测试源文件原字节不变，状态层不碰源URL。

```swift
let store = try BatchImportSession(file: file)
let created = try await store.create(groups: [.init(key: "series", title: "系列", targetBookId: "existing", requiresExistingBook: true,
    items: [.init(uri: "file:///external/one.epub", name: "卷一.epub", format: "epub", selectionIndex: 4)])])
try await store.start(taskID: created.taskId, group: 0, item: 0)
let reopened = try BatchImportSession(file: file)
let restored = await reopened.current()
let saved = try XCTUnwrap(restored)
XCTAssertEqual(saved.groups[0].items[0].state, .pending)
XCTAssertTrue(saved.groups[0].requiresExistingBook)
XCTAssertEqual(saved.groups[0].targetBookId, "existing")
```

- [ ] init仅限量读16MiB UTF8 JSON，超过限制、版本非1、非法UUID/状态、结构损坏、目录/符号链接当快照均明确错误并保留原文件；不得错误回退空队列导致覆盖。重开只在内存将running转pending，后续成功原子写落盘；完成/跳过/failed不变。不存在文件时才是空状态；丢权限/其他I/O错误不当成不存在。字符串不额外trim（原版Session.text只nil→空，与Planner不同）。URI作为opaque字符串保存，不打开或声称它具有跨重启授权。
- [ ] 所有变更在actor内无await：先复制next snapshot→验证本次taskID与group/item范围→按规则改next→编码并检查仍≤16MiB→Foundation `.atomic` 写入→成功才替换内存。无手写tmp/bak替换协议，使用现有LibraryStore已用的原子快照模式；测试实际写失败时前一快照/内存不变，并保留失败路径。内部可注入窄write(data,url)测试边界模拟磁盘失败，但同时必须用真实目录阻塞验证系统I/O错误，不能只mock保存成功。
- [ ] create拒绝旧批次未cancelled且存在非completed/skipped项，包括failed；cancelled或全部completed/skipped才可新建UUID。当前任务ID不匹配的迟到回调抛错且不改新批次；group/item越界抛错而不崩溃。cancelled时start明确报错，其他变更无操作；completed/skipped的complete/fail/skip均无操作。complete非空bookID更新target、空值保留；setTarget更新group。retry只将failed/running转pending并清error，completed/skipped保留；调用方必须先停旧worker，这一层不假装提供worker取消。pendingGroupIndices只返回含pending/running的组，保持原顺序，cancelled返回空。
- [ ] 补RED/GREEN：取消后迟到complete不能复活、结束旧批次后新建而旧taskID写不能污染、非法索引、坏JSON不能create覆盖、失败写回滚target/state/error/cancelled、精确16MiB读取/保存上限、默认requiresExistingBook旧JSON、无权限或主路径变目录。不移植Android bak内部布局的测试到不存在的Swift协议；通过实际atomic快照前后字节及重开行为证明等价用户结果。报告task-42-report.md，父代理限定文件提交/审查。未完成实际批量worker/恢复授权/分卷存储，不标为完整功能。

### Task 43: 流式内容指纹与文件夹清单身份

**Files:** 新增 `ios/ComicCore/Sources/ComicCore/ContentFingerprint.swift`、`Tests/ComicCoreTests/ContentFingerprintTests.swift`。对照Android `LocalImporter.java` 的文件复制SHA256与`computeFolderManifestFingerprint`；先读原方法及已有LocalFolderIndex/NaturalPathOrder/JmImageTransform平台散列分支。只产出身份计算，不修改导入/删除/恢复流程。后续对已拥有副本计算并发布，不能在外部源可能变化时先算hash后复制却信任旧hash。

**Interfaces:** `public enum ContentFingerprint` 提供 `static file(_ url:URL,maximumBytes:Int64=20*1024*1024*1024)throws->String`、`static folder(_ root:URL,relativeImagePaths:[String])throws->String`；输出64位小写十六进制。file不判断文件格式，空文件有标准SHA256；folder消费已通过图片探测的路径列表，不自己扫描或解码图片，不改变LocalFolderIndex规则。

- [ ] RED真实临时文件+固定密码学向量：空文件、abc、多chunk文件，原字节不改；固定folder数据2.png为abc、10.png为空，输入倒序仍得到固定manifest hash。期望由独立Node crypto按Android清单计算，不能用被测函数拼出测试期望。

```swift
XCTAssertEqual(try ContentFingerprint.file(abcFile), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
XCTAssertEqual(try ContentFingerprint.folder(root, relativeImagePaths: ["10.png", "2.png"]),
               "289a7e9d8b7639baa049ca4aed2c3fc55cf31ec0056560ea3459ff175cc325d3")
```

- [ ] Apple用系统CryptoKit.SHA256流式update/finalize，Linux沿现有测试工具链使用`/usr/bin/openssl dgst -sha256 -binary`，不加新依赖、不手写SHA256。最多256KiB一次FileHandle read，每块前后检查Task取消和累计大小；不Data(contentsOf:)整书读入、不把整书喂一次进程管道。Linux Process参数数组且不经shell，及时关闭stdin、检查退出码与32字节摘要，错误/取消回收进程；Apple代码无外部进程。内部最小共享digest-feed函数足够，不增加公共算法/hasher框架。
- [ ] file要求fileURL、regular非符号链接，最大值必须非负，声明或实际流超过maximumBytes均报错，读取错误/取消原样传递。前后大小变化或被截断不得返回“成功”的混合身份；读取后核对已读字节与初始/最终元数据，后续消费者仍必须对自己的稳定副本调用，不能承诺检测同大小同时间恶意替换。测试以小maximumBytes验证边界和超限，不创建20GiB大文件。
- [ ] folder按NaturalPathOrder排序原始相对路径，不剥共同包装目录。每个文件hash后向总hash输入UTF8 `relativePath + ':' + lowercaseFileHash + '\n'`，与Android字节一致；文件修改、相对路径改名改变指纹，扫描枚举顺序不改变。不使用mtime/文件名/尺寸代替内容。输入最多50000项，路径唯一且非空相对路径，仅`/`分隔；拒绝绝对路径、反斜杠、NUL、空段、`.`/`..`、根或中间目录/文件符号链接，解析后必须在root内。每图128MiB、累计20GiB，按实际读取累计；空列表允许标准空manifest摘要，是否允许导入空书由现有importer拒绝。
- [ ] 覆盖非ASCII/空格路径、自然序、rename/content变化、根/中间/文件symlink、越界路径、重复路径、提前/运行中取消、文件读失败。运行中取消可用内部窄readChunk注入触发真实Task取消并继续生产散列管线，不mock摘要；不得成功返回截断指纹。GREEN本任务与实际受影响测试，Apple条件分支未运行单列；报告task-43-report.md，父代理提交/审查。去重与墓碑恢复仍需集成，不能把散列核心当完整去重功能。

### Task 44: 本地导入准备与发布分离，保持现有单卷入口

**Files:** 新增 `ios/ComicCore/Sources/ComicCore/LocalImportPreparation.swift`、`Tests/ComicCoreTests/LocalImportPreparationTests.swift`；最小修改 `LocalLibrary.swift`、`LocalEpubLibrary.swift`、`LocalPdfLibrary.swift`、`LocalKindleLibrary.swift`。如现有 archive/folder index无需变更则保持。先读后续设计 `docs/superpowers/specs/2026-09-20-ios-local-library-lifecycle.md`、上述四个导入文件及其已有测试；不改解析器、阅读器、站源、Android。此任务为后续串行去重/合集提交提供准备边界，不实现目录快照、指纹集成或批量UI。

**内部接口：** `PreparedLocalImport: Sendable` 保存本次独有暂存目录及已完成验证的 `LocalBook`；只在Core内部可用。`LocalLibrary` 的每种现有导入提供对应内部 `prepareImages/prepareFolder/prepareArchive/prepareEpub/preparePdf/prepareKindle`，参数沿现有公共导入函数，返回准备结果；`publishPrepared(_:) throws -> LocalBook` 与 `discardPrepared(_:) throws`。公共 `importImages/importFolder/importArchive/importEpub/importPdf/importKindle` 保持签名和用户结果，由准备+发布组合实现。使用最小共用暂存辅助方法，避免六份目录生命周期逻辑；不建立插件、任意导入协议或通用事务框架。

**PDF验证平台边界：** Linux沿现有`LocalPdfLibraryTests`的inspect/render注入验证真实副本、暂存、发布和失败回收，不将注入元数据称作PDF解析验证。Apple条件测试使用真实PDF及`PdfRenderer`验证prepare/publish接线，Linux明确skip；不为了Linux引入第二个PDF解析器。EPUB/Kindle/ZIP的现有核心解析器可在Linux真实运行，不能用假解析替代。

**发布原语边界：** 最小实例归属令牌与固定root/staging目录描述符可用于身份校验；同卷发布使用不覆盖目录rename（Linux `renameat2(RENAME_NOREPLACE)`、Darwin `renameatx_np(RENAME_EXCL)`或等价系统调用）。发布前后核对身份，清理只针对仍拥有的资源。系统没有“比较源inode后原子rename”的接口，不承诺抵御持续恶意并发改名；确定性替换、符号链接与目标冲突必须拒绝，发现未知对象不能按旧路径删除。此边界不放宽Task39既有fd/linkat保护。

- [ ] 先真实RED：准备一份真实 EPUB 和一份图片卷后，书架仍不可见，暂存内已有完整book.json/资源/封面（若适用）；调用发布后重开书库可正常读取，准备目录消失。当前接口缺失的编译错误单列，至少有可编译行为桩的真实失败证明。其余格式复用现有真实fixture，不mock格式解析。
- [ ] 准备仍使用一次唯一`.import-UUID`目录；成功返回前完成原有源校验、限量复制、格式解析、图片probe、CRC、metadata与book.json写入。失败/取消回收本次目录，原文件、已发布书和其他准备结果不受影响。成功返回后由明确调用方拥有，不能在返回前defer删掉；也不能遗留没有调用方负责回收的目录。
- [ ] 发布校验本次准备结果归属、未被替换的暂存目录及完整元数据，最终取消检查后再沿现有单目录发布路径可见。不能发布其他library创建的结果、外部目录/符号链接、篡改book.id/manifest、已发布/已回收结果；已存在目标保留，不覆盖。发布失败也回收本次仍拥有的暂存结果，不能清理已存在目标。用于所有权校验的最小内部字段可由实现者选择，不能只信任任意URL字符串。
- [ ] 丢弃只接受本次库拥有且身份仍匹配的准备目录；已经成功发布或已丢弃可无操作，权限/其他I/O失败不能伪装成功。不能按目录名前缀枚举清理，不递归书库根，不在暂存路径被替换后沿新路径删除不属于本次操作的数据。保持Task39既有恢复fd发布/取消与赢家规则，不借重构退回path-only恢复。
- [ ] 公共导入函数使用同一准备与发布实现，不保留第二套旧导入副本。PDF仍只在导入时inspect和渲染封面；Kindle仍原包/派生同暂存并仅从拥有副本转换；普通EPUB缺失派生不能恢复；图片/ZIP/文件夹自然序、分章和原有限额不变。此任务不改变书ID生成或旧JSON格式，不提前添加未被使用的合集/指纹字段。
- [ ] 真实测试覆盖六种准备结果中有代表性的正文/图片读取、公共旧入口、准备阶段取消、准备完成后取消发布、目标已存在、跨库/外部/符号链接/替换目录拒绝、重复丢弃、两个独立准备结果互不清理，以及实际写/发布失败回收。仅操作测试拥有临时目录；狭窄系统错误注入可以补充，不能代替真实格式/文件行为。GREEN运行新测试与本次改动触及的本地格式测试，不重复未改的站源/元数据/解压算法全套。报告task-44-report.md，父代理限定提交/独立审查；不得把内部准备阶段称为批量导入界面完成。

### Task 45: 导入副本的真实指纹与原格式元数据

**Files:** 新增 `ios/ComicCore/Tests/ComicCoreTests/LocalImportFingerprintTests.swift`；最小修改 `LocalLibrary.swift`、`LocalFolderIndex.swift`、`LocalEpubLibrary.swift`、`LocalPdfLibrary.swift`、`ContentFingerprint.swift`、`LocalImportPreparation.swift`，对应扩展 `ContentFingerprintTests.swift`。不改解析器、Android、Native UI或站源，不实现目录快照与去重决策。先读Task44最终实现/报告及生命周期规格，沿其prepare/publish边界完成身份计算。

**Interfaces:** `public enum LocalImportFormat:String,Codable,Sendable` 定义在LocalLibrary.swift，值images/folder/zip/cbz/epub/pdf/mobi/azw/azw3；`LocalBook`追加只读 `importFormat:LocalImportFormat?` 和 `fingerprint:String?`，现有公开初始化器最后追加两个默认nil参数，旧JSON缺字段仍可读。新增导入的format明确保存；独立多图导入fingerprint仍nil，不凭猜测将其等同于Android文件夹清单。各file/folder指纹为Task43的64位小写SHA256。`LocalFolderIndex`新增内部`relativePaths:[String]`，与files一一对应，保留共同包装目录剥离前路径。`ContentFingerprint`新增内部 `folder(_ root:URL, files:[(relativePath:String, ownedFile:URL)])throws->String`，公开folder接口不变并复用同一清单管线；不复制SHA实现。

- [ ] RED使用真实图片文件夹和EPUB/ZIP/Kindle文件准备/发布后重开，断言新字段保存，外部原字节不变，旧无字段JSON仍可读。指纹测试预期采用独立Node crypto固定输入计算，不能用被测ContentFingerprint生成期望。文件夹原路径`2.png`/`10.png`分别为abc/empty，在内部映射到owned `0.png`/`1.png`时仍产生下列原清单指纹；探测可注入以验证字节身份，本例不冒称图片解码验证。

```swift
XCTAssertEqual(try ContentFingerprint.folder(staging, files: [
    (relativePath: "10.png", ownedFile: staging.appendingPathComponent("1.png")),
    (relativePath: "2.png", ownedFile: staging.appendingPathComponent("0.png"))]),
    "289a7e9d8b7639baa049ca4aed2c3fc55cf31ec0056560ea3459ff175cc325d3")
XCTAssertNil(legacy.fingerprint)
XCTAssertEqual(reopened.importFormat, .folder)
```

- [ ] ZIP/CBZ先用现有限量copy保存到本次staging的`source.archive`，再从该拥有副本调用LocalArchiveIndex，指纹也只读取同一副本，发布保留原包。原后缀cbz保存.cbz，其余archive入口保存.zip；文件实际格式仍由解析器校验。在图片probe中改写外部源后，完整导入应继续使用先前拥有副本；真实测试同时验证原包字节、已解压页面与独立hash一致。不对外部路径先hash再复制。旧ZIP没有source.archive不要求补造；新增archive声明原格式时，prepare发布验证及重开校验须要求owned普通source.archive且非symlink，沿现有所有权规则。
- [ ] EPUB hash拥有的content.epub，PDF hash content.pdf，Kindle hash source.kindle，不能hash派生EPUB冒充原包身份。全部在prepare返回前计算，取消/读失败按Task44回收本次暂存，原格式/指纹与book.json一次写成后才发布。复用prepareOwnedEpub的kindleFormat决定原包与枚举，不复制Kindle转换或增加第二次原包复制。PDF Linux测试仍仅检查存储/字节，Apple解析限制明确记录。
- [ ] folder扫描记录原相对路径，平铺复制完成后用原路径→owned页映射计算身份，不额外复制整份原树，不用平铺数字页名替代清单原路径；文件夹原路径改变应改变指纹，外部文件在复制完成后改写不影响拥有副本的已算身份。内部映射入口要求路径数相等由tuple保证、最多50000项，原路径仍执行公开接口的相对路径/原始UTF8唯一校验；ownedFile必须fileURL且在root内，逐级无符号链接，保持128MiB单图/20GiB累计/取消/实际读取检查。不得允许任意外部文件借原路径标签进入hash。公开旧folder向该同一管线提供原始路径对应URL，避免两份校验分叉。
- [ ] 新元数据若存在则验证合法组合：format与实际epub/pdf/kindle匹配，fingerprint须64位小写ASCII十六进制；旧两个字段均nil保持原行为，不重新散列所有旧书。所有新增文件/文件夹导入都有指纹，images只有format无指纹。不在book重开时读20GiB验证hash，重开只验证元数据和声明拥有原包；真正去重/损坏校验交给后续消费者。资源校验清单须包含新source.archive，Task44清理继续扁平且不覆盖赢家。
- [ ] GREEN运行新整合测试、ContentFingerprintTests及实际触及本地格式/准备测试；不要重跑未修改的站源或全部解析算法。报告task-45-report.md，列明ZIP现在保留原包+图片有双份实际占用，不能把本任务称去重/墓碑恢复/批量UI完成。父代理限定提交与独立审查后才进入目录快照整合。
