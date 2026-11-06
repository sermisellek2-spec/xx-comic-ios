# iOS 追平 Android 2.0.46 暨 iOS 15.0+（15.5）兼容开发计划

更新日期：2026-11-06  
目标基线：Android `master` **2.0.46 / versionCode 346** (`9d444e4`)  
iOS 工作区：`F:/softForCode/codex-project/xx-comic/.worktrees/ios-port`（分支 `codex/ios-port`）  
最低系统要求：**iOS 15.0**（完整兼容 iOS 15.5 等 iOS 15.x 设备与 iOS 16+ 设备，覆盖 iPhone 与 iPad）

---

## 一、阶段划分与文件唯一写入者分配

为确保多人/多子代理协作时不发生文件写冲突或构建缓存竞争，所有子代理仅修改各自独立分配的文件，构建与测试统一由主代理串行调度验证。

| 阶段 | 模块范围 | 对应 Android 参考 | 分配文件（唯一写入者） |
| --- | --- | --- | --- |
| **Stage 0** | **iOS 15.0+ (15.5) 最低部署目标兼容** | — | `ios/project.yml`、`ios/ComicCore/Package.swift`、`ios/XXComic/ThemeChoiceSheet.swift`、`ios/XXComic/DetailViewController.swift`、`ios/ComicCore/Tests/ComicCoreTests/KindlePublicationTests.swift`、`tools/audit-ios-package.py`（主代理已完成） |
| **Stage 1** | **2.0.45 全站搜索半匹配、高相似度评分与站源动态置顶** | `GlobalSearchMatchHelper.java`、`SourceOrder.java`、`GlobalSearchMatchHelperTest.java`、`SourceOrderTest.java` | `ios/ComicCore/Sources/ComicCore/SearchRules.swift`、`ios/ComicCore/Tests/ComicCoreTests/SearchRulesTests.swift` |
| **Stage 2** | **2.0.41~2.0.43 阅读器跨页还原、双页自动切分与自动缩放核心** | `SpreadDetector.java`、`SpreadPagePlan.java`、`SpreadStateStore.java`、`DoublePageDetector.java`、`DoublePagePlan.java`、`DoublePageStateStore.java`、`ReaderScalePolicy.java` | `ios/ComicCore/Sources/ComicCore/ReaderSpread.swift`、`ios/ComicCore/Sources/ComicCore/ReaderDoublePage.swift`、`ios/ComicCore/Sources/ComicCore/ReaderScalePolicy.swift`、`ios/ComicCore/Tests/ComicCoreTests/ReaderSpreadAndDoublePageTests.swift` |
| **Stage 3** | **2.0.46 详情页内嵌章节目录预览/分段跳转 & 2.0.44 离线选章网格/滑动多选组件** | `DetailChapterSectionView.java`、`ChapterSelectionGrid.java`、`SwipeChapterSelection.java` | `ios/ComicCore/Sources/ComicCore/DetailChapterSection.swift`、`ios/ComicCore/Tests/ComicCoreTests/DetailChapterSectionTests.swift`、`ios/XXComic/DetailChapterSectionView.swift`、`ios/XXComic/ChapterSelectionGridView.swift` |
| **Stage 4** | **2.0.43~2.0.44 新增漫画站源（卡拉/MangaDex/Gallery/Hipmh/Reviewed/Xcomic）与 VPN 徽标** | `KalamanhuaComicSource.java`、`MangaDexComicSource.java`、`GalleryComicSource.java`、`HipmhComicSource.java`、`ReviewedComicSource.java`、`ReviewedHtmlComicSource.java`、`XcomicComicSource.java`、`SourceVpnBadge.java` | `ios/ComicCore/Sources/ComicCore/KalamanhuaComicSource.swift`、`ios/ComicCore/Sources/ComicCore/ReviewedComicSources.swift`、`ios/ComicCore/Tests/ComicCoreTests/ReviewedSourcesTests.swift`、`ios/XXComic/SourceVpnBadgeView.swift` |
| **Stage 5** | **2.0.44 站源规则包、JS 规则引擎与订阅更新核心 (`source.rule.*`)** | `RuleDefinition.java`、`RuleCatalog.java`、`RuleStore.java`、`RuleCrypto.java`、`RuleHttp.java`、`RuleImages.java`、`RuleScript.java`、`ScriptComicSource.java`、`RuleSubscriptionUpdate.java` | `ios/ComicCore/Sources/ComicCore/SourceRules.swift`、`ios/ComicCore/Sources/ComicCore/ScriptComicSource.swift`、`ios/ComicCore/Tests/ComicCoreTests/SourceRulesTests.swift` |
| **Stage 6** | **2.0.45 离线下载并发提速、EPUB 批量兼容与全页面 UI 接线及 2.0.46 总回归** | `DownloadRuntime.java`、`SourceImageFetcher.java`、`EpubParser.java`、`MainActivity.java`、`ReaderSpreadSheet.java` | 主代理汇总接线、更新版本号至 `2.0.46 (346)` 并运行完整测试矩阵 |

---

## 二、iOS 15.0+ 编码约束

1. 严禁无条件使用 iOS 16.0+ 专属 API（如 `UISheetPresentationController.Detent.custom`、`ContinuousClock`、`Duration`、`Task.sleep(for:)`、`URL(filePath:)`、`URL.documentsDirectory`、Swift `Regex` 字面量、`UIBarButtonItem.isHidden`、`UIWindowScene.requestGeometryUpdate`）。
2. 如需在 iOS 16+ 使用更细腻的系统弹层高度（如 `.custom` detent），必须包裹在 `if #available(iOS 16.0, *)` 中，并提供完整的 iOS 15.0 回退实现（如 `[.medium(), .large()]` 或自定义底部面板）。

---

## 三、阶段完成状态

- **Stage 0（已完成）**：`ios/project.yml` 与 `ios/ComicCore/Package.swift` 最低系统目标下调至 **iOS 15.0**；全量排查并替换 `ContinuousClock` 为 `ProcessInfo.processInfo.systemUptime`，所有 `UISheetPresentationController.Detent.custom` 均包裹 `if #available(iOS 16.0, *)` 并提供 iOS 15 回退。
- **Stage 1（已完成）**：`SearchRules.swift` 与 `SearchRulesTests.swift` 完成 2.0.45 半匹配/子串/公共字符相似度评分（`calculateMatchScore`、`bestMatchScore`）、`SourceOrder.rankByScore` 与 `GlobalSearchState.visibleSourceIDs` 高匹配分站源置顶。
- **Stage 2 & 2B（已完成）**：`ReaderSpread.swift`、`ReaderDoublePage.swift`、`ReaderScalePolicy.swift`、`ReaderSpreadSheet.swift`、`ReaderSettingsViewController.swift` 及 `ReaderSpreadAndDoublePageTests.swift` 完成 2.0.41~2.0.43 跨页还原、双页宽图切分与自动缩放策略。
- **Stage 3（已完成）**：`DetailChapterSection.swift`、`DetailChapterSectionView.swift`、`ChapterSelectionGridView.swift` 及 `DetailChapterSectionTests.swift` 完成 2.0.46 详情页内嵌章节目录预览/分段跳转及 2.0.44 选章紧凑网格与滑动多选。
- **Stage 4（已完成）**：`KalamanhuaComicSource.swift`、`ReviewedComicSources.swift` 及 `ReviewedSourcesTests.swift` 完成 2.0.43~2.0.44 新增站源与 `SourceVpnPolicy` 标识。
- **Stage 5 & 5B（已完成）**：`SourceRules.swift`、`ScriptComicSource.swift`、`SourceRuleManagerViewController.swift` 及 `SourceRulesTests.swift` 完成 2.0.44 规则包、JavaScriptCore 沙盒规则引擎、订阅更新、首次空态引导卡片、批量操作与导入预览。
- **Stage 6（已完成代码实现，待 Docker/Apple CI 运行测试验证）**：`DownloadRuntime.swift` 多页并发章节下载与下一章预取、`EpubArchive.swift` / `EpubXML.swift` / `EpubParser.swift` 命名空间与字面量 `+` 路径兼容，以及 `AppEnvironment.swift`、`DetailViewController.swift`、`DownloadSelectionViewController.swift`、`ReaderViewController.swift`、`DiscoverViewController.swift`、`SourceSwitchSheet.swift`、`SourceSettingsViewController.swift` 全页面接线。
