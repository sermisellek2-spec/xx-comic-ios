# 包子站证书兼容

2026-09-15 检查 `cn.dzmanga.com`，服务器发送的链为：

- `*.dzmanga.com`
- `ZeroSSL RSA DV SSL CA 2`
- 上级根证书：`Sectigo Public Server Authentication Root R46`

服务器 OpenSSL 使用原有信任库报 `unable to get local issuer certificate`；指定 R46 根证书并启用 `-verify_hostname cn.dzmanga.com -verify_return_error` 后返回 `Verification: OK`。

根证书来源：https://curl.se/ca/cacert.pem （Mozilla CA 信任库镜像），提取条目 `Sectigo Public Server Authentication Root R46`。未将站点叶证书或中间证书设为信任锚。

Android Network Security Config 仅向 `cn.dzmanga.com` 添加此根证书，同时保留系统信任锚，禁止该域名明文连接；其余域名继续使用平台默认配置。证书过期、主机名不匹配及不受信任签发者仍应拒绝。

此配置从 Android 7（API 24）起生效；Android 6 继续使用平台证书库。此修复未添加 WebView 兜底，也不修改其他站源的验证逻辑。电脑侧 TLS 验证与 APK 构建不能代替受影响小米手机的实机验收。
