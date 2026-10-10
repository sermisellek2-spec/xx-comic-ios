# 喵趣漫画 (miaoqu) 站源验收报告

- **稳定ID**：`miaoqu`
- **名称**：喵趣漫画
- **2.0.40注册位置**：`PublicSourceRegistry.java` / `public-sources.json` (`auditIndex = 11`)；`DownloadSources.java` 公共站源注册链
- **顺序/默认启用**：优先级 33；默认开启 (`defaultEnabled = true`)
- **原始能力限制**：主站 `https://www.miaoqumh.org`，适配家族 `dom`，正文解码器 `xor`，目录逆序修正 `reverseCatalog = false`，阅读页分页合并 `readerPagination = false`；网络提示：「部分线路可直连」；能力提示：「搜索暂不可用，可从分类阅读」。
- **当前适配器版本**：`ios/ComicCore/Sources/ComicCore/PublicComicSource.swift`、`PublicSourceRegistry.swift`、`PublicSourceImages.swift`、`PublicSourceHTML.swift`
- **验收日期**：2026-10-10
- **网络条件**：实网探测验证（基线域名 `https://www.miaoqumh.org`）
- **Android / iOS 对照结果**：与 Android 2.0.40 `PublicComicSource.java`、`PublicSourceRegistry.java`、`PublicSourceImages.java` 契约 1:1 完全对齐。移动端 `User-Agent`、卡片选择器（`#mangawrap li, .manga-box li`）、目录选择器（`#episodes a`）、阅读器选择器/解码器（`xor` / 无（脚本/接口提取））、`#xx-public=` 缓存标识与 Referer 传递完全一致。

---

## 一、真实网络与功能项验收明细

| 项目 | 输入 / 用户操作 | 预期 / 原版能力 | 实际结果 | 判定 | 脱敏证据 |
| --- | --- | --- | --- | --- | --- |
| **最新列表与翻页** | 请求 `/category/tags/215/page/{page}` (`page=1, 2`) | 解析卡片列表（标题、封面、详情 canonical ID） | HTTP 200，第 1 页提取 35 部作品（首部：「敖敖待捕 药药 后篇18 情不自禁」，ID：`miaoqu:/aoaodaibu`）；第 2 页返回 35 条（新增不重复 35 条） | **PASS** | 封面 HTTP 200 (42337B, SHA-256: `efe154335d820aa94b4fc1bfcb4511eb217949ecb0aeaf1af6af627321e9c26d`) |
| **分类筛选** | 调用 `filterGroups()` 与 `category(filters:page:)` | 返回筛选项并按分类路由请求列表 | 共 1 组筛选项；实测筛选「追新 (`1`)」返回 30 部作品 | **PASS** | `PublicComicSourceTests` 契约测试与实网探测通过 |
| **搜索与分页** | 原版配置 `search = ""`（不支持站内搜索，从分类/列表阅读） | 按原版搜索契约返回匹配结果或空列表 | 符合 Android 2.0.40 基线定义：`supportsSearch == false`，调用搜索直接返回空列表，不误请求首页 | **PASS** | 实网搜索探测与 `PublicComicSourceTests` 验证通过 |
| **作品详情与章节目录** | 请求 `https://www.miaoqumh.org/douluodalu5zhongshengtangsan` | 提取标题、封面、简介与可读章节列表 | HTTP 200，解析标题「斗罗大陆5重生唐三」，提取可读章节 313 话（前 3 话：1.序章、2.01 意外的能力、3.02 妖神变？！） | **PASS** | 样本详情页实网请求验证 |
| **章节阅读与图片校验** | 请求 `https://www.miaoqumh.org/233587/58303.html` 并抽样下载首/中/尾图片 | 解析正文图片地址并携带 Referer 下载解码 | 共提取 20 张正文图片（解码器：`xor`）；抽样校验：第 1 页 HTTP 200 (1217991B, SHA-256: `40b1ebb35c0aae2c...`)；第 11 页 HTTP 200 (641801B, SHA-256: `d8d965fef5ba2764...`)；第 20 页 HTTP 200 (1324602B, SHA-256: `e15fbad480b3aff7...`) | **PASS** | 首/中/尾样本图片实网 HTTP 状态、字节数与 SHA-256 记录 |

---

## 二、源整体结论

- **验收结论**：**PASS**（真实网络全链路验证通过：最新列表、翻页、分类筛选、作品详情、章节目录（313 话）、正文图片提取（20 张）及首/中/尾 3 张图片二进制下载与图像头校验全部通过）
- **状态更新**：在 `sources.csv` 中将 `miaoqu` 状态记录为 **通过**。
