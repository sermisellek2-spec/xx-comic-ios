# Protected Source Cache And VPN Design

## Goal

恢复 18漫画和禁漫天堂的列表加载，并让受保护站源的验证状态具备明确的缓存、隔离、失效替换和手动验证行为；同时在站源管理中标识所有需要 VPN 的站源。

## Root Cause

18漫画和禁漫天堂当前都先返回 Cloudflare 403 挑战。验证在同一主文档内完成时，页面 DOM 已恢复为正常内容，但请求对象仍保留挑战响应的 403 状态；当前状态机随后把正常页面判为失败，列表 HTML 无法进入站源解析器。这是 `1.0.30` 新增主文档状态校验后的共同回归。

## Session And Cache Model

- 继续使用 Android `CookieManager` 和 `WebStorage`，不复制 Cookie 到 `SharedPreferences`。
- 18漫画和禁漫天堂各使用一个独立的 `CloudflareWebViewSession`；Cookie 由域名隔离，应用进程内每个站源只有一个会话实例。
- 挑战消失且页面就绪时，验证中的旧 403 不再覆盖正常 DOM；未进入验证流程的真实 HTTP 错误仍失败。
- Cloudflare 重新签发 Cookie 时由原生 Cookie 仓库替换旧值；失效后下一次请求重新进入验证。
- 缓存清理同时删除图片/解析缓存、WebView 页面缓存、Cookie 和 WebStorage。收藏、历史、进度和站源启停配置继续保留。

## Source Management UI

- `18漫画`、`禁漫天堂`、`HiperDEX`、`Hanman18`、`漫画柜`显示轻量 `VPN` 标记。
- 只有 `18漫画` 和 `禁漫天堂`在开关左侧显示紧凑的无边框“验证”按钮。
- 点击后只请求对应站源的列表入口；无有效凭证时显示现有验证层，有效时直接完成。
- 操作期间显示“正在验证”，结束后使用轻提示显示“验证完成”或简短失败原因，不影响另一站源。

## Verification And Release

新增 JVM 状态机回归测试和源码契约，运行完整单元测试与 Release 构建。版本升级为 `1.0.31 (31)`，提交并推送 `master`，发布相同 APK 到 COS 和服务器备用地址，再从两个公网地址回下载核对包名、版本、大小、签名和 SHA-256。
