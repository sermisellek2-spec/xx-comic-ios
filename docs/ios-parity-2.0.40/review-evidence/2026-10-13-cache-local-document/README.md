# 缓存正文清理和本地WebKit上下文候选

CI37确认正文残留和WebKit Cookie超时仍存在。HTTPResponseCache在保留后端/容量及原界限的前提下，同时调用removeCachedResponses(since: .distantPast)和removeAllCachedResponses；没有读写/删除数据库或扣减索引。

WebKit先完成CSP禁止资源的本地HTML导航，再请求实际allWebsiteDataTypes删除；本地页不访问网站、不呈现，不以创建空WKWebView就代表已完成。保留8秒失败/重试、迟到保护、Cookie真实删除及10秒UI检查。失败阶段仅记录框架code/阶段，新UI附件在失败当时保存，避免返回设置后的截图丢失错误。此为候选，当前Apple结果未运行，未声称WebKit内部根因已经证实。

13项原缓存影响回归0失败/8.194秒、输入SHA不变；90Swift两配置仅语法解析通过。完整本机核心922项执行、2个Apple PDF跳过、0失败、148.348秒，实际退出0且全部输入SHA不变；指定仓库Apple复验待上传后运行。设置分组标题同时补横屏安全区；真实站源继续暂停，未打包。

接口依据：[Apple时间范围清理](https://developer.apple.com/documentation/foundation/urlcache/removecachedresponses(since:))、[本地HTML加载](https://developer.apple.com/documentation/webkit/wkwebview/loadhtmlstring(_:baseurl:))、[WebKit实际清理回调](https://developer.apple.com/documentation/webkit/wkwebsitedatastore/removedata(oftypes:modifiedsince:completionhandler:))。
