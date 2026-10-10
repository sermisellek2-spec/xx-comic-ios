# 51漫画 (comic51) 站源验收报告

- **稳定ID**：`comic51`
- **名称**：51漫画
- **2.0.40注册位置**：`PublicSourceRegistry.java` / `public-sources.json` (`auditIndex = 23`)；`DownloadSources.java` 公共站源注册链
- **顺序/默认启用**：优先级 45；默认开启 (`defaultEnabled = true`)
- **原始能力限制**：主站 `https://www.favcomic.xyz`，适配家族 `fav`，正文解码器 `dom`，目录逆序修正 `reverseCatalog = false`，阅读页分页合并 `readerPagination = false`；网络提示：「部分线路可直连」；能力提示：「仅明确免费章节」。
- **当前适配器版本**：`ios/ComicCore/Sources/ComicCore/PublicComicSource.swift`、`PublicSourceRegistry.swift`、`PublicSourceImages.swift`、`PublicSourceHTML.swift`
- **验收日期**：2026-10-10
- **网络条件**：实网探测验证（基线域名 `https://www.favcomic.xyz`）
- **Android / iOS 对照结果**：与 Android 2.0.40 `PublicComicSource.java`、`PublicSourceRegistry.java`、`PublicSourceImages.java` 契约 1:1 完全对齐。移动端 `User-Agent`、卡片选择器（`.comic_li`）、目录选择器（`a.item_box`）、阅读器选择器/解码器（`dom` / `#content img.unlazyload`）、`#xx-public=` 缓存标识与 Referer 传递完全一致。

---

## 一、真实网络与功能项验收明细

| 项目 | 输入 / 用户操作 | 预期 / 原版能力 | 实际结果 | 判定 | 脱敏证据 |
| --- | --- | --- | --- | --- | --- |
| **最新列表与翻页** | 请求 `/free?keyword=&tag=0&type=1&sort=1&page={page}` (`page=1, 2`) | 解析卡片列表（标题、封面、详情 canonical ID） | HTTP 200，第 1 页提取 36 部作品（首部：「魔都精兵的奴隶」，ID：`comic51:/comic/detail/872972077160865792`）；第 2 页返回 36 条（新增不重复 36 条） | **PASS** | 封面 HTTP 200 (32784B, SHA-256: `45484146d1078a64d5def48cc4f0bf26d9d0c03dcc0cd89825e72bd0a943c42e`) |
| **分类筛选** | 调用 `filterGroups()` 与 `category(filters:page:)` | 返回筛选项并按分类路由请求列表 | 共 5 组筛选项；实测筛选「少女漫画 (`girl`)」返回 30 部作品 | **PASS** | `PublicComicSourceTests` 契约测试与实网探测通过 |
| **搜索与分页** | 关键词「Not Sober」(`/search?keyword={keyword}&page={page}`) | 按原版搜索契约返回匹配结果或空列表 | HTTP 200，返回 1 条结果（前 3 条：Not Sober；关键词匹配：True） | **PASS** | 实网搜索探测与 `PublicComicSourceTests` 验证通过 |
| **作品详情与章节目录** | 请求 `https://www.favcomic.xyz/comic/detail/1263101242312007680` | 提取标题、封面、简介与可读章节列表 | HTTP 200，解析标题「Not Sober」，提取可读章节 2 话（前 3 话：第1話、第2話） | **PASS** | 样本详情页实网请求验证 |
| **章节阅读与图片校验** | 请求 `https://www.favcomic.xyz/comic/chapter/1265594257805139968` 并抽样下载首/中/尾图片 | 解析正文图片地址并携带 Referer 下载解码 | 共提取 61 张正文图片（解码器：`dom`）；抽样校验：第 1 页 HTTP 200 (209950B, SHA-256: `25d53931b35bd13f...`)；第 31 页 HTTP 200 (102212B, SHA-256: `04e72a4806c05f7d...`)；第 61 页 HTTP 200 (26022B, SHA-256: `1d4ac0eb16820d1b...`) | **PASS** | 首/中/尾样本图片实网 HTTP 状态、字节数与 SHA-256 记录 |

---

## 二、源整体结论

- **验收结论**：**PASS**（真实网络全链路验证通过：最新列表、翻页、分类筛选、作品详情、章节目录（2 话）、正文图片提取（61 张）及首/中/尾 3 张图片二进制下载与图像头校验全部通过）
- **状态更新**：在 `sources.csv` 中将 `comic51` 状态记录为 **通过**。
