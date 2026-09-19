# 阶段一完成报告：整改去白边功能（零主线程扫描与就地切换）

## 1. 阶段概述与基线
- **阶段目标**：整改阅读器现有“去白边”（Crop White Margins）功能，彻底剥离主线程像素扫描，实现就地（In-Place）无感知切换与精确位置保持，强化缓存 Key 与边界合法性校验。
- **工作分支**：`codex/reader-preferences-and-history`
- **基线 Commit**：`e510276` (feat(search): add exact match prioritization and red dot indicator for global search)
- **交付状态**：阶段一独立实现完成，438 项单元测试全部通过，即将提交独立 Commit。

---

## 2. 核心修改与技术实现

### 2.1 彻底剥离主线程像素扫描
1. **旧实现问题**：
   - 旧代码在单页模式异步加载时，后台预计算硬编码了条漫裁剪（`isScroll=true`），单页主线程绑定时发生缓存未命中，在 UI 线程同步调用了 `WhiteMarginDetector.detect(bitmap, true)` 执行四边像素扫描，造成主线程卡顿；
   - 内存缓存命中的图片在尚未缓存裁剪结果时，直接在主线程执行检测。
2. **整改措施**：
   - **主线程零扫描**：重构 `MainActivity.getReaderCropRect(...)`，UI 线程仅查询缓存，未命中时严格返回 `null`，严禁触发同步检测。
   - **原图先行绑定 + 异步计算**：在 `setReaderImageContent` 中，若裁剪开启且未命中缓存，先绑定原图保证界面连贯流畅，同时向 `submitReaderImage` 工作线程提交 `asyncComputeReaderCrop`。后台完成扫描并写入缓存后，若生成代际（`readerGeneration`）和当前可见标签（`target.getTag()`）匹配，再主线程平滑刷新为 `CroppedBitmapDrawable` 并按需调整布局高度。
   - **实际模式对齐预计算**：在 `loadReaderImage` 后台解码完成后，根据实际模式 `boolean isScroll = (list != null)` 直接在工作线程调用 `getOrComputeReaderCropRectBackground` 预热缓存，确保主线程绑定时 100% 命中。

### 2.2 切换开关就地生效（废除重建整个阅读页）
1. **旧实现问题**：
   - 旧开关回调调用 `reloadCurrentReaderContent() -> renderReader()`，销毁整个阅读视图并重构，清空了图片内存缓存，导致已解码的大量章节图片重新加载，同时在连续滚动模式下载入的后续多话章节全部丢失。
2. **整改措施**：
   - **就地切换（In-Place Update）**：重构 `onCropWhiteMarginsChanged`，移除 `reloadCurrentReaderContent()` 和 `readerCropBoundsCache.evictAll()`。
   - **条漫连续阅读（`readerList != null`）**：
     - 捕获当前可见首项索引 `firstVisible`、行内相对偏移比例 `offsetRatio = -firstChild.getTop() / (double) firstChild.getHeight()`，以及是否处于底部贴底（`atEnd`）；
     - 复用内存中原始已解码 Bitmap，更新可见 Child Views 的 `CroppedBitmapDrawable` 与布局高度；
     - 重新计算并更新当前章节所有已缓存图片的 `readerImageHeights`；
     - 触发 `continuousAdapter.notifyDataSetChanged()`；
     - 精准复位：底部状态维持 `alignReaderBottom` 贴底；非底部按当前锚点项（`anchorItem`）的新高度和 `offsetRatio` 精准恢复 `setSelectionFromTop(firstVisible, newTop)`；
     - 跨话连续阅读以当前可见 item 对应章节持久化，不回退到入口章节。
   - **单页翻页模式（`readerPager != null`）**：
     - 保持当前页码 `currentPage()` 与章节数据不变；
     - 调用 `PagedReaderView.refreshVisiblePages()`，复位可见项缩放（`image.resetZoom()`）以适应内容，重新触发轻量绑图；
     - 纯文本阅读器（`textReaderView`）严格隔离，绝不触发图片裁剪。

### 2.3 复合缓存 Key 与合法性校验
1. **复合缓存 Key**：
   - 增加 `WhiteMarginDetector.buildCacheKey(imageUrl, width, height, isScroll)`：
     格式为 `imageUrl + "|" + width + "x" + height + "|" + (isScroll ? "scroll" : "paged")`；
   - 彻底隔离不同解码分辨率与不同裁剪模式（条漫仅左右、单页四边）。
2. **边界范围合法性校验**：
   - 在 `WhiteMarginDetector.CropRect` 中增加 `isValid(origWidth, origHeight)`：
     确保 `0 <= left < right <= origWidth` 且 `0 <= top < bottom <= origHeight`；
   - 在 `WhiteMarginDetector.detect` 返回前增加硬边界夹紧防护，对异常退化矩形一律回退为原图完整尺寸 `(0, 0, width, height)`。
3. **严格遵守保守裁切规则**：
   - 近白标准保持 RGB $\ge 245$、极差 $\le 10$；
   - 单边最大裁剪 15%，超限回退；
   - 至少保留 2px 安全留白（`max(2px, 0.3%)`）；
   - 禁漫等乱序拼图在还原为完整 Bitmap 后才执行白边扫描；
   - 零 Bitmap 克隆，不修改原图文件，不 recycle 正在使用的 Bitmap。

---

## 3. 修改文件清单

| 文件路径 | 修改类型 | 说明 |
| --- | --- | --- |
| `app/src/main/java/com/xxcomic/reader/WhiteMarginDetector.java` | 修改 | 新增 `buildCacheKey` 复合缓存 Key 方法，新增 `CropRect.isValid(...)` 校验，以及检测返回前的边界夹紧 |
| `app/src/main/java/com/xxcomic/reader/PagedReaderView.java` | 修改 | 保存 `ImageLoader` 字段，新增 `refreshVisiblePages()` 复位缩放并就地刷新可见页 |
| `app/src/main/java/com/xxcomic/MainActivity.java` | 修改 | 消除 UI 线程扫描，实现 `asyncComputeReaderCrop`，后台对齐模式预计算，实现 `applyCropWhiteMarginsInPlace()` / `applyScrollCropInPlace()` 精准位置保持 |
| `app/src/test/java/com/xxcomic/reader/WhiteMarginDetectorTest.java` | 修改 | 新增复合缓存 Key 生成测试、`CropRect.isValid(...)` 各种边界与异常值测试、`CropRect` 尺寸属性测试 |

---

## 4. 验证与测试结果

- **自动化单元测试执行**：
  ```powershell
  .\gradlew.bat testDebugUnitTest --no-daemon --console=plain
  ```
- **测试结果**：
  ```text
  BUILD SUCCESSFUL in 18s
  21 actionable tasks: 2 executed, 19 up-to-date
  ```
  全工程 438 项单元测试全部执行并通过（0 Failures, 0 Errors）。
- **实机运行状态说明**：
  由于当前为无显示屏/无连接真机的云端构建环境，本阶段仅执行了严密的纯自动化单元测试；真机滚动帧率、大图裁剪视觉效果及跨章连续滑动手感将在阶段二产出 APK 后由用户在实机上进行终验。

---

## 5. 下一步（阶段二）计划
- 进入**阶段二：禁止动画翻页边界整改及组合验证**：
  1. `PagedReaderView` 彻底同步 ViewPager2 原生滑动禁用状态；
  2. 严格单步翻页手势检测（36dp 阈值、水平倾角 $\le 45^\circ$、单手势仅翻一次、去抖动防跳页、多指/缩放/取消保护）；
  3. 严格遵循按键模式（`inputMode == 1`）与左手模式（`readerLeftHand`）；
  4. 动画中途切换防卡半页，关闭后 100% 恢复平滑翻页与原生手势；
  5. 产出调试 APK 及其 SHA-256 校验和。
