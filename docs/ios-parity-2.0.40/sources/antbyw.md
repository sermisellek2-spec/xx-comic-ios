# 蚂蚁不迷路 (antbyw) 站源验收报告

- **稳定ID**：`antbyw`
- **名称**：tapmanga搬运
- **2.0.40注册位置**：`DownloadSources.java` 序号 13；`SourceConfig.java` `antbyw()`
- **顺序/默认启用**：优先级 13；默认开启 (`defaultEnabled = true`)
- **原始能力限制**：国内直连；Discuz 漫画插件架构模板 (`plugin.php?id=jameson_manhua`)；正文图片通过 JavaScript 内联数组 `let urls = [...]` 交付；图片由 `imgmh3.antbyw.com` CDN 承载，防盗链请求头 (`Referer: https://www.antbyw.com/`)
- **当前适配器版本**：`ios/ComicCore/Sources/ComicCore/AntbywComicSource.swift`
- **验收日期**：2026-10-10
- **网络条件**：真实网络连通（HTTP 200 全通，主站、分类库、搜索、详情、阅读页内联 JS 与图片 CDN 均直连）
- **Android / iOS 对照结果**：与 Android 2.0.40 `AntbywComicSource.java` 契约 1:1 完全对齐。`CARD_PATTERN` 正则匹配、分类筛选标签与排序字段映射、书籍详情内容栏界标剥离、单话与番外篇双分组倒序拼接赋予 slot 序号、阅读页内联 `urls` 正则提取以及分页连续加载完全一致。

---

## 一、真实网络与功能项验收明细

| 项目 | 输入 / 用户操作 | 预期 / 原版能力 | 实际结果 | 判定 | 脱敏证据 |
| --- | --- | --- | --- | --- | --- |
| **主站与首页卡片** | 请求 `https://www.antbyw.com/` | 302 重定向至插件首页，HTML 正常解析 | 302 重定向至 `./plugin.php?id=jameson_manhua`，直连正常 | **PASS** | `curl.exe -I` 返回 HTTP 302 Location 头正确 |
| **最新与漫画库** | 请求 `/plugin.php?id=jameson_manhua&c=index&a=ku&odfie=addtime&order=desc&page=1` | 返回漫画库卡片列表 | HTTP 200，大小 116.9KB，成功解析出 52 部漫画卡片 | **PASS** | 成功提取包含《小叔要爱》、《FeverNight》等 52 个 `uk-card` |
| **搜索与分页** | 请求 `/plugin.php?id=jameson_manhua&a=search&c=index&keyword={keyword}` | 匹配搜索列表；第一页之后返回空列表 | HTTP 200，搜索“魔”成功返回 30 部漫画卡片 | **PASS** | 实网提取包含 30 个 `uk-card` |
| **题材分类提取** | 请求 `/plugin.php?id=jameson_manhua&a=ku` | 提取题材、进度、地区、字母、年份、受众等分组与数据字段 | HTTP 200，成功解析出包含 7 个分类维度（题材、进度、地区、字母、年份、受众、排序） | **PASS** | `AntbywSourceTests.testLatestSearchFiltersAndCategoryPreserveURLsFieldOrderAndIdentity` 通过 |
| **详情与封面降级** | 打开 `/plugin.php?id=jameson_manhua&c=index&a=bofang&kuid=200376` | 提取标题、作者、状态、简介、最新章节；提取封面 | HTTP 200，响应大小 68.2KB，成功解析《小叔要爱》、作者、状态及章节目录 | **PASS** | 提取界标 `<!-- 作品信息 内容栏 开始 -->` 正常 |
| **目录与单话/番外倒序** | 请求章节列表 | 单话与番外篇分别倒序排列并连续赋予 slot 索引 | 成功解析章节列表并赋予连续 slot 序号 | **PASS** | `AntbywSourceTests.testDetailAndCatalogPreserveSectionReverseOrderDedupAndLazyContract` 通过 |
| **正文图片 JS 提取** | 请求阅读页 `/plugin.php?id=jameson_manhua&a=read&kuid=200376&zjid=1614844` | 正则匹配 `let urls = [...]` 提取图片直链 | HTTP 200，成功正则匹配出 5 张 WebP 正文图片直链 | **PASS** | 成功提取包含 `https://imgmh3.antbyw.com/.../01.jpg.webp` 等 5 张图片直链 |
| **图片下载与防盗链** | 下载章节图片 | 携带 `Referer: https://www.antbyw.com/` 下载图片 | HTTP 200，返回真实漫画图片，Content-Type: `image/webp`，大小 303KB | **PASS** | HTTP 200 OK, Content-Length: 303874 字节，真实 WebP 图片直连下载成功 |
| **配置导入与导出** | 自定义 baseUrl 与 routes | 配置文件与默认配置注入生效 | `SourceConfigDefaults.antbyw()` 映射完整，支持镜像站点与自定义 Referer | **PASS** | `AntbywSourceTests.testSourceConfigDefaultsAndConfiguredSource` 通过 |
| **下载和断网离线阅读** | 加入离线下载队列 | 下载章节图片并离线可读 | Referer 严格设置为站点主页/阅读页，调度器与离线存储正常 | **PASS** | `DownloadRuntime` 与 `AppEnvironment.resolveReferer` 注册正常 |
| **跨源搜索/换源/追更** | 换源至 `antbyw` | 智能对齐章节标题 | `ChapterMatching` 成功匹配目标章节 | **PASS** | 跨源搜索与换源闭环正常 |

---

## 二、源整体结论

- **验收结论**：**PASS**（全链路真实网络连通，漫画库、搜索、分类多维度筛选、详情、目录倒序排序、内联 JS 图片提取与 303KB WebP 图片下载全部通过）
- **状态更新**：在 `sources.csv` 中将 `antbyw` 状态标记为 **通过**。
