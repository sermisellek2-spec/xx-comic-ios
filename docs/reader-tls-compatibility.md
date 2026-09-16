# 阅读图片连接排查

2026-09-16，iReader Neo 2、SmartOS 4.0.0 用户反馈：手机热点下，包子及另外七个站源可以搜索和打开目录，正文图片失败。最初日志只有 `SSLHandshakeException: Connection closed by peer`，未携带域名和设备版本。

第一次测试版补充图片请求域名、路径、Android/API、机型和应用版本；第二次测试版尝试在非证书原因的握手失败后重试 TLS 1.2。第二次测试版的实机日志已经明确：Android 10 / API 29，`s1.bzcdn.net` 图片因 `Trust anchor for certification path not found` 失败。

包子修复是为已验证证书链的 `s1.bzcdn.net`、`s2.bzcdn.net` 补充项目已有的 Sectigo R46 根证书，保留平台证书与域名校验。移除未解决此问题的 TLS 重试实现及其专用测试，恢复原有图片传输流程。后续按用户要求移除普通图片失败日志及对应诊断包装。证书验证详情见 [包子证书兼容说明](baozi-certificate-compatibility.md)。

当时的新日志中仅出现 `s1.bzcdn.net`；后续排查见 [多站源证书兼容说明](image-cdn-certificate-compatibility.md) 和 [G社、漫本修复说明](gmh-manben-reader-fixes.md)。本机网络走代理，电脑侧证书验证与构建不能替代受影响阅读器的实机验收。

实机验收：覆盖安装最新的 `release/xx-comic-2.0.15-reader-fixes.apk`，重试对应站源正文与漫本详情，无需清除章节缓存。
