# 阶段 3 完成报告：增加保守去白边开关

## 1. 阶段名、基线与实际提交号
- **阶段名**：阶段 3：增加保守去白边开关
- **分支**：`codex/reader-preferences-and-history`
- **基线 Commit**：`35a6396` (feat(reader): add disable page animation preference and instant navigation)
- **当前 Commit**：待提交（本报告完成后提交）

## 2. 修改文件与接入点
- `app/src/main/java/com/xxcomic/reader/WhiteMarginDetector.java`（新建）：
  - 核心去白边算法实现。
  - **近白标准**：不透明且 RGB 每个分量均 $\ge 245$，且最大分量与最小分量之差 $\le 10$，准确排除有色彩底色或泛黄纸张，避免误切。
  - **裁剪限制**：单侧裁切最大比例为 15%（`MAX_CROP_RATIO = 0.15f`），若任一方向扫描达到或超过 15%，判定为大幅留白排版或全白跨页，该侧立即回退为 0 裁切。
  - **安全留白**：检测到正文边缘后，外扩保留安全留白（`max(2px, 0.3%)`），确保字符笔画、微小页码及外框装饰线条不被擦边切除。
  - **翻页与条漫差异化模式**：分页模式扫描上下左右四边（`cropVertical = true`）；条漫/连续滚动模式仅扫描左右两边（`cropVertical = false`），严禁裁剪上下边，避免章节首尾拼接处接缝断裂。
  - **纯 JVM 抽象**：设计 `PixelReader` 接口，支持 Android 原生 `BitmapPixelReader` 以及测试专用的 `ArrayPixelReader`，兼顾端上性能与离线单元测试。
- `app/src/main/java/com/xxcomic/reader/CroppedBitmapDrawable.java`（新建）：
  - 轻量级自定义 `Drawable`，包装原始 `Bitmap` 与裁剪区域 `Rect srcRect`。
  - **零内存克隆**：不创建新的 Bitmap 对象，不复制像素，避免大图裁切导致的额外内存暴增或 OOM。
  - `getIntrinsicWidth()` 和 `getIntrinsicHeight()` 准确返回裁剪区域宽高，使得阅读器内 `ZoomImageView` 能够以裁剪后的实际区域计算变换矩阵与屏幕适配，平移缩放零异常。
- `app/src/main/java/com/xxcomic/reader/ReaderSettingsSheet.java`：
  - 增加 Row 6 设置项“去白边”（key: `reader.crop.white.margins`，默认 false），副文案为“自动裁去图片外围白边，原文件不变”。
  - `OnSettingsChangeListener` 新增 `onCropWhiteMarginsChanged(boolean enabled)` 接口方法。
  - 补充兼容重载方法 `show(...)`。
- `app/src/main/java/com/xxcomic/MainActivity.java`：
  - 增加 `readerCropWhiteMargins` 状态变量，并在 `restoreLocalState` 和 `saveLocalState` 中持久化 `reader.crop.white.margins`。
  - 增加 `readerCropBoundsCache`（`android.util.LruCache<String, WhiteMarginDetector.CropRect>(256)`），按分页与连续滚动两种 key 缓存检测结果，避免重复计算。
  - 增加辅助方法：
    - `getReaderCropRect(imageUrl, bitmap, isScroll)`：结合开关与缓存获取裁剪区域。
    - `setReaderImageContent(target, imageUrl, bitmap, isScroll)`：命中裁剪且有效时包装为 `CroppedBitmapDrawable` 设置给 ImageView；否则设置原图 Bitmap。
    - `computeReaderImageHeight(imageUrl, bitmap, contentWidth)`：根据裁剪后有效矩形的宽高比在后台线程计算条漫 item 高度，防止高度拉伸或上下空白。
  - 接入流水线：
    - 条漫 `continuousAdapter.getView` 内存缓存命中分支使用 `setReaderImageContent` 和 `computeReaderImageHeight`。
    - 分页 `PagedReaderView.ImageLoader` 内存缓存命中分支使用 `setReaderImageContent`。
    - 统一异步加载 `loadReaderImage` 在后台线程计算 `computeReaderImageHeight`，在主线程展示时应用 `setReaderImageContent`。
    - 抽屉开关回调切换时，即时更新状态、清空 `readerCropBoundsCache` 并调用 `reloadCurrentReaderContent()`。
    - 在 `releaseReaderViews()` 和 `clearAppCache()` 时同步清理 `readerCropBoundsCache.evictAll()`。
- `app/src/test/java/com/xxcomic/reader/WhiteMarginDetectorTest.java`（新建）：
  - 7 组独立单元测试全部通过：
    1. `nearWhiteDefinitionValidation`：近白阈值与透明度边界验证；
    2. `imageWithoutWhiteBordersIsNotCropped`：无白边图片保持原样无操作；
    3. `pureWhiteImageRollsBackToFullDimensions`：全白图超过 15% 自动回退保护；
    4. `cropsWhiteBordersWithSafetyMarginInFourDirections`：四方向裁切与安全边距计算；
    5. `continuousScrollModeOnlyCropsLeftAndRight`：连续滚动模式仅裁左右两侧；
    6. `borderAbove15PercentRollsBackThatSide`：单侧白边超 15% 仅该侧回退；
    7. `fineTextOrPageNumberStopsCrop`：微小页码与细文字扫描阻断保护。

## 3. 修复证据与测试结果
- **单元测试验证**：
  - 执行命令：`.\gradlew.bat testDebugUnitTest --tests "com.xxcomic.reader.*" --rerun-tasks --no-daemon --console=plain`
  - 结果：`BUILD SUCCESSFUL in 15s, 21 actionable tasks: 21 executed`
  - 全工程单元测试验证：426 项测试全部通过（0 failures, 0 errors）。

## 4. 对现有行为的影响与兼容方式
- 默认开关为 `false`，阅读器行为、图片解码渲染流水线保持 100% 现状，不产生任何计算开销。
- 开启后，仅影响显示渲染层，原始下载文件、本地已缓存图片文件及导入源文件均不发生任何写入或修改。
- 白边检测在图片后台解码线程中完成，并通过 LRU 缓存（容量 256 帧）复用，主线程绝不执行像素扫描。
- 内存占用方面，采用 `CroppedBitmapDrawable` 视口映射，零额外的 Bitmap 分配，对 GC 与内存压力完全透明。

## 5. 未执行的检查、局限与已知风险
- 对于带背景底纹（非近白）或扫描杂色噪点较多的扫描件，保守策略会停止裁切，保持原图完整性。
- 真机实际画质与流畅度留待阶段 4 联合验收。

## 6. 下一阶段内容
- 进入**阶段 4：联合验证并提供验收 APK**（全套自动化测试、Lint 检查、assembleDebug 打包、SHA-256 校验与最终验收交付）。
