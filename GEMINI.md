# Gemini 项目入口

先完整读取 `AGENTS.md`，再读取 `docs/IOS_2_0_40_GEMINI_PLAN.md`、`docs/ios-parity-2.0.40/STATUS.md` 和 `docs/ios-parity-2.0.40/requirements.csv`。这些文件定义本次iOS复刻范围和验收门槛。

本次任务：以冻结的 Android2.0.40 为准，先完成全部非站源功能、纯视觉和功能交互，完整自验后再逐个接入真实站源。由Gemini自行管理阶段、修复和验收，用户只负责最后总验收。

iOS实际开发目录为 `F:/softForCode/codex-project/xx-comic/.worktrees/ios-port`，分支 `codex/ios-port`。如果当前打开外层Android项目，先切换至该目录；其他机器使用对应iOS checkout。不要误用iOS checkout中的旧 `app/` 作为2.0.40参考。

现有2.0.29方案与旧Task45交接属于历史。不要从旧任务编号盲目重做；从最新源码状态和本次需求矩阵接手。

工作方式、数据保护、构建和检查命令遵守 `AGENTS.md`。例行阶段无需用户批准，阶段失败自行修复；必需检查未运行不记通过。回复使用简体中文。
