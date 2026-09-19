# 阶段 1 完成报告：增加完全本地的启动书架习惯

## 1. 阶段名、基线与实际提交号
- **阶段名**：阶段 1：增加完全本地的启动书架习惯
- **分支**：`codex/reader-preferences-and-history`
- **基线 Commit**：`6001164` (fix(history): resolve out-of-bounds crash in history progress label)
- **当前 Commit**：`faa22e0`

## 2. 修改文件与接入点
- `app/src/main/java/com/xxcomic/reader/ReadingHabitTracker.java`：新建完全本地的阅读习惯学习与冷启动标签解析状态机。
  - 支持启动书架三种模式：`自动跟随 (0)`、`我的书架 (1)`、`本地书架 (2)`。
  - 支持会话级状态机：`onEnterReader`、`onContentReadable`、`onUserAction`、`onOverlayVisibilityChanged`、`onAppBackground`、`onAppForeground`、`onExitReader`、`tick`。
  - 学习条件：连续可读且无菜单阻挡有效阅读满 60 秒且发生过交互；单次会话只计一票。
  - 判定规则：有效样本在过去 30 天内，至少 3 票，单一类型达到 70% 绝对优势才产生偏好；平局或均不占优时保持上一状态（滞后回滞）；无样本时默认我的书架。
  - 纯本地 SharedPreferences（`xxcomic_reading_habits`）持久化（JSON 样本集与偏好），不包含任何用户标识、分析统计或网络上报。
- `app/src/test/java/com/xxcomic/reader/ReadingHabitTrackerTest.java`：新建 15 组单元测试，覆盖冷启动解析、模式手动切换与持久化、30天样本过期、70%单向倒向与滞后、前后台切入切出时钟偏移、菜单打开暂停计时等场景。
- `app/src/main/java/com/xxcomic/MainActivity.java`：
  - 接入 `readingHabitTracker` 实例及 2 秒轮询 Runnable `readerTickRunnable`。
  - 在 `onCreate` 中恢复习惯状态，冷启动时根据 `resolveCurrentLaunchTab()` 设置初始 `bookshelfTab`。
  - 在 `switchBookshelfTab` 中记录 `lastManualTab`，保证用户手动点击书架标签即时记录。
  - 在设置页“阅读与外观”中增加“启动书架”条目与底部抽屉弹窗（单选三种模式，自动跟随模式附带实时文案反馈，如“根据近期阅读习惯自动打开我的书架/本地书架”）。
  - 全流程埋点接驳阅读生命周期：
    1. `showReader`：调用 `onEnterReader(comicId, isLocalComicDetail(detail))`；
    2. `renderTextReader`：调用 `onEnterReader(comicId, true)` 和 `onContentReadable()`；
    3. `continuousAdapter.getView` / `loadReaderImage` / `PagedReaderView.onPageChanged`：调用 `onContentReadable()`；
    4. `list.setOnScrollListener` (SCROLL_STATE_TOUCH_SCROLL / FLING)：调用 `onUserAction()`；
    5. `navigateReader` / `readerSeekBar` / `PagedReaderView.onInteraction`：调用 `onUserAction()`；
    6. `setReaderFullscreen`：调用 `onOverlayVisibilityChanged(!fullscreen)`；
    7. `enterScreen` / `onDestroy`：调用 `onExitReader()`，清理阅读计时器；
    8. `onResume` / `onPause`：调用 `onAppForeground()` / `onAppBackground()`。

## 3. 修复证据与测试结果
- **验证命令**：
  `.\gradlew.bat testDebugUnitTest`
- **测试结果**：
  - `ReadingHabitTrackerTest` 15 组单元测试全部一次性通过。
  - `HistoryProgressLabelTest` 5 组单元测试全部通过。
  - 全工程编译构建及单元测试通过：`BUILD SUCCESSFUL in 19s, 21 actionable tasks: 5 executed, 16 up-to-date`。

## 4. 对现有行为的影响与兼容方式
- 默认设置为“自动跟随”，首次使用且无习惯记录时无缝回退至默认“我的书架”，现有行为保持 100% 兼容。
- 用户可随时在设置中强制指定“我的书架”或“本地书架”，设置后优先级高于自动习惯。
- 零外部权限、零网络依赖、零后台常驻服务。

## 5. 未执行的检查、局限与已知风险
- 自动化测试在 JVM 虚拟时钟与 Robolectric 级别验证了状态机所有分支，真机实际操作（如真实滑动速度、长期待机唤醒）留待阶段 4 真机综合验收。

## 6. 下一阶段内容
- 进入**阶段 2：增加禁止动画翻页开关**（`reader.disable.page.animation`，去除平滑过渡动画、关闭 ViewPager2 滑动手势动效等）。
