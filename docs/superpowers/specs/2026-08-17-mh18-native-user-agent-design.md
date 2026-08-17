# 18漫画原生浏览器指纹设计

## 问题

18漫画验证页现在保持可见，但用户勾选后 Cloudflare 会重新生成验证框。App 只调用一次 `loadUrl()`，重复验证由挑战页自身触发。站点响应要求完整 Client Hints，而当前会话把 WebView 和 HTTP 都固定伪装为 Android 14 / Chrome 124；真实 WebView 版本与 UA Client Hints 不一致会使验证 token 被拒绝。

## 方案

- 仅 18漫画会话启用原生 UA 模式。
- 原生模式不调用 `WebSettings.setUserAgentString`，让 WebView 自行发送真实 UA 与 Client Hints。
- 初始化会话时读取 `WebSettings.getDefaultUserAgent(activity)`，预检 HTTP 使用同一个 UA，避免 Cookie、HTTP 与 WebView 指纹分裂。
- 禁漫天堂继续使用原固定 UA，不修改其构造、验证、Cookie 或解析逻辑。
- 保留严格可见验证、120 秒超时和现有完成条件。

## 验证与发布

先通过 JVM 测试锁定原生/固定 UA 选择，再通过源码契约确认只有 18漫画开启原生模式且原生 WebView 不覆盖 UA。运行完整测试和 Release 构建，发布 `1.0.41 (41)`，推送 `master`，同步 COS 与服务器备用包并回下载核验。
