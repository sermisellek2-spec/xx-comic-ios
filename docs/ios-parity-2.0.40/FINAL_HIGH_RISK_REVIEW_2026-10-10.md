# 第三轮修复后的高风险收尾复验

日期：2026-10-10。分支：`codex/ios-port`。检查时 HEAD：`5e226a91a42fd377547232e3a7d7692ebbcd1843`；原生构建报告提交：`19d0178544fb8250a069931096b2238441563e00`。两者只差 STATUS.md，业务源码一致。检查开始时 iOS 工作区干净。

**结论：R3-01、R3-02 已通过独立复验，可关闭此前的高风险代码整改项。本轮范围内没有发现新的编译或数据安全阻断。整体 Android 2.0.40 的 1:1 复刻验收仍待补齐实际 AI 运行和主要页面设备/主题矩阵证据，不能由构建成功替代。**

本轮只复验既有风险、源码版本和原生产物，没有扩大细微视觉问题清单，没有修改产品代码。原报告保留；风险项的当前结论以本报告为准。

## 已关闭的风险及独立结果

| 项目 | 复验结果 |
| --- | --- |
| R3-01：启动捕获 self | 恢复 Task 已移到全部成员初始化完成后，捕获局部 syncCoordinator；启动恢复与前台同步使用同一 SingleWriterGate。启动捕获探针 `swiftc -swift-version 5 -c` 退出 0。当前 xcresult 的原生构建状态也为 succeeded。 |
| R3-02：异常备份名称误删库 | 生产逻辑校验双 UUID、卷归属和解析后的直接子目录边界。原 RecoverySafetyProbe 重新链接当前 ComicCore；库根、既有卷、库外原文件和同级哨兵均保留，恢复不报错。 |
| R3-02：目标缺页误删好备份 | 生产逻辑逐页检查存在性、正文件大小和可读性。原探针中目标元数据仍可读但页文件缺失，恢复后页文件可读，好备份完成置换；对应新增单测通过。 |
| 既有同步与追更回归 | 12 项核心测试、0 跳过、0 失败。覆盖 FavoriteRevisionTests、FavoriteUpdateCheckerTests、LocalFolderSyncTests，包含稳定卷/章身份、写入失败回滚、正常中断恢复、互斥和分离详情/目录追更。 |
| 真实模型权重与打包 | 冻结 NCNN 文件的全部 18 层卷积权重/偏置、17 层 PReLU 参数，与当前 .mlmodel 和 IPA 内编译后的 model.espresso.weights 都逐数组一致；没有发现随机权重替换。 |
| 冻结基线与格式 | 527 个文件和 ZIP SHA-256 校验通过；`git diff --check` 退出 0。 |

本轮原探针输出：

```json
{
  "malformedBackupID": {
    "externalOriginalPreserved": true,
    "libraryRootPreserved": true,
    "previousOwnedBookReadable": true,
    "recoveryError": "none",
    "siblingSentinelPreserved": true
  },
  "missingTargetPage": {
    "goodBackupStillExists": false,
    "metadataValidationPassedBeforeRecovery": true,
    "pageReadableAfterRecovery": true
  }
}
```

探针仅在自身创建的唯一临时目录内注入异常名称和缺页；没有操作用户库或原始文件。

## 原生产物核实及证据边界

- 新 IPA：`ios/build/XXComic-unsigned.ipa`，**15,959,013 字节**；SHA-256：`56781DEE9AB09E51546E58E3CE80C29643C88C00FC4AC5C72528290997A84EDC`，与交付报告完全一致。
- 实际 Info.plist：版本 `2.0.40 (340)`，最低 iOS 16.0，设备族 `[1, 2]`。实际 Mach-O 为 iPhoneOS arm64，SDK 17.5；无代码签名命令，仍是未签名包，安装前需要适用的签名/分发流程。
- 实际包内包含 `.mlmodelc` 网络图、权重和 CoreML 元数据；编译权重 2,492,352 字节，SHA-256 为 `a2e013b931a8053b787add979cf6cfa1c5e3d5ba058b96a6120e40697b481c36`。
- 独立解码本地 `ios/build/ui-results/ui-results-iGB6Mo/UITests.xcresult`：原生构建和测试状态均 succeeded，**17 个不同 UI 用例全部 Success**。目的设备是 **iPhone 15 Pro / iOS 17.4 Simulator / arm64**，执行时间为 2026-10-10 13:55:24 至 14:02:21 UTC。
- 17 项测试主要覆盖 EPUB/Kindle、站源抽屉、验证页和导航偏好。它们没有验证实际 CoreML 图片预测，也没有提供 iPad × 横竖屏 × 深浅色的完整运行矩阵。
- GitHub Actions 运行 `38057433840`、macOS 全量核心测试 776 项及完整 Debug/Release 日志来自 Gemini 交付报告。本轮核实了本地产物与 xcresult，没有独立重跑 macOS 全量测试，也没有将不可访问的私有运行页面作为独立验证依据。

## 总验收前仍需 Gemini 自主完成的两组验证

这两组是原任务已有的必需验收项，不是本轮发现的新代码缺陷。实现存在、模型编译成功和设备族声明都不能代替运行验证。

1. **实际 AI 与阅读器闭环**：在 Apple 环境调用当前 ReaderEnhancementEngine 处理真实图片，记录 CoreML prediction 成功及没有进入普通增强回退；保存输入、2 倍输出与原图对照证据。至少覆盖跨瓦片边界、长按原图/松手恢复、取消和推理失败回退，记录耗时、峰值内存及设备。权重一致并不单独证明模型图、色彩/方向、瓦片拼接和 UI 接线正确。
2. **主要页面视觉与交互矩阵**：按已有要求覆盖 iPhone/iPad × 竖屏/横屏 × 浅色/深色，使用同内容 fixture 与冻结 Android 基线对照书架、发现/搜索、详情、阅读器/目录、下载和设置等主要入口。保留运行截图、必要的叠图/差分、版本和操作步骤；只修影响主要布局、可操作性、状态或流程的问题，低风险视觉差异集中记账。当前工作流仅选一台 iPhone，不能证明完整矩阵通过。

历史 NON_SOURCE_GATE.md、FINAL_ACCEPTANCE.md 中的整体 PASS 不能用来补足这些缺失证据；完成后应更新矩阵、差异台账与当前版本验收结论，保留历史记录并标明过时。

## 可直接交给 Gemini 的收尾指令

> Codex 收尾复验已关闭 R3-01、R3-02，当前原生 UI 结果、新 IPA 和真实模型权重均已核实。请依据 `docs/ios-parity-2.0.40/FINAL_HIGH_RISK_REVIEW_2026-10-10.md`，保留已通过的实现，只补齐两组原有必需验收：当前 ReaderEnhancementEngine 的实际 CoreML 图片预测与原图对照/取消/失败回退；主要页面在 iPhone/iPad、横竖屏、深浅主题的同内容 Android 对照与交互运行证据。不要将 coremlc 编译成功、17 项现有 UI 测试或设备支持声明写成这两组已验收。发现重要问题再修复并做影响范围回归，小视觉差异统一记账，不反复扩大整改。由你自主完成自验、更新矩阵与报告，全部必需检查完成后再交用户一次总验收。

## 本轮证据

保存在 `review-evidence/2026-10-10-final/`：原风险探针及新输出、12 项核心回归日志、源码哈希、IPA/源模型/编译模型权重核验、xcresult 解码脚本与摘要、基线校验和文件哈希清单。大型 IPA、原始 xcresult 和探针可执行文件保留在忽略的 `ios/build/`，没有重复加入 Git。
