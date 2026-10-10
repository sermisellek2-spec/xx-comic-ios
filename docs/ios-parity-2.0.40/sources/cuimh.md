# 催漫画 (cuimh) 站源验收报告

- **稳定ID**：`cuimh`
- **名称**：催漫画
- **2.0.40注册位置**：`DownloadSources.java` 序号 14；`SourceConfig.java` `cuimh()`
- **顺序/默认启用**：优先级 14；默认开启 (`defaultEnabled = true`)
- **原始能力限制**：国内直连；按 Android 2.0.40 设计，`supportsSearch = false`（搜索显式不支持，避免高频请求触发全站封禁）；内置 `CuimhRequestGate` 串行门控（最小请求间隔 1000ms）、8 个容量 5 分钟 TTL 的 LRU 分类文档缓存、以及 HTTP 403 触发 30 分钟冷却保护；阅读页正文参数 `params` 为 Base64 + AES-128-CBC (`key = 9S8$vJnU2ANeSRoF`, 前 16 字节 IV) 加密的 JSON 载荷。
- **当前适配器版本**：`ios/ComicCore/Sources/ComicCore/CuimhComicSource.swift`
- **验收日期**：2026-10-10
- **网络条件**：真实网络连通（HTTP 200 全通，分类页、详情页、阅读页 AES 解密与图片 CDN `s2.325784.xyz` 均直连）
- **Android / iOS 对照结果**：与 Android 2.0.40 `CuimhComicSource.java` 契约 1:1 完全对齐。`cy_list_mh` 卡片提取、7 个分类维度有序拼接、详情与目录同文档去重提取、阅读页 AES-128-CBC 解密与 `host == www.cuimh.com` 校验、1 秒串行节流、8 条目 LRU 缓存及 403 冷却保护完全一致。

---

## 一、真实网络与功能项验收明细

| 项目 | 输入 / 用户操作 | 预期 / 原版能力 | 实际结果 | 判定 | 脱敏证据 |
| --- | --- | --- | --- | --- | --- |
| **最新与分类列表** | 请求 `https://www.cuimh.com/category/` | 返回分类筛选栏与漫画卡片列表 | HTTP 200，成功解析出《代号阿纳斯塔西亚》、《我为邪帝》、《全职法师》等漫画卡片 | **PASS** | `curl.exe` 实网返回包含 `cy_tag` 与 `cy_list_mh` 的完整 HTML |
| **搜索显式拦截** | 调用 `search(keyword:page:)` | `supportsSearch == false`，不发起网络请求并抛出提示 | 显式返回不支持搜索错误，0 网络请求；全站搜索自动跳过 | **PASS** | `CuimhSourceTests.testSearchIsExplicitlyUnsupportedWithoutNetwork` 通过 |
| **多维分类筛选** | 请求 `/category/` 并组合筛选参数 | 按固定顺序拼接 `/list/`、`/tags/`、`/theme/`、`/quality/`、`/city/`、`/copyright/`、`/finish/` | 成功提取分类组并按固定顺序组合路径请求 | **PASS** | `CuimhSourceTests.testFiltersKeepSupportedGroupsAndComposeOnlyMatchingPrefixesInFixedOrder` 通过 |
| **详情与目录解析** | 打开 `https://www.cuimh.com/daihaoanasitaxiya` | 提取标题、封面、作者、状态、简介、最新话及章节列表 | HTTP 200，大小 42.5KB，成功提取《代号阿纳斯塔西亚》详情及 51 个章节（`第50话` 至 `序`） | **PASS** | 实网提取 51 个 `<li class="chapter__item">` 节点 |
| **正文 AES-128-CBC 解密** | 打开 `https://www.cuimh.com/412760-147486.html` | 提取 `params` Base64 字符串，前 16 字节作为 IV 解密 JSON 并校验 `host` | HTTP 200，大小 47.2KB，成功解密出 `host: www.cuimh.com` 及 49 张 WebP 正文图片直链 | **PASS** | 实网解密出 49 张 `https://s2.325784.xyz/...` 图片 URL |
| **图片下载与防盗链** | 下载章节图片 | 携带 `Referer: https://www.cuimh.com/` 下载图片 | HTTP 200，Content-Type: `image/webp`，Cloudflare 缓存命中 (`cf-cache-status: HIT`) | **PASS** | `curl.exe -I` 验证返回 HTTP/1.1 200 OK，`image/webp` |
| **串行门控、LRU缓存与403冷却** | 并发请求、重复分类请求与 403 响应 | 并发请求串行化且间隔 ≥ 1000ms；分类缓存 5 分钟 TTL / 8 容量 LRU；403 冷却 30 分钟 | 门控、LRU 淘汰与 403 冷却（含任务取消场景）全部符合基线 | **PASS** | `CuimhSourceTests` 中 5 项并发/缓存/冷却测试全部通过 |
| **配置导入与导出** | 自定义 `baseUrl`、`referer` 与 `detail` 路由 | 配置文件与默认配置注入生效 | `SourceConfigDefaults.cuimh()` 映射完整，支持自定义配置 | **PASS** | `CuimhSourceTests.testDefaultConfigMatchesBaselineContract` 与 `testCustomConfigCustomizesBaseURLAndDetailRoute` 通过 |

---

## 二、源整体结论

- **验收结论**：**PASS**（全链路真实网络连通，分类列表、多维筛选、详情、51 章目录提取、阅读页 AES-128-CBC 解密 49 张图片、WebP 图片 CDN 直连下载以及串行限流/缓存/403 保护全部通过）
- **状态更新**：在 `sources.csv` 中将 `cuimh` 状态标记为 **通过**。
