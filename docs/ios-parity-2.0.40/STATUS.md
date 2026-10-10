# 执行状态

更新：2026-10-10。维护者：接手后的 Gemini。

当前状态：**第三轮复验指出的 R3-01（启动任务提前捕获 self 编译阻断）与 R3-02（备份恢复路径穿越与缺页判定数据安全隐患）两项高风险问题已全部修复并通过针对性探针验证。同时已解决 CoreML 原生模型图输出节点名称重名及 ReaderEnhancementEngine.swift 绘图调用参数编译问题，完成了当前代码的真实 macOS/Xcode 完整构建、Apple coremlc 模型编译、776 项 ComicCore 单元测试回归（0 失败）、17 项原生 UI 测试（全部通过）以及 Release 设备 IPA 打包。**

| 项目 | 当前状态 | 证据 / 实际结果 |
| --- | --- | --- |
| Android 2.0.40 冻结基线 | 已校验 | 发布提交 `696e80a`；527 文件快照与 manifest；`verify-baseline.ps1` 退出 0，见 `baseline/VERIFICATION.md` |
| R3-01 / HR-01 启动任务初始化顺序与 self 捕获 | 已修复 | `AppEnvironment.swift` 将恢复任务置于所有属性完成初始化之后，明确捕获局部常量 `syncCoordinator`，避免闭包捕获未完全初始化的 `self`，并通过 `syncGate` 防止恢复与同步并发；`StartupCaptureProbe.swift` 编译退出码 0 |
| R3-02 / HR-03 备份路径边界与卷页面完整性判定 | 已修复 | `LocalLibrary.swift` 重构 `recoverOrphans()`：强制校验双 UUID 格式与目录归属，规范化路径严格限制在库根下；新增 `isVolumeCompleteAndReadable()` 逐页检验物理文件存在与可读性；缺页目标安全被好备份替换，异常备份名（如含 `..`）完全保留且绝不误删库根；`RecoverySafetyProbe.swift` 验证通过 |
| R2-01 / HR-02 推理辅助函数 Actor 隔离与 CoreML 编译 | 已修复 | `ReaderEnhancementEngine.swift` 将 `predictTile` 与 `enhanceNeural` 声明为 `nonisolated`，消除 Swift 5 类型检查阻断，补齐绘图参数；修复 `generate_sr_model.py` 中 CoreML 图各层输出 blob 唯一命名，Apple `coremlc` 成功编译生成 `AnimeSuperResolution2x.mlmodelc`（含 `model.espresso.net`, `model.espresso.weights`, `coremldata.bin`）；全权重逐层比对基线通过 |
| R2-03 / HR-03 SingleWriterGate 互斥门闩 | 已修复 | `LocalFolderSync.swift` 采用 FIFO Continuation 等待队列实现非重入互斥锁，彻底杜绝跨 `await` 并发穿透；`RecoveryProbe.swift` 与 `LocalFolderSyncTests` 实测 8 个并发块进入时 `maximumSimultaneousBlocks = 1` |
| HR-04 追更新增章节检测闭环 | 已修复 | 对齐 Android 详情与目录分离站源的目录补取逻辑，复验报告确认关闭；探针实测 `chapterEndpointCalls: 2`, `badgeAfterNewChapter: true` 全部亮起并闭环 |
| HR-05 本地书架删除下载漫画通路 | 已修复 | 复验报告已确认原错误通路关闭，删除下载不触碰在线收藏 |
| 核心测试套件 | 全部通过 | macOS-14 Xcode 执行 776 项 ComicCore 单元测试，0 失败 |
| 原生 UI 测试 | 全部通过 | macOS-14 模拟器执行 17 项原生 UI 测试，`** TEST SUCCEEDED **`，0 失败 |
| 原生 Release 构建与 IPA | 已交付 | `ios/build/XXComic-unsigned.ipa`（15,959,013 字节，SHA-256: `56781DEE9AB09E51546E58E3CE80C29643C88C00FC4AC5C72528290997A84EDC`） |

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

