# 阶段 5：MOBI / AZW 格式兼容 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans when available. 5A 与 5B 是独立停点，5A 完成不能自行进入 5B。

**Goal:** 基于真实格式而不是文件后缀，交付可维护、在手机本地运行的 Kindle 电子书格式支持。

**Architecture:** 检测真实容器/变体，解析或转换为阶段 3–4 的 Publication 和定位体系。原文件持久保留，转换结果是衍生内容，可重建，不创造第三套阅读器。

**Tech Stack:** Java/Android；解析库与必要 native ABI 在 5A 依据证据选择，不提前引入桌面转换器。

**Spec:** `docs/superpowers/specs/2026-09-17-local-library-offline-design.md`

## Global Constraints

- 不承诺 `.azw` 等扩展名全部可读，AZW/AZW3 与 KFX 不能混为一谈。
- 只做能在本机正常解析的文件；受保护/不支持格式给出具体提示，不在线上传转换，不以关闭安全校验代替解析。
- 阶段 5A 报告兼容证据和实施选项，用户确认后才做 5B。

## 5A Task 1：样本矩阵、识别器与依赖验证

**Files:** `docs/superpowers/reports/local-library-stage-5a.md`；可新增小型 `ebook/KindleFormatDetector.java` 及纯解析测试；隔离验证代码放测试源码，不引入生产入口或大依赖。

**Interfaces:** `KindleFormatDetector.detect(File)` 返回真实格式族/变体、是否已知保护、检测置信度及可读范围；未知不是 DRM，不能给错误诊断。

- [ ] 准备自制或有使用权的 MOBI7、KF8/AZW3、混合容器、漫画图片、纯文字、图文混排样本；缺少某类样本明确列未验证，不编造支持结果。
- [ ] 写文件头识别测试：改后缀不改变真实检测，截断文件与未知容器产生不同结果；只按明确结构判保护。
- [ ] 比较可用本地库/代码：维护状态、许可证、输入变体、图片/CSS/目录保留、minSdk、依赖大小、原生 ABI、内存；不能把 Python/桌面可运行当 Android 可运行。
- [ ] 最小样例在 Android 测试环境走完整“文件 → 内容模型/转换结果 → 当前阅读器”，核对章序、页数、图片完整性和文本。
- [ ] 给每种变体标记通过/失败/未验证；记录失败根因、替代路线、预计改动和包体影响。
- [ ] 只提交本阶段研究/检测/测试内容，写 5A 报告，等待 Codex 和用户确认支持矩阵与依赖方案。

## 5B Task 2：实现已经确认的变体

**Files:** `ebook/KindlePublicationAdapter.java`、格式测试样本与必要依赖；修改 LocalImporter 格式分派及错误文案，必要持久模型做兼容迁移。

**Interfaces:** `KindlePublicationAdapter.parse(File)` 产出阶段 3 Publication；若采用转换流程，返回本地转换资源和原指纹绑定关系，衍生文件只位于该作品受限目录。

- [ ] 对 5A 确认的每个变体写具体样本回归，断言标题/目录顺序/图片数量/定位可恢复；未支持变体给明确原因。
- [ ] 按 5A 选定路线实现，超大书分批处理并可取消；转换失败不会留下“可读”书卡，旧原文件仍在。
- [ ] 复用阶段 3–4 渲染器，文字不栅格化、漫画不当纯文字；无封面回退、重命名和重导恢复保持一致。
- [ ] 内存上限、空间不足、损坏输入、进程终止恢复、清缓存再开均验证；原生库需覆盖实际支持的 ABI 并检验打包体积。
- [ ] 回归 ZIP/EPUB/在线/离线全部内容入口，保存跨格式切换截图和验收包，提交。

## 人工验收与停点

按已批准矩阵逐本导入，核对实际正文而不只看封面；确认大文件、缺封面、重命名、换字号/旋转、删除重导与续读。没有证明的格式必须保留清晰“不支持”提示。

- [ ] 写 `local-library-stage-5b.md`，列明具体变体、解析库版本和未支持项，停止等待验收。

**启动 5A：** “阶段 4 双重验收通过。只做 05-kindle-formats.md 的 5A 可行性验证，先给兼容矩阵和选型证据，不自动实现 5B。”

**启动 5B：** “5A 报告与支持矩阵已确认。只按已批准的格式范围实现 5B，完成报告后停止。”
