# 收尾修复的第三次高风险复验

日期：2026-10-10。分支 `codex/ios-port`，HEAD `98d937e43441cc87f54eab49a6eed1267a71d81c` 加当前未提交修复。具体源码哈希见 `review-evidence/2026-10-10-recheck-3/source-hashes.json`。

**结论：R2-01 原 MainActor 辅助函数阻断关闭，R2-03 互斥穿透关闭，R2-02 正常中断恢复场景通过。仍暂不通过：新增启动任务有初始化编译阻断，恢复逻辑仍有两种可复现的数据删除问题。合并为下述两个 P1 收尾项。**

本轮仅检查编译与数据安全，不扩展细微视觉问题，未修改产品代码。历史报告保留，本报告更新相应风险项的当前状态。

## 本轮实际验证

| 检查 | 独立结果 |
| --- | --- |
| ActorIsolationProbe | 当前探针辅助函数声明 nonisolated；Swift 5.10 / `-swift-version 5 -typecheck` 退出 0。生产的 predictTile 与 enhanceNeural 也已使用 nonisolated。原语言级隔离问题关闭；不等同于完整 Apple 构建或推理运行通过。 |
| RecoveryProbe / 正常中断 | 重新链接当前 ComicCore：`oldVolumeReadableAfterRecovery: true`、`backupStillExists: false`、`catalogStillReferencesOldVolume: true`。旧卷正确恢复，备份不再残留。 |
| RecoveryProbe / 互斥 | 使用生产导出的 SingleWriterGate，最大同时进入数 1；新增 8 并发块互斥单测也通过。原门闩穿透关闭。 |
| 相关核心回归 | Docker `swift:5.10-jammy`，10 项实际执行、0 失败，覆盖 FavoriteRevision、追更和文件夹同步，含两个新增单测。本轮没有全量重跑 767 项。 |
| 基线与格式 | 527 文件及 ZIP SHA-256 校验通过；`git diff --check` 通过。 |
| Apple 产物 | 当前本地 IPA 仍是上一轮 14,625,809 字节产物；本轮没有当前修改的 Xcode 构建、实际 AI 输出或新版 IPA 证据。 |

## R3-01 / P1：新增启动任务在成员初始化完成前捕获 self

定位：`ios/XXComic/AppEnvironment.swift:116–120`。

新增的 `Task { try? await localLibrary.recoverOrphans() }` 中，localLibrary 是实例属性，闭包隐式捕获 self。该 Task 出现在 networkMonitor 初始化之前，Swift 不允许逃逸闭包在实例全部成员初始化完成前捕获 self。

独立探针保留同样的 @MainActor 类、属性访问、Task 和初始化顺序，执行 Swift 5 对象编译 `swiftc -swift-version 5 -c StartupCaptureProbe.swift`，退出 1：

```text
error: 'self' captured by a closure before all members were initialized
note: 'self.networkMonitor' not initialized
```

这是生产调用同构的语言检查，不冒充完整 UIKit/Xcode 编译。新辅助函数的类型检查通过不能排除 AppEnvironment 中这一不同的编译错误。

修复要求：将恢复任务安排在全部成员初始化完成之后，或明确捕获已初始化的库值以免捕获未完成的实例；同时管理恢复完成时机，避免恢复与导入/同步写事务并行。修复后立即运行当前版本 Apple Debug/Release 原生构建，不再仅依据 ComicCore 测试与单个探针标记 App 可构建。

证据：`StartupCaptureProbe.swift`、`startup-capture.log`。

## R3-02 / P1：恢复路径边界和完整性判定仍会删除数据

定位：`ios/ComicCore/Sources/ComicCore/LocalLibrary.swift:412–449`，以及 `book(id:)` / `pageURLs(for:)` 的图像卷处理。

### 异常备份 ID 可导致本地库目录被删除

代码只验证备份名最后一个 UUID，提取的 targetVolId 未验证 UUID，无法解析时还直接使用 remainder。随后拼接目标路径，并在 `book(id:)` 失败后调用 `removeItem(at: targetDir)`。

隔离库里建立可读卷，再放入 `.backup-..-<合法UUID>` 目录，调用真实 recoverOrphans。拼接的目标含 `..`，已超出库内精确卷目录的删除边界。实测：

```json
{
  "libraryRootPreserved": false,
  "previousOwnedBookReadable": false,
  "externalOriginalPreserved": true,
  "siblingSentinelPreserved": true
}
```

整个本地库根消失，原先可读卷不可读；库外原文件和哨兵仍保留。没有把未观测到的库外删除写成事实。这是异常名称的真实文件系统测试，不是对正常备份恢复结果的否定。

### 目标缺页仍被当作完整，唯一好备份被清理

`self.book(id:)` 对图像卷检查元数据与文件名，但 pageURLs 只构造 URL，没有验证页文件实际存在或可读。因此不能用该方法成功来代表“目标卷完整无损”。

隔离探针先建立可读卷与完整备份，保留目标 book.json、删除目标的一张页文件，再运行真实 recoverOrphans。实测：

```json
{
  "metadataValidationPassedBeforeRecovery": true,
  "pageReadableAfterRecovery": false,
  "goodBackupStillExists": false
}
```

恢复误判目标有效，删除了好备份，目标图片仍不可读。此前的中断恢复单测只覆盖目标整个目录缺失的场景，无法发现这个条件。

修复要求：备份命名必须完整匹配两个合法 UUID，核对卷归属；计算删除/移动目标前验证它是库根下的精确卷目录，不是库根、父目录或外部链接。未知/异常条目应保留。恢复前检查目标与备份所需页文件的真实存在、归属与可读性，目标损坏且备份完整时才置换，存在不确定性则保留最后可读副本。修复后的回归必须覆盖异常名称保留、目标缺页恢复、缺失目录恢复、完整目标安全回收备份。

证据：`RecoverySafetyProbe.swift`、`recovery-safety-probe.json`。所有目录和文件都属于探针唯一的临时容器；执行前校验含 `..` 的目标解析后仍位于该自建容器内。没有操作用户数据。早期探针因 URL 目录标志比较被自身保护拦下，修正为解析后的路径边界比较后才执行；本报告记录的是最终成功运行的结果。

## 交给 Gemini 的集中收尾指令

> R2-01 的辅助函数隔离问题和 R2-03 的互斥问题已关闭，正常中断恢复也通过。请按 `docs/ios-parity-2.0.40/ACCEPTANCE_RECHECK_3_2026-10-10.md` 收尾两个 P1：修正 AppEnvironment 启动 Task 在成员初始化完成前捕获 self 的编译错误；修正备份恢复的 UUID/路径归属检查和页文件完整性判定，确保异常备份名不删库、目标缺页时恢复好备份。保留此前通过的逻辑，补齐报告中明确的失败条件回归。随后必须实际完成当前代码的 Xcode Debug/Release 构建、CoreML 图片预测和对应版本 IPA，再集中更新交付结果；Linux 核心测试与孤立探针通过不能写成整个 App 原生验收通过。阶段验收继续由 Gemini 自行完成，用户只负责最后总验收。

本轮证据保存在 `review-evidence/2026-10-10-recheck-3/`。源码与原探针当前结果均可核对；没有扩大到新的视觉细节清单。
