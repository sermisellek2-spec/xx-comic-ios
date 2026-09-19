# 阶段 0 完成报告：修复本地漫画阅读历史闪退

## 1. 阶段名、基线与实际提交号
- **阶段名**：阶段 0：修复本地漫画阅读历史闪退
- **分支**：`codex/reader-preferences-and-history`
- **基线 Commit**：`9d34449`
- **当前 Commit**：（待提交）

## 2. 修改文件与接入点
- `app/src/main/java/com/xxcomic/reader/HistoryProgressLabel.java`：新建纯显示逻辑工具类，提供 `label(int savedIndex, List<String> chapterTitles)` 方法。
- `app/src/test/java/com/xxcomic/reader/HistoryProgressLabelTest.java`：新建单元测试，覆盖越界索引、有效索引、负数索引、空目录及异常标题回退。
- `app/src/main/java/com/xxcomic/MainActivity.java`：
  - 导入 `HistoryProgressLabel`。
  - 在 `showHistory()` 中对 `lastViewedAt` 条目按安全时间戳降序排序，并对每行渲染添加 try-catch 保护，避免单条脏记录使整个历史无法打开。
  - 在 `historyRow()` 中提取 `detail.chapters` 或本地 `localChapters` 的标题列表，使用 `HistoryProgressLabel.label(chapterIdx, chapterTitles)` 计算阅读进度文案，移除原 `chapterIdx >= detail.chapters.size() - 1` 时直接调用 `get(chapterIdx)` 导致的确定性越界崩溃缺陷。

## 3. 修复证据与测试结果
- **缺陷复现机制**：当漫画在历史记录中保存的进度索引（如 `chapterIdx = 256` 或合并/重导入后旧索引超出当前章节数）大于等于 `detail.chapters.size() - 1` 时，旧代码直接调用 `detail.chapters.get(chapterIdx)`，必然抛出 `IndexOutOfBoundsException` 导致 App 崩溃。本地书架有漫画时，`details.get(comicId)` 存在，因而必定触发该越界；清空书架后由于本地 detail 缺失，之前落入 fallback 因而暂未崩溃。
- **验证命令**：
  `.\gradlew.bat testDebugUnitTest`
- **测试结果**：
  - `HistoryProgressLabelTest` 5 组测试用例全部通过（越界索引显示 `目录已更新 · 点击继续`、有效索引显示 `上次看到 · [章节名]`、负数索引显示 `有阅读记录`、缺失目录显示 `上次看到 第 N 章` 等）。
  - 全工程单元测试通过：BUILD SUCCESSFUL。

## 4. 对现有行为的影响与兼容方式
- 保留了本地数据与所有现有阅读历史数据，不清除任何用户进度。
- 历史列表单行渲染即使遇到异常也会单独捕获并记录日志，不再导致整页闪退。
- 移除了“最后一章即已读完整”的绝对判定，显示真实的阅读章节位置或“目录已更新 · 点击继续”。

## 5. 未执行的检查、局限与已知风险
- 历史入口真机/插桩尚未执行（当前为 JVM 单元测试及 Gradle 构建验证，尚未进行物理真机验收）。
- 用户本地数据库中若存在已严重损坏的字段，可能显示为已清除或默认状态。

## 6. 下一阶段内容
- 进入**阶段 1：增加完全本地的启动书架习惯**（ReadingHabitTracker 及其状态机与设置项）。
