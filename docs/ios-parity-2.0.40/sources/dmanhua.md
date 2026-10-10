# D漫画 (dmanhua) 站源验收报告

- **稳定ID**：`dmanhua`
- **名称**：D漫画
- **2.0.40注册位置**：`PublicSourceRegistry.java` / `public-sources.json` (`auditIndex = 24`)；`DownloadSources.java` 公共站源注册链
- **顺序/默认启用**：优先级 46；默认开启 (`defaultEnabled = true`)
- **原始能力限制**：主站 `https://www.dmanhua.com`，适配家族 `wd`，正文解码器 `numbered`，目录逆序修正 `reverseCatalog = true`，阅读页分页合并 `readerPagination = false`；网络提示：「部分线路可直连」；能力提示：「支持列表、分类、详情、目录与正文阅读」。
- **当前适配器版本**：`ios/ComicCore/Sources/ComicCore/PublicComicSource.swift`、`PublicSourceRegistry.swift`、`PublicSourceImages.swift`、`PublicSourceHTML.swift`
- **验收日期**：2026-10-10
- **网络条件**：实网探测验证（基线域名 `https://www.dmanhua.com`）
- **Android / iOS 对照结果**：与 Android 2.0.40 `PublicComicSource.java`、`PublicSourceRegistry.java`、`PublicSourceImages.java` 契约 1:1 完全对齐。移动端 `User-Agent`、卡片选择器（`.card-content, .manga-card`）、目录选择器（``）、阅读器选择器/解码器（`numbered` / 无（脚本/接口提取））、`#xx-public=` 缓存标识与 Referer 传递完全一致。

---

## 一、真实网络与功能项验收明细

| 项目 | 输入 / 用户操作 | 预期 / 原版能力 | 实际结果 | 判定 | 脱敏证据 |
| --- | --- | --- | --- | --- | --- |
| **最新列表与翻页** | 请求 `/sort?category=0&tag=0&page={page}` (`page=1, 2`) | 解析卡片列表（标题、封面、详情 canonical ID） | HTTP 200，第 1 页提取 24 部作品（首部：「不要突然撲過來呀，常葉同學」，ID：`dmanhua:/comic/10369.html`）；第 2 页返回 24 条（新增不重复 24 条） | **PASS** | 封面 HTTP 200 (83104B, SHA-256: `4d0a8c5d0a78b4e8c14c5c912704a16b9ae41285c452df17b2569ba0ad503f95`) |
| **分类筛选** | 调用 `filterGroups()` 与 `category(filters:page:)` | 返回筛选项并按分类路由请求列表 | 共 2 组筛选项；实测筛选「韩国漫画 (`2`)」返回 24 部作品 | **PASS** | `PublicComicSourceTests` 契约测试与实网探测通过 |
| **搜索与分页** | 关键词「常葉」(`/search?query={keyword}&page={page}`) | 按原版搜索契约返回匹配结果或空列表 | HTTP 200，返回 15 条结果（前 3 条：不要突然撲過來呀，常葉同學、万族入侵：开局驯化史诗级巨兽、只有超能力者受伤害的世界；关键词匹配：True） | **PASS** | 实网搜索探测与 `PublicComicSourceTests` 验证通过 |
| **作品详情与章节目录** | 请求 `https://www.dmanhua.com/comic/10369.html` | 提取标题、封面、简介与可读章节列表 | HTTP 200，解析标题「不要突然撲過來呀，常葉同學」，提取可读章节 7 话（前 3 话：第01話、第1.1話、第1.2話） | **PASS** | 样本详情页实网请求验证 |
| **章节阅读与图片校验** | 请求 `https://www.dmanhua.com/chapter/10369-840563.html` 并抽样下载首/中/尾图片 | 解析正文图片地址并携带 Referer 下载解码 | 共提取 16 张正文图片（解码器：`numbered`）；抽样校验：第 1 页 HTTP 200 (146666B, SHA-256: `1362862ebfdcbba2...`)；第 9 页 HTTP 200 (229824B, SHA-256: `96b37389bbd4d4bd...`)；第 16 页 HTTP 200 (150958B, SHA-256: `209ff0dc156f5740...`) | **PASS** | 首/中/尾样本图片实网 HTTP 状态、字节数与 SHA-256 记录 |

---

## 二、源整体结论

- **验收结论**：**PASS**（真实网络全链路验证通过：最新列表、翻页、分类筛选、作品详情、章节目录（7 话）、正文图片提取（16 张）及首/中/尾 3 张图片二进制下载与图像头校验全部通过）
- **状态更新**：在 `sources.csv` 中将 `dmanhua` 状态记录为 **通过**。
