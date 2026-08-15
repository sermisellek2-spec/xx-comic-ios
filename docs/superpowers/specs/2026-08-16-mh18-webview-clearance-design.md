# 18漫画 WebView 验证设计

## 目标

解决 `18mh.org` 对纯 HTTP 客户端返回 Cloudflare `403 / Cf-Mitigated: challenge`，导致列表、分类、搜索和详情在解析前失败的问题。仅为“18漫画”增加用户可见的浏览器验证，不改变其他站源。

## 请求流程

- `Mh18ComicSource` 保持现有 HTML/API 解析逻辑，首次请求仍走 `HttpURLConnection`。
- 请求携带当前 18漫画会话的 Cookie 和 User-Agent。
- 仅当响应为 `403` 且 `Cf-Mitigated` 为 `challenge` 时，请求一个 WebView 验证会话；其他网络错误直接沿用现有错误处理。
- 验证成功后，将 WebView 的 Cookie 和 User-Agent 返回给站源，并只重试原请求一次。重试仍被挑战时直接失败，禁止循环弹窗或自动重试。
- 站源可用性检测只使用已有会话，不主动弹出验证页。

## WebView 验证会话

- `MainActivity` 负责创建一个全屏、可取消的 WebView 对话框，打开 `https://18mh.org/manga`。
- WebView 启用 JavaScript、DOM Storage、Cookie 和第三方 Cookie，使用系统 WebView 的真实 User-Agent。
- 页面不再显示 Cloudflare challenge，且 Cookie 中出现 `cf_clearance` 后判定成功；随后关闭对话框并恢复原请求。
- 对话框不显示返回按钮，系统返回手势用于取消。界面只保留紧凑标题和加载状态。
- 并发请求共享同一个验证任务，避免多个搜索线程同时打开多个 WebView。
- 验证最多等待三分钟；取消、超时或 Activity 销毁会唤醒等待线程并返回明确错误。

## 会话生命周期

- Cookie 由 Android `CookieManager` 管理，不写入站源配置或导出文件。
- MainActivity 内存中保留最近一次 Cookie/User-Agent，站源客户端重建后仍可读取。
- VPN 换节点、IP 变化或 Cookie 过期后，下一次明确收到 Cloudflare challenge 时重新验证。
- 不读取 Chrome Cookie，不接入远程代理，不保存 Cloudflare 页面内容。

## 发布

- 按用户要求不运行测试套件；执行 Release 构建、APK 包名/版本/签名与哈希校验。
- 版本升级为 `1.0.24 (24)`。
- 精确提交并推送 `master`，更新 COS 固定对象和服务器备用 APK/元数据，回下载比对 SHA-256。
