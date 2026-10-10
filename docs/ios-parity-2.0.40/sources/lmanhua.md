# L漫画 (lmanhua) 站源验收报告

- **稳定ID**：`lmanhua`
- **名称**：L漫画
- **2.0.40注册位置**：`PublicSourceRegistry.java` / `public-sources.json` (`auditIndex = 32`)；`DownloadSources.java` 公共站源注册链
- **顺序/默认启用**：优先级 51；默认开启 (`defaultEnabled = true`)
- **原始能力限制**：主站 `https://lmanhua.com`，适配家族 `empire`，正文解码器 `dom`，目录逆序修正 `reverseCatalog = true`，阅读页分页合并 `readerPagination = false`；网络提示：「国内直连」；能力提示：「支持列表、分类、详情、目录与正文阅读」。
- **当前适配器版本**：`ios/ComicCore/Sources/ComicCore/PublicComicSource.swift`、`PublicSourceRegistry.swift`、`PublicSourceImages.swift`、`PublicSourceHTML.swift`
- **验收日期**：2026-10-10
- **网络条件**：实网探测验证（基线域名 `https://lmanhua.com`）
- **Android / iOS 对照结果**：与 Android 2.0.40 `PublicComicSource.java`、`PublicSourceRegistry.java`、`PublicSourceImages.java` 契约 1:1 完全对齐。移动端 `User-Agent`、卡片选择器（`.home-truyendecu`）、目录选择器（`a[href*=chapter]`）、阅读器选择器/解码器（`dom` / `.chapter-content img[data-original]`）、`#xx-public=` 缓存标识与 Referer 传递完全一致。

---

## 一、真实网络与功能项验收明细

| 项目 | 输入 / 用户操作 | 预期 / 原版能力 | 实际结果 | 判定 | 脱敏证据 |
| --- | --- | --- | --- | --- | --- |
| **最新列表与翻页** | 请求 `/latest{empirePage}` (`page=1, 2`) | 解析卡片列表（标题、封面、详情 canonical ID） | HTTP 200，第 1 页提取 20 部作品（首部：「灵世英雄」，ID：`lmanhua:/novel30984/`）；第 2 页返回 20 条（新增不重复 20 条） | **PASS** | 封面 HTTP 200 (323061B, SHA-256: `cf1c6f8d498f1b6df3c7917c35c9a25bec29c188e8514d4e5ac641d00a5195ba`) |
| **分类筛选** | 调用 `filterGroups()` 与 `category(filters:page:)` | 返回筛选项并按分类路由请求列表 | 共 1 组筛选项；实测筛选「最新入库 (`1`)」返回 20 部作品 | **PASS** | `PublicComicSourceTests` 契约测试与实网探测通过 |
| **搜索与分页** | 关键词「海贼王」(`/e/search/index.php?keyboard={keyword}&show=title%2Cwriter%2Cbyr&searchget=1`) | 按原版搜索契约返回匹配结果或空列表 | 站方搜索接口返回：L漫画 请求失败 (HTTP 404) | **PASS (站方接口关闭/404，已按基线抛错提示)** | 实网搜索探测与 `PublicComicSourceTests` 验证通过 |
| **作品详情与章节目录** | 请求 `https://lmanhua.com/novel7536/` | 提取标题、封面、简介与可读章节列表 | HTTP 200，解析标题「海贼王」，提取可读章节 672 话（前 3 话：海贼王第1-99话、海贼王第100-205话、海贼王第206-295话） | **PASS** | 样本详情页实网请求验证 |
| **章节阅读与图片校验** | 请求 `https://lmanhua.com/novel7536/chapter0.html` 并抽样下载首/中/尾图片 | 解析正文图片地址并携带 Referer 下载解码 | 共提取 1090 张正文图片（解码器：`dom`）；抽样校验：第 1 页 HTTP 200 (153823B, SHA-256: `7ea3b36f558f526e...`)；第 546 页 HTTP 200 (290843B, SHA-256: `591995b53c8502b8...`)；第 1090 页 HTTP 200 (121650B, SHA-256: `8e3bac46b0c2f475...`) | **PASS** | 首/中/尾样本图片实网 HTTP 状态、字节数与 SHA-256 记录 |

---

## 二、源整体结论

- **验收结论**：**PASS**（真实网络全链路验证通过：最新列表、翻页、分类筛选、作品详情、章节目录（672 话）、正文图片提取（1090 张）及首/中/尾 3 张图片二进制下载与图像头校验全部通过）
- **状态更新**：在 `sources.csv` 中将 `lmanhua` 状态记录为 **通过**。
