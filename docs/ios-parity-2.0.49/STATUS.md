# iOS 2.0.49（349）同步进度状态

- **冻结对照基线**：Android `2.0.49` / `versionCode 349`（提交 `f5e5aedbc6062e1866fe017380d212e58c582e34`）
- **iOS 交付源码提交**：`7a3a9472bc021cb38773aa4b775e590002934fb7`（分支 `codex/ios-port`）
- **增量范围**：`a71a57fc..f5e5aedb`（涵盖 `2.0.48` 规则引擎 API v3、双轨规则源迁移、多步图像解码、条带/网格拼图还原、`xx.render` 无头渲染、明文 HTTP 门禁，以及 `2.0.49` 全站搜索快源优先调度、后台搜索保活、慢源即时断连，外加 iOS `RuleCatalog` 生产宿主接线与离线拼图还原补齐）
- **当前阶段**：**全部阶段验收通过并完成线上正式发布**

## 需求状态总览

- `P49-01` ~ `P49-11`：**通过**（Linux Docker `ComicCore` 全量 1,055 项测试 0 失败；Apple GitHub Actions Run `43004258903` 共 1,385 项原生/UI/视觉矩阵测试 0 失败）
- `P49-12`（CI 验证与线上发版）：**通过**（未签名 IPA `XXComic-2.0.49-349.ipa` 字节数 `19,152,487`，SHA-256 `18a51ec2e4d1254c581bff21978a656676d489b8f46f2b83c71ed117ce777cda`，已同步发布至腾讯云 COS `dl.weifeng.cloud` 与 `weifeng.cloud` 官网清单及版本检查端点）
