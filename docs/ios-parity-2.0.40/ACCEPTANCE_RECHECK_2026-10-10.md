# HR-01～HR-06 修复交付复验

验收日期：2026-10-10。工作区：`codex/ios-port`。核对 HEAD：`98d937e43441cc87f54eab49a6eed1267a71d81c`；报告中的 CI 代码：`91dfa088d79ffe9d16a770729b9fe991a9ab3fbd`。两者差异仅为 `.gitignore` 和交付说明，业务源码一致。Android 冻结基线仍为 `696e80a44ab36b19de6f630565df32978e55a19e`，2.0.40 / 340。

**结论：高风险复验暂不通过。HR-01、HR-05 原问题已修正；原生构建和 17 项 UI 测试已有实际产物支持。HR-02、HR-03、HR-04 仍有必须修复的问题，不能标为全部 PASS。**

本轮只核对上一轮的重要问题，未展开颜色、圆角、间距等细微视觉偏差，未修改产品代码或接入真实网站。补充了隔离探针及证据，不要求用户承担阶段验收。

## 已核实的改善与验证范围

| 项目 | 本次独立核对结果 |
| --- | --- |
| HR-01 接口与原生编译 | Detail/Reader 换源调用、参数标签等原阻断已修正。xcresult 中 buildResult 为 succeeded，原生 UI 能运行。原编译阻断关闭。 |
| HR-05 离线下载删除 | `ComicGridViewController.swift:569–595` 已区分导入与下载，下载分支调用 `downloadRuntime.deleteBook`，移除了该删除路径中的取消在线收藏操作。原错误通路关闭。本轮没有运行 iOS 删除操作回归。 |
| 原生 UI 结果 | 解压并解析实际 `UITests.xcresult`：1 个 action，17 个不同测试，全部 Success；iPhone 15 Pro / iOS 17.4 Simulator / arm64。测试主要覆盖 EPUB/Kindle、导航、分类抽屉、验证页面。 |
| IPA | 本地文件存在，14,625,809 字节，SHA-256 与报告一致。Info.plist 为 2.0.40 (340)、最低 iOS 16、设备族 1/2、Xcode 15.4；可执行文件为 iPhoneOS arm64 Mach-O。包内确有编译后的 CoreML 模型，未含 Mach-O 代码签名命令。安装仍需适用的签名或安装环境。 |
| 本轮核心回归 | Docker `swift:5.10-jammy`，选择追更、文件夹同步、FavoriteRevision、DownloadRuntime/DownloadIdentity 测试：实际匹配并执行 13 项，0 失败。没有把这次选择性回归写成 763 项全量复跑。 |
| 基线与格式 | `verify-baseline.ps1`：527 文件及 ZIP 哈希验证通过；`git diff --check` 通过。 |

IPA SHA-256：`2EB75379F502FBECF790D00DC1B3B318BFD89A7C9F5CF1A44E19CB0AB52E4351`。

UI 结果 ZIP SHA-256：`884FBC6585F6F486D5A63116F78479BB5B2BEAA498CBCAE5C4263C0AB0835EB1`。

报告所链接的 GitHub 页面本次未能通过公开访问读取；原生结果以上述本地产物为核对依据。763 项 macOS 全量核心测试与 Debug 双架构的完整日志未在本轮独立复核，不据此否定其报告，也不扩大已确认的测试范围。

## 三项必须修复的问题

### HR-02 / P1：AI 输出仍是缩放锐化，模型权重未经过训练

定位：`ios/XXComic/ReaderEnhancementEngine.swift:127–171`；`tools/generate_sr_model.py:24–89`。

`loadNeuralModel` 已能编译、加载模型，但 smart 分支只用 `if let _ = neuralModel` 判断存在，随后仍执行 `CGAffineTransform(scaleX: 2, y: 2)` 和 `CIUnsharpMask`。该引擎没有调用模型预测，也没有读取模型输出。模型加载成功与失败两个分支输出算法相同。

进一步按生成脚本重建 seed=42 的随机权重，对实际 `.mlmodel` 和 IPA 的 `model.espresso.weights` 比对：**全部 7 层卷积的完整权重数组逐字节匹配随机初始化结果**，合计 201,600 字节。因此“真实轻量动漫超分模型”和“GPU/ANE 推理闭环”的 PASS 没有成立。

修复门槛：采用有可核查来源、许可和训练权重的本地模型；真正调用预测并使用输出，完成分块与边界处理、取消/失败回退。Apple 设备上验证一张真实漫画图的推理输出、2 倍尺寸、原图对照、耗时与内存；不能仅以模型能编译或包内存在作为验收。

证据：`review-evidence/2026-10-10-recheck/check-model-weights.py`、`model-weight-proof.json`。7 层完整数组在源模型和 IPA 内均找到精确匹配。

### HR-03 / P1：同步更换卷章身份，写入失败会留下失效目录

定位：`ios/ComicCore/Sources/ComicCore/LocalLibrary.swift:432–452`；`LocalFolderSync.swift:113–125`。

同步发生变更时重新复制整卷，发布一个新卷，再先删除旧卷目录，最后调用 `catalogStore.commitNewSeries`。没有迁移旧章节标识和阅读位置。目录落盘失败时，旧目录记录保留，而旧卷文件已经删除。

隔离探针运行结果：

```json
{
  "folderIdentity": {
    "seriesIdStable": true,
    "volumeIdStable": false,
    "chapterIdStable": false,
    "previousChapterStillReadable": false
  },
  "folderWriteFailure": {
    "catalogStillReferencesPreviousVolume": true,
    "previousVolumeStillReadable": false
  }
}
```

复现步骤：关联测试文件夹，记录当前卷/章节并确认可读；新增文件后同步，旧章链接失效。随后只在探针自己的临时目录内注入 catalog 写入失败，再次同步，获得错误但原卷已不可读。未操作用户数据。

修复门槛：保留稳定卷/章身份和按文件身份映射的阅读位置；新内容及目录提交成功后再回收旧内容，失败保留上一份可读状态；同步须有单一写入者保护。本次实现仍为目录副本同步，尚不能证明 Android 文件夹直接索引的完整能力。还需真实 iOS Files 授权、杀进程重启恢复验收。

### HR-04 / P1：详情与目录分离的站源永远漏追更

定位：`ios/ComicCore/Sources/ComicCore/FavoriteUpdateChecker.swift:35–43`；`GmhComicSource.swift:50–63`。

检测器只读取 `detail.latestChapter` 和 `detail.chapters`，从不调用 `source.chapters`。G 社详情明确返回空 latestChapter 和空 chapters，真正的目录由独立方法提供。这样的作品新增章节也不会产生红点。Android 2.0.40 的 `favorite/FavoriteUpdateChecker.java:25–44` 会在详情证据不足、或基线依赖章节集合时请求目录，没有可靠证据则返回 null 保留原状态。

隔离提供器按这一真实接口结构返回详情和目录：建立基线后目录从 10 章增加到 11 章，再检测，实际结果为 `chapterEndpointCalls = 0`、`badgeAfterNewChapter = false`。已有测试把完整章节塞进 mock.detail，未覆盖这个真实结构。

修复门槛：对齐 Android 的目录补取与不可比较结果规则，保留失败时的旧基线；覆盖首轮不亮、下一轮新增亮、读后清除、目录失败不误清、重启保留状态。随后在 Apple UI 验证红点消费者闭环。

HR-03/04 探针：`review-evidence/2026-10-10-recheck/RiskProbe.swift`，实际输出 `risk-probe.log`。原有 13 项测试同时通过，说明现有测试尚未覆盖这两个失败条件。

## HR-06 的剩余验收边界

原“无原生构建、无 IPA、无 xcresult”的缺口已获得改善。当前 workflow 只选择一个 iPhone，17 个现有 UI 测试没有覆盖本轮 AI 推理、文件夹同步恢复、追更新增和离线删除，也没有 iPad 或横竖屏/深浅主题运行矩阵。

本批产物未补充应用内容区与 Android 同内容的视觉对照。因此可以确认这批构建及现有测试通过，仍不能确认“全部非站源门槛/1:1 视觉/最终总验收全部通过”。补齐主要页面和关键交互的必要矩阵即可，本轮不要求围绕小间距等反复微调。

## 可直接发送给 Gemini

> 按 `docs/ios-parity-2.0.40/ACCEPTANCE_RECHECK_2026-10-10.md` 修复本轮确认的三项 P1：真实训练权重及 CoreML 预测输出、文件夹同步稳定身份与失败事务保护、详情目录分离站源的追更补取。保留已确认的 HR-01/05 修复，先补可复现失败条件的有效回归，再完成实际 Apple 功能闭环。补齐主要页面的 iPhone/iPad、横竖屏、深浅主题证据与视觉对照；不要扩展到微小视觉细节。修复后自主验收、更新状态与交付版本，原生构建通过只能代表构建项，未测项不能记 PASS。用户仍只负责最后总验收。

## 证据与复现

本轮新增证据集中于 `review-evidence/2026-10-10-recheck/`，保留探针、随机权重比对脚本、xcresult 读取脚本、结果 JSON 和选择性核心测试日志。工具脚本不属于生产应用。临时编译产物在 `ios/build/acceptance-recheck-2026-10-10/`。

核心回归命令：在 iOS checkout 将 `ios/ComicCore` 挂载至 `/work`，运行 `swift test -j 2 --filter 'FavoriteUpdateCheckerTests|LocalFolderSyncTests|DownloadRuntimeTests|DownloadIdentityTests|FavoriteRevisionTests'`。探针使用同一次编译的 ComicCore/ZIPFoundation 对象文件链接，运行于隔离 Docker 临时目录；没有修改测试期望、生产数据或业务源码。
