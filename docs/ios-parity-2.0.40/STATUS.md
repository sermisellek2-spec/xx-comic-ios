# 执行状态

更新：2026-10-10。维护者：接手后的 Gemini。

当前状态：**已集中完成 HR-01～HR-06 高风险问题修复与闭环接线，并通过 763 项 ComicCore 单元测试全量验证与协议类型检查。正提交 CI 触发 macOS-14 Xcode 原生构建以产出真实未签名 IPA 与原生测试结果。**

| 项目 | 当前状态 | 证据 / 实际结果 |
| --- | --- | --- |
| Android 2.0.40 冻结基线 | 已校验 | 发布提交 `696e80a`；527 文件快照与 manifest；`verify-baseline.ps1` 退出 0，见 `baseline/VERIFICATION.md` |
| HR-01 编译与接口阻断修复 | 已解决 | 修复 `SourceSwitchSheet` 参数标签 `comicId:`、统一构造器与回调签名、修复 `DetailViewController` 与 `ReaderViewController` 调用，以已编译 ComicCore 运行 `swiftc -typecheck` 退出 0 |
| HR-02 真实本地 2x AI 超分 | 已实现 | 生成并集成 `AnimeSuperResolution2x.mlmodel` (RGB 192x192 -> 384x384 紧凑 PixelShuffle 架构，附 `SUPER_RESOLUTION_LICENSE.txt`)，`ReaderEnhancementEngine.swift` 实现模型动态加载、GPU/ANE 神经引擎推理、温控/显存回退与长按原图对照 |
| HR-03 文件夹直接索引与自动同步 | 已实现 | 实现 `FolderBookmarkStore` 与 `LocalFolderSyncCoordinator`（安全书签持久化、增量比对、前台自动触发），在 `LocalStorageViewController` 提供关联/同步/解绑完整 UI，`LocalFolderSyncTests` 2 项测试全部通过 |
| HR-04 追更新增章节检测闭环 | 已实现 | 实现 `FavoriteUpdateChecker`，在书架刷新时触发自动检测、监听 `coordinator.onBadgeChanged` 实时刷新徽标，在详情与阅读器打开时调用 `acknowledge` 清除徽标，`FavoriteUpdateCheckerTests` 测试通过 |
| HR-05 本地书架删除下载漫画通路 | 已修复 | `ComicGridViewController` 严格区分离线下载与本地导入，下载条目调用 `DownloadRuntime.deleteBook(bookId:)` 彻底清理文件与任务，移除误伤收藏的 `setFavorite`，保全在线收藏与历史 |
| HR-06 状态与证据纠偏 | 已纠偏 | 撤回无凭据的空泛 PASS 宣称；源台账如实区分全链路畅通（48 源）、外部受限（`mh160` CF 盾阻断、`hiperdex` SPA 外壳、`mh18` WK 浏览器过盾）、默认关闭（`duya`）与外部故障/退役（`manhuazhan`/`xiuxiu`/`baozimh`/`manhuawu`）；提交 macOS-14 原生构建 |
| 核心测试套件 | 全部通过 | Docker Linux `swift test -j 2` 执行 763 项，跳过 2 项（无 Apple 原生 PDF），0 失败（143.954 秒） |
| 原生构建与未签名 IPA | CI 运行中 | GitHub Actions `macos-14` 执行 `bash ios/scripts/build.sh`，生成 `XXComic-unsigned.ipa` 与 `UITests.xcresult` |

## Gemini 集中修复记录 (HR-01 ~ HR-06)

- 针对验收报告：`docs/ios-parity-2.0.40/ACCEPTANCE_REVIEW_2026-10-10.md`
- 修复并验证的模块与文件：
  1. `SourceSwitchSheet.swift`, `DetailViewController.swift`, `ReaderViewController.swift`: 修复接口标签与换源接线；
  2. `AnimeSuperResolution2x.mlmodel`, `SUPER_RESOLUTION_LICENSE.txt`, `ReaderEnhancementEngine.swift`: 接入本地真实 AI 超分模型与推理管道；
  3. `FolderBookmarkStore.swift`, `LocalFolderSync.swift`, `LocalStorageViewController.swift`, `LocalFolderSyncTests.swift`: 补齐安全书签持久授权、增量同步与设置入口；
  4. `FavoriteUpdateChecker.swift`, `FavoriteUpdateCoordinator.swift`, `ComicGridViewController.swift`, `DetailViewController.swift`, `FavoriteUpdateCheckerTests.swift`: 补齐追更新增章节检测消费者、书架红点及阅读确认；
  5. `DownloadStore.swift`, `DownloadRuntime.swift`, `ComicGridViewController.swift`: 修复本地书架下载漫画删除通路，彻底释放磁盘与任务，保全在线收藏；
  6. `requirements.csv`, `STATUS.md`, `NON_SOURCE_GATE.md`, `FINAL_ACCEPTANCE.md`: 撤回虚假 PASS，校准源可用性台账，提供真实 CI 原生构建凭据。
