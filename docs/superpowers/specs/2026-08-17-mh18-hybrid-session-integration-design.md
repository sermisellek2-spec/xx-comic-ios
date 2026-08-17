# 18漫画混合会话与完整内容链路设计

## 目标

在不修改禁漫天堂实现的前提下，将 18漫画接入方式调整为与禁漫天堂一致的混合会话：首次遇到 Cloudflare 挑战时后台静默验证，验证成功后复用浏览器上下文获取业务数据。同时修正 18漫画目录和正文依赖异步接口、当前抓取时机过早的问题。

发布目标为 Android `1.0.36 (36)`，完成代码提交、推送、Release 构建、COS 主安装包更新和服务器备用安装包更新。

## 已确认现状

- `https://18mh.org/manga` 的普通 HTTP 请求返回 `403`，响应头包含 `Cf-Mitigated: challenge`。
- 浏览器通常会在约 10 秒内自动完成验证；120 秒是整个请求的超时上限，不是固定等待时间。
- 验证后的同一浏览器会话访问列表分页和搜索可在约 1 秒内返回，不需要重复验证。
- 18漫画当前创建 `CloudflareWebViewSession` 时使用 `preferHttp=false`，所以列表、搜索、详情、目录和正文请求均进行 WebView 整页导航。
- `/chapterlist/{slug}` 初始 DOM 只包含目录容器，章节列表稍后由页面脚本请求接口并注入。页面完成时立即抓取 DOM 会得到空目录。
- 目录容器提供 `data-mid` 与 `data-host`，真实接口为 `${data-host}/manga/get?mid=${data-mid}&mode=all`。
- 章节页 `#chapterContent` 提供 `data-ms`、`data-cs`、`data-ct` 与 `data-host`，真实正文接口为 `${data-host}/chapter/getcontent?m=${data-ms}&c=${data-cs}`。

## 会话与验证设计

18漫画改用 `preferHttp=true` 的现有 `CloudflareWebViewSession`，不新增网络依赖，也不复制第二套验证状态机。

请求流程如下：

1. 新会话先进行一次普通 HTTP 请求。
2. 正常业务响应直接返回；Cloudflare challenge 转入后台 WebView 验证。
3. 自动业务请求始终隐藏 WebView，只显示现有蕾姆风格轻提示“18漫画 正在验证”。用户可以继续切换页面或站源。
4. 验证完成后显示轻提示“18漫画 验证完成”，并在同一浏览器上下文内完成原请求。
5. 浏览器上下文就绪后，后续请求跳过失败的 HTTP 探测，使用同源 JavaScript `fetch`，复用 Cookie、User-Agent 和浏览器指纹。
6. 如果浏览器上下文再次收到 challenge，则仅清除该 18漫画会话的就绪状态并重新静默验证，不并发创建第二个验证流程。
7. 只有“设置 -> 站点管理 -> 18漫画 -> 验证”调用交互式请求；挑战持续超过现有 4 秒延迟时才展示网站验证页面供用户处理。

18漫画与禁漫天堂继续各持有独立 `CloudflareWebViewSession` 实例。验证 Cookie 由 Android `CookieManager` 按域保存；清除缓存时继续清除浏览器 Cookie、WebStorage 和会话就绪状态。

## 内容数据流

### 列表、搜索与分类

- 最新列表、分页、分类筛选和搜索路径保持现有 18漫画 URL 规则。
- 业务 HTML 由混合会话返回，解析器继续按 `/manga/{slug}`、封面和 `h3.cardtitle` 生成漫画摘要。
- 分类页继续解析 `/manga-genre/{slug}` 与 `/manga-tag/{slug}`，分别显示为“漫画类型”和“热门标签”。
- 空结果是合法结果；页面存在漫画区域但解析不到卡片时才报告解析失败，避免把站点错误页显示为空列表。

### 详情

- 详情继续读取 `ComicSeries` JSON-LD，并保留 `og:title`、`og:image` 和 `description` 回退。
- 漫画 ID 始终使用当前详情页 slug，目录和正文参数不得从推荐漫画、广告或页面其他卡片提取。
- 详情请求只获取详情数据，不等待目录异步加载。

### 目录

1. 请求 `/chapterlist/{slug}`。
2. 从唯一的 `#allchapters` 容器读取 `data-mid` 和 `data-host`。
3. 校验 `data-mid` 为正整数，并校验 API 主机为 `18mh.org` 或其子域。
4. 请求 `${data-host}/manga/get?mid=${data-mid}&mode=all`。
5. 只解析 `href` 指向当前漫画 slug、同时包含 `data-cs` 与 `data-ct` 的章节链接；按接口顺序去重。
6. 容器参数或章节结果为空时分别返回明确的“目录参数解析失败”或“目录解析失败”。

该设计直接调用页面声明的接口，不使用固定延时等待 DOM 注入。

### 阅读正文

1. 请求章节 URL。
2. 从唯一的 `#chapterContent` 读取 `data-ms`、`data-cs`、`data-ct` 与 `data-host`。
3. 校验两个 ID 为正整数，并校验 API 主机白名单。
4. 请求 `${data-host}/chapter/getcontent?m=${data-ms}&c=${data-cs}`。
5. 优先读取图片 `data-src`，再读取 `src`；忽略占位 data URI、相对静态资源和重复 URL。
6. `ChapterPage` 保留原章节 URL，使现有图片请求继续携带正确 Referer。

## 边界与错误处理

- 只修改 18漫画初始化、解析器及其测试；禁漫天堂文件和行为不变。
- 页面声明的 API URL 必须使用 HTTPS，主机必须是 `18mh.org` 或其子域。校验失败时不发起请求。
- Cloudflare challenge、普通 HTTP 错误、接口参数缺失和内容解析失败分别报告，不把验证失败伪装成“没有漫画”或“没有目录”。
- 自动验证失败后由当前页面的重试入口重新发起；设置页手动验证保留交互能力。
- 不新增后台服务、定时任务、持久队列或新的缓存层。

## 测试与验收

新增 JVM 回归测试覆盖：

- 18漫画使用 HTTP 优先会话配置。
- 列表、搜索分页、分类类型和分类值解析。
- JSON-LD 详情仅使用目标漫画数据。
- 目录容器参数解析、真实目录接口 URL、252 章样例及当前漫画 slug 过滤。
- 正文容器参数解析、真实正文接口 URL、懒加载图片和占位图过滤。
- 非白名单 API 主机被拒绝。
- 手动验证继续调用交互式请求，普通请求只调用静默请求。
- 现有禁漫天堂及 `CloudflareWebViewSession` 测试保持通过。

发布前执行完整 JVM 单元测试、Release 构建、APK 包名/版本/签名检查。发布后从 COS 和服务器备用地址重新下载并核对 SHA-256：

- COS 对象：`apk/xx-comic/xx-comic.bin`
- 服务器 APK：`/var/lib/xx-comic/releases/android/xx-comic.apk`
- 服务器元数据：`/var/lib/xx-comic/releases/android-release.json`
- COS 公网地址：`https://xx-1321588235.cos.ap-guangzhou.myqcloud.com/apk/xx-comic/xx-comic.bin`
- 服务器公网地址：`https://weifeng.cloud/xx-comic/releases/xx-comic.apk`
