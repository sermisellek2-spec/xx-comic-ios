# 图片域名证书适配

实机日志确认 iReader Neo 2（Android 10 / API 29）不信任包子图片服务器的证书链。用户要求为其余故障站源做相同适配；本次依据实际服务器证书链补充根证书，尚不能认定其余站源均由缺根证书引起。配置仅作用于列出的域名，保留系统信任、证书有效期和主机名校验：

- 包子、六漫画：`cn.dzmanga.com`、`s1.bzcdn.net`、`s2.bzcdn.net` → Sectigo R46
- 漫画栈、比卡：`manhua.5um.net` → ISRG Root X1 / X2
- G 社已核验图片节点：`6wm.top` 及其子域 → ISRG Root X1 / X2
- 催漫画：`*.baipiaoguai.org`；tapmanga：`*.antbyw.com` → GTS Root R4
- 漫本：`*.cdndm5.com` → Go Daddy Root Certificate Authority - G2

每组域名单独限制 trust anchors，避免一个图片站的根证书扩展到其他站源。没有配置明文 HTTP，也没有关闭证书或主机名验证。

根证书取自本机 Node.js v22.20.0 的 `tls.rootCertificates`（随 Node 发布的 Mozilla CA 快照），按准确 subject 选择自签 CA。未把服务端叶证书或交叉签中间证书作为信任锚。新增证书的 SHA-256、有效期和测试结果记录在后文。

已实际获取漫画栈/比卡 `manhua.5um.net`、漫本 `manhua1032zjcdn26.cdndm5.com`、tapmanga `imgmh3.antbyw.com`、G社 `c-nc-1.6wm.top` 的样例图片。催漫画 `img1.baipiaoguai.org` 的 TLS 验证成功，根路径返回 HTTP 403，不能据此声称正文访问已验证。

G社旧正文节点 `f40-1-4.g-mh.online`、`t40-1-4.g-mh.online` 在本机 TLS 握手前返回 ECONNRESET，未取得证书链，因此未为其猜测添加根证书。后续已根据官网脚本更新到 `c-nd2-1.6wm.top` / `c-nd3-1.6wm.top`，详见 [G社与漫本修复](gmh-manben-reader-fixes.md)。

桌面网络走代理，仍需要用户设备验收。后续按用户要求已停止记录普通图片加载失败；章节解析等错误仍保留日志。

## 根证书审计

- `isrg_root_x1`: SHA-256 `96:BC:EC:06:26:49:76:F3:74:60:77:9A:CF:28:C5:A7:CF:E8:A3:C0:AA:E1:1A:8F:FC:EE:05:C0:BD:DF:08:C6`; 有效期 Jun  4 11:04:38 2015 GMT 至 Jun  4 11:04:38 2035 GMT。
- `isrg_root_x2`: SHA-256 `69:72:9B:8E:15:A8:6E:FC:17:7A:57:AF:B7:17:1D:FC:64:AD:D2:8C:2F:CA:8C:F1:50:7E:34:45:3C:CB:14:70`; 有效期 Sep  4 00:00:00 2020 GMT 至 Sep 17 16:00:00 2040 GMT。
- `gts_root_r4`: SHA-256 `34:9D:FA:40:58:C5:E2:63:12:3B:39:8A:E7:95:57:3C:4E:13:13:C8:3F:E6:8F:93:55:6C:D5:E8:03:1B:3C:7D`; 有效期 Jun 22 00:00:00 2016 GMT 至 Jun 22 00:00:00 2036 GMT。
- `go_daddy_root_certificate_authority___g2`: SHA-256 `45:14:0B:32:47:EB:9C:C8:C5:B4:F0:D7:B5:30:91:F7:32:92:08:9E:6E:5A:63:E2:74:9D:D3:AC:A9:19:8E:DA`; 有效期 Sep  1 00:00:00 2009 GMT 至 Dec 31 23:59:59 2037 GMT。
