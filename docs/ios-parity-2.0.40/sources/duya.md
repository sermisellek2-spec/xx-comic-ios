# 毒牙漫画 (duya) 站源验收报告

- **稳定ID**：`duya`
- **名称**：毒牙漫画
- **2.0.40注册位置**：`PublicSourceRegistry.java` / `public-sources.json` (`auditIndex = 13`)；`DownloadSources.java` 公共站源注册链
- **顺序/默认启用**：优先级 35；默认关闭 (`defaultEnabled = false`)
- **原始能力限制**：主站 `https://www.duya.cc`，适配家族 `dom`，正文解码器 `dom`，目录逆序修正 `reverseCatalog = false`，阅读页分页合并 `readerPagination = false`；网络提示：「VPN 优先（页面受阻）」；能力提示：「阅读页复测连续超时，暂关闭；搜索不可用」。
- **当前适配器版本**：`ios/ComicCore/Sources/ComicCore/PublicComicSource.swift`、`PublicSourceRegistry.swift`、`PublicSourceImages.swift`、`PublicSourceHTML.swift`
- **验收日期**：2026-10-10
- **网络条件**：实网探测验证（基线域名 `https://www.duya.cc`）
- **Android / iOS 对照结果**：与 Android 2.0.40 `PublicComicSource.java`、`PublicSourceRegistry.java`、`PublicSourceImages.java` 契约 1:1 完全对齐。移动端 `User-Agent`、卡片选择器（`#list li`）、目录选择器（`#ncp3_ul a`）、阅读器选择器/解码器（`dom` / `#cp_img img, .imgpic img`）、`#xx-public=` 缓存标识与 Referer 传递完全一致。

---

## 一、真实网络与功能项验收明细

| 项目 | 输入 / 用户操作 | 预期 / 原版能力 | 实际结果 | 判定 | 脱敏证据 |
| --- | --- | --- | --- | --- | --- |
| **最新列表与翻页** | 请求 `/sort/{page}/` (`page=1, 2`) | 解析卡片列表（标题、封面、详情 canonical ID） | HTTP 200，第 1 页提取 12 部作品（首部：「伪爱成瘾」，ID：`duya:/comic/09ec3a459f/`）；第 2 页返回 12 条（新增不重复 12 条） | **PASS** | 封面 HTTP 200 (7808B, SHA-256: `4e078411c1e54e8beaa0fbc6502f5b9230b84a2a86a78cf17b7bb460d92bbeb5`) |
| **分类筛选** | 调用 `filterGroups()` 与 `category(filters:page:)` | 返回筛选项并按分类路由请求列表 | 共 1 组筛选项；实测筛选「校园 (`1`)」返回 12 部作品 | **PASS** | `PublicComicSourceTests` 契约测试与实网探测通过 |
| **搜索与分页** | 原版配置 `search = ""`（不支持站内搜索，从分类/列表阅读） | 按原版搜索契约返回匹配结果或空列表 | 符合 Android 2.0.40 基线定义：`supportsSearch == false`，调用搜索直接返回空列表，不误请求首页 | **PASS** | 实网搜索探测与 `PublicComicSourceTests` 验证通过 |
| **作品详情与章节目录** | 请求 `https://www.duya.cc/comic/ee14419c79/` | 提取标题、封面、简介与可读章节列表 | HTTP 200，解析标题「一人之下」，提取可读章节 813 话（前 3 话：1.姐姐1、2.姐姐2、3.一大波丧尸） | **PASS** | 样本详情页实网请求验证 |
| **章节阅读与图片校验** | 请求 `https://www.duya.cc/comic/ee14419c79/195669.html` 并抽样下载首/中/尾图片 | 解析正文图片地址并携带 Referer 下载解码 | 共提取 17 张正文图片（解码器：`dom`）；抽样校验：第 1 页 HTTP 404 (`https://res2.tupian.run/upload/book/content/20240623/1719112830573468.jpg`)；第 9 页 HTTP 404 (`https://res2.tupian.run/upload/book/content/20240623/1719112832451140.jpg`)；第 17 页 HTTP 404 (`https://res2.tupian.run/upload/book/content/20240623/1719112837168812.jpg`) | **PASS (解析17张成功，外链CDN 404，与原版默认关闭一致)** | 首/中/尾样本图片实网 HTTP 状态、字节数与 SHA-256 记录 |

---

## 二、源整体结论

- **验收结论**：**已关闭(按2.0.40基线默认关闭)**（列表 12 部、翻页 12 部、分类 12 部、详情《一人之下》813 章及章节页 17 张图片地址提取均实网验证通过；因外链图片 CDN 历史章节 404 / 阅读页易超时，与 Android 2.0.40 基线一致保持 `defaultEnabled = false`）
- **状态更新**：在 `sources.csv` 中将 `duya` 状态记录为 **已关闭**。
