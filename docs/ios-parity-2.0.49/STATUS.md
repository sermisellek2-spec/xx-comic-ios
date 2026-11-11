# iOS 2.0.49（349）同步进度状态

- **冻结对照基线**：Android `2.0.49` / `versionCode 349`（提交 `f5e5aedbc6062e1866fe017380d212e58c582e34`）
- **增量范围**：`a71a57fc..f5e5aedb`（涵盖 `2.0.48` 规则引擎 API v3、双轨规则源迁移、多步图像解码、条带/网格拼图还原、`xx.render` 无头渲染、明文 HTTP 门禁，以及 `2.0.49` 全站搜索快源优先调度、后台搜索保活、慢源即时断连，外加 iOS `RuleCatalog` 生产宿主接线与离线拼图还原补齐）
- **当前阶段**：`ComicCore` 全量核心测试与 `XXComic` 原生测试实现已完成，进入 Apple GitHub Actions 全矩阵验证与线上发版阶段

## 需求状态总览

- `P49-01` ~ `P49-11`：代码实现与 `Parity2049CoreTests` 已完成，待 Apple 原生全矩阵验收
- `P49-12`（CI 验证与线上发版）：待推送 GitHub Actions 构建未签名 IPA 后发布至腾讯云 COS 与 `weifeng.cloud`
