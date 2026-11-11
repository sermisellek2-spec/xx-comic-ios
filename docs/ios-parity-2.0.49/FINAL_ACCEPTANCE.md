# XX Comic iOS `2.0.49 (349)` 最终验收与发布报告

## 1. 基线与交付版本

| 项目 | 值 |
| --- | --- |
| Android 冻结对照基线 | `2.0.49` / `versionCode 349`（提交 `f5e5aedbc6062e1866fe017380d212e58c582e34`，增量范围 `a71a57fc..f5e5aedb`） |
| iOS 交付分支 / 源码提交 | `codex/ios-port` / `7a3a9472bc021cb38773aa4b775e590002934fb7` |
| iOS 版本号 | `CFBundleShortVersionString = 2.0.49`，`CFBundleVersion = 349` |
| Apple 全矩阵打包 Run | GitHub Actions Run `43004258903`（`validation_scope=full`，`package_ipa=true`，状态 `success`） |
| 未签名 IPA 文件名 | `XXComic-2.0.49-349.ipa`（CI 制品 `XXComic-unsigned`，Artifact ID `13861515281`） |
| 未签名 IPA 字节大小 | `19,152,487` bytes |
| 未签名 IPA SHA-256 | `18a51ec2e4d1254c581bff21978a656676d489b8f46f2b83c71ed117ce777cda` |
| 规则包一致性 | `rules/dist/xx-comic-all-sources.xxrules.json`（111 条规则：109 条 `engineApi=2` + 2 条 `engineApi=3`）与 Android 2.0.49 字节级完全一致 |

## 2. 同步功能与架构闭环矩阵（`P49-01` ~ `P49-12`）

1. **规则引擎 API v3 模型与双轨订阅迁移（`P49-01`、`P49-02`）**：
   - `RuleDefinition` 支持 `engineApi = 1..3`、`requires`（`render` 等能力列表）、`cleartextHosts`（含 7 个历史兼容域名白名单）、`minIntervalMs`（`0..60_000`）及 FNV-1a 内容哈希对齐。
   - 默认订阅源平滑从旧版 `v2/index.json` 迁移至 `https://dl.weifeng.cloud/rules/xx-comic/v3/index.json`，支持 `parseCompatible` / `readCompatible` / `prepareCompatible` 高版本规则兼容跳过并在导入/刷新反馈中明确提示。
2. **生产级 `RuleHttp`、加解密、字节管线与拼图还原（`P49-03` ~ `P49-07`）**：
   - `RuleHttp` 支持二进制请求/响应（`bodyEncoding: utf8/base64/hex`、`bytesBase64`）、手动逐跳重定向安全审查（阻断 HTTPS->未授权 HTTP 降级与内网 SSRF 地址）、按源 `minIntervalMs` 配速、会话 Cookie 持久化与取消即断连。
   - `RuleCrypto` 补齐 `hex`、`HMAC-SHA1`/`HMAC-SHA256`、`AES/CBC|ECB|CTR` 加解密、`xorBytes`、`int64` 加减乘模与输出编码切换。
   - `RuleImageData`（1..8 步链式字节解码）与 `RuleBitmapTransform`（`stripes` / `tiles` / `reverseBands` 含余数边、旋转与翻转）全链路接入封面、阅读器正文与离线下载落盘。
   - `RuleImages` 识别 HTTP 错误页、`text/*`/JSON 响应与非图像字节，自动回调 `source.image(descriptor, forceRefresh=true)` 刷新失效图床节点并重试；全网关强制默认 HTTPS + `cleartextHosts` 应用层门禁。
3. **受控无头网页渲染 `xx.render` 与 111 规则包校验（`P49-08`、`P49-09`）**：
   - 离屏非持久化 `WKWebView` + `WKContentRuleList` 原生拦截图片/媒体/字体子资源，实施 `requires: ["render"]` 门禁、单次最多 4 次渲染上限、`waitSelector` / `waitMs` 等待与取消即销毁。
   - 冻结 v3 全量 111 条规则在 Apple 原生 `JavaScriptCore` 下 100% 通过语法加载、入口校验与能力边界检查。
4. **2.0.49 全站搜索快源优先调度与前台让路（`P49-10`、`P49-11`）**：
   - `GlobalSearchLatencyStore` 记忆各站源耗时与近期失败状态，按快源 -> 常规源 -> VPN 源 -> 慢/失败源分层派发，12 并发窗口，单站源超时通过 `RuleCancelToken` 立即断开底层连接。
   - 从发现页进入漫画详情加载期间持有 `beginForegroundDetailBusy()` 令牌暂停新搜索派发，同时保留后台已启动搜索会话不丢失结果。

## 3. 实际构建与测试记录

- **本机 Linux Swift 5.10 容器核心回归**：
  - `ComicCoreTests`：执行 **1,055** 项（跳过 2 项 Apple 专属项），**0 失败**（含 `Parity2049CoreTests` 7/7、`SourceRulesTests` 49/49）。
- **Apple macOS 15 + Xcode 16.4（iOS 18.5 SDK）全量验证（GitHub Actions Run `43004258903`）**：
  - Debug / Release 双配置真机与模拟器构建、`verify_app_icon.py`、`verify_release_isolation.py`、`http-cache-probe` 全部通过。
  - Apple `ComicCorePackageTests`：执行 **1,063** 项，**0 失败**（`Parity2049CoreTests` 7/7 通过）。
  - `iPhone 15 Pro`（`1A3716EE-6320-4354-A994-83C0BB59BF4B`）：`XXComicTests` **46/46** 通过（`Parity2049NativeTests` 4/4 通过），`XXComicUITests`（含视觉矩阵）**115/115** 通过。
  - `iPad Pro 11-inch (M4)`（`4958D4DC-061A-4B2E-8FCB-F5711F024581`）：`XXComicTests` **46/46** 通过（`Parity2049NativeTests` 4/4 通过），`XXComicUITests`（含视觉矩阵）**115/115** 通过。

## 4. 线上分发端点与自签安装说明

| 端点 | 地址 | 核验状态 |
| --- | --- | --- |
| 腾讯云 COS CDN 最新包 | https://dl.weifeng.cloud/ios/xx-comic-latest.ipa | HTTP 200，`19,152,487` bytes，SHA-256 端到端回拉校验一致 |
| 腾讯云 COS 版本归档包 | `cos://xx-1321588235/ios/XXComic-2.0.49-349.ipa` | 上传完成，元数据一致 |
| 官网下载清单 | https://weifeng.cloud/downloads/manifest.json | `ios.versionName = "2.0.49"`，`versionCode = 349`，SHA-256 一致 |
| App 内检查更新清单 | https://weifeng.cloud/xx-comic/releases/ios-release.json | `versionName = "2.0.49"`，`versionCode = 349`，`downloadUrl` 指向 CDN |

- **安装方式**：线上提供未签名 `XXComic-2.0.49-349.ipa`，用户在 iPhone / iPad 上使用 AltStore、SideStore、Sideloadly、牛蛙助手、爱思助手或自有 Apple 开发者证书签名后即可直接覆盖安装，原有书架收藏、分组、阅读历史、本地导入漫画及已订阅站源均完整保留并自动完成规则通道升级。

## 5. 平台差异台账

详见同目录 `differences.md`（保留用户已确认的 0 默认内置站源引导 `P44-EMPTY`/`P44-GUIDE`、无音量键翻页 `DIFF-2047-01`、`UIAlertController` + `RemToastView` `DIFF-2047-02`，以及本次实现等价用户结果的 `DIFF-2049-01` 应用层明文 HTTP 白名单、`DIFF-2049-02` JSCore 多槽位隔离取消与 `DIFF-2049-03` 离屏 `WKWebView` 渲染）。

## 6. 用户一次总验收清单

1. 下载 https://dl.weifeng.cloud/ios/xx-comic-latest.ipa 签名安装后，进入“设置 -> 关于”确认版本号为 `2.0.49 (349)`；点击“检查更新”提示当前已是最新版本。
2. 进入“设置 -> 站源规则管理”，点击“一键订阅默认规则”或“检查规则更新”，确认拉取 `v3` 通道规则包成功（111 个规则源全部可解析且无语法报错）。
3. 在发现页发起全站搜索并在搜索进行中点进任一漫画详情页，确认详情与章节目录秒开不被慢站阻塞，返回搜索页后结果继续保留。
4. 打开含拼图还原或加密图片的站源章节阅读并缓存下载后断网重进，确认封面、在线正文与离线阅读图片均正常还原显示。
