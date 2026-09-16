# 漫蛙站源

站源 ID：`manwa`；默认站点：`https://manwace.cc`。核对日期：2026-09-16。

## 接口

| 功能 | 请求 | 数据 |
| --- | --- | --- |
| 搜索 | `GET /api/search?type=mh&keyword={keyword}&page={page}&pageSize=20` | `data.list`、`data.total` |
| 分类/最新 | `POST /api/cate` 或 `/api/cate/{tagSlug}`，JSON 请求体及 `typeId` Cookie | `data.list`、`data.total` |
| 详情 | `GET /comic/{comicId}` | HTML 标题、封面、作者、状态、简介、标签、最新话 |
| 完整目录 | `GET /api/comic/{comicId}/chapters` | `data.list`，按 `sortId` 升序，保留小数番外顺序 |
| 章节标题 | `GET /api/comic/chapter/info/{chapterId}` | `data.current` |
| 图片分页 | `GET /api/comic/image/{chapterId}?page={page}&page_size=100&image_source={encodedOrigin}` | `data.images[].url`、`data.pagination` |

分类参数：

```json
{
  "page": {"page": 1, "pageSize": 36},
  "category": "comic",
  "sort": 0,
  "comic": {"status": -1, "day": 0, "tag": "", "level": 1, "areaId": 0, "typeId": 0},
  "video": {"year": 0, "typeId": 0, "typeId1": 0, "area": "", "lang": "", "status": -1, "day": 0, "level": 0},
  "novel": {"status": -1, "day": 0, "sortId": 0, "level": 0}
}
```

- 默认 `level=1`（普通）；`0` 全部、`2` VIP。分类支持范围、类型、题材、地区、状态、星期、排序组合。
- 搜索的类型值是 `mh`，传 `comic` 会得到“暂不支持”的空结果。
- 分类列表使用 `/api/cate`，题材必须追加网页对应的路径，例如冒险 `/api/cate/adventure`、恋爱 `/api/cate/romance`；仅传请求体 `comic.tag` 会被网站忽略。选回全部时移除题材路径。
- 类型必须随单次分类请求传 `Cookie: typeId={comic.typeId}`；仅传 JSON 的类型字段不生效。全部显式传 `typeId=0`，不写全局 Cookie，也不影响搜索、详情和其他站源。
- 请求保留浏览器 UA、Referer；分类 POST 使用 JSON Content-Type。
- 默认图片线路来自阅读页公开的 `IMAGE_SOURCES`：`https://tu.mwzu.cc`；可在站源配置 `routes.imageSource` 改为公开备用线路 `https://mwtuwu.cc`。接口不指定线路时曾返回 `https://tu.mhttu.cc`。

## 图片处理

封面和章节图片均可能为加密数据，扩展名 `.jpg` 不代表解码后的真实格式。

按网站公开 `base.js` 中的 `BaseUtil.getSecureImageUrl` / `chapter.js` 处理：

1. 普通 JPEG / PNG / GIF / WebP 原样读取。
2. 其他数据以前 16 字节为 IV，剩余为 AES-CBC/PKCS7 密文；Java 使用等价的 `AES/CBC/PKCS5Padding`。
3. 格式密钥来自公开前端脚本，保存在 `routes.imageKey`。无需账号密钥。
4. 使用流式解码，将正常图片字节写入原有缓存，覆盖封面、阅读预取、离线读取路径。

阅读接口逐页收集全部图片，校验页码、总数、重复 URL 和完整性。App 的条漫/日漫模式共同使用该图片列表。目录不受网页每屏 20 话的显示限制。

会员或登录限制按服务器原有权限处理；未实现账号登录。接口异常、权限不足、图片不完整均抛出明确错误，不当成正常空章节。

## 验证

- 首次接入结果（2026-09-16）：188 项 JVM 测试通过（其中漫蛙新增 17 项）；16 项 Android 联网验收通过；Debug APK 编译通过。
- 2026-09-17 筛选修复：对照网站分类页与前端请求确认题材路径和类型 Cookie；补充全部题材路径、组合筛选分页、恢复全部、真实 HTTP 请求 Cookie 隔离的回归用例。
- 修复后 208 项 JVM 测试通过，Release APK 构建通过。使用修复后的 Java 请求代码联网核对：全部 15025、本次冒险 2429、BL向 871、冒险 + BL向 81；翻页结果不同，恢复全部后列表恢复一致。本次未进行 Android 真机验收，实时数量会随站点更新变化。
- `ManwaComicSourceTest`：搜索编码及分页、普通默认值、组合分类、详情实体、完整目录、小数排序、图片多页合并、重复/缺页/权限错误、配置往返。
- `ManwaImageDecoderTest`：独立加密样本、明文图片、短读网络流、截断和错误响应、图片域名隔离。
- 可选 Android 联网验收（普通离线回归不会执行）：

```text
adb shell am instrument -w -e manwaOnly true com.xxcomic.test/com.xxcomic.ReaderInstrumentation
```

该验收检查注册/全局搜索入口、搜索、分类 POST、详情目录、38 张章节图片、Android 图片解码缓存、条漫和单页打开，以及站源开关配置恢复。请使用测试设备或模拟器。

联网样本：最速进化的史莱姆无双 `163037` / `2161449`（38 张图片）；我是大神仙 `7751`（当时为 878 话）。网站实时数据可能变化。
