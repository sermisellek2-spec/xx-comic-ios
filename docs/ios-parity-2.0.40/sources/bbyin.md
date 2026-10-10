# 比卡漫画 (bbyin) 站源验收报告

- **稳定ID**：`bbyin`
- **名称**：比卡漫画
- **2.0.40注册位置**：`DownloadSources.java` 序号 12；`SourceConfig.java` `bbyin()`
- **顺序/默认启用**：优先级 12；默认开启 (`defaultEnabled = true`)
- **原始能力限制**：国内直连；5um 架构模板；正文图片由 `manhua.5um.net` CDN 承载，防盗链请求头 (`Referer: https://bbyin.com/`)
- **当前适配器版本**：`ios/ComicCore/Sources/ComicCore/FiveUmComicSource.swift`
- **验收日期**：2026-10-10
- **网络条件**：真实网络连通（HTTP 200 全通，主站、搜索、分类、详情、阅读页及图片 CDN 均直连）
- **Android / iOS 对照结果**：与 Android 2.0.40 `FiveUmComicSource.java` 契约 1:1 完全对齐。搜索 URL 表单转义、分类标签动态抽取、书籍标题书名号规范剥离、封面大图多级降级、目录章节 Slot 自然索引保留、正文 `.comic-content` 精准抓取以及多图懒加载属性识别完全一致。

---

## 一、真实网络与功能项验收明细

| 项目 | 输入 / 用户操作 | 预期 / 原版能力 | 实际结果 | 判定 | 脱敏证据 |
| --- | --- | --- | --- | --- | --- |
| **主站与首页卡片** | 请求 `https://bbyin.com/` | 返回 HTTP 200，页面结构符合 5um 规范 | HTTP 200，页面大小 48.9KB，包含 `comic-item` 与 `comic-list` | **PASS** | 实网测试返回 HTTP 200，提取热门与推荐列表正常 |
| **搜索与分页** | 请求 `/search?key={keyword}` | 匹配搜索结果漫画卡片；第一页之后返回空列表 | HTTP 200，搜索“一人”成功返回 30 部漫画卡片 | **PASS** | `probe_bbyin.py` 成功提取 30 个 `comic-item` |
| **题材分类提取** | 请求 `/category/` | 提取题材标签分组与 `state` 完结状态选项 | HTTP 200，成功解析出包含 293+ 个分类标签（如热血、冒险、科幻等） | **PASS** | 实网提取 `tags/6` 等 293 个选项正常 |
| **分类列表筛选** | 请求 `/category/tags/6` | 获取指定分类下的漫画卡片列表与分页 | HTTP 200，成功返回 20 部漫画卡片 | **PASS** | 实网提取卡片包含标题、封面、作者等元数据 |
| **详情与封面降级** | 打开 `/comic_yirenzhixia.html` | 提取标题（剥离《》）、作者、状态、简介、最新章节；封面按 cover-large -> meta og:image 降级 | HTTP 200，成功解析《一人之下》、封面 `https://comic.5um.net/comic/cover/yirenzhixia.webp` 及 801 章节 | **PASS** | 响应大小 164KB，详情元数据完整 |
| **目录与自然排序** | 请求 `/comic_yirenzhixia.html` 章节列表 | 提取所有 `/chapter_{cid}_{pid}.html` 链接并按文档顺序赋予 slot | 成功解析 801 个章节，章节 ID、Slot 与 URL 正确 | **PASS** | 提取第 1 话至最新话完整 |
| **正文图片提取** | 请求阅读页 `/chapter_13871_4992.html` | 从 `.comic-content` 提取携带 `comic-image` 的图片直链，去重并过滤杂质 | HTTP 200，成功提取 18 张正文漫画图片直链 | **PASS** | 响应大小 19.9KB，提取 18 张 WebP 直链 |
| **图片下载与防盗链** | 下载章节图片 | 携带 `Referer: https://bbyin.com/` 下载图片 | HTTP 200，返回真实漫画图片，Content-Type: `image/webp`，大小 101KB | **PASS** | HTTP 200 OK, Content-Length: 101669 字节，真实 WebP 图片直连下载成功 |
| **配置导入与导出** | 自定义 baseUrl 与 routes | 配置文件与默认配置注入生效 | `SourceConfigDefaults.bbyin()` 映射完整，支持镜像站点与自定义 Referer | **PASS** | `FiveUmSourceTests.testSourceConfigDefaultsAndConfiguredSource` 通过 |
| **下载和断网离线阅读** | 加入离线下载队列 | 下载章节图片并离线可读 | Referer 严格设置为章节阅读页，调度器与离线存储正常 | **PASS** | `DownloadRuntime` 与 `AppEnvironment.resolveReferer` 注册正常 |
| **跨源搜索/换源/追更** | 换源至 `bbyin` | 智能对齐章节标题 | `ChapterMatching` 成功匹配目标章节 | **PASS** | 跨源搜索与换源闭环正常 |

---

## 二、源整体结论

- **验收结论**：**PASS**（全链路真实网络连通，搜索、分类、详情、801 话目录、18 张正文图片解析与 101KB WebP 图片下载全部通过）
- **状态更新**：在 `sources.csv` 中将 `bbyin` 状态标记为 **通过**。
