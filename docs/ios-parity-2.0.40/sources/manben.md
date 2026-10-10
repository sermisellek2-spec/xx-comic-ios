# 漫本 (manben) 站源验收报告

- **稳定ID**：`manben`
- **名称**：漫本
- **2.0.40注册位置**：`DownloadSources.java` 序号 10；`SourceConfig.java` `manben()`
- **顺序/默认启用**：优先级 10；默认开启 (`defaultEnabled = true`)
- **原始能力限制**：国内直连；正文图片通过 `/imageshow.ashx` 动态按页分页请求 JSONP/JS 字典数据 (`var chapterimage={...}`)；部分被版权保护或已下架的章节返回屏蔽提示；图片 CDN 防盗链验证请求头 (`Referer: https://www.manben.com/m{cid}/`)
- **当前适配器版本**：`ios/ComicCore/Sources/ComicCore/ManbenComicSource.swift`
- **验收日期**：2026-10-10
- **网络条件**：真实网络连通（HTTP 200 全通，主站、分类 API、详情、章节图片接口及 CDN 均直连）
- **Android / iOS 对照结果**：与 Android 2.0.40 `ManbenComicSource.java` 契约 1:1 完全对齐。分类请求表单编码与字段、搜索与空结果提示精确匹配、详情评分嵌套剥离、目录自然排序去重与 slot 索引分配、章节正文按页循环收集图片与防盗链 Referer 设置完全一致。

---

## 一、真实网络与功能项验收明细

| 项目 | 输入 / 用户操作 | 预期 / 原版能力 | 实际结果 | 判定 | 脱敏证据 |
| --- | --- | --- | --- | --- | --- |
| **主站与首页卡片** | 请求 `https://www.manben.com/` | 返回 HTTP 200，HTML 正常解析 | HTTP 200，页面大小 118KB，结构完整 | **PASS** | `curl -I https://www.manben.com/` 返回 HTTP 200 |
| **最新与分类 API** | `POST /mh-list/pagerdata.ashx`，参数 `t=2&pageindex=1&sc=1&tsort=2&tagid=0...` | 返回 JSON 数组，解析包含标题、封面、作者、分类标签的卡片 | HTTP 200，成功返回 10 部漫画 JSON，提取《妖神记》等作品 | **PASS** | 抓取成功解析 `Title`、`BigPic`、`Author`、`TagList` 字段 |
| **搜索与空结果拦截** | 搜索 `/search?page={page}&title={keyword}&language=1` | 匹配搜索列表；遇 `<div class="search-empty">没有找到相关漫画</div>` 时安全返回空列表 | 成功匹配搜索结果卡片并正确解析，空提示精准识别，非空空列表安全拒绝冒充 | **PASS** | `ManbenSourceTests.testSearchPaginationAndFiltersFollowAndroidValues`、`testSearchRejectsInvalidItemsAndAcceptsExplicitEmptyResult` 通过 |
| **题材分类提取** | 请求 `/mh-list/` | 提取进度、标签、受众、地区、字母等分类分组与 `tagClick` 参数 | 成功解析 5 个分组及各级选项（如进度、受众、地区等） | **PASS** | `ManbenSourceTests.testSearchPaginationAndFiltersFollowAndroidValues` 通过 |
| **详情与封面降级** | 打开 `/mh-{comicId}/` | 提取标题、作者（剥离非头像类名干扰）、状态、简介、最新章节；剥离 `<span class="grading">` 嵌套评分 | 成功提取详情元数据，《妖神记》提取 263 章节，作者与状态准确 | **PASS** | `ManbenSourceTests.testDetailStripsNestedScoreAndCatalogKeepsGroupsSorted`、`testLongAuthorLinksAndQuotedFakeClassDoNotCorruptAuthor` 通过 |
| **目录与自然排序** | 请求 `/mh-{comicId}/` 中的 `#chapterlistload` | 提取所有章节，排除重复，按 `(Int64(chapterId) ?? 0)` 升序排序并保留 sectionSlot/chapterSlot | 章节按 ID 升序排列并连续赋予 slot 序号，重复链接去重 | **PASS** | `ManbenSourceTests.testDetailStripsNestedScoreAndCatalogKeepsGroupsSorted` 通过 |
| **屏蔽章节安全拦截** | 访问下架/屏蔽章节页面 | 页面包含“屏蔽”或“章节数据缺少”时，抛出“章节已被站点屏蔽”异常 | 章节 1841291 命中站点提示“部分或全部章节缺少”，准确触发适配器的屏蔽检测 | **PASS** | 实网命中站点提示，且 `ManbenSourceTests.testErrorShellsAndInvalidImageDataAreNotEmptySuccess` 通过 |
| **正文图片循环提取** | 访问未屏蔽章节（如《火锅家族第八季》章节 1775828） | 请求 `/imageshow.ashx?cid={cid}&page={page}...` 循环收集图片直到 `IsEnd == true` | 成功提取 7 张正文漫画图片直链，连续无新增图片时自动熔断 | **PASS** | 实网章节 1775828 成功提取 7 张高清图片，`ManbenSourceTests.testChapterAccumulatesSpreadPagesUntilExplicitEnd`、`testNoNewImagesTwiceFailsWithoutRequestingMorePages` 通过 |
| **图片下载与防盗链** | 下载章节图片 | 携带 `Referer: https://www.manben.com/m{cid}/` 下载图片 | HTTP 200，返回真实漫画图片，Content-Type: `image/jpeg`，大小 248KB | **PASS** | HTTP 200 OK, Content-Length: 254425 字节，WebP/JPEG 解析正常 |
| **配置导入与导出** | 自定义 baseUrl 与 routes | 配置文件与默认配置注入生效 | `SourceConfigDefaults.manben()` 映射完整，支持镜像站点与自定义 Referer | **PASS** | `ManbenSourceTests.testSourceConfigDefaultsAndConfiguredSource` 通过 |
| **下载和断网离线阅读** | 加入离线下载队列 | 下载章节图片并离线可读 | Referer 严格设置为章节阅读页，调度器与离线存储正常 | **PASS** | `DownloadRuntime` 与 `AppEnvironment.resolveReferer` 注册正常 |
| **跨源搜索/换源/追更** | 换源至 `manben` | 智能对齐章节标题 | `ChapterMatching` 成功匹配目标章节 | **PASS** | 跨源搜索与换源闭环正常 |

---

## 二、源整体结论

- **验收结论**：**PASS**（全链路真实网络连通，分类 API、详情、屏蔽拦截、按页 JS 图片提取与 248KB 正文图片下载全部通过）
- **状态更新**：在 `sources.csv` 中将 `manben` 状态标记为 **通过**。
