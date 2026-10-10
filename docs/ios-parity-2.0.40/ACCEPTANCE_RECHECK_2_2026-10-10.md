# 三项高风险修复的第二次复验

日期：2026-10-10；iOS checkout：`codex/ios-port`，HEAD `98d937e43441cc87f54eab49a6eed1267a71d81c` 加本轮未提交的修复工作树。源码哈希保存在 `review-evidence/2026-10-10-recheck-2/source-hashes.json`。本报告补充并更新第一次复验的相关结论，历史失败证据仍保留。

**结论：修复有实质进展。原隔离探针全部转正，追更漏报关闭，真实模型权重确认通过；仍有三处 P1 必须修复：新推理代码的 actor 隔离编译错误、同步中断后缺少备份恢复、SingleWriterGate 实际不互斥。**

本轮不讨论微小视觉差异，不改产品代码，不请求用户阶段验收。只新增验收报告、隔离探针和实际运行证据。

## 已验证修好的问题

1. 原 `RiskProbe.swift` 未改动，重新链接当前 ComicCore 编译对象运行：series/volume/chapter 身份稳定，旧章可读；catalog 写入失败后旧卷仍可读；分离详情目录的追更接口调用 2 次，新增第 11 章后红点为 true。结果见 `original-risk-probe.json`。
2. 直接读取冻结 Android 参考 ZIP 内 NCNN 文件，与当前 CoreML 文件核对：完整消费 1,247,368 字节；全部 18 层卷积完整权重、偏置及 17 层 PReLU 斜率，按 FP16→FP32 解码后均在当前模型中逐字节匹配。旧随机权重问题关闭。这个验证覆盖模型参数来源，不证明完整计算图与实际图像输出等价。
3. 代码中现在确有 `model.prediction(from:)`、图像输出读取、瓦片裁剪与拼接，旧“只加载模型、仍然仅缩放锐化”的实现已经替换。但新实现尚有下述编译阻断，Apple 推理运行验收仍待完成。
4. 本轮 Docker 选择性回归：FavoriteUpdateCheckerTests、LocalFolderSyncTests、FavoriteRevisionTests，8 项全部通过，包含新增的两个回归用例。没有把本轮验证写成 765 项全量重跑；用户报告中的全量结果未在此轮复跑。
5. `verify-baseline.ps1` 校验 527 文件及 ZIP 成功；`git diff --check` 成功。CRLF 转换提示不是检查失败。

冻结 NCNN SHA-256：`548a36f9c3f4ab8da56cd3b13badf23968bee207b396dad14d04b830e5f2ab2d`。

当前 CoreML：2,488,320 字节，SHA-256 `14f5b4bbce70fa5c44720d421d2498f721acae095e1d5a7c2dfa980e68bbfca8`。

## R2-01 / P1：新推理辅助函数造成语言级编译阻断

定位：`ios/XXComic/ReaderEnhancementEngine.swift:18`、`:121`、`:235–253`。

整个类标为 `@MainActor`，静态 `predictTile`、`enhanceNeural` 同样继承这个隔离。`Task.detached` 内用 `try Self.enhanceNeural(...)` 同步调用，没有跨 actor 的 await。

保留相同类隔离、静态辅助函数和 detached 调用结构，独立使用 `swift:5.10-jammy` 执行 `swiftc -swift-version 5 -typecheck ActorIsolationProbe.swift`，退出码 1：

```text
error: expression is 'async' but is not marked with 'await'
note: calls to static method 'enhanceNeural()' from outside of its actor context are implicitly asynchronous
```

这是与生产调用同构的 Swift 语言检查，未冒充完整 UIKit/Xcode 构建。项目 `SWIFT_VERSION = 5.0`，当前生产代码具有同一错误结构。ComicCore 的 Linux 测试不编译这个 UIKit 文件，不能排除这一阻断。

修复要求：把不访问 UI 状态的重计算/推理辅助函数正确设为非主线程隔离的实现，使耗时推理继续在后台运行。仅添加 await、把整个瓦片循环迁回主线程，不满足线程约束。随后实际完成当前修复版本的 Apple 原生构建、真实模型推理与图片输出验收。

证据：`ActorIsolationProbe.swift`、`actor-isolation.log`。

## R2-02 / P1：中断窗口留下唯一备份，恢复函数却将其删除

定位：`ios/ComicCore/Sources/ComicCore/LocalLibrary.swift:394–403`、`:442–460`。

普通抛错时的 catch 回滚已修好，但旧卷重命名为 `.backup-...` 后、新卷发布前仍有进程中断窗口。进程终止不会执行 catch。此时持久化目录仍引用原卷路径，而完整旧卷只存在于备份路径。

新 `recoverOrphans` 按 `.backup-` 前缀直接删除目录，没有判断旧卷缺失、交易是否提交，也没有恢复备份。源码搜索还确认该方法目前只有测试调用，生产启动恢复尚未接线。

隔离探针模拟这个确切磁盘状态：建立真实本地库，旧卷移动到实现中使用的备份命名路径，重新实例化 LocalLibrary，再调用真实 `recoverOrphans()`。结果：

```json
{
  "catalogStillReferencesOldVolume": true,
  "oldVolumeReadableAfterRecovery": false,
  "backupStillExists": false
}
```

因此当前实现既无法在重启后恢复中断事务，调用所谓孤儿恢复还会删除仅剩的可读副本。没有调用生产恢复函数时，原卷主路径依然缺失。

修复要求：记录能区分准备、发布、提交、回收状态的事务信息；启动时核实目录、卷和备份身份，恢复未提交事务，保留最后一份完整可读内容。只清理确认已完成、归属明确的备份，不能按前缀统一清理。补充真实中断状态→重启恢复的回归并完成生产接线。

证据：`RecoveryProbe.swift`、`recovery-probe.json`。探针仅操作自己的临时目录，没有动用户数据。

## R2-03 / P1：SingleWriterGate 允许并行事务进入

定位：`ios/ComicCore/Sources/ComicCore/LocalFolderSync.swift:3–6`、`:72–76`。

门闩实现只是 actor 内 `try await block()`。异步 block 挂起时 actor 可以接收下一次 execute，没有任何跨挂起点持有的锁定状态或等待队列。该实现不能保证整次文件夹同步的单一写入者。

独立复制完全相同的门闩实现，四个并发调用在 block 内进入计数器、短暂异步挂起、退出。实测 `maximumSimultaneousBlocks = 4`；正确互斥应为 1。这个结果证明门闩本身不互斥，没有声称本轮已复现生产并发文件损坏。

生产存在前台唤醒自动同步和设置页手动“立即同步全部”两个入口；同步内部又有 catalog actor 的 await。两次事务可能同时处理同一个目标卷路径，干扰备份、发布和回滚。

修复要求：实现持有至异步事务结束的等待队列/门闩，正常、抛错、取消均可靠释放；覆盖并发同步同一关联记录，确认最大同时写入数为 1，且最终目录与可读卷一致。单纯给函数套 actor 不满足这一条件。

## 当前 Apple 证据边界

本地 IPA 仍为上一轮 SHA-256 `2EB75379F502FBECF790D00DC1B3B318BFD89A7C9F5CF1A44E19CB0AB52E4351`。上一轮 17 项 UI 测试与旧 IPA 的有效结论保留，但不能覆盖这次尚未提交的新 Swift 代码和新模型。本轮没有当前修复版本的 Apple 编译/推理运行证据。

此前要求的 iPhone/iPad、横竖屏、深浅主题及主要页面视觉对照仍按既有门槛执行，本轮没有扩展新的视觉细节清单。

## 可直接交给 Gemini

> 原隔离探针已全部通过，追更漏报和随机模型权重问题可以关闭。请按 `ACCEPTANCE_RECHECK_2_2026-10-10.md` 只收尾三个 P1：修正后台推理辅助函数的 MainActor 隔离编译错误；增加文件夹同步中断事务的启动恢复，禁止误删唯一备份；把 SingleWriterGate 改成真正跨 await 互斥的单一写入者。补齐对应失败条件的有效测试，不修改已通过探针的期望；完成当前代码的 Xcode 构建与实际 CoreML 图像预测验收，再生成对应版本 IPA。继续自主验收，未运行的 Apple 项目不得标 PASS，用户只负责最终总验收。不要围绕细微视觉差异反复扩展范围。

全部本轮证据位于 `review-evidence/2026-10-10-recheck-2/`，包括原探针当前输出、权重验证脚本与结果、恢复/互斥探针、actor 类型检查和 8 项核心回归日志。
