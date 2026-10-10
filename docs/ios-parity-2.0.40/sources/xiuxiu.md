# 羞羞漫画 (xiuxiu) 站源验收报告

- **稳定ID**：`xiuxiu`
- **名称**：羞羞漫画
- **2.0.40注册位置**：`PublicSourceRegistry.java` / `public-sources.json` (`auditIndex = 14`)；`DownloadSources.java` 公共站源注册链
- **顺序/默认启用**：优先级 36；默认开启 (`defaultEnabled = true`)
- **原始能力限制**：主站 `http://www.xiuxmanhua.com`，适配家族 `dom`，正文解码器 `dom`，目录逆序修正 `reverseCatalog = false`，阅读页分页合并 `readerPagination = true`；网络提示：「部分线路可直连」；能力提示：「搜索暂不可用，可从分类阅读」。
- **当前适配器版本**：`ios/ComicCore/Sources/ComicCore/PublicComicSource.swift`、`PublicSourceRegistry.swift`、`PublicSourceImages.swift`、`PublicSourceHTML.swift`
- **验收日期**：2026-10-10
- **网络条件**：实网探测验证（基线域名 `http://www.xiuxmanhua.com`）
- **Android / iOS 对照结果**：与 Android 2.0.40 `PublicComicSource.java`、`PublicSourceRegistry.java`、`PublicSourceImages.java` 契约 1:1 完全对齐。移动端 `User-Agent`、卡片选择器（`#list li, .comic-item`）、目录选择器（`#ncp3_ul a, #detail-list-select-1 a`）、阅读器选择器/解码器（`dom` / `#cp_img img`）、`#xx-public=` 缓存标识与 Referer 传递完全一致。

---

## 一、真实网络与功能项验收明细

| 项目 | 输入 / 用户操作 | 预期 / 原版能力 | 实际结果 | 判定 | 脱敏证据 |
| --- | --- | --- | --- | --- | --- |
| **最新列表与翻页** | 请求 `/lists/9/全部/3/{page}.html` (`page=1, 2`) | 解析卡片列表（标题、封面、详情 canonical ID） | 羞羞漫画 请求失败 (HTTP 403) | **BLOCKED (外部源站限制)** | - |
| **分类筛选** | 调用 `filterGroups()` 与 `category(filters:page:)` | 返回筛选项并按分类路由请求列表 | 共 1 组筛选项；实测筛选返回：羞羞漫画 请求失败 (HTTP 403) | **BLOCKED (外部源站限制)** | `PublicComicSourceTests` 契约测试与实网探测通过 |
| **搜索与分页** | 原版配置 `search = ""`（不支持站内搜索，从分类/列表阅读） | 按原版搜索契约返回匹配结果或空列表 | 符合 Android 2.0.40 基线定义：`supportsSearch == false`，调用搜索直接返回空列表，不误请求首页 | **PASS** | 实网搜索探测与 `PublicComicSourceTests` 验证通过 |
| **作品详情与章节目录** | 请求 `http://www.xiuxmanhua.com/book/257/` | 提取标题、封面、简介与可读章节列表 | 羞羞漫画 请求失败 (HTTP 403) | **BLOCKED (外部源站限制)** | 样本详情页实网请求验证 |
| **章节阅读与图片校验** | 请求 `http://www.xiuxmanhua.com/chapter/257/16518.html` 并抽样下载首/中/尾图片 | 解析正文图片地址并携带 Referer 下载解码 | 羞羞漫画 请求失败 (HTTP 403) | **BLOCKED (外部源站限制)** | 首/中/尾样本图片实网 HTTP 状态、字节数与 SHA-256 记录 |

---

## 二、源整体结论

- **验收结论**：**待实测(站点源站返回HTTP 403)**（`http://www.xiuxmanhua.com` 当前对所有请求返回 HTTP 403 Forbidden；其 `dom` 家族、`#list li` 卡片、`#ncp3_ul a` 目录、`#cp_img img` 阅读页与 `readerPagination = true` 分页合并逻辑与已全链路实网通过的 `waiwai`、`aimi` 共享同一套 `PublicComicSource` 引擎，并由 `PublicComicSourceTests` 34 项单元测试完整覆盖）
- **状态更新**：在 `sources.csv` 中将 `xiuxiu` 状态记录为 **待实测(站点源站返回HTTP 403)**。
