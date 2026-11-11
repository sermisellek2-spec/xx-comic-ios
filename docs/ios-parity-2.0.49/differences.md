# iOS 2.0.49 同步平台差异台账

基线：Android `2.0.49`（`versionCode 349`，冻结提交 `f5e5aedbc6062e1866fe017380d212e58c582e34`）。

## 延续既有用户确认差异

| 编号 | 领域 | Android 行为 | iOS 行为 | 依据 |
| --- | --- | --- | --- | --- |
| `P44-EMPTY` / `P44-GUIDE` | 初始站源与引导 | 安装后引导订阅站源规则 | 全新安装默认 0 内置漫画源，展示发现页与站源管理导入引导卡；升级用户保留既有配置 | 用户既定产品决策 |
| `DIFF-2047-01` | 音量键翻页 | 支持音量上下键翻页设置 | iOS 系统音量键由硬件 HUD 接管，不提供音量键翻页开关 | 用户确认平台差异 |
| `DIFF-2047-02` | 居中弹窗样式 | 自定义圆角 Dialog + 顶部胶囊 Toast | 居中确认/输入弹窗采用原生 `UIAlertController`；非阻塞轻提示采用顶部 `RemToastView` | 用户确认平台差异 |

## 2.0.48 -> 2.0.49 新增架构差异（等价用户结果）

| 编号 | 领域 | Android 实现 | iOS 实现 | 用户结果一致性 |
| --- | --- | --- | --- | --- |
| `DIFF-2049-01` | 明文 HTTP 动态白名单机制 | `network_security_config.xml` 允许 socket 明文，并在 `RuleHttp` / `RuleImages` / `RuleRepository` / `AppUpdateChecker` / `FileDownloadWorker` 实施应用层 HTTPS 默认门禁 + `cleartextHosts` 白名单 | iOS 无法在运行时修改签名后的 `Info.plist` ATS 域名表，保持 `NSAllowsArbitraryLoads=true`（不启用会覆盖 `URLSession` 的 `NSAllowsArbitraryLoadsInWebContent`），并在同一批网关实施完全一致的应用层 HTTPS 默认门禁 + `rule.allowsCleartext(host)` 白名单 | 完全一致：未声明 `cleartextHosts` 的 HTTP 站源/图片/更新包/订阅一律拦截，声明授权的明文图床正常加载 |
| `DIFF-2049-02` | 规则脚本运行时与并发隔离 | 独立 `:rule` 进程 + Rhino 解释器 + `RuleProcess`（搜索 12 槽 / 前台 4 槽）+ `RuleCancelToken` 强断底层连接 | iOS App 沙盒禁止派生子进程，采用原生 `JavaScriptCore` 独立 `JSContext` + `RuleHostExecutor`（搜索 12 槽 / 前台 4 槽独立信号量，不在主线程执行）+ `RuleCancelToken` 同步取消 `URLSessionDataTask` 与 `WKWebView` | 完全一致：慢站源取消/超时毫秒级释放槽位与底层连接，不阻塞详情、目录与阅读 |
| `DIFF-2049-03` | 受控无头网页渲染（`xx.render`） | 主进程隐藏 `android.webkit.WebView` + `shouldInterceptRequest` 拦截图媒字请求 | 主线程离屏 `WKWebView` + `WKWebsiteDataStore.nonPersistent()` + `WKContentRuleList` 原生阻断 `image`/`media`/`font` 资源 + `decidePolicyFor` 校验每次跳转域名与明文权限 | 完全一致：仅在声明 `requires: ["render"]` 时可用，单次调用最多 4 次，超时/取消立即销毁视图 |
