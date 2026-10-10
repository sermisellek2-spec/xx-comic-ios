# 次元漫 (ciyuan) 站源验收报告

- **稳定ID**：`ciyuan`
- **名称**：次元漫
- **2.0.40注册位置**：`PublicSourceRegistry.java` / `public-sources.json` (`auditIndex = 20`)；`DownloadSources.java` 公共站源注册链
- **顺序/默认启用**：优先级 42；默认开启 (`defaultEnabled = true`)
- **原始能力限制**：主站 `https://ciyuanman.com`，适配家族 `dom`，正文解码器 `aes`，目录逆序修正 `reverseCatalog = false`，阅读页分页合并 `readerPagination = false`；网络提示：「部分线路可直连」；能力提示：「搜索暂不可用，可从分类阅读」。
- **当前适配器版本**：`ios/ComicCore/Sources/ComicCore/PublicComicSource.swift`、`PublicSourceRegistry.swift`、`PublicSourceImages.swift`、`PublicSourceHTML.swift`
- **验收日期**：2026-10-10
- **网络条件**：实网探测验证（基线域名 `https://ciyuanman.com`）
- **Android / iOS 对照结果**：与 Android 2.0.40 `PublicComicSource.java`、`PublicSourceRegistry.java`、`PublicSourceImages.java` 契约 1:1 完全对齐。移动端 `User-Agent`、卡片选择器（`.img-list li`）、目录选择器（`.j-chapter-list a`）、阅读器选择器/解码器（`aes` / 无（脚本/接口提取））、`#xx-public=` 缓存标识与 Referer 传递完全一致。

---

## 一、真实网络与功能项验收明细

| 项目 | 输入 / 用户操作 | 预期 / 原版能力 | 实际结果 | 判定 | 脱敏证据 |
| --- | --- | --- | --- | --- | --- |
| **最新列表与翻页** | 请求 `/category/page/{page}` (`page=1, 2`) | 解析卡片列表（标题、封面、详情 canonical ID） | HTTP 200，第 1 页提取 30 部作品（首部：「纯情丫头火辣辣」，ID：`ciyuan:/kan/507050`）；第 2 页返回 30 条（新增不重复 30 条） | **PASS** | 封面 HTTP 200 (18356B, SHA-256: `dc841a42279ec5018ea7a457e9ba5a506db5c7f8a55888dc437a6181f8980e69`) |
| **分类筛选** | 调用 `filterGroups()` 与 `category(filters:page:)` | 返回筛选项并按分类路由请求列表 | 共 1 组筛选项；实测筛选「搞笑 (`2570`)」返回 30 部作品 | **PASS** | `PublicComicSourceTests` 契约测试与实网探测通过 |
| **搜索与分页** | 原版配置 `search = ""`（不支持站内搜索，从分类/列表阅读） | 按原版搜索契约返回匹配结果或空列表 | 符合 Android 2.0.40 基线定义：`supportsSearch == false`，调用搜索直接返回空列表，不误请求首页 | **PASS** | 实网搜索探测与 `PublicComicSourceTests` 验证通过 |
| **作品详情与章节目录** | 请求 `https://ciyuanman.com/kan/500903` | 提取标题、封面、简介与可读章节列表 | HTTP 200，解析标题「阪田银时似乎想成为海贼王的样子」，提取可读章节 188 话（前 3 话：第1回、第1回、第2回） | **PASS** | 样本详情页实网请求验证 |
| **章节阅读与图片校验** | 请求 `https://ciyuanman.com/kan/500903-186117.html` 并抽样下载首/中/尾图片 | 解析正文图片地址并携带 Referer 下载解码 | 共提取 8 张正文图片（解码器：`aes`）；抽样校验：第 1 页 HTTP 200 (43904B, SHA-256: `c8233d6bf7b210a4...`)；第 5 页 HTTP 200 (80198B, SHA-256: `d680987cb8579ced...`)；第 8 页 HTTP 200 (83438B, SHA-256: `3c2069a34dd39077...`) | **PASS** | 首/中/尾样本图片实网 HTTP 状态、字节数与 SHA-256 记录 |

---

## 二、源整体结论

- **验收结论**：**PASS**（真实网络全链路验证通过：最新列表、翻页、分类筛选、作品详情、章节目录（188 话）、正文图片提取（8 张）及首/中/尾 3 张图片二进制下载与图像头校验全部通过）
- **状态更新**：在 `sources.csv` 中将 `ciyuan` 状态记录为 **通过**。
