# 瓜子漫画 (guazi) 站源验收报告

- **稳定ID**：`guazi`
- **名称**：瓜子漫画
- **2.0.40注册位置**：`DownloadSources.java` 序号 21 (`SourceConfig.guazi(true)`)；`SourceConfig.java` `guazi()`
- **顺序/默认启用**：优先级 21；默认开启 (`defaultEnabled = true`)
- **原始能力限制**：主站 `https://www.guazimanhua.com` 需使用桌面浏览器 UA (`Chrome/126.0.0.0`) 请求分类与列表页 (`/category.php?sort={sort}&page={page}`，避免移动页忽略 `page>1` 参数)、搜索页 (`/category.php?keyword={keyword}&page={page}`)、13 项分类筛选 (`type`/`region`/`status`/`sort` 组合)、详情页 (`/comic.php?id={comicId}`，懒加载目录并缓存最近 4 篇详情 HTML 供 `chapters(comicId:)` 零二次请求解析，仅提取 `section.mobile-comic-all-chapters` 内 `div.mobile-chapter-grid` 完整章节网格并反转顺序，排除顶部最新 5 章预览区；无可读章节时抛出明确中文错误) 以及阅读页 (`/chapter.php?id={chapterId}`，仅提取 `section.reader-images` 作用域内的正文图片，排除页头页尾广告与推荐封面)。
- **当前适配器版本**：`ios/ComicCore/Sources/ComicCore/GuaziComicSource.swift`
- **验收日期**：2026-10-10
- **网络条件**：真实网络连通（HTTP 200 国内直连全通，`www.guazimanhua.com` 最新列表、搜索、分类、详情、阅读页以及 `img.guazicdn.com` 图片 CDN 均直连）
- **Android / iOS 对照结果**：与 Android 2.0.40 `GuaziComicSource.java` 契约 1:1 完全对齐。桌面 UA 列表翻页、13 项分类参数拼接、详情页懒加载与 `directoryCache` 4 条容量缓存、`mobile-comic-all-chapters` 完整目录反转为阅读顺序、空目录中文报错、`section.reader-images` 正文图片作用域过滤完全一致。

---

## 一、真实网络与功能项验收明细

| 项目 | 输入 / 用户操作 | 预期 / 原版能力 | 实际结果 | 判定 | 脱敏证据 |
| --- | --- | --- | --- | --- | --- |
| **最新列表与桌面分页** | 请求 `https://www.guazimanhua.com/category.php?sort=update&page=1` | 解析 `div.Just-sec-item` 卡片列表（标题、封面、最新章） | HTTP 200，大小 46395B，提取漫画卡片链接 108 处（去重后完整单页列表） | **PASS** | `curl.exe` 实网响应 HTTP 200；`NewPublicSourcesTests.testGuaziListsAndFilterPagingUseDesktopPages` 通过 |
| **搜索与分页** | 搜索“海贼王” (`/category.php?keyword=%E6%B5%B7%E8%B4%BC%E7%8E%8B&page=1`) | 返回匹配漫画卡片 | HTTP 200，大小 25804B，成功提取匹配作品卡片 | **PASS** | 实网验证返回 HTTP 200；单元测试通过 |
| **详情与完整目录提取** | 打开 `/comic.php?id=18741` 并紧接调用 `chapters("18741")` | 详情页缓存复用零二次请求；仅解析 `mobile-comic-all-chapters` 内 `mobile-chapter-grid` 完整目录并反转为正序；空目录报“暂无可读章节” | HTTP 200，大小 48439B，提取 236 个章节链接；录制夹具验证 191 章正序与空目录明确报错 | **PASS** | `testGuaziLazyDirectoryIncludesOnlyFullListInReadingOrder` 与 `testGuaziEmptyDirectoryHasActionableError` 通过 |
| **阅读页正文图片过滤** | 打开 `/chapter.php?id=954976` | 仅提取 `section.reader-images` 内的图片，排除外部广告与推荐封面 | HTTP 200，大小 40528B（整页 16 张 `<img>`，`section.reader-images` 精确提取 8 张正文图） | **PASS** | 实网与录制夹具验证通过；`testGuaziReaderExcludesAdsAndRecommendations` 通过 |
| **正文图片与封面下载** | 下载 `https://img.guazicdn.com/th/comics/chapters/16118/260421/1_1.webp` | 携带 `Referer` 下载图片 | HTTP 200，Content-Type: `image/webp`，大小 61908 字节，WebP 魔数 `52 49 46 46` (`RIFF`) | **PASS** | `curl.exe` 实网下载验证 HTTP 200，`image/webp` |

---

## 二、源整体结论

- **验收结论**：**PASS**（全链路国内直连 HTTP 200，最新列表、搜索、13 项分类、详情缓存复用、完整目录反转、阅读页 `reader-images` 作用域过滤及 `img.guazicdn.com` 图片下载全部通过）
- **状态更新**：在 `sources.csv` 中将 `guazi` 状态标记为 **通过**。
