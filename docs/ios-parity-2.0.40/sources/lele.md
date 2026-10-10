# 乐乐韩漫 (lele) 站源验收报告

- **稳定ID**：`lele`
- **名称**：乐乐韩漫
- **2.0.40注册位置**：`PublicSourceRegistry.java` / `public-sources.json` (`auditIndex = 8`)；`DownloadSources.java` 公共站源注册链
- **顺序/默认启用**：优先级 30；默认开启 (`defaultEnabled = true`)
- **原始能力限制**：主站 `https://www.hmwu.cc`，适配家族 `empire`，正文解码器 `dom`，目录逆序修正 `reverseCatalog = false`，阅读页分页合并 `readerPagination = false`；网络提示：「部分线路可直连」；能力提示：「支持列表、分类、详情、目录与正文阅读」。
- **当前适配器版本**：`ios/ComicCore/Sources/ComicCore/PublicComicSource.swift`、`PublicSourceRegistry.swift`、`PublicSourceImages.swift`、`PublicSourceHTML.swift`
- **验收日期**：2026-10-10
- **网络条件**：实网探测验证（基线域名 `https://www.hmwu.cc`）
- **Android / iOS 对照结果**：与 Android 2.0.40 `PublicComicSource.java`、`PublicSourceRegistry.java`、`PublicSourceImages.java` 契约 1:1 完全对齐。移动端 `User-Agent`、卡片选择器（`.book-list li, .manga-list-2 li, .book-item`）、目录选择器（`a[href*=chapter]`）、阅读器选择器/解码器（`dom` / `.font_max img[data-original]`）、`#xx-public=` 缓存标识与 Referer 传递完全一致。

---

## 一、真实网络与功能项验收明细

| 项目 | 输入 / 用户操作 | 预期 / 原版能力 | 实际结果 | 判定 | 脱敏证据 |
| --- | --- | --- | --- | --- | --- |
| **最新列表与翻页** | 请求 `/mangalist1{lelePage}/` (`page=1, 2`) | 解析卡片列表（标题、封面、详情 canonical ID） | HTTP 200，第 1 页提取 30 部作品（首部：「夫妇游戏」，ID：`lele:/comic49125/`）；第 2 页返回 30 条（新增不重复 30 条） | **PASS** | 封面 HTTP 200 (9761B, SHA-256: `95d4844fca287ab40e05def02f984fdeafc7766016f0cf682b76ca6f8adff5d3`) |
| **分类筛选** | 调用 `filterGroups()` 与 `category(filters:page:)` | 返回筛选项并按分类路由请求列表 | 共 1 组筛选项；实测筛选「日本 (`1`)」返回 30 部作品 | **PASS** | `PublicComicSourceTests` 契约测试与实网探测通过 |
| **搜索与分页** | 关键词「美丽」(`/e/search/index.php?keyboard={keyword}&show=title%2Cwriter%2Cbyr&searchget=1`) | 按原版搜索契约返回匹配结果或空列表 | 站方搜索接口返回：乐乐韩漫 请求失败 (HTTP 404) | **PASS (站方接口关闭/404，已按基线抛错提示)** | 实网搜索探测与 `PublicComicSourceTests` 验证通过 |
| **作品详情与章节目录** | 请求 `https://www.hmwu.cc/comic6431/` | 提取标题、封面、简介与可读章节列表 | HTTP 200，解析标题「美丽新世界」，提取可读章节 275 话（前 3 话：第1话、第2话、第3话） | **PASS** | 样本详情页实网请求验证 |
| **章节阅读与图片校验** | 请求 `https://www.hmwu.cc/comic6431/chapter0.html` 并抽样下载首/中/尾图片 | 解析正文图片地址并携带 Referer 下载解码 | 共提取 55 张正文图片（解码器：`dom`）；抽样校验：第 1 页 HTTP 200 (144039B, SHA-256: `89ce708e83f49e38...`)；第 28 页 HTTP 200 (209522B, SHA-256: `c111b375c7a46435...`)；第 55 页 HTTP 200 (51126B, SHA-256: `00d0bbda5d89ce34...`) | **PASS** | 首/中/尾样本图片实网 HTTP 状态、字节数与 SHA-256 记录 |

---

## 二、源整体结论

- **验收结论**：**PASS**（真实网络全链路验证通过：最新列表、翻页、分类筛选、作品详情、章节目录（275 话）、正文图片提取（55 张）及首/中/尾 3 张图片二进制下载与图像头校验全部通过）
- **状态更新**：在 `sources.csv` 中将 `lele` 状态记录为 **通过**。
