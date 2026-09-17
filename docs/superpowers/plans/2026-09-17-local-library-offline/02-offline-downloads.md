# 阶段 2：章节离线下载 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans when available. Gemini 只执行本阶段，完成报告后停止。

**Goal:** 在线漫画单章、多章、全章下载，进入本地书架离线阅读，任务可恢复且文件可安全清理。

**Architecture:** 持久下载队列调用现有站源章节接口，独立有界执行并写入阶段 1 的内容存储。前台服务维持用户发起的后台任务，图片按页校验、章节按完整性提交；保持在线进度键。

**Tech Stack:** Java、Android foreground dataSync Service、SQLite、HttpURLConnection、现有站源与图片处理。

**Spec:** `docs/superpowers/specs/2026-09-17-local-library-offline-design.md`

## Global Constraints

- 2026-09-17 用户明确要求进入第二阶段，全部阶段完成后统一真机验收；第一阶段设备验证仍待完成，不将延期当作已通过。沿用 Codex 接管后的实际接口。
- 默认仅 Wi-Fi，1 个章节任务、至多 2 个图片请求；已完成页不重复下载。
- 不改变 JM/18mh 验证实现、图片 TLS 策略、阅读模式和旧升级下载流程。

## Task 1：稳定任务身份、状态机与持久恢复

**Files:** 新建 `download/DownloadModels.java`、`DownloadStore.java`、`DownloadCoordinator.java`、`DownloadPolicy.java`；测试 `download/DownloadCoordinatorTest.java`、`DownloadPolicyTest.java`；阶段 1 数据库增量迁移。

**Interfaces:** `DownloadCoordinator.enqueue(String sourceId, String comicId, List<String> chapterIds)`、`pause(String taskId)`、`resume(String taskId)`、`cancel(String taskId)`；操作幂等。DownloadModels 保存 spec 的状态、稳定身份、代次、失败原因、实际页计数和字节数。DownloadPolicy 使用当前网络/用户暂停/验证/空间状态决定能否运行，不直接做 UI 操作。

- [x] 先测试重复 enqueue 不重复下载、chapterId 与排序无关、手动暂停后网络恢复仍暂停、取消后晚回调不能完成任务。
- [x] 写持久状态与迁移：恢复只处理未完成/异常终止任务，completed 不重排队，waiting_verification 不自动启动浏览器。使用新增独立 downloads.db，保留阶段 1 数据库原 schema。
- [x] 测试一个站源等待验证而另一个可运行；失败 3 次后需要用户重试，不无限循环。
- [x] 章节目录快照在用户确认范围时记录，按稳定身份存储；全部不是自动下载未来新章。
- [ ] 运行任务模型单测与 Android 数据库迁移测试，提交。

## Task 2：下载页内容并保持原图片处理

**Files:** 新增 `download/SourceImageFetcher.java`；对 MainActivity 必要图片请求/解码代码做小范围提取到可复用边界；复用 ManwaImageDecoder 和 JM 切片逻辑，新增 transport 与图像对比测试。

**Interfaces:** SourceImageFetcher 接受来源、原 imageUrl、referer、取消信号并写入指定 staging 文件；返回页大小、校验信息与明确变换状态。阶段 1 LocalContentResolver 按该页变换状态生成阅读资源，不再用 file 路径推断网站。

- [x] 用本地 ServerSocket 测试服务构造 200、206、429、403、截断、实体变化与错误 HTML；先断言不会把错误页标为图片完成。
- [x] 章节解析走既有 ComicSource.chapter，复用其完整图片列表；包子的 nextPageUrl 实为下一章，不跟进串章；保留来源相关 UA/Referer/凭证和超时。
- [x] 按页写 `.part`、关闭流并校验可解码/字节数后重命名；最后一页完成才设置章节 completed。未知总长度只展示已知页数/字节数。
- [x] 实现页级恢复；采用安全重下未完成单页，不启用字节级 Range，绝不能把 200 全体附加到半文件。
- [x] 漫蛙使用已验证字节解码，不持久化会员凭证；JM 保存还原所需 metadata，共用在线还原函数，不二次还原、不有损重压缩；原生像素断言已编译，尚未设备运行。
- [ ] 使用独立生成样本验证加密流/切片整页完整性；有授权联网条件时小范围下载代表性章节作比对，报告具体站点而非声称全部实测。
- [x] 图片已完成后离线打开不请求在线详情/目录；缺失文件提示损坏并允许手动重下；哈希校验位于工作线程。
- [x] 跑原 ManwaImageDecoderTest、JmImageSlicesTest 及全部 JVM 回归；阅读器真机回归延期至总验收。

## Task 3：后台服务、通知与网络策略

**Files:** 新建 `download/DownloadService.java`；修改 `AndroidManifest.xml`，必要 strings/drawable；Android 生命周期验证。

- [x] 状态测试覆盖 Wi-Fi 策略、允许移动网络、用户暂停优先、单工作者与恢复；真实网络切换待设备验收。
- [x] 从用户点击下载/恢复时启动前台服务，及时创建通知；添加 API 相应权限及 dataSync 服务类型，旧 API 使用兼容分支。
- [x] 实现通知暂停/继续与不可变 PendingIntent；通知权限与拒绝场景待设备验证。
- [x] Activity 销毁不销毁下载工作者；服务退出失效当前任务。下次 App 启动按策略恢复；系统省电/强停不做绕过承诺。
- [x] 配置空间检查及重试退避；收到站源验证异常仅将该站任务改为 waiting_verification，用户可去原站源页验证。
- [ ] API 23 和 API 34 环境验证启动/通知/后台限制；至少一台真机验证切页、锁屏、断网及重新打开。无设备列阻塞证据，不假称后台能力已验收。
- [ ] 运行构建和生命周期检查后提交。

## Task 4：下载 UI、进度共享与存储清理

**Files:** 新建 `DownloadSelectionSheet.java`、`DownloadCenterView.java`、`DownloadTaskDetailView.java`、`local/StorageManagementView.java`；修改 MainActivity 详情、设置、本地书架入口和本地优先判定；扩展 LocalStorageManager。

- [x] 在线详情添加紧凑下载入口，76% 底部抽屉支持当前章/勾选多章/全章，已有任务可识别且不重复创建；反转排序身份测试通过。
- [x] 开放本地书架右上角下载中心；作品聚合任务可进入章节详情，能暂停、恢复、重试、取消。
- [x] 设置新增仅 Wi-Fi 和存储管理；后台统计导入、下载、可再生页面缓存；可批量删除副本，原文件不受影响。
- [x] 同源作品多次下载并入原本地作品，共用在线 progressKey；跨站同名不合并；保留完整目录与原 chapterId。
- [x] 删除整本先使旧任务失效；删部分章保留其余；取消保留已正式完成章；保留收藏/进度，更新实际占用。
- [x] 已下载章优先本地；未下载章在线读，断网提示并可打开下载中心；损坏章需要用户显式重下。
- [ ] 覆盖下载中/等待网络/验证/手动暂停/部分完成/失败/完成/删除失败的浅深色状态并提交。

## 人工验收与停点

1. 分别下载单章、乱序选择的多章、全部章节，检查章序、页序、封面与正文一致。
2. 下载时切页/锁屏，暂停后断开再连网络不自动继续；异常终止后重开只补未完成内容。
3. 断网并清缓存，再从本地书架打开完整下载的书、目录和每一页；在线与本地进度互通。
4. 删除部分章/整书时文件、任务、空间统计一致；原在线收藏与历史保留。
5. 模拟验证失效，不出现自动网页弹框，其他站源任务可继续；用户手动验证后可恢复。
6. 从阶段 1 安装包覆盖升级，原导入副本、名称和续读记录全部保留。

- [x] 写 `local-library-stage-2.md`，提供独立验收 APK 与本机证据。未打勾的设备/视觉/原生执行项留到用户要求的总真机验收，不虚标完成。

**用户启动指令：** “阶段 1 已通过 Codex 和人工验收。只按 02-offline-downloads.md 执行阶段 2，完成报告后停止，不发布 COS。”
