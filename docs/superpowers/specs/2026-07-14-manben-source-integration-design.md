# 漫本站源完整接入设计

> 日期：2026-07-14  
> 目标站点：https://www.manben.com  
> 范围：接入设计与实施说明，不包含本次代码修改。  
> 推荐实现：新增独立 `ManbenComicSource`，沿用现有 `ComicSource`、`SourceConfig` 和原生 `HttpURLConnection`。

## 1. 目标

将“漫本”作为内置站源接入 XX Comic，支持：

- 分类筛选和滚动分页。
- 关键词搜索和搜索分页。
- 详情页元数据与封面。
- 点击目录时按需加载完整章节。
- 阅读页解析全部漫画图片。
- 全站并发搜索的独立站源 Tab。
- 站源启用、禁用、健康检查。
- 完整配置随站源 JSON 导入和导出。
- 网络失败、章节屏蔽、空目录和空图片均能退出 loading 并写入错误日志。

本次不引入 WebView、不修改 `ComicSource` 公共接口、不抽取 DM5/漫本共享基类，也不增加第三方依赖。

## 2. 已验证结论

以下链路已于 2026-07-14 实际请求验证：

| 能力 | 结论 |
|---|---|
| 列表页 | `GET /mh-list/` 返回服务端 HTML |
| 分类分页 | `POST /mh-list/pagerdata.ashx` 返回 JSON 数组 |
| 搜索 | `GET /search?page={page}&title={keyword}&language=1` 返回服务端 HTML |
| 详情 | `GET /mh-{slug}/` 返回封面、作者、状态、简介和章节列表 |
| 章节页 | `GET /m{chapterId}/` 返回章节元数据和页数组占位 |
| 图片数据 | `GET /imageshow.ashx?...` 返回 `var chapterimage={...};` |
| 图片 CDN | `ImagePix + Images[n]` 拼接后返回 `200 image/jpeg` |
| WebView | 不需要，所有必要数据都可由普通 HTTP 请求获得 |

站点与 DM5 使用相同的 `cdndm5.com` CDN 体系，但本项目当前没有可直接复用的 DM5 适配器。为避免提前抽象，本次保持独立实现。

## 3. 站源身份

| 字段 | 值 |
|---|---|
| `id` | `manben` |
| `name` | `漫本` |
| `domain` | `www.manben.com` |
| `baseUrl` | `https://www.manben.com` |
| `referer` | `https://www.manben.com/` |
| 默认状态 | 启用，与当前内置站源行为一致 |

漫画 ID 使用详情路径中 `/mh-` 后的 slug，例如：

```text
详情 URL：https://www.manben.com/mh-yaoshenji/
comicId：yaoshenji
```

章节 ID 使用路径中的纯数字，例如：

```text
章节 URL：https://www.manben.com/m615293/
chapterId：615293
```

## 4. 接口清单

### 4.1 分类首页

```http
GET https://www.manben.com/mh-list/
```

首页 HTML 可用于健康检查和解析静态分类定义，但列表数据建议统一走分类 JSON 接口，避免第一页和后续页维护两套卡片解析器。

### 4.2 分类与分页

```http
POST https://www.manben.com/mh-list/pagerdata.ashx
Content-Type: application/x-www-form-urlencoded; charset=UTF-8
```

请求参数：

| 参数 | 含义 | 默认值 |
|---|---|---:|
| `t` | 请求类型 | `2` |
| `pageindex` | 页码，从 1 开始 | `1` |
| `sc` | 固定参数 | `1` |
| `tsort` | 排序：更新时间 `2`，热门 `4` | `2` |
| `tagid` | 题材 ID | `0` |
| `tst` | 状态：全部 `0`、连载 `1`、完结 `2` | `0` |
| `tarea` | 地区 ID | `0` |
| `tgroup` | 受众 ID | `0` |
| `tnm` | 首字母 | 空字符串 |

响应是 JSON 数组，已验证页面脚本使用以下字段：

```json
{
  "Url": "/mh-yaoshenji/",
  "BigPic": "https://mhfm8tel.cdndm5.com/...jpg",
  "Title": "妖神记",
  "LastPartUrl": "m1801111",
  "LastPartShowName": "第522回",
  "Author": ["踏雪动漫"],
  "AuthorUrl": ["/search?..."],
  "TagList": ["热血", "奇幻"],
  "Content": "简介"
}
```

解析规则：

- `comicId`：从 `Url` 去掉开头 `/mh-` 和结尾 `/`。
- `title`：`Title`。
- `coverUrl`：`BigPic`。
- `subtitle`：优先第一个作者，作者为空时使用 `LastPartShowName`。
- `tags`：按顺序读取 `TagList` 并去重。
- 同一页按 `comicId` 使用 `LinkedHashSet` 去重。

### 4.3 搜索

```http
GET https://www.manben.com/search?page={page}&title={urlEncodedKeyword}&language=1
```

搜索结果在 `.mainSearch .bookList_2 .item` 中，每项包含：

- 详情链接 `/mh-{slug}/`。
- 封面 `.cover`。
- 标题 `.title`。
- 简介 `.tip`。

搜索页未直接提供可靠作者字段，因此 `ComicSummary.subtitle` 使用简介短文本，不从错误节点猜作者。作者在详情页再解析。

分页由 `.pager` 提供，格式为：

```text
/search?page=2&title={keyword}&language=1
```

当目标页没有 `.bookList_2 .item` 时返回空列表，不能重复第一页。

### 4.4 详情

```http
GET https://www.manben.com/mh-{comicId}/
```

详情页解析：

| 字段 | 首选来源 | 回退来源 |
|---|---|---|
| 标题 | 详情主标题 | `<title>` 去掉站点后缀 |
| 封面 | 详情主封面图片 | 分享图片或 Open Graph 图片 |
| 作者 | 作者信息区链接文本 | 空字符串 |
| 状态 | 详情信息区的连载状态 | 空字符串 |
| 简介 | 详情简介容器 | `meta[name=Description]` |
| 最新章节 | 详情页最新章节入口 | 章节列表第一个有效项 |
| 标签 | 详情标签区 | 空列表 |

`detail()` 只解析元数据，不把完整章节列表塞进返回对象。详情页进入后应尽快完成，用户点击“目录”时再调用 `chapters()`。

### 4.5 目录

目录位于：

```html
<div class="chapterList" id="chapterList">
  <div id="chapterlistload">
    <div class="list">正式章节...</div>
    <div class="list">其他分组...</div>
    <div class="list">番外...</div>
  </div>
</div>
```

章节锚点格式：

```html
<a href="/m615293/" target="_blank" class="ib">第174回 回归（下）</a>
```

解析规则：

1. 只在 `#chapterlistload` 内解析，避免把推荐漫画、最新评论和导航链接当作章节。
2. 接受 `/m数字/` 格式链接。
3. 同时读取可见和 `style="display:none"` 的章节；“查看更多”只是前端显示控制，隐藏节点仍是完整目录的一部分。
4. 保留正式章节与番外分组，分别写入 `sectionSlot`。
5. 按 `chapterId` 去重，保留第一次出现的标题和 URL。
6. 每个分组按站点 DOM 顺序读取后，正规章节转换成从旧到新的阅读顺序。
7. `chapterSlot` 使用转换后的稳定序号，阅读页上一章/下一章直接依赖该顺序。

站点目录数量可能与标题里显示的最新回数不同。部分新章节会因数据不完整而被站点屏蔽。适配器只返回详情 HTML 中实际提供的章节，不制造缺失章节。

### 4.6 章节页面

```http
GET https://www.manben.com/m{chapterId}/
```

正常章节页包含：

```javascript
CHAPTER_ID = 615293;
COMIC_MID = 33771;
```

以及若干 `.pageItem` 图片占位。真实图片不在 HTML 中，由图片数据接口按阅读页组加载。

被屏蔽章节会返回 HTTP 200，但正文包含“章节数据缺少”“屏蔽处理”等提示，并且没有正常阅读脚本。`chapter()` 必须先识别这种页面，抛出带上下文的 `IOException`，例如：

```text
漫本章节已被站点屏蔽：第522回
```

不能把 HTTP 200 等同于章节可读，也不能进入无限 loading。

### 4.7 图片数据接口

```http
GET https://www.manben.com/imageshow.ashx
    ?cid={chapterId}
    &page={spreadPage}
    &showtype=1
    &ispre=0
Referer: https://www.manben.com/m{chapterId}/
```

已验证响应：

```javascript
var chapterimage={
  "PageIndex":2,
  "Images":[
    "/1_6422.jpg?cid=615293&key=...",
    "/2_1934.jpg?cid=615293&key=..."
  ],
  "ImageSize":["800/1133","800/1133"],
  "ImagePix":"https://manhua1032-223-111-182-10.cdndm5.com/34/33771/615292",
  "IsEnd":false,
  "PreloadPix":null,
  "PreloadImages":["/3_9251.jpg?...", "/4_2556.jpg?..."]
};
```

禁止执行返回 JavaScript。安全解析步骤：

1. 验证文本包含 `chapterimage`。
2. 取第一个 `{` 到与其匹配的最后一个 `}`。
3. 使用 `JSONObject` 解析。
4. 读取 `ImagePix`、`Images`、`IsEnd`。
5. 每个图片 URL 使用 `ImagePix + Images[i]` 拼接。
6. 使用 `LinkedHashSet` 保持顺序并去重。
7. `PreloadImages` 只是下一组预加载提示，不加入最终列表，避免后续请求重复。

`page` 表示阅读页组而不是单张图片序号。算法从 `page=1` 开始，每次加 1，直到 `IsEnd=true`：

```text
spreadPage = 1
while spreadPage <= 1000:
    response = fetchImageData(chapterId, spreadPage)
    append response.Images
    if response.IsEnd: break
    spreadPage++
```

保护规则：

- 最多请求 1000 组，防止异常接口造成死循环。
- 连续两组没有新增图片时立即失败。
- `IsEnd=true` 且图片为空时视为解析失败。
- 图片 URL 必须是 `http/https`，并限制在返回的 `ImagePix` 域名下。
- 不持久化带签名的远程 URL；继续使用现有图片字节磁盘缓存。

### 4.8 图片请求

CDN 图片请求必须携带：

```http
User-Agent: 与页面请求一致的桌面浏览器 UA
Referer: https://www.manben.com/m{chapterId}/
Accept: image/avif,image/webp,image/apng,image/*,*/*;q=0.8
```

已验证拼接后的 URL 返回 `200`、`Content-Type: image/jpeg`，且支持 Range。App 不需要 WebView Cookie。

## 5. 分类模型

当前 `ComicSource.category(String region, String state, int page)` 只有一个通用分类维度和一个状态维度，无法直接表达站点的题材、地区、受众、字母四组筛选。

最小实现采用扁平分类，不修改公共接口：

```text
全部
题材·搞笑
题材·奇幻
题材·热血
题材·悬疑
题材·格斗
题材·科幻
题材·励志
题材·校园
题材·爱情
题材·日常
题材·战争
题材·其他
受众·少年向
受众·少女向
受众·青年向
地区·港台
地区·日韩
地区·大陆
地区·欧美
```

状态继续使用现有三个选项：

```text
全部 / 连载中 / 已完结
```

适配器把分类配置值拆成 `参数:值`：

```json
{
  "category.全部": "",
  "category.题材·搞笑": "tagid:37",
  "category.题材·奇幻": "tagid:14",
  "category.题材·热血": "tagid:31",
  "category.题材·悬疑": "tagid:17",
  "category.题材·格斗": "tagid:28",
  "category.题材·科幻": "tagid:25",
  "category.题材·励志": "tagid:10",
  "category.题材·校园": "tagid:1",
  "category.题材·爱情": "tagid:26",
  "category.题材·日常": "tagid:7",
  "category.题材·战争": "tagid:12",
  "category.题材·其他": "tagid:3",
  "category.受众·少年向": "tgroup:1",
  "category.受众·少女向": "tgroup:2",
  "category.受众·青年向": "tgroup:3",
  "category.地区·港台": "tarea:35",
  "category.地区·日韩": "tarea:36",
  "category.地区·大陆": "tarea:37",
  "category.地区·欧美": "tarea:52",
  "state.all": "0",
  "state.serial": "1",
  "state.pub": "2"
}
```

首字母和热门排序暂不放入 App 分类 UI，因为现有页面没有第三个筛选维度。接口和默认路由仍写入 JSON，后续可在不改解析器的情况下扩展 UI。

## 6. SourceConfig 设计

在 `SourceConfig` 增加：

```java
public static SourceConfig manben(boolean enabled)
```

建议导出配置：

```json
{
  "id": "manben",
  "name": "漫本",
  "domain": "www.manben.com",
  "baseUrl": "https://www.manben.com",
  "referer": "https://www.manben.com/",
  "enabled": true,
  "routes": {
    "latest": "/mh-list/pagerdata.ashx",
    "categoryIndex": "/mh-list/",
    "category": "/mh-list/pagerdata.ashx",
    "search": "/search?page={page}&title={keyword}&language=1",
    "detail": "/mh-{comicId}/",
    "chapter": "/m{chapterId}/",
    "chapterImages": "/imageshow.ashx?cid={chapterId}&page={page}&showtype=1&ispre=0"
  },
  "filters": {
    "sort.latest": "2",
    "sort.popular": "4",
    "state.all": "0",
    "state.serial": "1",
    "state.pub": "2",
    "category.全部": "",
    "category.题材·搞笑": "tagid:37",
    "category.题材·奇幻": "tagid:14",
    "category.题材·热血": "tagid:31",
    "category.题材·悬疑": "tagid:17",
    "category.题材·格斗": "tagid:28",
    "category.题材·科幻": "tagid:25",
    "category.题材·励志": "tagid:10",
    "category.题材·校园": "tagid:1",
    "category.题材·爱情": "tagid:26",
    "category.题材·日常": "tagid:7",
    "category.题材·战争": "tagid:12",
    "category.题材·其他": "tagid:3",
    "category.受众·少年向": "tgroup:1",
    "category.受众·少女向": "tgroup:2",
    "category.受众·青年向": "tgroup:3",
    "category.地区·港台": "tarea:35",
    "category.地区·日韩": "tarea:36",
    "category.地区·大陆": "tarea:37",
    "category.地区·欧美": "tarea:52"
  }
}
```

约束：

- URL、域名、Referer、路由和筛选值必须来自 `SourceConfig`，确保导入 JSON 后行为一致。
- POST 方法、响应解析规则和图片循环算法属于代码协议，不塞入 JSON。
- `SourceConfig.fromJson()` 继续把导入值覆盖到默认配置，缺失字段回退到内置值。

## 7. ManbenComicSource 职责

新增文件：

```text
app/src/main/java/com/xxcomic/source/ManbenComicSource.java
```

方法职责：

| 方法 | 实现 |
|---|---|
| `id()` | 返回 `manben` |
| `name()` | 返回 `config.name` |
| `domain()` | 返回 `config.domain` |
| `latest(page)` | POST 分类接口，固定最新排序和全部筛选 |
| `search(keyword,page)` | GET 搜索 HTML并解析卡片 |
| `categories()` | 从 `config.filters` 返回扁平分类显示值 |
| `category(category,state,page)` | POST 分类接口并设置对应参数 |
| `detail(comicId)` | GET 详情，只解析元数据 |
| `chapters(comicId)` | GET 详情，限定目录容器解析章节 |
| `chapter(chapterUrl)` | 校验章节页，再循环图片数据接口 |
| `healthCheck()` | GET `/mh-list/`，验证 2xx 和关键 DOM |

建议私有方法保持最少：

- `fetchGet(String url, String referer)`
- `fetchPost(String url, Map<String,String> body, String referer)`
- `parseCategoryJson(String json)`
- `parseSearchCards(String html)`
- `parseChapterImageData(String script)`
- `absolute(String path)`
- `clean(String html)`

不为单次使用的逻辑创建额外抽象。

## 8. 网络策略

页面请求：

- 连接超时 10 秒。
- 读取超时 20 秒。
- 固定桌面浏览器 User-Agent。
- 设置 `Referer: config.referer`。
- 支持 gzip。
- 仅跟随最多 5 次重定向。

目录和图片数据：

- 连接超时 10 秒。
- 读取超时 30 秒。
- 图片数据 Referer 必须是当前章节 URL。
- 每个响应读取完成后关闭流并断开连接。

站点会设置 `DM5_MACHINEKEY`、`ILUSER_MACHINEKEY` 等 Cookie，但已验证分类、搜索、详情、章节、图片数据和图片 CDN 均可在普通匿名请求中完成。本次不新增全局 Cookie 管理器。若真机后续出现依赖 Cookie 的个别章节，再单独增加该站源的轻量 CookieJar，不提前引入 WebView。

## 9. MainActivity 接入点

实施时只按现有显式注册方式增加漫本，不重构 `MainActivity`：

1. 增加 `manbenConfig`、`manbenClient`、`manbenEnabled` 字段。
2. 在客户端重建方法中使用 `new ManbenComicSource(manbenConfig)`。
3. 在站源管理页增加漫本站源卡片，并继续保持已开启站源排在前面。
4. 加入当前站源查找、站源名称映射和 ID 映射。
5. 加入已启用站源列表，使普通搜索和全站并发搜索都能使用。
6. 加入站源下拉框和分类加载分支。
7. 加入 SharedPreferences 的启用状态恢复和保存。
8. 加入站源 JSON 导出与导入分支。
9. 图片请求的 Referer 选择中，为 `manben` 返回当前章节 URL。
10. 清除缓存、收藏和阅读历史逻辑不增加站源特例。

当前全站搜索线程池为固定 9 线程，现有内置站源也是 9 个。漫本加入后，将 `searchIo` 调整为 10 线程，使一次全站搜索仍可为每个开启站源分配任务。不要改成无界线程池。

## 10. 错误处理

所有失败必须结束 loading，并支持正常返回上一页。

| 场景 | 行为 |
|---|---|
| 分类 HTTP 非 2xx | 保留已有列表，Toast“漫本分类加载失败”，写日志 |
| 分类 JSON 非数组 | 抛出带响应片段的 `IOException` |
| 搜索无结果 | 返回空列表，显示正常空状态 |
| 详情缺少标题 | 以 comicId 回退，其他字段允许为空 |
| 目录为空 | 抛出“漫本目录为空：{comicId}” |
| 章节被屏蔽 | 显示站点屏蔽提示，不请求图片接口 |
| 图片接口格式变化 | 抛出“漫本图片数据格式异常”，记录前 500 字符 |
| 图片循环无新增 | 中止并报错，不能继续请求 |
| CDN 图片 403 | 重新请求一次图片数据获取新签名；仍失败则记录日志 |
| 请求取消 | `InterruptedIOException` 不记为错误，只结束当前任务 |

日志不得记录完整 Cookie、签名 key 或用户隐私。图片 URL 可仅记录域名、章节 ID 和 HTTP 状态。

## 11. 缓存策略

- 封面继续使用现有图片磁盘缓存。
- 详情和目录不新增长期缓存结构，避免扩大改动。
- 图片接口返回的签名 URL不写入收藏数据。
- 成功加载的漫画图片继续落入现有 1000MB 磁盘缓存，并按最旧文件淘汰。
- 清理缓存只清图片和临时文件，不清收藏、阅读历史和站源配置。

## 12. 测试方案

### 12.1 固定样本

实施前保存脱敏后的最小样本：

```text
tools/fixtures/manben-category.json
tools/fixtures/manben-search.html
tools/fixtures/manben-detail.html
tools/fixtures/manben-chapter.html
tools/fixtures/manben-chapter-blocked.html
tools/fixtures/manben-imageshow.txt
```

样本只保留解析所需结构，不提交 Cookie 和完整签名。

### 12.2 解析检查

增加 `tools/check-manben-source.js`，至少验证：

1. 分类 JSON 能解析 comicId、标题、封面、作者、标签。
2. 搜索页能解析“妖神记”且分页 2 不重复第一页。
3. 详情能解析标题、封面、作者、状态和简介。
4. 目录只读取 `#chapterlistload`，隐藏章节也被包含。
5. 推荐漫画和评论链接不会进入目录。
6. 正式章节顺序从旧到新，番外分组稳定。
7. 图片数据能安全提取 JSONObject，不执行 JavaScript。
8. `ImagePix + Images` 顺序正确且无重复。
9. 屏蔽章节能被识别。
10. 空结果、损坏 JSON、连续空图片均明确失败。

### 12.3 在线探测

增加 `tools/probe-manben.js`，串行执行并在请求间隔 500ms：

1. 分类第一页。
2. 搜索“妖神记”。
3. 打开一个正常详情。
4. 读取目录中的一个正常章节。
5. 请求第一组图片数据。
6. 对第一张图片执行 HEAD，确认 2xx 和 `image/*`。

探测失败不应修改应用数据。

### 12.4 Android 构建

```powershell
$env:JAVA_HOME='F:\softForCode\Java\jdk-17'
$env:Path="$env:JAVA_HOME\bin;$env:Path"
.\gradlew.bat assembleDebug --no-daemon
```

成功标准：

- Java 编译通过。
- APK 生成于 `app/build/outputs/apk/debug/app-debug.apk`。
- 没有新增 lint 级别的资源或 Manifest 错误。

### 12.5 真机验收

分类页：

- 漫本可选择并正常加载。
- 分类按钮一排三个且可上下滚动。
- 切换分类重置到第一页。
- 下拉分页保持当前滚动位置，列表不闪回顶部。
- 奇数结果最后一项保持单列宽度。

搜索：

- 键盘搜索后才发请求。
- 搜索“妖神记”显示正确标题和封面。
- 搜索下一页不回顶部。
- 全站搜索中漫本结果进入独立 Tab，不阻塞其他站源。

详情和目录：

- 详情先显示 loading，再正常展示封面和简介。
- 详情阶段不提前解析图片。
- 点击目录后加载，返回键可随时关闭 loading/抽屉。
- 正序、倒序均正确。

阅读：

- 正常章节图片全部显示。
- 上一章、下一章与目录顺序一致。
- 阅读进度能精确恢复到图片位置。
- 被屏蔽章节显示明确错误并可返回。
- 图片失败不产生 `thread interrupted` 噪声日志。

导入导出：

- 导出 JSON 包含漫本全部 routes、filters 和 enabled。
- 在另一台设备导入后无需修改代码即可使用相同域名和路由。
- 修改 JSON 中 `baseUrl`、`referer` 或接口路径后，适配器使用导入值。

## 13. 已知风险

### 13.1 站点数据屏蔽

部分漫画的最新章节入口存在，但章节正文由站点主动屏蔽。适配器无法恢复站点未提供的数据，只能准确提示并保持可返回。

### 13.2 TLS 差异

Windows curl 探测曾出现证书吊销列表离线错误，使用 `--ssl-no-revoke` 后请求正常。这是 Windows Schannel 的吊销联网检查问题，不代表 Android 必然失败。必须以 Android 真机连接和图片加载结果为准，不能在 App 中关闭证书校验。

### 13.3 接口兼容性

`pagerdata.ashx` 和 `imageshow.ashx` 属于站点内部接口，可能改字段或参数。所有路径都写入 JSON，解析异常写日志；不要静默返回旧数据。

### 13.4 图片签名

CDN 图片包含 `cid` 和 `key`。签名可能失效，因此每次打开章节重新请求图片数据接口，磁盘只缓存图片字节，不长期保存签名 URL。

## 14. 完成定义

只有同时满足以下条件，漫本站源才算接入完成：

- 分类、搜索、详情、目录、图片五类固定样本检查通过。
- 在线探测能取得至少一张有效漫画图片。
- Android Debug APK 构建成功。
- 真机分类和搜索分页不跳顶、不闪屏。
- 正常章节可完整阅读，屏蔽章节能退出 loading。
- 全站搜索独立 Tab 正常。
- JSON 导出和重新导入后行为一致。
- 收藏、阅读历史、缓存清理和其他九个站源无回归。

## 15. 实施顺序

1. 固化最小测试样本和失败样本。
2. 编写解析检查，先让检查失败。
3. 实现 `ManbenComicSource` 的分类和搜索。
4. 实现详情与目录。
5. 实现图片数据循环和屏蔽章节识别。
6. 增加 `SourceConfig.manben()`。
7. 完成 `MainActivity` 显式注册、筛选、导入导出和 Referer。
8. 运行固定样本检查、在线探测和 Android 构建。
9. 真机完成全部验收项后再打包发布。
