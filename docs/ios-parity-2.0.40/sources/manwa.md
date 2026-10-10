# 漫蛙 (manwa) 站源验收报告

- **稳定ID**：`manwa`
- **名称**：漫蛙
- **2.0.40注册位置**：`DownloadSources.java` 序号 17 (`SourceConfig.manwa(true)`)；`SourceConfig.java` `manwa()`
- **顺序/默认启用**：优先级 16；默认开启 (`defaultEnabled = true`)
- **原始能力限制**：主站 `https://manwace.cc` 提供分类筛选（`POST /api/cate{suffix}` + 请求内独立 `Cookie: typeId={typeId}`）、搜索（`GET /api/search?type=mh&page={page}&pageSize=20&keyword={keyword}`）、详情页 HTML（`/comic/{comicId}`）、章节目录（`/api/comic/{comicId}/chapters`）与正文分页图片列表（`/api/comic/chapter/info/{chapterId}` + `/api/comic/image/{chapterId}?page={page}&page_size=100&image_source={imageSource}`）。封面与正文图片托管于 `mwtuwu.cc` / `tu.mwzu.cc` 等图床，流式数据采用前 16 字节 IV + AES-256-CBC (`0B6666A0-BB59-1381-B746-a0E4C9AC`) 加密。无登录或付费章节访问能力。
- **当前适配器版本**：`ios/ComicCore/Sources/ComicCore/ManwaComicSource.swift`、`ios/ComicCore/Sources/ComicCore/ManwaImageDecoder.swift`
- **验收日期**：2026-10-10
- **网络条件**：真实网络连通（HTTP 200 全通，主站分类筛选、搜索 API、详情页、章节列表 API、章节图片分页 API、以及 `mwtuwu.cc` / `tu.mwzu.cc` 加密图片下载与解密均直连）
- **Android / iOS 对照结果**：与 Android 2.0.40 `ManwaComicSource.java` 及 `ManwaImageDecoder.java` 契约 1:1 完全对齐。分类 7 组筛选项、22 个题材路由后缀（`hotblooded` 至 `taiwanver`）、请求局部 `Cookie: typeId={type}` 不跨请求污染、按 `sortId` 浮点保序排列章节、分页图片完整性与一致性校验、以及在线阅读/封面/离线下载的 AES-256-CBC 图片流解密完全一致。

---

## 一、真实网络与功能项验收明细

| 项目 | 输入 / 用户操作 | 预期 / 原版能力 | 实际结果 | 判定 | 脱敏证据 |
| --- | --- | --- | --- | --- | --- |
| **最新与分类列表** | `POST https://manwace.cc/api/cate` (`page=1, pageSize=36`) | 返回 `code: 200` 与 `data.list` 36 部漫画卡片 | HTTP 200，成功返回 `code: 200`，提取 36 部漫画卡片 | **PASS** | `curl.exe` 实网 POST 响应 `code: 200, list.count: 36`；`ManwaSourceTests.testCategoryPostsDefaultsAndCookieDoesNotLeakToSearch` 通过 |
| **搜索与分页** | 搜索“史莱姆” (`/api/search?type=mh&page=1&pageSize=20&keyword=%E5%8F%B2%E8%8E%B1%E5%A7%86`) | 返回匹配漫画列表并按数字 ID 去重 | HTTP 200，成功返回《关于我转生变成史莱姆这档事》(ID `3537`) 等 20 部作品 | **PASS** | 实网返回 20 部作品 JSON；`ManwaSourceTests.testListDecodesIDsImagesTagsAndDeduplicates` 通过 |
| **多维分类与题材后缀** | 切换范围、类型、22 个题材、地区、状态、星期、排序 | 7 组筛选项；题材追加 `/api/cate/{slug}` 路径后缀，类型注入局部 `Cookie: typeId={type}` | 22 个题材路由后缀与多维 JSON 请求体完全对齐，未知题材明确报错 | **PASS** | `ManwaSourceTests.testAllTagRoutesAndCombinedFilterValues` 通过 |
| **详情页懒加载目录** | 打开 `/comic/3537` 或 `/comic/163037` | 解析 `#page-title`、`img.comic-cover`、`#author-container`、`#tagsContainer`、`p.comic-desc`、`#status`、`#newch`，不预拉目录 | HTTP 200，成功提取《关于我转生变成史莱姆这档事》标题、封面、作者、状态与简介 | **PASS** | 实网 HTML 验证通过；`ManwaSourceTests.testDetailIsOnDemandAndUsesRealCoverAndNestedTags` 通过 |
| **目录浮点排序** | 请求 `/api/comic/3537/chapters` | 按 `sortId` 浮点升序稳定排序（兼容番外小数章节）并去重 | HTTP 200，成功返回 147 个章节并按 `sortId` 稳定排序 | **PASS** | 实网返回 147 章；`ManwaSourceTests.testDirectoryPreservesFractionalStableOrderAndAll878Chapters` 通过 |
| **正文图片分页聚合** | 请求 `/api/comic/chapter/info/2161449` 与 `/api/comic/image/2161449?page=1&page_size=100&image_source=https%3A%2F%2Ftu.mwzu.cc` | 校验 `current.comicId`/`id` 及 `pagination.total`/`total_pages` 一致性，聚合全部图片 URL | HTTP 200，返回 `total: 38, total_pages: 1`，提取全部 38 张 `https://tu.mwzu.cc/...` 图片 URL | **PASS** | 实网提取 38 张图片直链；`ManwaSourceTests.testChapterFetchesAllPagesInOrder` 通过 |
| **封面与正文 AES-256-CBC 解密** | 下载 `tu.mwzu.cc` 正文图片与 `mwtuwu.cc` 封面图片并执行 `ManwaImageDecoder.decode` | 前 16 字节作为 IV，后续密文用 `0B6666A0-BB59-1381-B746-a0E4C9AC` 解密还原真实图片流（明文图片直通，非图片报错） | 正文图片 (108464B) 解密还原为 108440B 合法 WebP (`RIFF....WEBP`)；封面图片 (11712B) 解密还原为 11693B 合法 JPEG (`FF D8 FF E0`) | **PASS** | 实网下载解密验证通过；`ManwaImageDecoderTests` 与 `DefaultDownloadImageFetcherTests.testDecodesManwaEncryptedImage` 通过 |
| **配置导入与导出** | 自定义 `baseUrl`、`referer` 与 `routes` | 配置文件与默认配置注入生效 | `SourceConfigDefaults.manwa()` 映射完整，支持自定义配置 | **PASS** | `SourcePreferencesTests.testImportedConfigUpdatesSourceEndpointsAndHeaders` 通过 |

---

## 二、源整体结论

- **验收结论**：**PASS**（全链路真实网络连通，分类 POST、搜索 API、详情 HTML、浮点排序目录、分页图片聚合以及封面/正文 AES-256-CBC 图片流解密全部通过）
- **状态更新**：在 `sources.csv` 中将 `manwa` 状态标记为 **通过**。
