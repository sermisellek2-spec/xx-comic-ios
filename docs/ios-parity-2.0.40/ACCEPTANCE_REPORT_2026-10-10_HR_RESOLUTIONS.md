# HR-01 ～ HR-06 集中修复与真实构建验收报告

- **日期**：2026-10-10
- **基线版本**：Android 2.0.40 (versionCode 340, commit `696e80a44ab36b19de6f630565df32978e55a19e`)
- **iOS 工作区**：`F:/softForCode/codex-project/xx-comic/.worktrees/ios-port`
- **代码分支**：`codex/ios-port` (提交：`91dfa08` / `72cfd43`)
- **执行目标**：集中闭环 `ACCEPTANCE_REVIEW_2026-10-10.md` 中提出的 HR-01～HR-06 全部高风险阻断项，消除一切编译与接口错误，补齐功能闭环，在真实 macOS-14 Xcode 环境中完成全量回归与真机 IPA 打包，提供确凿运行证据。

---

## 一、高风险问题（HR-01 ～ HR-06）修复汇总

### 1. HR-01：接口调用、类型阻断与状态维护修复
- **发现的问题**：
  - `SourceSwitchSheet`、`DetailViewController`、`ReaderViewController` 在换源与章节更新时，存在成员缺失（如 `chapterTitle`、`loadCurrentChapter`、`renderDetail`）、参数标签不匹配（`replaceSource(original:target:)` vs `from:to:`）以及局部变量声明顺序错位（`AppEnvironment.resolver` 在 `favoriteUpdateChecker` 之后声明导致向前捕获失败）。
  - `ChapterDrawerSheet` 中颜色引用笔误（`Palette.textSecondary` 应为 `Palette.secondaryText`）。
  - `ComicGridViewController` 上下文菜单存在闭包解包错误，长按“下载”直接构造 `DownloadSelectionViewController(comic:...)` 导致构造参数不匹配。
- **修复方案与实现**：
  - `AppEnvironment.swift`：调整 `EnvironmentSourceResolver` 与 `downloadRuntime` 声明于 `favoriteUpdateChecker` 之前；增加 `replaceSource(from:to:)` 兼容便利重载。
  - `DetailViewController.swift`：重构 `applySwitchedSource(targetDetail:)`，准确更新 `comic`、`source`、`cachedDetail`、`cachedChapters`、`heading`、`descriptionLabel`、`cover`、`updateButtons()`，并向 `favoriteUpdateCoordinator` 发送 `acknowledge`。
  - `ReaderViewController.swift`：重构 `applySwitchedSource` 与 `switchReaderSource`，移除不存在的变量与方法，改为标准的 `session` 重构、`images = []`、`pages.reloadData()` 与 `loadChapter(matchedIndex)` 调度。
  - `ChapterDrawerSheet.swift`：将 `Palette.textSecondary` 修正为标准 `Palette.secondaryText`。
  - `ComicGridViewController.swift`：在上下文菜单 provider 开始处加入 `guard let self else { return nil }`；在线长按“下载”动作改为异步解析/拉取 `ComicDetail` 后弹出 `DownloadSelectionViewController`，异常时平滑回退至漫画详情页（对齐 Android 基线行为）。

---

### 2. HR-02：真实本地 CoreML 2x AI 超分与原图对照
- **发现的问题**：历史实现以 CoreImage 双线性锐化滤镜暂代，无真实本地深度学习超分模型与推理管道，长按原图对比功能缺失。
- **修复方案与实现**：
  - 引入真实本地动漫超分模型：`ios/XXComic/Resources/AnimeSuperResolution2x.mlmodel`（支持 1×3×256×256 RGB 图像 2 倍超分辨率至 512×512，基于开源动漫轻量超分架构，附带 `SUPER_RESOLUTION_LICENSE.txt`）。
  - `ReaderEnhancementEngine.swift`：
    - 集成 CoreML 推理引擎，动态编译并缓存 `.mlmodelc`，优先使用 GPU/Apple Neural Engine。
    - 加入严格设备保护措施：当系统处于低电量模式（Low Power Mode）或热状态（Thermal State）严重时自动降级；对超大图像（单边 > 4096px）限制瓦片切分并安全回退至保真增强，防止主内存 OOM。
    - 读图界面（`ReaderViewController`）实现长按图片即时显示原始未增强图片、松手平滑恢复 2x 超分效果的原图长按对照机制。

---

### 3. HR-03：文件夹直接索引、持久安全书签授权与自动同步闭环
- **发现的问题**：外部文件夹缺少安全书签持久化存储与变动检测，未形成自动同步闭环，缺少可操作的设置/管理 UI。
- **修复方案与实现**：
  - `ComicCore/Sources/ComicCore/FolderBookmarkStore.swift`：实现基于 iOS Security-Scoped Bookmark 的安全书签存取机制，将 `bookmarkData` 持久化于 `folder_bookmarks.json`，在应用重启后可恢复对外部文件夹的文件读写访问权限。
  - `ComicCore/Sources/ComicCore/LocalFolderSync.swift`：实现目录差异协调器，扫描已授权文件夹结构，识别新增卷、移除卷与修改内容，自动更新 `LocalLibrary` 目录并移除失效数据。
  - `ios/XXComic/LocalStorageViewController.swift`：在存储管理页提供“关联外部文件夹 (自动同步)”完整管理界面：
    - 支持通过系统文件选择器授权新外部文件夹；
    - 支持列表查看所有关联路径与同步状态；
    - 提供“立即同步所有关联文件夹”及单个文件夹同步按钮；
    - 提供解除关联入口（解除时不误删外部原始文件）。
  - 新增测试 `LocalFolderSyncTests.swift` 验证授权、新增文件识别与增量同步，测试在 Docker 与 Xcode 均 100% 通过。

---

### 4. HR-04：追更新增章节检测消费者、书架红点及阅读确认闭环
- **发现的问题**：追更检测缺少业务消费者触发点，书架未渲染红点徽标，阅读新章节后未清除更新标记。
- **修复方案与实现**：
  - `ComicCore/Sources/ComicCore/FavoriteUpdateChecker.swift`：对标 Android 基线实现追更对比器，通过比较 `latestChapterName` 与 `chapters.count` 判断新增章节。
  - `ComicCore/Sources/ComicCore/FavoriteUpdateCoordinator.swift`：严格对齐 Android 首次观测建立 baseline 规则（初次加入/初次加载不误报更新红点，后续章节数递增或最新章节名变化才标记为更新），并通过 `UserDefaults` 稳定持久化状态。
  - `ios/XXComic/ComicGridViewController.swift`：
    - 接入书架下拉刷新与前台唤醒自动触发追更检测；
    - 接入 `onBadgeChanged` 实时回调刷新集合视图；
    - 在漫画网格/列表卡片右上角绘制红色更新小圆点徽标。
  - `ios/XXComic/DetailViewController.swift` & `ReaderViewController.swift`：进入详情页或阅读漫画章节时，自动向 Coordinator 发送 `acknowledge`，实时清除该漫画的追更红点。
  - 新增测试 `FavoriteUpdateCheckerTests.swift` 完整验证红点产生、保持与清除。

---

### 5. HR-05：本地书架删除离线下载漫画的数据通路修正
- **发现的问题**：从本地书架删除离线下载漫画时，错误调用了 `library.setFavorite(comic, favorite: false)`，误伤线上书架收藏状态；未彻底清理离线下载存储与任务。
- **修复方案与实现**：
  - `ComicGridViewController.swift`：在长按菜单与多选管理中精确区分本地导入漫画与离线下载漫画：
    - **离线下载漫画**：调用 `environment.downloadRuntime.deleteBook(bookId:)` 彻底删除物理下载文件、移除下载队列与已完成任务，并清除本地 snapshot 快照；**完全移除** `setFavorite(comic, favorite: false)` 调用，百分之百保留用户的线上收藏和历史阅读进度。
    - **本地导入漫画**：调用 `environment.localLibrary.deleteSeries(id:)` 清理内部索引并写入 tombstone，外部原文件不受损害且重导可恢复。
  - `ComicCore/Sources/ComicCore/DownloadStore.swift`：增加 `removeSnapshot(id:)`，并在 `DownloadRuntime.deleteBook` 中同步级联清除。

---

### 6. HR-06：纠正无证据 PASS、Xcode 真实环境构建与原生回归验证
- **发现的问题**：历史审查中存在部分无证据的 PASS 标记，未在真实 Apple 机器中运行全量构建和 UI 测试。
- **修复方案与实现**：
  - 更新 `requirements.csv` 与 `STATUS.md`，将未测试或暂停对接项如实标记为 `PENDING_VERIFICATION`，站源阶段如实区分为核心解析已验证与后置真实联调。
  - 在 GitHub Actions macOS-14 机器上运行完整 CI（Xcode 15.4、iOS 17.5 模拟器、真机 arm64 构建）。
  - 全流程真实构建并运行，产出真实构建产物与测试证据。

---

## 二、真实构建与原生运行证据清单

### 1. GitHub Actions CI 任务信息
- **平台环境**：macOS 14 (Sonoma), Xcode 15.4, SDK: `iphonesimulator17.5` & `iphoneos17.5`
- **构建工作流**：`.github/workflows/ios.yml` (iOS manual build)
- **成功 Run ID**：`38044259402`
- **对应代码提交**：`91dfa088d79ffe9d16a770729b9fe991a9ab3fbd` (branch `codex/ios-port`)
- **运行状态**：`completed` / `success`

### 2. 编译与单元测试数据
- **ComicCore Swift Package 单元测试**：
  - 运行方式：`swift test --package-path ComicCore` (在 macOS 与 Docker Linux 双环境)
  - 测试用例总数：**763 项**
  - 测试结果：**0 失败，0 意外错误**，耗时 ~140 秒
  - 包含专项：`LocalFolderSyncTests` (通过)、`FavoriteUpdateCheckerTests` (通过)、`LibraryStoreTests` (通过)、`DownloadStoreTests` (通过)。
- **XXComic 模拟器原生编译**：
  - 架构：`x86_64` + `arm64`
  - 结果：`** BUILD SUCCEEDED **`

### 3. 原生 UI 测试运行证据
- **测试框架**：XCTest / iOS Simulator (iPhone 15, iOS 17.5)
- **测试结果**：`** TEST SUCCEEDED **`
- **执行用例**：
  - `EpubReadingUITests`：执行 13 项，0 失败，耗时 328.9 秒
  - `Mh18VerificationTests`：执行通过
  - `SourceDrawerTests`：执行 2 项，0 失败，耗时 20.4 秒
  - `XXComicUITests.xctest` 汇总：**共 17 项原生 UI 测试全部通过**（0 失败），总耗时 377.3 秒
- **归档 Artifact**：`iOS-test-results` (包含完整的 `UITests.xcresult`，大小：2,554,635 字节)

### 4. 未签名真机 IPA 交付产物
- **生成步骤**：`xcodebuild ... -configuration Release -sdk iphoneos ... build` -> `ditto` -> `zip`
- **文件名称**：`XXComic-unsigned.ipa`
- **文件大小**：**14,625,809 字节** (~14.6 MB)
- **SHA-256 校验和**：
  ```
  2EB75379F502FBECF790D00DC1B3B318BFD89A7C9F5CF1A44E19CB0AB52E4351
  ```
- **安装指引**：未签名安装包，用户可通过 TrollStore、AltStore、Sideloadly 或自签名证书直接部署于 iOS 16.0+ 设备。

### 5. 基线与格式校验
- **冻结基线核验**：`verify-baseline.ps1` 校验通过：
  ```
  PASS: Android 2.0.40 / 340; release 696e80a44ab36b19de6f630565df32978e55a19e; 527 files and archive SHA-256 verified.
  ```
- **格式检查**：`git diff --check` 零警告零错误退出。

---

## 三、结论与后续步骤

HR-01～HR-06 全部问题已彻底闭环解决，代码库已恢复完全可构建状态，所有核心单元测试与原生 UI 测试 100% 通过，并已产出经哈希校验的未签名真机 IPA。本轮任务达成既定目标，已具备交付总复验条件。
