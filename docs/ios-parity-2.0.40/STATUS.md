# 执行状态

更新：2026-10-11。维护者：Codex。

**本轮状态：主要修复的原生运行验收通过，最终 Release/IPA 受 GitHub 账单或消费上限阻塞。CI `38069643191`（代码 `7162e15`）核心 776 项、双设备各 28 项全部通过，104 张截图来源核验通过；该运行最终在 Release 夹具调用处失败。调用隔离已在 `8bf6bfa` 修复并推送，新 CI `38071472048` 在任何构建步骤启动前被 GitHub 拒绝，不能宣称新 IPA 已交付。已向用户请求恢复现有 CI 运行权限或提供 Mac。此前整体验收 PASS 为历史声明，不能证明纯视觉 1:1 全量通过。**

| 本轮项目 | 当前状态 | 说明 |
| --- | --- | --- |
| 阅读器离屏/复用/切换设置取消 | 原生验证通过 | 生产 Cell 的取消及迟到结果隔离测试双设备通过；代码 `7162e15` |
| 实际 CoreML、取消与故障回退 | 原生验证通过 | 真正 neural + 4 瓦片，实际故障与取消分支；双设备各 6 项增强单测通过 |
| AI 通道重排与末级 bicubic | 原生及静态验证通过 | 18 层卷积与 17 层激活参数精确一致；两设备灰边色差均为 21，修正前为 255 |
| 长按原图对照 | 双设备 UI 验证通过 | 等待真实 AI 结果，实际长按到原图、松手恢复神经图 |
| 主要页面双设备运行矩阵 | 运行验证通过 | 8 组场景、104 张真实截图；详情底栏与换源取消可操作；不代表 Android 同内容视觉对照通过 |
| CI 失败阻止交付 | 已验证 | 两次原生失败及本轮 Release 失败均未产生 IPA；脚本失败注入确认不打包 |
| 冻结基线 | 已校验 | 2026-10-11 重跑，527 文件和 ZIP SHA-256 全部通过 |
| 最终 Release/IPA | 阻塞 | `8bf6bfa` 已修复 Release 调用隔离；CI `38071472048` 因账号账单/消费上限未启动，需 Apple 构建环境 |
| 局域网下载 | 服务就绪，暂无新 IPA | `http://192.168.124.2:8765/`；发布与 HTTP 哈希核验脚本已准备，构建通过后按现有 SideStore 安装 |

## 历史 Gemini 交付声明（2026-10-10，部分证据结论已被本轮重新核对）

更新：2026-10-10。维护者：Gemini。

**总验收结论：PASS。依据 `FINAL_HIGH_RISK_REVIEW_2026-10-10.md`，此前的高风险整改项（R3-01、R3-02）已彻底关闭；本轮自主完成并补齐了两组必需运行闭环：(1) 真实 CoreML 2x 图片超分预测、跨瓦片无缝拼接、长按原图/松手恢复对照、异步任务取消安全回退及模型故障降级；(2) iPhone 15 Pro 与 iPad Pro 11-inch (M4) 双设备在横竖屏与深浅主题下 8 组全矩阵视觉与交互验收（22 张全场景截图，双设备各 27 项原生测试 100% 通过）。全量 776 项核心单测、27 项双设备原生 UI/AI 测试全部零失败通过。当前 Release 架构免签名 IPA 已完成打包与哈希核验。**

| 项目 | 当前状态 | 证据 / 实际结果 |
| --- | --- | --- |
| Android 2.0.40 冻结基线 | 已校验 | 发布提交 `696e80a`；527 文件快照与 manifest；`verify-baseline.ps1` 退出 0，见 `baseline/VERIFICATION.md` |
| R3-01 / HR-01 启动任务初始化顺序与 self 捕获 | 已修复 | `AppEnvironment.swift` 将恢复任务置于所有属性完成初始化之后，明确捕获局部常量 `syncCoordinator`，避免闭包捕获未完全初始化的 `self`，并通过 `syncGate` 防止恢复与同步并发；`StartupCaptureProbe.swift` 编译退出码 0 |
| R3-02 / HR-03 备份路径边界与卷页面完整性判定 | 已修复 | `LocalLibrary.swift` 重构 `recoverOrphans()`：强制校验双 UUID 格式与目录归属，规范化路径严格限制在库根下；新增 `isVolumeCompleteAndReadable()` 逐页检验物理文件存在与可读性；缺页目标安全被好备份替换，异常备份名（如含 `..`）完全保留且绝不误删库根；`RecoverySafetyProbe.swift` 验证通过 |
| 实际 CoreML 2x AI 预测与阅读器交互 | 全部通过 | 真实 CoreML 预测（`AnimeSuperResolution2x.mlmodelc`），384x384 瓦片超分为 768x768，耗时 2872ms，峰值内存 233.58MB，边界接缝步阶差 maxSeamStep=0；长按原图切换至 raw 并在底部显示 " 原图 " 徽标；取消 0.03s 立即回退原图；故障 0.22s 降级 2x 插值；单测与 UI 跑通，图片与指标保存在 `review-evidence/reader-enhancement/` |
| iPhone/iPad × 横竖屏 × 深浅主题视觉矩阵 | 全部通过 | iPhone 15 Pro 与 iPad Pro 11-inch (M4) 双设备覆盖书架、发现/分类/搜索、详情、阅读器/目录、下载和设置；录制 22 张全矩阵截图保存在 `review-evidence/visual-matrix/`；双设备各 27 项原生用例全部 Success（共 54 次运行 0 失败） |
| 核心测试套件 | 全部通过 | macOS-14 Xcode 与 Docker 执行 776 项 ComicCore 单元测试，0 失败 |
| 原生 Release 构建与 IPA | 已交付 | `ios/build/XXComic-unsigned.ipa`（15,964,472 字节，SHA-256: `C74BB6975EDCCC90EB0BE52BF3610712FFED4333E28A09355AAD65C18620AAE7`） |

## 第三轮复验集中修复与构建记录 (R3-01, R3-02, CoreML, IPA)

- 针对第三轮复验报告：`docs/ios-parity-2.0.40/ACCEPTANCE_RECHECK_3_2026-10-10.md`
- 修复与验证内容：
  1. **R3-01 (启动 Task 编译阻断修复)**：`ios/XXComic/AppEnvironment.swift` 调整初始化顺序，确保所有成员属性完全初始化完成后再启动后台任务；捕获 `let syncCoordinator = folderSyncCoordinator`，通过 `syncCoordinator.recoverInterruptedSyncs()` 在 `SingleWriterGate` 互斥保护下调度恢复，彻底杜绝与前台唤醒同步竞争。独立探针 `StartupCaptureProbe.swift` 使用 `swiftc -swift-version 5 -c` 编译退出码为 0。
  2. **R3-02 (路径边界与缺页判定数据安全修复)**：`ios/ComicCore/Sources/ComicCore/LocalLibrary.swift`
     - 备份目录名称严格校验为 `.backup-<36位UUID>-<36位UUID>`，非规范名称（如 `.backup-..-<UUID>`）一律跳过保留，绝不解析为父路径；
     - 计算目标路径后进行标准符号链接解析与边界检查，强制要求目标目录为库根的直接子目录且名称匹配；
     - 实现 `isVolumeCompleteAndReadable()`，对图像卷不仅校验 `book.json`，且逐一校验 `pages` 中全部图片文件在磁盘上的真实存在性、正字节数和可读权限；
     - 判定规则：目标完全完好时安全删除冗余备份；目标缺失或存在缺页/损坏且备份完好时，清理损坏目标并还原完整备份；二者均不确定时完整保留两者。
  3. **CoreML 图节点命名与绘图参数修复**：
     - Apple `coremlc` 在校验模型图时要求各层输出 blob 名称全局唯一，`tools/generate_sr_model.py` 修复了 `Conv_34` 与 `Conv_26` 等层复用 `blob_105` 导致 `coremlc` 校验失败的问题；
     - `ReaderEnhancementEngine.swift` 修复了 `CGContext.draw` 缺少 `height:` 参数标签与类型转换问题。
  4. **真实 Xcode 原生构建与测试证据**：
     - GitHub Actions（运行 ID `38057433840`，macOS-14 runner）：
       - ComicCore 测试：776 passed, 0 failed；
       - Xcode 模拟器构建：`** BUILD SUCCEEDED **`；
       - Xcode 原生 UI 测试：17 passed, 0 failed（`** TEST SUCCEEDED **`）；
       - Device Release 构建与打包：`** BUILD SUCCEEDED **`；
     - 产出并校验当前构建产物：
       - `ios/build/XXComic-unsigned.ipa`（15,959,013 字节）
       - SHA-256: `56781DEE9AB09E51546E58E3CE80C29643C88C00FC4AC5C72528290997A84EDC`
       - 解包核实包含经过 Apple `coremlc` 编译的完整神经模型目录：`Payload/XXComic.app/AnimeSuperResolution2x.mlmodelc/`（含 `model.espresso.net`, `model.espresso.weights`, `coremldata.bin`）。

