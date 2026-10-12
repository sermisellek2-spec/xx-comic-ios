# 缓存清理完成与正文残留接续

CI35完整失败证明两项仍未闭合：UI清理10秒后仍禁用，iPad原生diskPath清理后/重开4份正文仍命中。保留原日志、树、截图和断言；系统管理文件与实际正文残留分别记录，不能用D115的口径修正解释正文残留。

当前HTTPResponseCache保持原磁盘后端及容量，移除每50ms因管理字节非零而再次清理、磁盘容量1与恢复导致的重复操作。两次实际removeAllCachedResponses之间等待真实占用安静，增长才再次清理，按单调时钟设有界等待；临时内存容量在结束/取消时恢复，返回实际两项记账。生产不读写、删除URLCache数据库或未知文件。

WebKit清理保持一个不加载文档/网站的真实上下文至完成回调；8秒无回调产生清理失败/重试，不停在永久禁用，也不报成功。独立原生用例验证没有打开过网站时能清理、重复执行并移除验证标记。该用例须Apple实际运行。

10项原缓存回归实际退出0、0失败/5.472秒，原测试源码未改。全部缓存13项影响结果另见impact-all-validation.json。语法解析及后续Apple复验分开记录；此候选尚未通过完整门槛，真实站源继续暂停。

依据：[Apple URLCache清理接口](https://developer.apple.com/documentation/foundation/urlcache/removeallcachedresponses())、[WebKit异步数据清理回调](https://developer.apple.com/documentation/webkit/wkwebsitedatastore/removedata(oftypes:modifiedsince:completionhandler:))。这些API不承诺系统管理文件零字节；实际正文和完成反馈仍须本轮设备实证。
