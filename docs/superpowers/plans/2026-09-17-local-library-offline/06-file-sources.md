# 阶段 6：直接文件站源扩展 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans when available. 完成能力验收后停止；没有用户指定的真实站点不虚构对接。

**Goal:** 文件型站源可以下载完整文件，经既有本地解析与阅读链路打开，旧图片型站源继续工作。

**Architecture:** 文件能力是可选能力；站源解析可刷新的下载描述，统一下载模块传输，成功后提交给格式解析器。作品、卷/文件和下载内容身份分开，不按文件 URL 合并书籍。

**Tech Stack:** Java、既有下载/本地/ebook 模块、可控 HTTP fixture 服务。

**Spec:** `docs/superpowers/specs/2026-09-17-local-library-offline-design.md`

## 2026-09-18 Codex 收尾

本轮用户明确授权合并 master、升级版本、推送与 COS 强更新，不需要重复确认。最终实现和验证范围见 [阶段报告](../../reports/local-library-stage-6.md)。原清单作为验收要求保留，实际状态如下：

- [x] 可选文件能力、卷顺序与稳定 source/comic/file 身份，旧图片源不强制实现。
- [x] 文件任务持久队列、一次刷新、请求头隔离、网络/暂停/有限重试。
- [x] 受控 HTTP 行为验证：ZIP/EPUB/未知长度/HTML/截断/206/忽略 Range 的 200/URL 失效/哈希不符。
- [x] 魔数识别后复用格式解析，私有文件同盘提交，无第二份原始大文件副本。
- [x] 新版本保留旧可读内容直到提交；页面缓存按 hash 隔离，同内容续读、变更内容从头开始。
- [x] 详情按 capability 显示文件卷抽屉与下载/阅读按钮，本地阅读和删除入口接通。
- [x] 原生 SQLite/真实图片闭环用例及测试 APK 编译，阶段报告和支持边界更正。
- [ ] Android 原生用例、全部页面及设备生命周期真机回归：本机未连接设备，保留待用户验收。
- [ ] 真实文件站点：用户尚未指定，本阶段不虚构对接。

每卷是独立本地阅读条目，可包含多个章节。纯 KF8 正文重建不在已实现矩阵，文件导入明确报不支持，不假装成功。

## Global Constraints

- 图片/电子书依已验收格式矩阵支持，未知格式不显示虚假的“可阅读”。
- 先完整下载、校验、解析再阅读，不做远程 ZIP 随机读取。
- 不让所有现有 ComicSource 强制实现文件方法，不改共享验证逻辑。

## Task 1：最小文件源能力与下载描述

**Files:** 新建 `source/FileSourceCapability.java`、`FileResource.java`；新增 `download/FileDownloadWorker.java` 或在现有 coordinator 中明确文件任务类型；fixture 适配器仅在测试目录。

**Interfaces:** FileSourceCapability 提供 `listFiles(String comicId)` 与 `resolveFile(String comicId, String fileId)`；FileResource 包含稳定 fileId/revision、标题/卷序、预期格式、大小（可未知）、可选校验值、实际下载 URL、允许的请求信息与有效期。下载执行和持久任务由阶段 2 模块负责，凭证不写入普通 manifest/日志。

- [ ] 先写能力测试：不支持文件的现有站源保持原路径；文件源一作品多卷保持稳定卷序，不按 URL 作唯一键。
- [ ] 实现下载描述与资源更新边界；短期签名过期最多刷新一次，刷新后实体变化要重新下载，不能反复重新请求造成循环。
- [ ] cookie/token 仍由对应站源持有；重定向到不相关域不传播敏感 Authorization/Cookie，文件名由 App 生成且防路径越界。
- [ ] 加文件任务持久状态与解析阶段；格式解析结束后才标 completed，与普通图片章节任务共同遵循并发/暂停/网络规则。
- [ ] 运行纯模型与队列兼容测试后提交。

## Task 2：文件传输、入库与详情行为

**Files:** 扩展 DownloadCoordinator、LocalImporter/格式分派、本地身份关联；MainActivity 详情按 capability 显示下载/下载后阅读；受控传输和 Android 闭环测试。

- [ ] 使用本地 HTTP 服务返回完整 ZIP、EPUB、未知长度文件、HTML 错误页、截断流、合法 206、Range 被忽略的 200、URL 过期和校验失败；验证下载结果而不是只检查请求参数。
- [ ] 文件内容按魔数和实际解析识别，Content-Disposition 与扩展名只辅助展示；校验不通过不得入可读库。
- [ ] 全文件成功后调用同一格式导入路径，避免复制两份原始大文件；以稳定 sourceId/comicId/fileId 关联线上身份和本地作品。
- [ ] 多卷顺序正确；源文件版本变化保留现有可读版本，新的完整版本校验后再替换，续读按稳定定位恢复，不能静默覆盖成错误位置。
- [ ] 原详情按钮按能力显示“下载后阅读/正在下载/继续阅读”；点击任务可进入下载中心，不劫持现有在线图片阅读按钮。
- [ ] 下载完成后断网仍有封面、详情、目录和正文；删除同时取消相应文件任务，旧回调不能复活文件。
- [ ] 回归阶段 1–5 的所有入口和旧在线流程；提交。

## 人工验收与停点

1. 从受控示例文件源打开详情、下载、解析、进入本地书架、阅读、续读；示例只用于 debug/测试，不作为虚构真实站源出现在 release。
2. 下载中可用其他页面，恢复任务不重复产生本地书，HTML/损坏文件不生成成功状态。
3. 多卷与版本更新保持作品/卷身份；本地文件管理可以完整回收文件。
4. 已有 HTML/API 图片站源的搜索、详情、目录和阅读仍使用原在线路径。

- [ ] 写 `local-library-stage-6.md`，明确“文件源能力通过受控样例，真实站点未对接”，交验收包并停止。
- [ ] 全部阶段通过后再由用户决定合并 master、正式版本号、更新策略和 COS 发布，不自动沿用以前的强更新指令。

**用户启动指令：** “前序阶段已完成或已明确批准跳过不支持格式。只执行 06-file-sources.md，用受控样例验收文件源完整流程，不自行增加未知真实站点，完成后停止。”
