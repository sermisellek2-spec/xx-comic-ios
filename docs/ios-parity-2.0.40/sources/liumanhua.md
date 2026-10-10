# 六漫画 (liumanhua) 站源验收报告

- **稳定ID**：`liumanhua`
- **名称**：六漫画
- **2.0.40注册位置**：`DownloadSources.java` 序号 15 (`SourceConfig.liumanhua(true)`)；`SourceConfig.java` `liumanhua()`
- **顺序/默认启用**：优先级 17；默认开启 (`defaultEnabled = true`)
- **原始能力限制**：主站 `https://www.liumanhua.com` 原版设计不提供关键词搜索 (`supportsSearch = false`，调用 `search` 明确抛出“六漫画暂不支持搜索”)，仅通过 `/category` 多维分类列表（分类、题材/标签、类型、品质、地区、版权、进度，自动过滤“资费”分组）、详情页 `/{comicId}`（内联提取 `cy_plist` 章节目录或回退同作品 `cy_kan` 在线阅读链接，忽略 `rd-guess__comic` 推荐列表）以及阅读页 `/{comicId}/{chapterId}.html`（`params` Base64 前 16 字节 IV + AES-128-CBC `9S8$vJnU2ANeSRoF` 解密 JSON）提供浏览与阅读。
- **当前适配器版本**：`ios/ComicCore/Sources/ComicCore/LiumanhuaComicSource.swift`
- **验收日期**：2026-10-10
- **网络条件**：真实网络连通（HTTP 200 国内直连全通，分类筛选页、详情页、阅读页 `params` 解密、以及 `s2.bzcdn.net` 图片 CDN 均直连）
- **Android / iOS 对照结果**：与 Android 2.0.40 `LiumanhuaComicSource.java` 契约 1:1 完全对齐。`supportsSearch == false`、7 个分类维度映射（自动剔除“资费”）、`cy_list_mh > ul` 卡片提取、`cy_plist` 与 `cy_kan` 严格同漫画 ID 校验、阅读页 `params` AES-128-CBC 解密及 `comic_down == 0` / `source_id == 6` / `host` / `comic_id` / `chapter_id` 多重身份校验完全一致。

---

## 一、真实网络与功能项验收明细

| 项目 | 输入 / 用户操作 | 预期 / 原版能力 | 实际结果 | 判定 | 脱敏证据 |
| --- | --- | --- | --- | --- | --- |
| **最新与分类列表** | 请求 `https://www.liumanhua.com/category` | 解析 `cy_list_mh > ul` 漫画卡片列表，忽略推荐区 | HTTP 200，大小 51.1KB，成功解析《魔都精兵的奴隶》(ID `263176`) 等 30 部漫画卡片 | **PASS** | `curl.exe` 实网响应 HTTP 200；`LiumanhuaSourceTests.testLatestParsesOnlyScopedCardsAndUsesCategoryPagination` 通过 |
| **多维分类字典提取** | 解析 `/category` 中 `.cy_tag` | 提取分类、题材、状态等筛选组，跳过“资费”组 | 实网 HTML 包含 `.cy_tag` 与 `.cy_list_mh`，筛选组提取与路由拼接正常 | **PASS** | `LiumanhuaSourceTests.testFiltersSkipPaidGroupAndCategoryUsesFirstSupportedSelection` 通过 |
| **搜索能力显式禁用** | 检查 `supportsSearch` 或调用 `search(keyword:page:)` | `supportsSearch == false`，不发起网络请求并抛出“六漫画暂不支持搜索” | 零网络请求，准确抛出“六漫画暂不支持搜索” | **PASS** | `LiumanhuaSourceTests.testSearchIsUnsupportedWithoutNetwork` 通过 |
| **详情与目录同页解析** | 打开 `/263176` | 解析 `.cy_title h1`、`.cy_info_cover img`、作者/状态/最新/简介及 `.cy_plist` 目录（严格匹配 `/263176/*.html`） | HTTP 200，成功提取《魔都精兵的奴隶》详情及 224 个章节（最新 `/263176/225087.html` 第187话） | **PASS** | 实网提取 224 章；`LiumanhuaSourceTests.testDetailIncludesOnlyItsCatalogFromTheSameDocument` 通过 |
| **正文 AES-128-CBC 解密** | 打开 `/263176/225087.html` | 提取 `params` Base64，前 16 字节为 IV，密钥 `9S8$vJnU2ANeSRoF` 解密并校验 `source_id == 6`、`host == www.liumanhua.com`、`comic_down == 0` | HTTP 200，`params` (2688 字符) 成功解密出 `source_id: 6, host: www.liumanhua.com, comic_down: 0` 及 21 张图片直链 | **PASS** | 实网解密出 `https://s2.bzcdn.net/scomic/modujingbingdenuli-zhucunyangping/0/225-mf9e/1.jpg` 等 21 张图片 |
| **异常与安全边界拦截** | 注入 `comic_down != 0`、`source_id != 6`、跨站 `host`、串章 ID 或错误壳 HTML | 拒绝返回半成品或错误数据，明确抛出对应原因 | 9 种加密负载异常向量与 HTML 错误壳全部被准确拦截 | **PASS** | `LiumanhuaSourceTests.testPayloadRejectsRestrictionsIdentityMismatchesAndInvalidImages` 通过 |
| **图片下载与防盗链** | 下载 `https://s2.bzcdn.net/scomic/.../1.jpg` | 携带 `Referer: https://www.liumanhua.com/` 下载图片 | HTTP 200，Content-Type: `image/jpeg`，Content-Length: 549823 字节 | **PASS** | `curl.exe -I` 验证返回 HTTP/1.1 200 OK，`image/jpeg` |
| **配置导入与健康检查** | 自定义 `baseUrl`、`detail` 路由及调用 `healthCheck()` | 配置文件与默认配置注入生效，`healthCheck()` 校验 `cy_list_mh` 与 `cy_tag` | `SourceConfigDefaults.liumanhua()` 映射完整，`healthCheck()` 返回 `true` | **PASS** | `LiumanhuaSourceTests.testSourceConfigDefaultsAndHealthCheck` 通过 |

---

## 二、源整体结论

- **验收结论**：**PASS**（全链路国内直连 HTTP 200，分类筛选、详情同页 224 章目录提取、阅读页 `params` AES-128-CBC 解密 21 张正文图片以及 `s2.bzcdn.net` 图片下载全部通过）
- **状态更新**：在 `sources.csv` 中将 `liumanhua` 状态标记为 **通过**。
