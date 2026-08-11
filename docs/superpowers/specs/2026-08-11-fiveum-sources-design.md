# 漫画栈与比卡漫画站源接入设计

## 背景

新增两个内置站源：

- 漫画栈：`https://www.60ti.com/`
- 比卡漫画：`https://bbyin.com/`

两个站点当前使用相同的服务端 HTML 结构，搜索、分类、详情、章节和阅读页路由一致，封面与正文图片均由 `5um.net` 系列域名提供。

实测两个站点的搜索、详情和章节页面均返回 UTF-8 HTML。`5um.net` 图片在缺少 Referer 时返回状态码 200 的 HTML 防盗链页面，携带任一站点 Referer 时返回正确的 `image/webp`。

## 目标行为

- 两个站源作为独立内置站源显示，稳定 ID 分别为 `manhuazhan` 和 `bbyin`。
- 两个站源默认启用，参与单站搜索、默认分类列表和全站搜索。
- 支持搜索、完整动态分类、分类分页、详情、章节目录和正文阅读。
- 两个站源的数据、收藏、历史、缓存和阅读进度按不同 source ID 隔离。
- 封面和正文图片携带可通过 `5um.net` 防盗链校验的 Referer，且不把 HTML 错误页写入图片缓存。
- 不增加第三方依赖，不修改 `ComicSource` 接口，不迁移现有缓存格式。

## 方案选择

采用一个参数化共享解析器 `FiveUmComicSource`，通过不同的 `SourceConfig` 创建漫画栈与比卡漫画两个实例。

未采用两个独立解析器，因为会复制相同的网络、正则、去重和错误处理逻辑。未采用抽象基类与两个空子类，因为两个站点当前没有行为差异，额外类型只会增加样板代码。

共享解析器仍返回不同的 source ID，因此上层缓存和导航不会合并两个站点的数据。站点差异只保存在配置中：名称、ID、域名、base URL、Referer 和路由。

## 路由与数据流

### 默认列表与分类分页

默认列表使用：

- 第 1 页：`/category`
- 第 N 页：`/category/page/{page}`

分类列表从 `/category/` 的 `.filter-section` 中定位“漫画类型”，解析全部 `.filter-item`，得到标签显示名和 `/category/tags/{id}` 路径。

`categories()` 在局部 `LinkedHashMap` 中完成全部解析后，将其替换为不可变的 `volatile` 快照。这样网络线程不会向其他请求暴露构建到一半的分类映射。分类加载失败时保留上一份有效快照。

选中“全部”时使用默认分类路由。选中动态标签时，`category(region, state, page)` 将 `region` 作为标签名查询快照，并生成：

- 第 1 页：`/category/tags/{id}`
- 第 N 页：`/category/tags/{id}/page/{page}`

`MainActivity.codeForRegion()` 对这两个站源保留原始标签名，使现有 `ComicSource` 接口无需增加分类 ID 参数。

### 搜索

搜索使用 `/search?key={UTF-8 keyword}`。站点没有搜索分页，因此 `search(keyword, page)` 只在 `page == 1` 时联网；`page > 1` 立即返回空列表，让现有分页状态停止继续加载，避免重复追加第一页。

搜索卡片从 `.comic-list .comic-item` 解析详情路径、封面 URL、图片 `alt` 标题和作者。漫画 ID 使用详情路径中 `comic_` 与 `.html` 之间的 slug，并添加当前站源前缀。

### 详情与章节

详情路由为 `/comic_{comicId}.html`。解析内容包括：

- `h1` 标题；
- 页面封面；
- 作者、状态、简介和标签；
- 最新章节标题；
- `.chapter-list .chapter-item a` 章节目录。

`detail()` 返回详情基础信息，章节仍由 `chapters()` 独立加载，继续复用应用现有的缓存优先和后台刷新流程。

章节 URL 为 `/chapter_{comicNumericId}_{chapterId}.html`。目录按页面顺序生成 `chapterSlot`，并按绝对 URL 去重。

### 阅读页

阅读页只在 `.comic-content` 内解析 `.comic-image`，图片地址优先级为 `data-src`、`data-original`、`src`。图片按页面顺序去重，避免把 logo、推荐封面或其他页面资源加入正文。

`ChapterPage.chapterId` 保存章节绝对 URL；`nextPageUrl` 保持为空，因为站点一章的全部图片已在同一 HTML 中。

## 图片防盗链

网页请求使用各自站点的 User-Agent 和 Referer。正文图片加载继续把当前章节 URL 传给现有 `refererForImage(imageUrl, pageReferer)`。

`refererForImage()` 对 `manga.5um.net`、`comic.5um.net` 和 `manhua.5um.net` 增加规则：有页面 Referer 时优先使用页面 Referer；封面等没有页面 Referer 的请求使用漫画栈 Referer 作为统一兜底。实测该 Referer 对两个站点的 `5um.net` 图片都有效。

对于 `5um.net` 图片，响应必须满足 HTTP 成功且 `Content-Type` 以 `image/` 开头。若服务器返回状态码 200 的 HTML 防盗链页，则视为加载失败，不写入磁盘缓存；其他现有站源的图片响应规则保持不变。

## 应用注册

`SourceConfig` 新增两个工厂配置。`MainActivity` 增加对应的配置、启用状态和客户端字段，并接入以下既有路径：

- 站源管理卡片与开关；
- 当前站源选择和名称/ID 映射；
- 启用站源列表与全站搜索；
- 漫画 ID、详情来源解析；
- 配置导入、导出和 `source.configs` 编解码；
- `SharedPreferences` 启用状态读写；
- 图片 Referer；
- 健康检查。

活动内置站源由 9 个增加到 11 个，搜索线程池同步由 9 调整为 11，使全站搜索可以同时启动所有启用站源。

## 错误处理

- HTML 请求使用连接和读取超时，非成功状态抛出包含站点名称与 HTTP 状态的 `IOException`。
- 搜索无结果和分类末页属于正常空列表。
- 详情缺少标题、章节页缺少 `.comic-content` 正文图片时抛出明确解析错误，避免把站点改版静默显示为空白。
- 分类标签映射缺失时重新加载一次分类索引；仍找不到标签则抛出明确错误，不回退到“全部”。
- 漫画、章节和图片按稳定 URL 去重；文本通过 Android 平台 HTML 解码并折叠空白。
- `healthCheck()` 对 `/category/` 执行轻量 GET 并验证响应结构，不使用可能不受支持的 HEAD。

## 测试策略

新增精简本地 fixture，覆盖搜索卡片、分类索引、分类分页、详情、章节目录和正文图片。fixture 分别带有漫画栈和比卡漫画示例，确保共享解析器仍生成不同 source ID。

先新增 `tools/check-fiveum-source.js` 并在生产实现前确认失败。校验范围包括：

- 两个 `SourceConfig` 与客户端实例的完整注册；
- 搜索仅第 1 页联网；
- 完整动态分类映射、“全部”和标签分页 URL；
- 详情字段、章节顺序、URL 去重和正文图片顺序；
- 缺少标题或正文图片时的失败语义；
- 两个站源 ID、缓存键和详情路由互不串用；
- `5um.net` Referer 与图片内容类型保护；
- 搜索线程池数量与活动站源数量一致。

确定性验证使用本地 fixture。真实站点请求只作为发布前 smoke test，不作为持续测试门槛，避免网络波动造成假失败。

回归验证继续运行现有搜索加载、搜索缓存、站源切换、分类 generation、请求取消、下拉刷新、阅读器预加载、阅读器内存和阅读请求令牌检查，最后运行：

```powershell
.\gradlew.bat :app:testReleaseUnitTest :app:assembleRelease
```

## 验收标准

- 两个站源默认启用，并在站源管理、搜索筛选和全站搜索中显示。
- 两个站源的完整分类可在筛选抽屉中滚动选择，分类第 2 页及后续页可正常追加。
- 搜索不会重复追加第一页。
- 搜索结果可进入详情，目录顺序正确，章节正文图片完整且不是防盗链 HTML。
- 快速切换两个站源时，结果、分类、详情、封面、历史和阅读进度不串数据。
- 禁用任一站源后状态可持久化，配置导入导出保持一致。
- 新增检查、现有相关回归检查、差异格式检查和 Android Release 构建全部通过。

## 不在本次范围

- 不修改 `ComicSource` 接口或搜索筛选 UI 的整体结构。
- 不为搜索伪造分页，也不抓取其他搜索引擎补充结果。
- 不增加正式签名、自动更新、验证码绕过或代理服务。
- 不重构其他站源，不清理当前 Gradle 构建缓存或既有本地 Release 产物。
