# 动漫啦 (dongmanla) 站源验收报告

- **稳定ID**：`dongmanla`
- **名称**：动漫啦
- **2.0.40注册位置**：`DownloadSources.java` 序号 19 (`SourceConfig.dongmanla(true)`)；`SourceConfig.java` `dongmanla()`
- **顺序/默认启用**：优先级 19；默认开启 (`defaultEnabled = true`)
- **原始能力限制**：主站 `https://www.dongman.la` 提供首页聚合列表 (`/manhua/`，按每页 24 条在内存中切片分页，避免请求不存在的 `/manhua/2.html`)、搜索 (`/manhua/so/{keyword}/{page}.html`)、48 项分类列表 (`/manhua/{region}/` 与 `/manhua/class/{genreId}/`，翻页追加 `{page}.html`)、详情页 (`/manhua/detail/{comicId}/`，懒加载目录并缓存最近 4 篇详情 HTML 供 `chapters(comicId:)` 零二次请求解析 `cy_plist` / `#chapterList`) 以及整章阅读页 (`/manhua/chapter/{comicId}/{chapterId}/all.html`，仅保留 `img.dongman.la` 下 `/[a-z]/[^/]+/.+\.(jpg|jpeg|png|webp|gif)` 规则的正文图片)。
- **当前适配器版本**：`ios/ComicCore/Sources/ComicCore/DongmanLaComicSource.swift`
- **验收日期**：2026-10-10
- **网络条件**：真实网络连通（HTTP 200 国内直连全通，首页聚合、搜索页、分类页、详情页、阅读页 `all.html`、以及 `img.dongman.la` 图片 CDN 均直连）
- **Android / iOS 对照结果**：与 Android 2.0.40 `DongmanLaComicSource.java` 契约 1:1 完全对齐。48 个分类项映射、首页 24 条内存切片、详情页懒加载目录与 `pendingDirectoryHtml` 4 条容量缓存、`cy_plist` 倒序目录反转为正序、阅读页自动切换 `all.html` 并按 `img.dongman.la` 首字母目录规则过滤全章图片完全一致。

---

## 一、真实网络与功能项验收明细

| 项目 | 输入 / 用户操作 | 预期 / 原版能力 | 实际结果 | 判定 | 脱敏证据 |
| --- | --- | --- | --- | --- | --- |
| **最新列表与切片分页** | 请求 `https://www.dongman.la/manhua/` | 解析 `.cy_wide_list li` / `ul` 卡片，按 24 条切片分页 | HTTP 200，大小 36.0KB，提取 ID `22564`、`22562`、`5985` 等漫画卡片 | **PASS** | `curl.exe` 实网响应 HTTP 200；`DongmanLaSourceTests.testSearchCategoryDetailDirectoryAndAllReaderAreParsed` 通过 |
| **搜索与分页** | 搜索“海贼王” (`/manhua/so/%E6%B5%B7%E8%B4%BC%E7%8E%8B/1.html`) | 返回匹配漫画卡片列表 | HTTP 200，大小 24.4KB，成功返回《海贼王》(ID `5314`)、ID `11010` 等作品 | **PASS** | 实网验证返回作品卡片；单元测试通过 |
| **48 项分类与翻页** | 选择“日本漫画” (`jp`) 第 2 页 | 请求 `/manhua/japan/2.html` | 48 个分类选项（含地区、进度与 40 个 `genre.*` 题材）完整，翻页路径精确匹配 | **PASS** | `DongmanLaSourceTests.testSourceConfigDefaultsAndFilterGroups` 通过 |
| **详情与目录缓存复用** | 打开 `/manhua/detail/5329/` 并紧接请求 `chapters("5329")` | 详情页提取标题、封面、简介与最新章节，不提前返回章节数组；紧接调用 `chapters` 复用缓存 HTML 不发第 2 次请求 | HTTP 200，提取《全职猎人》及 135 个章节，缓存命中零重复请求 | **PASS** | 实网提取 135 章；单元测试断言 `detailRequests == afterChaptersRequests` 通过 |
| **全章阅读页图片过滤** | 打开 `/manhua/chapter/5329/44074/` | 自动请求 `/manhua/chapter/5329/44074/all.html`，过滤出 `img.dongman.la` 下首字母分目录正文图 | HTTP 200，大小 18.2KB，精确提取全部 30 张正文图片 (`001.jpg` 至 `030.jpg`) | **PASS** | 实网与录制夹具 `dongmanla-44074.html` 均精确提取 30 张图片；`testHunter44074KeepsAllThirtyImagesOutsideHDirectory` 通过 |
| **图片下载与防盗链** | 下载 `https://img.dongman.la/q/qzlr/klpkhy1/001.jpg` | 携带 `Referer` 下载图片 | HTTP 200，Content-Type: `image/jpeg`，Content-Length: 153590 字节 | **PASS** | `curl.exe -I` 验证返回 HTTP/1.1 200 OK，`image/jpeg` |

---

## 二、源整体结论

- **验收结论**：**PASS**（全链路国内直连 HTTP 200，首页聚合、搜索、48 项分类、详情缓存复用、135 章目录、`all.html` 30 张正文图片提取以及 `img.dongman.la` 图片下载全部通过）
- **状态更新**：在 `sources.csv` 中将 `dongmanla` 状态标记为 **通过**。
