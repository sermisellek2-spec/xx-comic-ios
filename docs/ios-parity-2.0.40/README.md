# 本次交接资料

入口：`../IOS_2_0_40_GEMINI_PLAN.md`；可复制指令：`../GEMINI_START_PROMPT.md`；工作规范：根目录`AGENTS.md`和`GEMINI.md`。

| 文件 | 用途 |
| --- | --- |
| baseline/ | 2.0.40源码包和逐文件manifest，完整包仅存iOS checkout |
| verify-baseline.ps1 | 不解包、不改文件的完整性校验 |
| STATUS.md | Gemini当前阶段及实际退出状态 |
| requirements.csv | 需求骨架，必须从冻结源码继续补齐和维护 |
| differences.md | 实现差异、平台差异和外部阻塞证据 |
| STAGE_REPORT_TEMPLATE.md | 每阶段完整自主验收模板 |
| NON_SOURCE_GATE_TEMPLATE.md | P5门槛证据模板，当前不能写PASS |
| SOURCE_REPORT_TEMPLATE.md | P6每个真实站源的完整闭环报告 |
| FINAL_ACCEPTANCE_TEMPLATE.md | 全部自验完成后的一次用户总验收包 |
| stages/Pxx/ | Gemini实施后创建的阶段报告与证据 |
| NON_SOURCE_GATE.md | P5全部必需项通过后才创建PASS记录 |
| sources.csv | P6开始时从固定目录拆解逐源闭环 |
| history/ | 保留过时交接原文，不能覆盖新范围 |

矩阵是接手起点，不是已经穷尽功能的证明，也不是要求把已有实现重做。`android_reference` 中短Java路径相对 `app/src/main/java/com/xxcomic/`；`app/`开头表示冻结参考根；`ios/`和`docs/`表示当前iOS checkout。Gemini把泛指目录细化到准确类/方法/行号，补充默认值、用户步骤和证据。

状态可用：待核对、待实现、待验收、通过、失败、阻塞、后置站源。一个必需项不能因外部环境未测被记成通过。SOURCE行只是占位，必须拆为每源完整需求。

用户只做最后一次总验收。阶段安排、验收、问题修复和资料更新由Gemini负责，阶段通过自动推进。
