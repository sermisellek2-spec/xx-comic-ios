# XX Comic 新增站源分析报告

> 探测日期：2026-07-03
> 探测方式：Node.js 探针脚本 + DoH (DNS over HTTPS) 破解 DNS 污染
> 探测关键词："柯南"

---

## 一、探测背景

为 XX Comic app 扩充漫画站源。首批 5 个候选站源中 4 个 DNS 污染，1 个域名失效。通过 DoH 解析真实 IP 后，成功连通了 3 个站源。

### DNS 污染情况

| 站源 | 系统 DNS | DoH 真实 IP | 连通性 |
|------|----------|-------------|--------|
| 拷贝漫画 `api.copymanga.site` | `157.240.2.50`（Facebook） | `172.236.114.191` | Cloudflare JS Challenge |
| 动漫之家 `v3api.dmzj.com` | `180.184.33.18`（字节跳动） | `115.190.10.83` | ECONNRESET（SNI 阻断） |
| 漫画柜 `www.manhuagui.com` | `...face:b00c...`（Facebook） | `107.189.8.124` | ETIMEDOUT（IP 被封） |
| **mangabz** `mangabz.com` | `...face:b00c...`（Facebook） | `104.21.25.145`（Cloudflare） | **200，真实 HTML** |
| 动漫狂 `www.cartoonmad.com` | `76.223.54.146` | 同 | 域名停放页面，失效 |

补充探测的国内站源：

| 站源 | 连通性 |
|------|--------|
| **漫客栈** `www.mkzhan.com` | DoH 直连 200，25915 字节 |
| **极速漫画** `www.1kkk.com` | 直接 200，53550 字节 |
| 36漫画 `www.36mh.com` | 超时 |
| 77漫画 `www.77mh.nl` | 连接拒绝 |
| 733动漫 `www.733dm.com` | 证书过期 |
| 动漫之家移动 `m.idmzj.com` | SNI 阻断 |

### 结论

- **DNS 污染**是主要障碍，通过 DoH 可解析真实 IP
- **SNI 阻断**（动漫之家）无法通过 DoH 绕过，需要代理
- **Cloudflare JS Challenge**（拷贝漫画）需要浏览器执行 JS
- **最终可用站源**：mangabz、漫客栈、极速漫画

---

## 二、可用站源详细分析

### 2.1 mangabz

| 项目 | 内容 |
|------|------|
| 域名 | `mangabz.com` |
| 风格 | 日漫为主，繁体中文 |
| 连接方式 | DoH 解析 IP，IP 直连（带 Host 头） |
| Cloudflare | 是，但无 JS Challenge |
| 置信度 | 高（全链路验证通过） |

#### 搜索

```text
URL: https://mangabz.com/search?title={keyword}
方法: GET
Referer: https://mangabz.com/
```

HTML 结构：

```html
<ul class="mh-list">
  <li>
    <div class="mh-item">
      <a href="/35666bz/">
        <img class="mh-cover" src="https://cover.mangabz.com/36/35666/20241217140248_180x240_22.jpg">
      </a>
      <div class="mh-item-detali">
        <h2 class="title">
          <a href="/35666bz/" title="柯爾特小子">柯爾特小子</a>
        </h2>
        <p class="chapter">
          <span>完結</span>
        </p>
      </div>
    </div>
  </li>
</ul>
```

解析正则：

```text
卡片: <a href="/(\d+bz)/"><img class="mh-cover" src="(https://cover\.mangabz\.com/[^"]+)">
标题: <a href="/\d+bz/" title="([^"]+)">
状态: <p class="chapter"><span>([^<]+)</span>
```

- comicId 提取：从 `href="/35666bz/"` 中取 `35666bz`
- 封面 URL：直接使用 `cover.mangabz.com` 的完整 URL

#### 详情

```text
URL: https://mangabz.com/{comicId}/    如 /249bz/
方法: GET
```

返回 127KB HTML，包含漫画标题、作者、状态、简介和章节列表（可多达 559 个章节）。无 og:meta 标签，需从 HTML 正则提取。

章节链接格式：

```text
<a href="/m500676/">名偵探柯南 第1163話</a>
```

- 章节路径：`/m{chapterId}/`
- 章节标题：链接文本

#### 章节图片

```text
URL: https://mangabz.com/m{chapterId}/    如 /m500676/
方法: GET
```

页面 JS 变量（关键）：

```javascript
var MANGABZ_CID = 500676;        // 章节ID
var MANGABZ_MID = 249;            // 漫画ID
var MANGABZ_IMAGE_COUNT = 16;    // 本话图片数量
var MANGABZ_CURL = "/m500676/";  // 章节URL
var MANGABZ_CURL_END = "/m500676-end/";
```

**图片加载方式（重要）**：

图片由 `chapter.js` 的 `chapterload2()` 函数动态加载，分页 URL 格式为：

```text
https://mangabz.com/m{chapterId}-p{页码}/
```

每页包含一张图片，但图片 URL 通过 JS 注入到 `#cp_img` 容器，HTML 源码中不含 `<img>` 标签。需用 WebView 执行 JS 才能提取图片 URL。

#### 分类

有分类页 `/manga-list/`，可按类型浏览。

#### 连接注意事项

- **DoH 必需**：系统 DNS 将 `mangabz.com` 解析到 Facebook IP
- 封面图域名 `cover.mangabz.com` 和 CSS 域名 `css.mangabz.com` 也会被污染，需同样用 DoH 解析
- 或在 app 中使用自定义 DNS 解析器
---

### 2.2 漫客栈（mkzhan）

| 项目 | 内容 |
|------|------|
| 域名 | `www.mkzhan.com` |
| 风格 | 国漫为主（知音漫客系） |
| 连接方式 | DoH 解析 IP，IP 直连 |
| 置信度 | 中（搜索结构已验证，详情/章节需进一步探测） |

#### 搜索

```text
URL: https://www.mkzhan.com/search/?keyword={keyword}
方法: GET
```

HTML 结构：

```html
<div class="common-comic-item" data-cid="217053">
  <a class="cover" href="/217053/">
    <img class="lazy" data-src="https://oss.mkzcdn.com/comic/cover/...jpg!cover-400">
  </a>
  <p class="comic__title"><a href="#">羞耻侠</a></p>
  <p class="comic-update">更至：<a class="hl" href="/217053/1068035/">第255话 完结</a></p>
  <p class="comic-count">人气：26.49万</p>
</div>
```

解析要点：
- comicId：从 `data-cid` 或 `href="/{id}/"` 提取
- 封面：`data-src` 属性（懒加载，不是 `src`）
- 标题：`.comic__title a` 文本
- 最新话：`.comic-update a` 文本
- 人气：`.comic-count` 文本

注意：搜索"柯南"无结果（偏国漫），需用国漫关键词测试。

#### 详情和章节

从搜索结果推断 URL 格式：
- 详情：`https://www.mkzhan.com/{comicId}/`
- 章节：`https://www.mkzhan.com/{comicId}/{chapterId}/`（如 `/217053/1068035/`）

#### 连接注意事项

- 系统 DNS 解析到 IPv6 超时，DoH 解析到 `120.233.179.100` 正常
- 封面图域名 `oss.mkzcdn.com` 和 `static.mkzcdn.com` 可能也需 DoH

---

### 2.3 极速漫画（1kkk）

| 项目 | 内容 |
|------|------|
| 域名 | `www.1kkk.com` |
| 风格 | 日漫+国漫 |
| 连接方式 | 直接连接（无需 DoH） |
| 置信度 | 低（搜索页已验证，详情链路超时未走通） |

#### 搜索

```text
URL: https://www.1kkk.com/search?title={keyword}
方法: GET
```

返回 53550 字节 HTML，包含 25 张图片。编码 utf-8。详情/章节链路因超时未验证，需进一步探测。

---

## 三、无法使用的站源及原因

### 拷贝漫画（CopyManga）
- DoH 解析成功，IP 直连返回 200
- 但返回 Cloudflare JS Challenge 页面（"Redirecting..."）
- 无法通过 HTTP 请求绕过，需要浏览器执行 JS
- 如 app 端集成 WebView 可考虑

### 动漫之家（DMZJ）
- DoH 解析成功，但 IP 直连 ECONNRESET
- SNI 阻断：GFW 在 TLS 握手时检测到 `v3api.dmzj.com` 就 RST
- 无法通过 DoH 绕过，需要代理或 VPN

### 漫画柜（ManHuaGui）
- DoH 解析成功，但 IP 直连 ETIMEDOUT
- IP 可能被封或 SNI 阻断

### 动漫狂（CartoonMad）
- 域名已失效，返回域名停放页面
- `window.location.href="/lander?keyword=..."` 是广告跳转
---

## 四、融入 App 的实现方案

### 4.1 新增 ComicSource 实现类

```text
app/src/main/java/com/xxcomic/source/
  MangabzComicSource.java      // mangabz 站源
  MkzhanComicSource.java        // 漫客栈站源
  OnekkkComicSource.java        // 极速漫画站源（待验证后）
```

### 4.2 SourceConfig 配置

在 `SourceConfig.java` 中新增工厂方法：

```java
public static SourceConfig mangabz(boolean enabled) {
    JSONObject routes = new JSONObject();
    JSONObject filters = new JSONObject();
    routes.put("search", "/search?title={keyword}");
    routes.put("detail", "/{comicId}");
    routes.put("chapter", "/{chapterId}");
    routes.put("chapterPage", "/m{chapterId}-p{page}");
    return new SourceConfig("mangabz", "mangabz", "mangabz.com",
        "https://mangabz.com", "https://mangabz.com/",
        "", "", "", "", enabled, routes, filters);
}
```

### 4.3 DoH 解析模块（关键）

mangabz 和漫客栈需要 DoH 解析真实 IP。推荐方案：站点级 IP 直连，不引入新依赖。

```java
// 新增 DoHDns.java
public class DoHDns {
    private static final Map<String, String> CACHE = new HashMap<>();

    public static String resolve(String hostname) {
        String cached = CACHE.get(hostname);
        if (cached != null) return cached;
        // GET https://doh.pub/dns-query?name={host}&type=A
        // Accept: application/dns-json
        // 解析 JSON 提取 A 记录
        String ip = doDohRequest(hostname);
        CACHE.put(hostname, ip);
        return ip;
    }
}
```

在 ComicSource 实现中，如果系统 DNS 解析的 IP 是已知的污染 IP 段，则用 DoH 解析的真实 IP 直连，并设置 Host 头和 SNI。判断条件：IP 以 `157.240.` 开头或 IPv6 含 `face:b00c`。

### 4.4 mangabz 图片加载（特殊处理）

mangabz 章节图片通过 JS 动态加载，HTML 源码不含图片 URL。两种方案：

**方案 A：WebView 提取（推荐）**

```java
// 1. 解析章节页 HTML，提取 MANGABZ_CID, MANGABZ_IMAGE_COUNT
// 2. 构造分页 URL: /m{cid}-p{1~count}/
// 3. 用 WebView 加载每个分页 URL，注入 JS 提取 #cp_img 内的 img src
```

**方案 B：逆向 chapter.js**

如果能在 chapter.js 中找到图片 URL 的 AJAX 接口，可直接 HTTP 请求获取图片列表，无需 WebView。需进一步逆向分析。

### 4.5 MainActivity 集成

在 `MainActivity.java` 中新增字段和初始化：

```java
private ComicSource mangabzClient;
private SourceConfig mangabzConfig = SourceConfig.mangabz(true);
private boolean mangabzEnabled = true;
```

在 `rebuildSourceClients()` 中加入：

```java
mangabzClient = new MangabzComicSource(mangabzConfig.withEnabled(mangabzEnabled));
```

在 `enabledBuiltinSources()` 中加入 `mangabzClient`。
在导出/导入的 `sourceConfigJson()` 和 `applySourceConfigJson()` 中加入 mangabz 配置。

### 4.6 优先级建议

| 优先级 | 站源 | 理由 |
|--------|------|------|
| P0 | mangabz | 日漫资源丰富，搜索/详情/章节全链路验证通过，只需解决 DoH + WebView 图片提取 |
| P1 | 漫客栈 | 国漫资源丰富，搜索结构清晰，需补充详情/章节链路探测 |
| P2 | 极速漫画 | 无需 DoH，但详情链路未验证，需进一步探测 |

---

## 五、探测脚本清单

本次探测创建的脚本：

```text
tools/probe-sources.js      初始多站源探测（系统 DNS）
tools/probe-doh.js           DoH 破解 DNS 污染探测
tools/probe-domestic.js      国内站源批量探测
tools/probe-mangabz.js       mangabz 深度链路探测
tools/probe-mangabz-images.js mangabz 章节图片加载分析
tools/probe-mangabz-page.js  mangabz 分页 URL 验证
tools/probe-mkzhan.js        漫客栈深度链路探测
tools/probe-1kkk.js          极速漫画深度链路探测
```

所有脚本通过 `node tools/probe-xxx.js` 运行，需联网权限。