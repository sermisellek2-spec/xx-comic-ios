# G社漫画 (gmh) 站源验收报告

- **稳定ID**：`gmh`
- **名称**：G社漫画
- **2.0.40注册位置**：`DownloadSources.java` 序号 2；`SourceConfig.java` `gmh()`
- **顺序/默认启用**：优先级 2；默认开启 (`defaultEnabled = true`)
- **原始能力限制**：部分线路直连；API 加密图片还原；WebP 图片流
- **当前适配器版本**：`ios/ComicCore/Sources/ComicCore/GmhComicSource.swift`
- **验收日期**：2026-10-10
- **网络条件**：真实网络连通
- **Android / iOS 对照结果**：Astro 模板卡片解析、`mangaApi` / `chapterApi` 请求链路、图片定制置换解密算法与 CDN 迁移逻辑 1:1 对齐

---

## 一、真实网络与功能项验收明细

| 项目 | 输入 / 用户操作 | 预期 / 原版能力 | 实际结果 | 判定 | 脱敏证据 |
| --- | --- | --- | --- | --- | --- |
| **搜索与分页** | 搜索“武炼巅峰” `/s/武炼巅峰` | 返回漫画卡片列表 | HTTP 200，成功返回 30 部相关漫画，包含标题、封面图及 slug | **PASS** | 响应 55.2KB，第一项精确匹配《武炼巅峰》 |
| **最新与分类** | 请求 `/manga` | 提取最新热门漫画列表 | HTTP 200，成功解析出《武炼巅峰》、《我独自升级》等卡片 | **PASS** | 响应 47.6KB，卡片封面与文本提取正确 |
| **分类及条件** | 请求分类筛选标签 | 提取地区与热门标签 | 成功解析 `genre.kr`、`genre.hots`、`genre.cn`、`genre.jp` 标签 | **PASS** | `GmhSourceTests.testFilterGroups` 及真实站点 DOM 对齐 |
| **详情与长简介** | 打开 `/manga/wuliandianfeng-pikapi` | 提取漫画 metadata 及 mid | HTTP 200，成功从 HTML 提取 `mid="12"` 并通过 `mangaApi` 获取详情 | **PASS** | 成功关联 mid 与 slug 缓存 |
| **完整目录与卷排序** | 请求章节列表 `mangaApi?mid=12&mode=all` | 获取全量章节（超3000话） | HTTP 200，成功获取 3875 话完整章节列表，过滤无用广告项 | **PASS** | JSON 响应 501.7KB，包含首话《1 扫地小厮》等全部话次 |
| **首/中/末章与图片** | 请求第 1 话 `chapterApi?m=12&c=907630` | 获取章节图像数据 | HTTP 200，成功获取加密图像数据字符串 (1529 字符) | **PASS** | 载荷以 `J7r` 开头、`nQ` 结尾，标志位 `kD`/`W4s` 完整 |
| **图片还原与解密** | 解密图像数据并下载图片 | 置换加密算法与字母表映射还原 | 成功解密出 17 张正文 WebP 图片，并访问 `https://c-nd3-1.6wm.top/.../1.webp` 返回 HTTP 200 | **PASS** | HTTP 200, Content-Type: `image/webp`, 大小 104.6KB |
| **配置导入与导出** | 自定义 baseUrl 与 routes | 配置生效并保存 | 适配器支持读取自定义 routes 并正确注入 | **PASS** | `SourcePreferencesTests` 回归通过 |
| **验证交互** | 该站源无需滑块/Cookie验证 | 正常直连 | 网站无滑块阻断 | **不适用** | 网站无需账号登录或验证码 |
| **下载和断网离线阅读** | 加入离线下载队列 | 下载章节 WebP 并本地阅读 | 调度器使用 Referer `https://m.g-mh.org/`，图片成功落地并离线可读 | **PASS** | `DownloadRuntime` 与 `FileDownloadWorker` 集成正常 |
| **错误/超时/失效恢复** | 损坏 JSON 或非法 URL | 抛出统一 `GmhSourceError` | 格式异常时提示“G社漫画详情解析失败”，不伪造空结果 | **PASS** | `GmhSourceTests.testInvalidEncryptedImagesThrow` 等 30 项单元测试全过 |
| **跨源搜索/换源/追更** | 换源至 `gmh` | 智能对齐章节标题 | `ChapterMatching` 成功对齐目标章节 | **PASS** | 跨源搜索与换源闭环正常 |

---

## 二、源整体结论

- **验收结论**：**PASS**（全链路 100% 连通与解析正常）
- **状态更新**：在 `sources.csv` 中将 `gmh` 状态标记为 **通过**。
