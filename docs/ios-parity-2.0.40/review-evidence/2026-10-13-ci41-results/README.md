# CI41 验证界面影响复验实际成功

指定仓库[38312023209](https://github.com/sermisellek2-spec/xx-comic-ios/actions/runs/38312023209)，输入ee762957b5f209bf0a7f05c899c4bb86e2a0902a，verification-ui，不出IPA。

两SDK构建、图标资源、Release隔离实际通过；Apple Core929零失败，iPhone/iPad各35原生和2验证UI全部通过，无跳过。新用例实际走超时→本机HTTP重试→生产完成/Cookie屏障→返回已验证→重置→重启未验证；原关闭/重开用例也实际通过。

真实网站、Cloudflare和TLS认证没有验证；不把本机响应冒充站源可用。原日志ZIP、完整build log、原始xcresult归档及隔离/图标JSON已下载，字节/SHA见original-downloads.json；实际套件见summary.json。

这是验证影响范围通过，不含最新分组选源修正，也不代最终35原生/111UI完整回归、视觉和总验收IPA。门槛仍待关闭。
