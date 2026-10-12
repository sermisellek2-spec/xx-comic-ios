# 缓存占用的隔离取证

2026-10-12新增Apple实证：[独立诊断38190616735](https://github.com/sermisellek2-spec/xx-comic-ios/actions/runs/38190616735)在同一b8be2d9输入的独立ref运行，没有取消完整回归38190082897，没有IPA。两配置SDK构建成功；Mac Core902项/1缓存失败（119.052秒）；iPhone原生24项/1几何失败（7.500秒），iPad24项/1几何失败（8.110秒）。此范围没有执行UI，不能冒充完整Apple或视觉通过。

旧diskPath和directory两种初始化的隔离结果一致：fresh占81920字节/0可命中响应，stored占1212928字节/4响应/1048576正文；cleared及四次等待均144016字节/0命中/0已知正文。清理后只剩Cache.db、shm和wal三个文件，四个256KiB正文文件已移除；复制数据库中的blob/receiver/response三表行数从4降为0，原包仍保留。只读副本有明确非原子限制，未检查WAL历史内容，不能推断生产或小正文也完全相同。原始ZIP、原样日志、完整14次观测及哈希见apple-*证据；没有把剩余字节减去常数或改为0。

当前明确区分两件事：隔离的大响应已从可重用缓存中移除；Apple仍报告真实占用，原物理归零断言仍失败。下一输入增加iOS原生隔离测试，覆盖小/大正文、两种构造、同目录另建缓存不可命中、容量恢复和原包保护，并如实记录字节。该新增测试尚未Apple运行，不替代或删除原Mac失败断言。D51及非站源门槛仍未关闭。

探针同时实证清理返回值36864小于恢复容量后的144016，生产返回值在defer恢复之前已计算。新增可控记账回归实际复现后，当前改为正常结束先恢复容量再取真实统计，异常仍恢复；不改变isEmpty、不减少真实字节、不改原归零断言。修正后Linux完整903项/2跳过/0失败，Apple仍待运行，详见[本地修正证据](../2026-10-12-ci15-repair/README.md)。

以下为新增Apple取证之前的记录，其中“Apple待取得”指当时状态。

第十三/十四轮Apple均在生产URLCache清理后报告非零磁盘占用。清响应、容量恢复、旧响应不可命中及原包保留的断言保留；未改生产算法，也未把剩余字节改为固定0。

`ios/scripts/CacheProbeMain.swift`直接与当前`HTTPResponseCache.swift`编译。所有URL、响应及原包由探针生成，不联网；创建UUID独立目录，观察旧diskPath和Apple directory初始化的真实占用。每次复制自己的文件与侧文件后，只读查询复制SQLite的表名/行数及页数，不读取正文，不删除或直接写缓存数据库。非原子快照和查询错误明确记录。

初版Linux报告是`linux-cache-probe.json`与`validation.json`；接续版本增加只读快照查询，重新执行结果是`linux-cache-probe-current.json`、`linux-probe-current.log`及`validation-current.json`，没有覆盖初版结果。Linux当前编译/运行退出0，四个响应存入后均可命中，清理后立即及四次等待均0且不可命中，原包保留。Linux不用Apple CFNetwork，不能证明Apple也归零，更不能据此关闭D51。

完整Apple范围和独立cache-diagnostics范围都会执行探针，任何探针/核心失败继续阻止总体通过和IPA，但仍保留独立UI证据。Apple结果待取得。

Apple文档分别定义[当前磁盘缓存大小](https://developer.apple.com/documentation/foundation/urlcache/currentdiskusage)、[移除全部响应](https://developer.apple.com/documentation/foundation/urlcache/removeallcachedresponses())及[目录初始化](https://developer.apple.com/documentation/foundation/urlcache/init(memorycapacity:diskcapacity:directory:))。本轮先取实际数据，不以API名称推断所有剩余字节的归属。
