# 缓存占用的隔离取证

第十三/十四轮Apple均在生产URLCache清理后报告非零磁盘占用。清响应、容量恢复、旧响应不可命中及原包保留的断言保留；未改生产算法，也未把剩余字节改为固定0。

`ios/scripts/CacheProbeMain.swift`直接与当前`HTTPResponseCache.swift`编译。所有URL、响应及原包由探针生成，不联网；创建UUID独立目录，观察旧diskPath和Apple directory初始化的真实占用。每次复制自己的文件与侧文件后，只读查询复制SQLite的表名/行数及页数，不读取正文，不删除或直接写缓存数据库。非原子快照和查询错误明确记录。

初版Linux报告是`linux-cache-probe.json`与`validation.json`；接续版本增加只读快照查询，重新执行结果是`linux-cache-probe-current.json`、`linux-probe-current.log`及`validation-current.json`，没有覆盖初版结果。Linux当前编译/运行退出0，四个响应存入后均可命中，清理后立即及四次等待均0且不可命中，原包保留。Linux不用Apple CFNetwork，不能证明Apple也归零，更不能据此关闭D51。

完整Apple范围和独立cache-diagnostics范围都会执行探针，任何探针/核心失败继续阻止总体通过和IPA，但仍保留独立UI证据。Apple结果待取得。

Apple文档分别定义[当前磁盘缓存大小](https://developer.apple.com/documentation/foundation/urlcache/currentdiskusage)、[移除全部响应](https://developer.apple.com/documentation/foundation/urlcache/removeallcachedresponses())及[目录初始化](https://developer.apple.com/documentation/foundation/urlcache/init(memorycapacity:diskcapacity:directory:))。本轮先取实际数据，不以API名称推断所有剩余字节的归属。
