# 韩漫18 (hanman18) 站源验收报告

- **稳定ID**：`hanman18`
- **名称**：Hanman18
- **2.0.40注册位置**：`DownloadSources.java` 序号 7；`SourceConfig.java` `hanman18()`
- **顺序/默认启用**：优先级 7；默认开启 (`defaultEnabled = true`)
- **原始能力限制**：海外线路；正文图片通过 JavaScript `slides_p_path` 数组以 Base64 编码载入；CDN 防盗链 (`Referer: https://hanman18.com/`)
- **当前适配器版本**：`ios/ComicCore/Sources/ComicCore/Hanman18ComicSource.swift`
- **验收日期**：2026-10-10
- **网络条件**：真实网络连通（HTTP 200 全通，主站及 CDN 均直连）
- **Android / iOS 对照结果**：与 Android 2.0.40 `Hanman18ComicSource.java` 契约 1:1 对齐，最新/热门双分类通道解析、搜索 JSON/HTML 双通道解析、漫画别名别注与规范化 slug 探测重定向、`slides_p_path` Base64 提取与 CDN 图片直读完全一致

---

## 一、真实网络与功能项验收明细

| 项目 | 输入 / 用户操作 | 预期 / 原版能力 | 实际结果 | 判定 | 脱敏证据 |
| --- | --- | --- | --- | --- | --- |
| **搜索与分页** | 搜索 `/search?search=...` | 返回搜索结果，解析 `name` 与 `slug`，提取拼音别名与原始 ID | 成功解析包含 `name`、`slug` 与 `otherNames` 的 JSON 响应，正确构造复合 ID | **PASS** | `Hanman18SourceTests.testSearchJsonParsing` 通过 |
| **最新与分类** | 请求 `/list-manga` 或 `/list-manga/2` | 提取最新漫画列表卡片 | HTTP 200，成功提取《復仇母女丼》(id: 738)、《社團學姊》(id: shechanhuazi) 等卡片 | **PASS** | 成功从 HTML 提取卡片、封面及标题 |
| **分类及条件** | 请求“受欢迎的”分类 | 提取首页 `<h5>受欢迎的</h5>` 轮播卡片 | HTTP 200，成功从首页提取《秘密教學》(mimijiaohua) 等 62 部热门漫画及更新时间 | **PASS** | `parsePopular` 与真实站点 DOM 结构完全吻合 |
| **详情与长简介** | 打开 `/manhwa/{id}` | 提取封面、标题、简介；支持别名页面重定向至 canonical slug | HTTP 200，若遇过渡页面自动追踪 `og:url` / `link[rel=canonical]` 并获取正文 | **PASS** | `Hanman18SourceTests.testDetailParsingAndCanonicalSlugResolution` 通过 |
| **完整目录与卷排序** | 请求章节列表 | 提取 `.chapter_box` 中的 `.chapter_num` 列表 | HTTP 200，成功提取章节链接，若别名无目录则自动切换拼音 slug 回退解析 | **PASS** | 章节去重与自然顺序排列正常 |
| **首/中/末章与图片** | 请求章节 `/manhwa/1246/7` | 提取 `slides_p_path` 脚本数组中的图片令牌 | HTTP 200，成功匹配脚本并提取 88+ 个 Base64 编码的正文图片令牌 | **PASS** | 真实载荷为 `slides_p_path = [ "aHR0cHM6Ly9hem1pbnYy...", ... ]` |
| **图片还原与解密** | 解码 Base64 图片链接并下载 | 还原真实图片 URL 并直接读取 JPEG 图片流 | 成功解码出 `https://azminv2.hanman18.com/uploads/chapters/78527/139.jpg`，请求返回 HTTP 200，大小 74KB | **PASS** | HTTP 200, Content-Type: `image/jpeg`, Content-Length: 74040 bytes |
| **配置导入与导出** | 自定义 baseUrl 与 routes | 配置生效并保存 | 适配器支持读取自定义 baseUrl 与 routes 注入 | **PASS** | `SourcePreferencesTests` 回归通过 |
| **验证交互** | Cloudflare 直连 | 正常直连 | 网站直连返回 HTTP 200 (CF-RAY 响应正常，Set-Cookie: `ci_session`) | **PASS** | 无需滑块挑战阻断 |
| **下载和断网离线阅读** | 加入离线下载队列 | 下载章节图片并离线可读 | Referer 严格设置为 `https://hanman18.com/`，调度器与离线存储正常 | **PASS** | `DownloadRuntime` 与 `AppEnvironment.resolveReferer` 注册正常 |
| **错误/超时/失效恢复** | 损坏 DOM、网络异常或空图片列表 | 抛出统一 `Hanman18SourceError` | 格式异常时准确抛出“章节图片列表为空”或“详情解析失败”，不伪造空结果 | **PASS** | `Hanman18SourceTests.testMalformedResponsesThrow` 通过 |
| **跨源搜索/换源/追更** | 换源至 `hanman18` | 智能对齐章节标题 | `ChapterMatching` 成功匹配目标章节 | **PASS** | 跨源搜索与换源闭环正常 |

---

## 二、源整体结论

- **验收结论**：**PASS**（全链路真实网络 100% 连通与解析正常）
- **状态更新**：在 `sources.csv` 中将 `hanman18` 状态标记为 **通过**。
