# 本轮比较与验证记录

日期：2026-10-11。Android 冻结提交 `696e80a44ab36b19de6f630565df32978e55a19e`，2.0.40/340；iOS 为 `codex/ios-port`、`1e2287c7e5bcd51d84507a477ff68db3b66a6421` 加本地未提交修改。**本轮是差异核对与局部修正，不是全量复刻验收或新 IPA 交付。**

## 实际运行

命令从 iOS checkout 执行，Docker 绑定路径使用当前 checkout 的绝对路径。

| 检查 | 命令 / 输入 | 实际结果 | 证据 |
| --- | --- | --- | --- |
| 冻结包 | `pwsh -NoProfile -File docs/ios-parity-2.0.40/verify-baseline.ps1` | 527 文件与 ZIP SHA-256 匹配；退出 0 | [baseline-check.log](baseline-check.log) |
| 源目录 | `python tools/audit-ios-source-catalog.py --output docs/ios-parity-2.0.40/review-evidence/2026-10-11-current-comparison/source-catalog-proof.json` | 51 当前、22+29、默认启用 50；名称/顺序/退役 ID 匹配；退出 0 | [source-catalog-proof.json](source-catalog-proof.json) |
| 核心全量 | `docker run --rm --mount "type=bind,source=<ios/ComicCore绝对路径>,target=/work" -w /work swift:5.10-jammy swift test -j 2` | 执行 780 项、2 跳过、0 失败；134.772 秒；退出 0 | [core-full-test.log](core-full-test.log) |
| 独立反馈状态 | `docker run --rm --mount "type=bind,source=<checkout绝对路径>,target=/repo,readonly" -w /repo swift:5.10-jammy bash tools/verify-ios-detail-feedback.sh` | 6 项、0 失败；退出 0。脚本把应用反馈源和原生单测原样复制到临时 Package，未改断言 | [detail-feedback-green.log](detail-feedback-green.log) |
| 反馈测试先失败 | 同一命令，反馈 API 仅有空实现时执行 | 6 项测试失败、13 个断言失败；退出 1。证明缺少反馈行为可被检测，**不是原 UIKit 故障的运行复现** | [detail-feedback-red.log](detail-feedback-red.log) |
| 原生语法 | `swiftc -frontend -parse -swift-version 5`；第二轮加 `-D DEBUG`，输入 `ios/XXComic/*.swift ios/XXComicTests/*.swift ios/XXComicUITests/*.swift` | 当前 51 文件、两配置退出 0；不加载 Apple SDK | [native-syntax.log](native-syntax.log) |
| 图标静态 | Pillow 按 `Contents.json` 检查 18 图的实际像素、不透明 RGB、SHA-256；核对 XcodeGen 编译键 | 实际退出 0；按冻结 `#4AAEFB` 背景去除半透明；未生成新 IPA | [icon-static-proof.json](icon-static-proof.json) |
| 工作树空白与矩阵 | `git diff --check`；CSV ID/状态/源目录与 proof 一致性 | 退出 0；换行转换提醒不属于错误 | [validation-summary.json](validation-summary.json) |

两项 Linux 跳过均需要 Apple PDF 框架：`LocalImportPreparationTests.testNativePdfPreparationAndPublicationUseRealRenderer`、`PdfRendererTests.testNativePDFRenderingRequiresAppleFrameworks`。核心全量后未再编辑 ComicCore 源码和核心测试；后续改动为 UIKit 接线、独立反馈状态、Debug fixture、UI 用例、图标与文档。

源码输入文件的逐项 SHA-256 和按范围摘要保存在 [input-hashes.json](input-hashes.json)，在本轮核对结束时采集，不冒充 CI 签名或执行前快照。实际测试数量和日志哈希见 [validation-summary.json](validation-summary.json)。

## 未运行与未通过

- 当前工作树 Apple SDK 类型检查、Xcode 构建、原生图像/注册单测、10 项新增 UI 用例均未运行。反馈的 6 项原生单测源码只在独立 Linux Package 中运行，不代表宿主 App 测试通过。
- 当前没有新 IPA、Assets.car/CFBundleIcons 解包结果或主屏图标显示证据。旧 IPA 缺图标资源与当前 PNG 半透明是分别发现的问题，不能推断为同一原因。
- 缺 iPhone/iPad × 横竖屏 × 浅深色的同内容视觉对照、叠图和逐组件差分，以及当前 Files、后台、性能与恢复完整运行证据。
- Windows 无 Xcode。本轮未推送或触发新仓库 CI；旧仓库额度问题已解决。真实网站验收按要求后置，未联网冒充通过。

因此非站源门槛未通过，不开启真实源阶段，也不邀请用户做阶段试包。

## 审查与历史证据

[code-review.md](code-review.md) 记录独立只读审查的两处产品竞态和一处夹具问题及修正边界。

[ci-and-ipa-proof.json](ci-and-ipa-proof.json) 是新仓库成功 CI `38104946234`、旧 `a5aeec9` IPA 的过滤记录；[visual-reference-manifest.json](visual-reference-manifest.json) 对应四张真实参考图。旧 iOS 图已与原 CI 哈希匹配，Android 图缺完整设备/版本元数据，均仅作组件参考；没有把旧图记作本轮代码的视觉验收。

`historical-*` 保留更新前的矩阵、状态与报告，其中全绿状态、旧额度阻塞和错误退役源名已过时。当前结论见 [差异报告](../../../comparisons/2026-10-11-ios-android-current-assessment.md)、[requirements.csv](../../requirements.csv) 和 [differences.md](../../differences.md)。
