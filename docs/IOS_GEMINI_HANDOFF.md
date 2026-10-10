# Gemini交接入口（2026-10-10）

本次目标为 **Android2.0.40完整复刻**，取代2026-09-20的2.0.29目标、Task45继续点和旧阶段安排。不能按旧文档的源码版本/未提交状态判断当前实现。

按以下顺序接手：

1. 根目录AGENTS.md与GEMINI.md。
2. `IOS_2_0_40_GEMINI_PLAN.md`：目标、固定基线、顺序、完整自主验收。
3. `GEMINI_START_PROMPT.md`：用户可复制指令。
4. `ios-parity-2.0.40/STATUS.md`、requirements.csv、differences.md与模板。
5. `comparisons/2026-10-10-ios-android-audit.md`与当前源码。

实际iOS工作目录为 `F:/softForCode/codex-project/xx-comic/.worktrees/ios-port`。先全部完成非站源功能/视觉/交互并自验，再逐一接真实源。Gemini自行管理阶段，用户只负责最后总验收。

旧交接原文保存在iOS checkout的 `ios-parity-2.0.40/history/2026-09-20-legacy-handoff.md`。历史记录保留供追溯，不是当前执行指令。ios/PARITY、VALIDATION、旧基线等旧完成结论需要按新源码和实际运行重新核对。
