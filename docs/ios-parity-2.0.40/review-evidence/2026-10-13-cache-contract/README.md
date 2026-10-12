# 缓存清理契约核对与当前修正

本轮明确修正一项原验收口径：原测试要求URLCache物理占用必须为0，原UI要求固定“0 B”。冻结Android MainActivity.java第12919行统计漫画图片缓存，第14919至14923行清理images目录并重置图片记账/内存；这不是Foundation底层数据库全部文件字节的要求。原测试失败历史不删，不记为原断言通过。

[Apple URLCache文档](https://developer.apple.com/documentation/foundation/urlcache)规定removeAllCachedResponses移除存储响应，currentDiskUsage报告真实占用；[diskCapacity文档](https://developer.apple.com/documentation/foundation/urlcache/diskcapacity?language=objc)描述必要时截断内容，没有保证系统数据库物理文件归零。CI31/32的隔离0联网探针显示：新空缓存已有81920字节；4份正文共1MiB清理后已知正文/文件消失，复制SQLite的response/blob/receiver行均0，仍有144016字节管理文件。快照非原子，不能泛化为任意并发请求保证；生产不直接访问或删除系统数据库。

原三份测试源码逐字节保存在historical-*及SHA清单。当前Core测试将“物理0”改为清理返回值必须等于URLCache实际记账，并新增同路径重开正文不得恢复；原正文不可命中、容量恢复、之后正常缓存及原CBZ文件保护断言保留。不是扣除索引、把140KB假报成0，或跳过失败来完成门槛；这是对有独立基线/公开API证据的原错误口径作透明纠正，需当前Apple重新运行。

生产清理结果展示实际剩余占用，说明系统可能保留管理文件或新请求缓存；出错仍有失败/重试。设置页继续显示实际memory+disk，没有减索引或伪造0。Debug显式UI测试将同一次实际统计挂到值标签，无生产fixture。当前UI检查反馈10秒内完成、按钮恢复、可见数值与真实两项统计及显示精度相符。真实系统缓存字节范围差异在视觉对照中公开，不遮罩该值。

13项缓存影响回归实际退出0，0失败，12.141秒，原始impact.log保留；88个UIKit/原生/UI Swift文件Release/DEBUG语法解析退出0，尚不等于Apple类型/运行通过。最新全量Core结果另见core-full-validation.json，当前Apple/完整UI/64场景视觉仍待验收。站源暂停，尚无总验收IPA。
