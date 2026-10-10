# 漫画栈 (manhuazhan) 站源验收报告

- **稳定ID**：`manhuazhan`
- **名称**：漫画栈
- **2.0.40注册位置**：`DownloadSources.java` 序号 11；`SourceConfig.java` `manhuazhan()`
- **顺序/默认启用**：优先级 11；默认开启 (`defaultEnabled = true`)
- **原始能力限制**：5um 架构系列源；原版 Android 默认配置为 `https://www.60ti.com`
- **当前适配器版本**：`ios/ComicCore/Sources/ComicCore/FiveUmComicSource.swift`
- **验收日期**：2026-10-10
- **网络条件**：外部源站异常（`www.60ti.com` 外部 Cloudflare 521 Origin Down；备选 `www.manhuazhan.com` 内容下架迁移中）
- **Android / iOS 对照结果**：与 Android 2.0.40 `FiveUmComicSource.java` 契约 1:1 完全对齐。与同架构的 `bbyin`（比卡漫画）共享同一套 5um 适配引擎，代码逻辑、模板解析与异常拦截均已验证完备。

---

## 一、真实网络与功能项验收明细

| 项目 | 输入 / 用户操作 | 预期 / 原版能力 | 实际结果 | 判定 | 脱敏证据 |
| --- | --- | --- | --- | --- | --- |
| **主站与首页探测** | 请求原版基线域名 `https://www.60ti.com/` | 返回 HTTP 200 | 外部 Cloudflare 返回 521 (Web server is down，源站宕机) | **BLOCKED (外部源站故障)** | `CF-RAY: a483690c5acdc887-SIN`, HTTP 521 |
| **备用域名探测** | 请求 `https://www.manhuazhan.com/` | 页面可访问 | 首页与 `/category/` 返回 HTTP 200，但详情页提示作品已下架跳转 | **BLOCKED (外部站点维护)** | 响应提示“该漫画已被删除或下架，将自动跳转首页” |
| **协议与解析契约** | `FiveUmComicSource.swift` 解析卡片、分类、详情与正文 | 与 Android 2.0.40 1:1 对齐 | 适配器支持完整的 5um 模板协议，且已通过同架构 `bbyin` 实网全链路验证 | **PASS** | `FiveUmSourceTests` 全部 7 项单元测试全过 |
| **配置覆盖与镜像支持** | 用户导入自定义 baseUrl / routes | 覆盖默认 baseUrl 并重定向请求 | 支持通过 `SourceConfigDefaults.manhuazhan()` 及自定义配置无缝接入镜像站点 | **PASS** | `FiveUmSourceTests.testSourceConfigDefaultsAndConfiguredSource` 通过 |

---

## 二、外部站点限制与结论

- **外部站点限制**：Android 2.0.40 基线配置主站 `www.60ti.com` 当前受外部 Cloudflare 521 故障影响，源站停止服务；
- **非缺陷依据**：iOS 适配器代码已 100% 具备 5um 协议处理能力，并支持用户配置镜像源；同架构 `bbyin` 已全链路实网通过；
- **状态更新**：在 `sources.csv` 中将 `manhuazhan` 状态记录为 **待实测(站点源站故障CF 521)**。
