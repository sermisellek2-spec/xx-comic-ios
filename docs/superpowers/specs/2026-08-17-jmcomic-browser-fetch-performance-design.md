# 禁漫天堂浏览器上下文请求优化设计

## 目标

禁漫天堂完成一次 Cloudflare 验证后，列表翻页、分类、详情、目录和阅读页 HTML 不再重复执行失败的普通 HTTP 探测和 WebView 整页导航。正常网络下以 5 秒内返回 HTML 数据为验收目标，站点或 VPN 本身超时不伪装成解析问题。

改动只应用于 `jmcomic`。`mh18` 继续使用现有浏览器导航路径，其他站源保持原有 HTTP 实现。

## 已确认问题

当前 `CloudflareWebViewSession.fetch()` 对禁漫请求先调用 `HttpURLConnection`。Cloudflare 若按 TLS 指纹而不是仅按 Cookie 放行，请求会返回 challenge，随后代码调用 `WebView.loadUrl()` 加载完整页面。业务页在 WebView 中能够打开时不会再次显示验证 UI，但脚本、广告和图片仍会参与页面导航，导致每次翻页可能超过 10 秒。

同一 `requestLock` 包围普通 HTTP 和 WebView 请求，分类加载期间进入详情也会排队。分类在首个列表之后单独请求 `/theme/`；详情和目录又分别请求相同的 `/album/{id}` 页面，进一步放大网络延迟。

## 方案比较

### 方案一：继续普通 HTTP 优先

改动最小，但无法解决 Cloudflare 拒绝非浏览器 TLS 指纹的情况。即使 Cookie 有效，每次请求仍可能浪费一次 HTTP challenge，再进入完整页面导航。

### 方案二：始终使用 WebView 整页导航

验证兼容性高，但每页都会加载页面资源，正是当前 10 秒以上等待的主要来源。

### 方案三：验证后使用 WebView 同源 `fetch`（采用）

第一次 challenge 仍由 WebView 导航完成。业务页成功打开后保留这个 WebView，并在其同源 JavaScript 环境中执行 `fetch(url, { credentials: "include" })`。该请求使用浏览器网络栈和验证 Cookie，只下载 HTML，不导航页面，也不加载页面图片、广告和业务脚本。

## 会话状态与数据流

`CloudflareWebViewSession` 保留现有公开接口，增加进程内 `browserContextReady` 状态：

1. `preferHttp == false`：保持现有 WebView 导航行为。
2. 禁漫新会话且浏览器上下文未就绪：普通 HTTP 探测一次。
3. HTTP 返回正常业务 HTML：直接返回，继续使用轻量 HTTP。
4. HTTP 返回明确 challenge：WebView 导航并完成验证或打开业务页；成功后设置 `browserContextReady = true`。
5. 后续禁漫请求：跳过普通 HTTP，使用当前 WebView 内的同源 JavaScript `fetch`。
6. JavaScript `fetch` 返回正常业务 HTML：直接交给原解析器。
7. JavaScript `fetch` 返回 challenge：清除就绪状态并执行一次 WebView 导航验证；成功后恢复上下文。
8. 普通 4xx/5xx、JavaScript 网络错误和解析错误：直接报告，不循环验证。

一次会话仍只允许一个 WebView 请求，避免多个 challenge 同时打开。普通 HTTP 成功路径不改变现有行为。

## 浏览器响应桥接

同源请求通过现有 `XXComicBridge` 返回以下字段：

- `url`：最终响应 URL，用现有 host/path 规则校验。
- `status`：HTTP 状态码。
- `mitigated`：`cf-mitigated` 响应头。
- `body`：完整 HTML。
- `error`：JavaScript fetch 失败信息，只转换为通用 App 错误，不写入敏感日志。

桥接结果复用现有 challenge 识别和 `HttpAction` 判定，不新增第二套 Cloudflare 规则。

## 数据复用

`JmComicSource` 增加两个小型进程内缓存：

- 分类缓存：首次成功解析 `/theme/` 后保存结果，当前进程后续打开筛选不重复请求。失败和空结果不缓存。
- 详情页缓存：只保留最近一个漫画的 `/album/{id}` HTML。`detail()` 和紧随其后的 `chapters()` 共用该响应，切换到其他漫画时替换，避免无边界内存增长。

App 现有结构不会在同一进程内无限刷新同一详情；最近一页缓存与当前刷新语义一致。清理 App 缓存时浏览器上下文失效，后续重新验证。

## 阅读图片边界

`/photo/{id}` HTML 使用新的浏览器上下文请求，因此图片地址列表会提速。实际漫画图片仍由现有 CDN 下载、磁盘缓存、Bitmap 解码和切片还原链路处理，不放入 WebView fetch，也不改变图片顺序和还原算法。

## 测试与验收

自动化测试覆盖：

- 浏览器上下文就绪后选择 `BROWSER_CONTEXT`，不再选择普通 HTTP。
- 新禁漫画会话仍先探测 HTTP；`mh18` 仍使用浏览器导航。
- 浏览器上下文 challenge 只触发一次导航回退。
- 分类连续读取只请求一次 `/theme/`。
- 详情后读取目录只请求一次 `/album/{id}`。
- 普通 4xx/5xx 不误触发验证。

真机验收：验证一次后连续翻页三次，每次应不再出现完整网页导航，目标 5 秒内出现新列表；随后依次打开分类、详情、目录和阅读页，Cookie 有效期间不重复验证。

