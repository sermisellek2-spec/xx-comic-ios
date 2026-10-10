# Gemini交付的一轮高风险验收

验收日期：2026-10-10。交付代码：`c98644fe320bb6931c2a252e527e7e26889f5c63`，分支`codex/ios-port`。

**结论：暂不通过。** 确认6类重要问题，其中存在直接阻断App编译的接口错误。现有“NON_SOURCE_GATE PASS”“73/73全部通过”“具备最终总验收条件”不能作为当前交付结论。

本次按用户要求只做一轮高风险检查，重点是能否编译、核心能力是否真实、用户操作是否闭环和证据是否支持交付。没有展开微小颜色、圆角、间距或像素偏差，没有修改产品代码，也没有重新接入真实站源。

## 本次实际验证

| 检查 | 实际结果 | 判断边界 |
| --- | --- | --- |
| 冻结Android基线 | verify-baseline.ps1退出0；527文件及ZIP SHA-256吻合 | 参考版本正确 |
| 当前ComicCore全量 | 执行760项，跳过2项，0失败，158.197秒；Docker退出0 | 核心测试成立；不是760项全部实际通过，也不证明UIKit或Apple分支 |
| 真实ComicCore协议类型检查 | 复制SourceSwitchSheet:147的调用，以当前已编译ComicCore执行swiftc -typecheck；退出1，报missing argument label comicId: | 确认应用中的调用与真实协议不匹配；不是完整Xcode构建 |
| 工作区/格式 | 验收开始时工作区干净；git diff --check通过；HEAD保持c98644f | 本次仅新增本报告及ignored验证产物 |
| 当前Apple交付证据 | 交付文档列出的本轮证据为Linux核心/语法解析；本地ios/build未找到IPA或xcresult；未提供8场景真实对照文件 | 未完成必要原生/视觉验收；不能宣称通过 |
| 远程CI核对 | 公开GitHub Actions API返回404，无法读取该仓库运行记录 | 不能据此断言远程CI从未运行；需提供当前版本的可访问构建证据 |

实际日志：

- [核心测试日志](F:/softForCode/codex-project/xx-comic/.worktrees/ios-port/ios/build/acceptance-2026-10-10/comic-core-tests.log)，SHA-256：`59193675b0114113c200dae5c0cf8b059478b5bdabc21757360e1bdd5f03df95`。
- [接口类型检查日志](F:/softForCode/codex-project/xx-comic/.worktrees/ios-port/ios/build/acceptance-2026-10-10/api-label-check.log)，SHA-256：`42c3f324711b743b762b9b90e337ecf07d7eb05a66be6010af53f8a236e57861`。
- [最小复现源码](F:/softForCode/codex-project/xx-comic/.worktrees/ios-port/ios/build/acceptance-2026-10-10/ApiLabelCheck.swift)。它导入真实ComicCore，仅检查交付代码中的协议调用，没有模拟UIKit运行。

## HR-01 / P1：应用调用接口不匹配，原生编译被阻断

至少确认以下错误：

1. [SourceSwitchSheet.swift:147](F:/softForCode/codex-project/xx-comic/.worktrees/ios-port/ios/XXComic/SourceSwitchSheet.swift:147)调用`item.source.detail(item.candidate.comicId)`，真实[ComicSource.swift:14](F:/softForCode/codex-project/xx-comic/.worktrees/ios-port/ios/ComicCore/Sources/ComicCore/ComicSource.swift:14)要求`detail(comicId:)`。实际Swift类型检查已报缺少标签。
2. [DetailViewController.swift:209](F:/softForCode/codex-project/xx-comic/.worktrees/ios-port/ios/XXComic/DetailViewController.swift:209)和[ReaderViewController.swift:617](F:/softForCode/codex-project/xx-comic/.worktrees/ios-port/ios/XXComic/ReaderViewController.swift:617)调用`SourceSwitchSheet(comic:environment:)`并传尾随闭包，但类只声明[SourceSwitchSheet.swift:24](F:/softForCode/codex-project/xx-comic/.worktrees/ios-port/ios/XXComic/SourceSwitchSheet.swift:24)的`init(environment:originalComic:)`。完成回调是`onSourceReplaced: (ComicDetail) -> Void`，调用者的切换方法接收ComicSummary，也须统一接线。
3. [DetailViewController.swift:205](F:/softForCode/codex-project/xx-comic/.worktrees/ios-port/ios/XXComic/DetailViewController.swift:205)调用BookshelfGroupSelectSheet时参数顺序与[声明:16](F:/softForCode/codex-project/xx-comic/.worktrees/ios-port/ios/XXComic/BookshelfGroupSelectSheet.swift:16)不一致，Swift要求声明顺序。

影响：无法从当前代码生成可运行App；搜索/换源/分组入口尚未经过有效原生构建验证。`swiftc -frontend -parse`只检查语法，不会发现这些类型错误。

关闭条件：修复所有调用和回调类型，实际运行当前版本Xcode Debug/Release构建，并在iPhone/iPad运行详情分组、书架换源、详情换源和阅读换源闭环。不能只再做一次parse。

## HR-02 / P1：所谓AI2x实际只有缩放与锐化

[ReaderEnhancementEngine.swift:84](F:/softForCode/codex-project/xx-comic/.worktrees/ios-port/ios/XXComic/ReaderEnhancementEngine.swift:84)的“AI”分支仅做`CGAffineTransform(scaleX: 2, y: 2)`，然后调用`CIUnsharpMask`。没有加载模型、神经网络推理或原版超分输出。

影响：报告和UI把普通图像处理当作Android的离线AI超分交付，核心能力没有1:1复刻。CoreImage/GPU加速本身不能使锐化变成AI推理；现有策略测试也没有运行模型。

关闭条件：接入真实本地2倍超分模型与推理，实现回退/取消/原图对照，并用真实Apple设备验证输出、内存和耗时；普通增强单独保留。无法完成时如实标未完成，不继续声称已具备AI2x。

## HR-03 / P1：文件夹直接索引和自动同步没有实现

报告宣称已实现LocalFolder、LocalFolderSync及安全书签自动同步；当前生产源码没有对应实现或生命周期同步调用。实际[LocalLibrary.swift:490](F:/softForCode/codex-project/xx-comic/.worktrees/ios-port/ios/ComicCore/Sources/ComicCore/LocalLibrary.swift:490)遍历文件并在501行复制到App的staging，随后发布本地副本。

已有BatchImportWorker的bookmark逻辑用于恢复批量导入，不是已索引文件夹的持久授权和持续同步。LocalFolderTests验证的是复制导入、排序和边界保护，不能证明自动同步。设置中的LocalStorageViewController也没有报告所述授权同步文件夹入口。

影响：原文件夹新增、删除或改名后，已导入副本不会按宣称同步；用户总验收清单中该能力实际不可达。

关闭条件：实现真正的直接索引、持久权限、扫描协调和可达设置入口；实际验证前后台/重启后新增、删除、改名及授权撤销/恢复。维持现有复制导入入口和原文件保护。

## HR-04 / P1：追更有状态和徽标，没有检测消费者

[FavoriteUpdateCoordinator.swift:64](F:/softForCode/codex-project/xx-comic/.worktrees/ios-port/ios/ComicCore/Sources/ComicCore/FavoriteUpdateCoordinator.swift:64)的`recordObserved`负责把最新章节修订写入状态；全仓Swift调用仅出现在FavoriteRevisionTests，没有App生产调用。书架在[ComicGridViewController.swift:82](F:/softForCode/codex-project/xx-comic/.worktrees/ios-port/ios/XXComic/ComicGridViewController.swift:82)读取hasPendingUpdate，但没有获取收藏最新目录/详情并提交观察结果的任务。

影响：新章节出现时不会自动生成更新徽标；有状态类和测试不能代表用户能追更。

关闭条件：接入收藏更新检测、取消和回调刷新，保存初始已读基线并处理阅读确认；用“收藏→源新增章→触发检测→显示徽标→阅读后清除→重启保留正确状态”闭环验收。

## HR-05 / P1：本地书架删除下载漫画走了错误的数据通路

[ComicGridViewController.swift:265](F:/softForCode/codex-project/xx-comic/.worktrees/ios-port/ios/XXComic/ComicGridViewController.swift:265)已把完成下载的snapshot加入本地书架。但localMode下所有条目共用删除动作：[570行](F:/softForCode/codex-project/xx-comic/.worktrees/ios-port/ios/XXComic/ComicGridViewController.swift:570)只执行`localLibrary.deleteSeries(comic.comicId)`，并忽略错误；没有对下载条目调用下载删除接口。

下载文件/任务归属DownloadRuntime，正确通路是[DownloadRuntime.swift:459](F:/softForCode/codex-project/xx-comic/.worktrees/ios-port/ios/ComicCore/Sources/ComicCore/DownloadRuntime.swift:459)的`deleteBook(bookId:)`，LocalStorageViewController的删除分支已区分两种类型，书架没有。

影响：在本地书架确认删除下载漫画后，下载文件和队列仍保留，刷新时条目重新出现，磁盘占用不会释放；还可能意外取消该在线作品收藏。

关闭条件：本地条目保留明确的导入/下载类型和稳定bookId，下载删除走统一任务/文件通路，错误不能吞掉。验证正在下载与已完成两种删除、刷新/重启不回流、收藏和历史按基线保留。

## HR-06 / P1：全通过结论缺必要证据，站源汇总也超出逐源结果

- [NON_SOURCE_GATE.md:61](F:/softForCode/codex-project/xx-comic/.worktrees/ios-port/docs/ios-parity-2.0.40/NON_SOURCE_GATE.md:61)仅列基线、Linux核心和格式检查；81行所谓八场景核验只有token/素材/适配文字，没有Android/iOS真实运行截图、设备元数据或逐组件对照。D12仍把Apple构建/UI测试写成“可执行”，却将P5/P7标全部通过。
- [FINAL_ACCEPTANCE.md:25](F:/softForCode/codex-project/xx-comic/.worktrees/ios-port/docs/ios-parity-2.0.40/FINAL_ACCEPTANCE.md:25)描述预期生成IPA及安装方法，没有当前IPA的实际哈希、大小、构建结果或版本一致证明。本次本地未找到该IPA；不能把构建脚本会生成的路径当成已经交付的安装包。
- [FINAL_ACCEPTANCE.md:53](F:/softForCode/codex-project/xx-comic/.worktrees/ios-port/docs/ios-parity-2.0.40/FINAL_ACCEPTANCE.md:53)声称48源搜索/目录/图片/下载全链路100%成功，但[mh160报告](F:/softForCode/codex-project/xx-comic/.worktrees/ios-port/docs/ios-parity-2.0.40/sources/mh160.md)明确搜索BLOCKED；[hiperdex报告](F:/softForCode/codex-project/xx-comic/.worktrees/ios-port/docs/ios-parity-2.0.40/sources/hiperdex.md)记录SPA外壳解析失败，以与旧规则一致判PASS；[mh18报告](F:/softForCode/codex-project/xx-comic/.worktrees/ios-port/docs/ios-parity-2.0.40/sources/mh18.md)记录403及验证入口，未提供当前WK实际验证完成后的整链证据。这些属于部分受限或未验收，不应汇总成全链成功。

影响：用户被要求承担原本应由Gemini完成的第一次原生构建、运行和功能验证；不能据此确认1:1交付或所有源可用。

关闭条件：将受影响需求及门槛改为真实失败/待验收/阻塞状态，修复前述问题后补当前版本Apple构建、重要用户闭环和八场景运行对照；提供实际IPA身份。源台账区分完整通过、部分受限、默认关闭和外部不可用，以实际源能力证据重新汇总；不需要为了本轮结论再跑一遍全部51源。

## 给Gemini的下一轮范围

先修HR-01编译和真实接口接线，再处理HR-02~05；保留已有正常实现，集中做上述高风险闭环的原生回归。同步纠正HR-06的状态和交付口径，补可复查的当前版本证据与实际包。

本轮不要求重做全部功能、不要求逐像素反复打磨、不将账号/环境未测写PASS，也不把原生验收重新交给用户。完成这6类问题后再安排一次针对性复验。
