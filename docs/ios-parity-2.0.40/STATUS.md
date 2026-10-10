# 执行状态

更新：2026-10-10。维护者：接手后的 Gemini。

当前状态：**已完成第三轮复验指出的 R3-01（启动任务提前捕获 self 编译阻断）与 R3-02（备份恢复路径穿越与缺页判定数据安全隐患）两项高风险问题攻坚修复。Docker 下完整回归并通过全部 769 项 ComicCore 单元测试（0 失败），并通过探针 `StartupCaptureProbe.swift`（编译退出 0）及 `RecoverySafetyProbe.swift`（异常备份名保留库目录、目标缺页成功恢复好备份）。**

| 项目 | 当前状态 | 证据 / 实际结果 |
| --- | --- | --- |
| Android 2.0.40 冻结基线 | 已校验 | 发布提交 `696e80a`；527 文件快照与 manifest；`verify-baseline.ps1` 退出 0，见 `baseline/VERIFICATION.md` |
| R3-01 / HR-01 启动任务初始化顺序与 self 捕获 | 已修复 | `AppEnvironment.swift` 将恢复任务置于所有属性完成初始化之后，明确捕获局部常量 `syncCoordinator`，避免闭包捕获未完全初始化的 `self`，并通过 `syncGate` 防止恢复与同步并发；`StartupCaptureProbe.swift` 编译退出码 0 |
| R3-02 / HR-03 备份路径边界与卷页面完整性判定 | 已修复 | `LocalLibrary.swift` 重构 `recoverOrphans()`：强制校验双 UUID 格式与目录归属，规范化路径严格限制在库根下；新增 `isVolumeCompleteAndReadable()` 逐页检验物理文件存在与可读性；缺页目标安全被好备份替换，异常备份名（如含 `..`）完全保留且绝不误删库根；`RecoverySafetyProbe.swift` 验证通过 |
| R2-01 / HR-02 推理辅助函数 Actor 隔离 | 已修复 | `ReaderEnhancementEngine.swift` 将 `predictTile` 与 `enhanceNeural` 声明为 `nonisolated`，消除 Swift 5 类型检查阻断，推理全链路在 `Task.detached` 后台线程池运行；`ActorIsolationProbe.swift` 检查退出 0 |
| R2-03 / HR-03 SingleWriterGate 互斥门闩 | 已修复 | `LocalFolderSync.swift` 采用 FIFO Continuation 等待队列实现非重入互斥锁，彻底杜绝跨 `await` 并发穿透；`RecoveryProbe.swift` 与 `LocalFolderSyncTests` 实测 8 个并发块进入时 `maximumSimultaneousBlocks = 1` |
| HR-04 追更新增章节检测闭环 | 已修复 | 对齐 Android 详情与目录分离站源的目录补取逻辑，复验报告确认关闭；探针实测 `chapterEndpointCalls: 2`, `badgeAfterNewChapter: true` 全部亮起并闭环 |
| HR-05 本地书架删除下载漫画通路 | 已修复 | 复验报告已确认原错误通路关闭，删除下载不触碰在线收藏 |
| 核心测试套件 | 全部通过 | Docker Linux `swift test -j 2` 执行 769 项，跳过 2 项（无 Apple 原生 PDF），0 失败（133.226 秒） |

## 第三轮复验集中修复记录 (R3-01, R3-02)

- 针对第三轮复验报告：`docs/ios-parity-2.0.40/ACCEPTANCE_RECHECK_3_2026-10-10.md`
- 修复与验证内容：
  1. **R3-01 (启动 Task 编译阻断修复)**：`ios/XXComic/AppEnvironment.swift` 调整初始化顺序，确保所有成员属性完全初始化完成后再启动后台任务；捕获 `let syncCoordinator = folderSyncCoordinator`，通过 `syncCoordinator.recoverInterruptedSyncs()` 在 `SingleWriterGate` 互斥保护下调度恢复，彻底杜绝与前台唤醒同步竞争。独立探针 `StartupCaptureProbe.swift` 使用 `swiftc -swift-version 5 -c` 编译退出码为 0。
  2. **R3-02 (路径边界与缺页判定数据安全修复)**：`ios/ComicCore/Sources/ComicCore/LocalLibrary.swift`
     - 备份目录名称严格校验为 `.backup-<36位UUID>-<36位UUID>`，非规范名称（如 `.backup-..-<UUID>`）一律跳过保留，绝不解析为父路径；
     - 计算目标路径后进行标准符号链接解析与边界检查，强制要求目标目录为库根的直接子目录且名称匹配；
     - 实现 `isVolumeCompleteAndReadable()`，对图像卷不仅校验 `book.json`，且逐一校验 `pages` 中全部图片文件在磁盘上的真实存在性、正字节数和可读权限；
     - 判定规则：目标完全完好时安全删除冗余备份；目标缺失或存在缺页/损坏且备份完好时，清理损坏目标并还原完整备份；二者均不确定时完整保留两者。
  3. **探针与测试回归验证**：
     - `RecoverySafetyProbe.swift` 实测输出：
       ```json
       "malformedBackupID": {
         "libraryRootPreserved": true,
         "previousOwnedBookReadable": true,
         "externalOriginalPreserved": true,
         "siblingSentinelPreserved": true,
         "recoveryError": "none"
       },
       "missingTargetPage": {
         "metadataValidationPassedBeforeRecovery": true,
         "pageReadableAfterRecovery": true,
         "goodBackupStillExists": false
       }
       ```
     - `RecoveryProbe.swift` 再次复测：`maximumSimultaneousBlocks: 1`，`oldVolumeReadableAfterRecovery: true`，`backupStillExists: false`。
     - `LocalFolderSyncTests` 包含针对异常路径保护和缺页自动恢复的回归测试；全量 769 项 ComicCore 单元测试 0 失败，冻结基线 527 项文件 SHA-256 校验 100% 通过。
