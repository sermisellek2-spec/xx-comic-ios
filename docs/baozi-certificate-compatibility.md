# 包子站证书兼容

2026-09-15 检查 `cn.dzmanga.com`，服务器发送的链为：

- `*.dzmanga.com`
- `ZeroSSL RSA DV SSL CA 2`
- 上级根证书：`Sectigo Public Server Authentication Root R46`

服务器 OpenSSL 使用原有信任库报 `unable to get local issuer certificate`；指定 R46 根证书并启用 `-verify_hostname cn.dzmanga.com -verify_return_error` 后返回 `Verification: OK`。

根证书来源：https://curl.se/ca/cacert.pem （Mozilla CA 信任库镜像），提取条目 `Sectigo Public Server Authentication Root R46`。未将站点叶证书或中间证书设为信任锚。

Android Network Security Config 仅向 `cn.dzmanga.com`、`s1.bzcdn.net`、`s2.bzcdn.net` 添加此根证书，不包含子域，同时保留系统信任锚并禁止这些域名明文连接。其他站源的独立域名配置见 [图片域名证书适配](image-cdn-certificate-compatibility.md)。证书过期、主机名不匹配及不受信任签发者仍应拒绝。

2026-09-16，iReader Neo 2（Android 10 / API 29）的新版日志明确显示 `s1.bzcdn.net` 正文图片因 `Trust anchor for certification path not found` 失败。此前配置只覆盖主站，遗漏图片服务器，因此补充上述两个图片域名。`s2.bzcdn.net` 也用于六漫画正文图片；已独立确认其证书链使用同一根证书，但尚未收到该设备访问 s2 的日志。

验证日志中的《武炼巅峰》图片 `https://s1.bzcdn.net/scomic/wuliandianfeng-pikapi/0/0-98bj/1.jpg`：仅信任项目内的 R46 根证书时，TLS 1.2 校验通过，返回 HTTP 200 / `image/jpeg`。`s2.bzcdn.net` 的 TLS 校验也通过。使用不匹配的根证书时连接被拒绝；验证错误主机名时返回 `ERR_TLS_CERT_ALTNAME_INVALID`。

项目内 R46 证书 SHA-256：`7B:B6:47:A6:2A:EE:AC:88:BF:25:7A:A5:22:D0:1F:FE:A3:95:E0:AB:45:C7:3F:93:F6:56:54:EC:38:F2:5A:06`。

此配置从 Android 7（API 24）起生效；Android 6 继续使用平台证书库。此修复未添加 WebView 兜底。电脑侧 TLS 验证与 APK 构建不能代替受影响 iReader 设备的实机验收。
