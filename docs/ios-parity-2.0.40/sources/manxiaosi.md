# 漫小肆 (manxiaosi) 站源验收报告

- **稳定ID**：`manxiaosi`
- **名称**：漫小肆
- **2.0.40注册位置**：`PublicSourceRegistry.java` / `public-sources.json` (`auditIndex = 7`)；`DownloadSources.java` 公共站源注册链
- **顺序/默认启用**：优先级 29；默认开启 (`defaultEnabled = true`)
- **原始能力限制**：主站 `https://www.pknbc.com`，适配家族 `dom`，正文解码器 `dom`，目录逆序修正 `reverseCatalog = false`，阅读页分页合并 `readerPagination = false`；网络提示：「部分线路可直连」；能力提示：「支持列表、分类、详情、目录与正文阅读」。
- **当前适配器版本**：`ios/ComicCore/Sources/ComicCore/PublicComicSource.swift`、`PublicSourceRegistry.swift`、`PublicSourceImages.swift`、`PublicSourceHTML.swift`
- **验收日期**：2026-10-10
- **网络条件**：实网探测验证（基线域名 `https://www.pknbc.com`）
- **Android / iOS 对照结果**：与 Android 2.0.40 `PublicComicSource.java`、`PublicSourceRegistry.java`、`PublicSourceImages.java` 契约 1:1 完全对齐。移动端 `User-Agent`、卡片选择器（`.manga-list li, .book-list li`）、目录选择器（`#detail-list-select a`）、阅读器选择器/解码器（`dom` / `#cp_img img.lazy`）、`#xx-public=` 缓存标识与 Referer 传递完全一致。

---

## 一、真实网络与功能项验收明细

| 项目 | 输入 / 用户操作 | 预期 / 原版能力 | 实际结果 | 判定 | 脱敏证据 |
| --- | --- | --- | --- | --- | --- |
| **最新列表与翻页** | 请求 `/booklist?tag=全部&page={page}` (`page=1, 2`) | 解析卡片列表（标题、封面、详情 canonical ID） | HTTP 200，第 1 页提取 21 部作品（首部：「單身育兒好寂寞」，ID：`manxiaosi:/book/1247`）；第 2 页返回 21 条（新增不重复 21 条） | **PASS** | 封面 HTTP 200 (23531B, SHA-256: `7f777d746e14c424621fe9e925f7590f5eb812bfaa3157df7fc9f00143135db5`) |
| **分类筛选** | 调用 `filterGroups()` 与 `category(filters:page:)` | 返回筛选项并按分类路由请求列表 | 共 1 组筛选项；实测筛选「连载 (`1`)」返回 21 部作品 | **PASS** | `PublicComicSourceTests` 契约测试与实网探测通过 |
| **搜索与分页** | 关键词「衣冠」(`/search?keyword={keyword}&page={page}`) | 按原版搜索契约返回匹配结果或空列表 | HTTP 200，返回 2 条结果（前 3 条：衣冠禽獸、她的直播間；关键词匹配：True） | **PASS** | 实网搜索探测与 `PublicComicSourceTests` 验证通过 |
| **作品详情与章节目录** | 请求 `https://www.pknbc.com/book/1224` | 提取标题、封面、简介与可读章节列表 | HTTP 200，解析标题「衣冠禽獸」，提取可读章节 15 话（前 3 话：第1話-想要叛逆的乖乖牌、第2話-學妹過分的請求、第3話-先由我開始品嘗） | **PASS** | 样本详情页实网请求验证 |
| **章节阅读与图片校验** | 请求 `https://www.pknbc.com/chapter/57217` 并抽样下载首/中/尾图片 | 解析正文图片地址并携带 Referer 下载解码 | 共提取 310 张正文图片（解码器：`dom`）；抽样校验：第 1 页 HTTP 200 (16834B, SHA-256: `a4d4ad17bae4531b...`)；第 156 页 HTTP 200 (8982B, SHA-256: `c8f267019d4ff2c6...`)；第 310 页 HTTP 200 (6911B, SHA-256: `b3124d23272f68e0...`) | **PASS** | 首/中/尾样本图片实网 HTTP 状态、字节数与 SHA-256 记录 |

---

## 二、源整体结论

- **验收结论**：**PASS**（真实网络全链路验证通过：最新列表、翻页、分类筛选、作品详情、章节目录（15 话）、正文图片提取（310 张）及首/中/尾 3 张图片二进制下载与图像头校验全部通过）
- **状态更新**：在 `sources.csv` 中将 `manxiaosi` 状态记录为 **通过**。
