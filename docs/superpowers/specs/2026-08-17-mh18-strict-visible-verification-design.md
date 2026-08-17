# 18漫画严格可见验证设计

## 背景

18漫画的 Cloudflare Turnstile 在用户勾选后会先生成 `cf-turnstile-response`，随后才由挑战页向服务端确认并进入目标页面。`1.0.38` 将 WebView 移出屏幕，`1.0.39` 将 WebView 放到 App 内容下层；两种方案都会停留在 `verifying=true, challenge=true, ready=true` 并最终超时。

根因是 App 把“客户端 token 已生成”当成了“服务端验证完成”，在挑战 DOM 仍存在时提前让验证页失去顶层可见和交互状态。

## 方案

18漫画采用严格可见验证：

- 验证页显示后保持全屏、置顶、可见和可交互。
- `cf-turnstile-response` 出现或 `cf_clearance` 变化都不再触发提前关闭。
- 继续轮询当前 WebView；只有挑战 DOM 消失、页面加载完成且 URL 仍属于请求目标时，才提示“验证完成”并隐藏验证页。
- 保留 120 秒总超时与现有失败提示。
- 禁漫天堂继续使用当前会话行为，不修改其验证、解析或缓存逻辑。

## 状态边界

1. `SHOW_VERIFICATION`：展示并聚焦验证 WebView。
2. `KEEP_VERIFYING`：包括用户已经勾选但挑战 DOM 尚未消失的阶段；视图保持不变。
3. `CAPTURE`：挑战 DOM 已消失且目标页完整加载；此时才关闭验证页并返回 HTML。

## 验证

- JVM 回归测试证明严格模式不会因 Turnstile token 或 clearance 变化提前交回 App。
- 现有非严格模式断言继续通过，保护禁漫天堂行为。
- 运行完整 JVM 测试、受保护站源源码契约和 Release 构建。
- 发布 `1.0.40 (40)`，核验 APK 包名、版本、签名、大小和 SHA-256；推送 `master`，同步 COS 与服务器备用包并回下载比对。

## 范围

只修改共享 WebView 会话中的提前交回判定、对应测试和失效的源码契约，再递增发布版本。不会修改 18漫画解析器、禁漫天堂、UA、Cookie、缓存、网络超时或其他站源。
