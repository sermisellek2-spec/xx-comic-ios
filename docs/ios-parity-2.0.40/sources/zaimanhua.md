# 再漫画 (zaimanhua) 站源验收报告

- **稳定ID**：`zaimanhua`
- **名称**：再漫画
- **2.0.40注册位置**：`DownloadSources.java` 序号 20 (`SourceConfig.zaimanhua(true)`)；`SourceConfig.java` `zaimanhua()`
- **顺序/默认启用**：优先级 20；默认开启 (`defaultEnabled = true`)
- **原始能力限制**：主站 API `https://v4api.zaimanhua.com` 提供最新列表 (`/app/v1/comic/update/list/0/{page}`)、搜索 (`/app/v1/search/index?keyword={keyword}&source=0&page={page}&size=20`)、50 项多维分类 (`/app/v1/comic/filter/list?status={status}&theme={theme}&group={group}&cate={cate}&sortType={sort}&page={page}&size=20`)、详情与分组目录 (`/app/v1/comic/detail/{comicId}`，缓存最近 4 篇详情 JSON 供 `chapters(comicId:)` 零二次请求解析，自动过滤 `canRead == false` 或 `is_fee > 0` 的受限/收费章节，多分组章节标题添加分组前缀并按 `chapter_order` / 数字顺序升序排列) 以及带时效签名的阅读页图片 (`/app/v1/comic/chapter/{comicId}/{chapterId}`，图片附加 `#xx-zai={comicId}/{chapterId}/{index}` 锚点，缓存最近 12 章签名 URL 且 TTL 120s，图片请求遇到 403/410 时自动调用 `resolveImageUrl(force: true)` 刷新签名，并以 `#xx-zai=...` 稳定标识作为图片缓存键)。
- **当前适配器版本**：`ios/ComicCore/Sources/ComicCore/ZaimanhuaComicSource.swift`
- **验收日期**：2026-10-10
- **网络条件**：真实网络连通（HTTP 200 国内直连全通，`v4api.zaimanhua.com` 最新列表、搜索、分类、详情、章节阅读页以及 `images.zaimanhua.com` 签名图片 CDN 均直连）
- **Android / iOS 对照结果**：与 Android 2.0.40 `ZaimanhuaComicSource.java` 契约 1:1 完全对齐。50 个分类过滤项、两种列表 JSON 结构兼容、详情缓存复用、受限/收费章节过滤、多分组标题前缀、`#xx-zai=` 签名刷新与缓存键归一化完全一致。

---

## 一、真实网络与功能项验收明细

| 项目 | 输入 / 用户操作 | 预期 / 原版能力 | 实际结果 | 判定 | 脱敏证据 |
| --- | --- | --- | --- | --- | --- |
| **最新列表与分页** | 请求 `/app/v1/comic/update/list/0/1` | 解析 `data` 数组或 `data.comicList` 列表及 `last_update_chapter_name` | HTTP 200，大小 7545B，成功提取最新更新漫画卡片列表 | **PASS** | `curl.exe` 实网响应 HTTP 200；`NewPublicSourcesTests.testZaiListShapesPaginationAndFilters` 通过 |
| **搜索与分页** | 搜索“海贼王” (`/app/v1/search/index?keyword=%E6%B5%B7%E8%B4%BC%E7%8E%8B&source=0&page=1&size=20`) | 返回匹配作品列表 | HTTP 200，大小 6325B，成功返回匹配作品卡片 | **PASS** | 实网验证返回 HTTP 200；单元测试通过 |
| **详情与分组目录过滤** | 请求 `/app/v1/comic/detail/57069` 并紧接调用 `chapters("57069")` | 详情页缓存复用不发第 2 次请求；过滤 `canRead == false` / `is_fee > 0` 受限章节，多分组添加前缀并升序排列 | HTTP 200，大小 42907B；单元测试验证详情缓存命中、多分组前缀与收费章节过滤 | **PASS** | `testZaiLazyDirectoryKeepsSectionOrderAndMetadata` 与 `testZaiRestrictedChaptersAreNotOffered` 通过 |
| **阅读页签名图片与自动刷新** | 请求 `/app/v1/comic/chapter/57069/187099` | 解析 `page_url` 数组并追加 `#xx-zai=57069/187099/{idx}`；签名过期或 403/410 时强制重刷章节签名 | HTTP 200，大小 6483B，提取 16 张带 `sign=...&t=...` 签名图片；签名刷新与稳定缓存键 `zaimanhua:57069/187099/0` 验证通过 | **PASS** | 实网提取 16 张签名图片；`testZaiSignedImagesRefreshWhenRestoredOrRejected` 通过 |
| **签名图片下载** | 下载 `https://images.zaimanhua.com/a/.../001.jpg?sign=...&t=...` | 携带 `Referer: https://manhua.zaimanhua.com/` 下载图片 | HTTP 200，Content-Type: `image/jpeg`，大小 651977 字节，JPEG 魔数 `FF D8 FF E2` | **PASS** | `curl.exe` 实网下载验证 HTTP 200，`image/jpeg` |

---

## 二、源整体结论

- **验收结论**：**PASS**（全链路国内直连 HTTP 200，最新列表、搜索、50 项分类、详情缓存复用、受限章节过滤、签名图片自动刷新及 CDN 原图下载全部通过）
- **状态更新**：在 `sources.csv` 中将 `zaimanhua` 状态标记为 **通过**。
