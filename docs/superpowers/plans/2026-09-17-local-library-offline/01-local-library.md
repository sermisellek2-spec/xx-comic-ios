# 阶段 1：本地漫画完整闭环 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans when available. Gemini 按勾选任务顺序执行；本阶段完成即停止。

**Goal:** 导入图片文件夹及 ZIP/CBZ，在主题一致的本地书架、详情及现有阅读器中阅读、续读并安全删除。

**Architecture:** 原生 SAF 复制文件到持久专用目录；SQLite 记录书/章/页，ZipFile 按需索引与读取。本地页面只经过本地读取入口，在线路径保留原行为。

**Tech Stack:** Java、Android SAF / SQLite / View、ZipFile、JUnit、现有 ReaderInstrumentation。

**Spec:** `docs/superpowers/specs/2026-09-17-local-library-offline-design.md`

## Global Constraints

- 继承 README 全部共同约束；只实现本阶段，不增加空的下载/电子书入口。
- 原文件不改不删；私有副本排除系统备份；缓存清理绝不删除该副本。
- 书架标题、76% 目录和现有阅读模式不得改成其他设计。

## Task 1：建立基线与可恢复的本地内容模型

**Files:** 新增 `app/src/main/java/com/xxcomic/local/LocalModels.java`、`LocalLibraryStore.java`、`LocalStorageManager.java`；相应 `app/src/test/java/com/xxcomic/local/` 测试；必要 Android 数据库测试放 `app/src/androidTest/java/com/xxcomic/LocalLibraryChecks.java`。

**Interfaces:** `LocalModels` 定义 Book、Chapter、Page、ImportState；Book 至少含 ID、指纹、标题、格式、来源类型、进度键、大小和可读状态；Chapter 含稳定 ID、顺序、标题；Page 含稳定 ID、章节 ID、顺序、相对文件/entry、尺寸与变换类型。`LocalLibraryStore` 提供 `listBooks()`、`findByFingerprint(String)`、`getChapters(String)`、`getPages(String)`、事务式导入提交和 deleting 状态；所有 IO 在后台。

- [x] 保存 git 基线及未提交文件清单，运行共同验证命令，记录已有失败与新失败的区别。
- [x] 用临时目录与测试数据库编写行为测试：同指纹去重、同名不同文件不合并、写入一半崩溃后无“可读空书”。
- [x] 明确创建 v1 数据表和唯一索引；使用外键或事务维护书/章/页关联；保存用户进度的键与原数据兼容，不搬迁全部旧 SharedPreferences。
- [x] 实现 staging → 正式文件 → 索引提交的日志状态与启动恢复；删除流程先标记、停工作、后删受限目录，失败可重试。
- [x] 对真实数据库执行重复插入、进程重建、磁盘失败恢复测试；JVM 只覆盖纯业务模型，不能用 mock Android SQLite 假装数据库运行正常。
- [x] 只提交该任务源码和测试，记录 commit。

## Task 2：导入、章节划分与压缩包索引

**Files:** 新增 `local/LocalImporter.java`、`ArchiveIndex.java`、`NaturalPathOrder.java`；测试 `ArchiveIndexTest.java`、`NaturalPathOrderTest.java`。

**Interfaces:** `ArchiveIndex.read(File)` 返回 `LocalModels` 章节与页面描述；`NaturalPathOrder` 实现 `Comparator<String>`。`LocalImporter` 接收 SAF `Uri`、ContentResolver、取消信号和进度回调，复制/计算指纹/解析，最后用 Task 1 的事务提交，不在 UI 线程执行。

最小排序测试内容：

```java
@Test public void ordersNumericNamesNaturally() {
    List<String> paths = new ArrayList<>(Arrays.asList("第10话/1.jpg", "第2话/10.jpg", "第2话/2.jpg"));
    Collections.sort(paths, new NaturalPathOrder());
    assertEquals(Arrays.asList("第2话/2.jpg", "第2话/10.jpg", "第10话/1.jpg"), paths);
}
```

- [x] 先测试平铺 3 页、2 个章节、单一包装层、根图+子目录、深层路径、中文文件名、不连续页码和伪扩展名；再实现排序与章节识别。
- [x] ZIP 测试使用 `ZipOutputStream` 动态生成；路径穿越、重复规范化路径、空包、无图包、超预算/截断分别断言失败，原目标目录不能出现越界文件。
- [x] 使用 ACTION_OPEN_DOCUMENT 多选、ACTION_OPEN_DOCUMENT_TREE 文件夹；读取 displayName/MIME 作提示，实际流识别格式。取消系统选择不产生空任务。
- [x] 复制时计算 SHA-256，未知大小采用字节数进度，不显示虚假的百分比；每次写入响应取消和空间不足。
- [x] 同指纹已有可读书则移除本次暂存，返回原作品；若只有已删除身份记录则新副本恢复同一进度键。
- [x] 文件夹身份由规范化相对路径和图片内容哈希构成；相同文件夹换外层名称可恢复，变更内容不强行共享进度。
- [x] 正常导入仅复制支持的文件；ZIP 不整体解压。取消只清本次 staging，批量导入某一本失败不影响其他书。
- [ ] 运行上述纯逻辑测试及测试设备 SAF 选择/权限撤销测试，提交（待用户真机验收）。

## Task 3：本地资源接入现有阅读器

**Files:** 新增 `local/LocalContentResolver.java`；修改 `MainActivity.java` 中 `showDetailThenRead`、章节加载、图片加载/预取的必要入口；必要时修改 `reader/PagedReaderView.java` 的 ImageLoader 使用，不修改其手势规则；新增本地阅读测试。

**Interfaces:** `LocalContentResolver.openPage(String pageId)` 返回必须关闭的 InputStream；`materializePage(String pageId)` 返回受限衍生目录中的 File，供现有按尺寸采样逻辑使用。用显式 local 资源标识区分 HTTP，不把用户磁盘路径当任意 URL 传给网络请求。

- [x] 写一个本地页面永不触发 HTTP、损坏页可失败、ZIP 翻页不全量展开的测试，再接入分流。
- [x] 纯本地章节由索引读取，不调用 ComicSource，不触发详情全站匹配、凭证验证或收藏更新检查。
- [x] 复用 ReaderPosition、ReaderNavigation 与现有采样预算；切页取消旧加载、防止复用 View 显示旧图，关闭流和 ZipFile 句柄。
- [x] 阅读位置按稳定 chapterId/pageId 保存；旧图漫在线进度读写路径继续工作。删除重导同一文件能找回原位置。
- [ ] 测试条漫/单页 × 左/右手 × 触碰/按钮/手势，章首末边界与目录正逆序；断网打开、旋转、退出重进、缩放均验收（待用户真机验收）。
- [x] 运行现有阅读定位和 JM 图片切片测试，避免共享入口引入重复图片处理；提交。

## Task 4：书架、详情、删除及状态 UI

**Files:** 新增 `local/LocalLibraryView.java`、`LocalDetailView.java`；修改 MainActivity 书架标题/路由、历史续读和清缓存入口的受限适配；复用 UIHelpers，不重设整个主题。

- [x] 实现“我的书架 | 本地书架”标题切换及 200ms 过渡，独立滚动状态、导入按钮、空书架与导入状态；第一阶段不显示下载中心按钮。
- [x] 使用现有网格及漫画封面，卡片无进度条；本地详情包含封面、格式/大小、目录和续读，不提供无效在线站源操作。
- [x] 名称缺失生成“未命名漫画 N”；第一张有效图片生成封面但保留在正文；封面不可用使用 rem_no_image。本地详情更多菜单提供重命名，空白名称拒绝，变更不影响指纹/历史；重导同文件保留用户名称。测试无名称、坏首图但后续可读、重命名后续读。
- [x] 导入中允许切页，返回能继续看状态；失败用蕾姆短提示和重试，空 ZIP、损坏 ZIP、重复导入有明确结果。
- [x] 长按/更多菜单删除，弹框显示释放空间、原文件不受影响、进度保留；取消不删任何数据。
- [x] 修改普通缓存清理使其只处理缓存/衍生文件，确保原有验证凭证清理策略不变；纯导入历史需可重入本地详情，删除后显示已移除而不是误发在线请求。
- [ ] 记录浅深色、窄屏、大字体、长标题、导入中/空/错误/删除前后截图与切换录屏；完成单元/构建/设备检查后提交（待用户真机验收）。

## 本阶段人工验收（待用户真机验收）

1. 平铺图片文件夹导入为 1 章；带 2 个子目录的 CBZ 为 2 章，图片按 1、2、10 顺序。（待用户真机验收）
2. 同文件导入两次只有一本，同名不同内容保留两本；原文件删除后 App 副本仍能阅读。（待用户真机验收）
3. 切换全部图片阅读模式，退出重进恢复章/页/位置；切换浅深色和书架标题无跳动。（待用户真机验收）
4. 飞行模式打开本地详情、目录和正文；清普通缓存后仍可读。（待用户真机验收）
5. 删除本地书释放文件空间、不删原文件；重导同一文件恢复进度；取消删除无变化。（待用户真机验收）
6. 现有在线搜索、详情、站源切换、收藏、阅读和验证流程符合基线。（待用户真机验收）
7. 无书名或封面仍可导入有正文的作品；重命名后重新进入、删除重导均保持名称和原阅读位置。（待用户真机验收）

## 交付与停点

- [x] 按 REPORT-TEMPLATE 写 `docs/superpowers/reports/local-library-stage-1.md`；提供独立验收包与哈希。
- [x] 明确自检结论和未测项，停止等待 Codex 及用户验收。阶段 1 不包含离线下载。
