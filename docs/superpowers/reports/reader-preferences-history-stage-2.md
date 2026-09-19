# 阶段 2 完成报告：增加禁止动画翻页开关

## 1. 阶段名、基线与实际提交号
- **阶段名**：阶段 2：增加禁止动画翻页开关
- **分支**：`codex/reader-preferences-and-history`
- **基线 Commit**：`46a43aa` (feat(bookshelf): add local reading habit tracker and launch bookshelf preference)
- **当前 Commit**：`98453e6`

## 2. 修改文件与接入点
- `app/src/main/java/com/xxcomic/reader/ReaderSettingsSheet.java`：
  - 增加设置项“禁止动画翻页”（key: `reader.disable.page.animation`，默认 false），副文案为“开启后直接切页，滑动手势仍可用”。
  - 优化抽屉正文容器结构：增加 `MaxHeightScrollView`（限制最大高度为屏幕高度 65%），使得小屏幕、横屏和较大字体环境下均可完整操作所有设置行。
  - 在 `SheetRootLayout.onInterceptTouchEvent` 中注入 ScrollView 向上滚动状态检查（`scrollView.canScrollVertically(-1)`），避免正文向下滚动时被底部抽屉的下滑关闭手势抢占；顶部拖柄及正文处于顶部时正常保留下滑关闭交互。
  - `OnSettingsChangeListener` 新增 `onDisablePageAnimationChanged(boolean disabled)` 默认接口方法。
- `app/src/main/java/com/xxcomic/reader/PagedReaderView.java`：
  - 接入 `animationDisabled` 状态及运行时即时切换方法 `setAnimationDisabled(boolean)`。
  - `updateUserInputEnabled()` 统一管控原生 ViewPager2 用户输入：当动画被禁用时，强制关闭原生 ViewPager2 的手势拖拽（`pager.setUserInputEnabled(inputMode != 1 && !isZoomed() && !animationDisabled)`），避免手指拖动时产生平滑位主动画。
  - `moveTo(int page)` 统一使用 `pager.setCurrentItem(page, !animationDisabled)`，开关开启时立即瞬间切页。
  - 在 `dispatchTouchEvent` 中，当 `animationDisabled` 为真时，复用既有手势识别（`ReaderNavigation.swipeDelta`，阈值 36dp、水平角度判定且时限 1000ms 内），松手后直接通过 `listener.onNavigate(delta)` 瞬间切页或跨章。
  - 触控中途切换开关时自动置位 `blockedGesture = true`，取消本次手势，避免状态不一致。
- `app/src/main/java/com/xxcomic/MainActivity.java`：
  - 增加 `readerDisablePageAnimation` 字段；在 `restoreLocalState` 和 `saveLocalState` 中持久化 `reader.disable.page.animation`。
  - 在 `showReaderSettingsDrawer` 中将开关传入 `ReaderSettingsSheet`，并在变更时保存并即时通知 `readerPager.setAnimationDisabled(disabled)`。
  - 在 `renderReader` 初始化 `readerPager` 时传入当前开关状态。
  - 条漫（连续滚动）模式：横滑切章时，若开启无动画模式，禁用 `v.setTranslationX` 横向位移与松手后的 220ms 回弹动画；垂直滚动及连章加载原生惯性保持不变。
- `app/src/test/java/com/xxcomic/reader/PagedAnimationDisableTest.java`：
  - 新建 5 组单元测试，覆盖监听器默认方法兼容性、开关值变动捕获、左右滑动与日漫反向滑动判定、手势误触与斜滑排除、以及章内切页与跨章边界的精准识别。

## 3. 修复证据与测试结果
- **验证命令**：
  `.\gradlew.bat testDebugUnitTest`
- **测试结果**：
  - `PagedAnimationDisableTest` 5 组测试全部通过。
  - `ReaderSettingsSheetTest` 5 组测试全部通过。
  - `ReadingHabitTrackerTest` 15 组测试全部通过。
  - `HistoryProgressLabelTest` 5 组测试全部通过。
  - 全工程测试通过：`BUILD SUCCESSFUL in 19s, 21 actionable tasks: 5 executed, 16 up-to-date`。

## 4. 对现有行为的影响与兼容方式
- 默认值为 `false`，既有平滑过渡动画和原生 ViewPager2 滑动手感保持 100% 现状。
- 开启后仅去除切页与切章动画，图片放大后的平移/双指缩放手感完全不受影响；中间轻触、沉浸模式、设置/目录抽屉等基础界面动效不受影响。
- 设置抽屉使用 MaxHeightScrollView，解决了此前特定分辨率或系统字体放大后底部开关可能被遮挡的问题。

## 5. 未执行的检查、局限与已知风险
- 物理真机手感、墨水屏真实刷新延迟留待阶段 4 进行全面真机体验验收。

## 6. 下一阶段内容
- 进入**阶段 3：增加保守去白边开关**（`reader.crop.white.margins`，WhiteMarginDetector 矩形检测、CroppedBitmapDrawable 包装、图片流水线接入与边界缓存）。
