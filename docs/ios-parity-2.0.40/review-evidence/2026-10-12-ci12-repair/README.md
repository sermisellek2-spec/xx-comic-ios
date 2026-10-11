# 第十二轮实际结果与后续取证

2026-10-12。只使用sermisellek2-spec/xx-comic-ios；认证与推送已成功，不需要用户重新登录。非站源门槛未通过，51真实站源继续后置，无IPA。

[第十二轮运行](https://github.com/sermisellek2-spec/xx-comic-ios/actions/runs/38177012735)代码为c55d4a3a0752461b1a1a80aaf90c75fc5ed70c07。Debug模拟器和Release真机SDK构建通过；Apple核心实际884项、1失败，100.612秒。CacheMaintenanceTests.testDiskCleanupRestoresLimitsAndAllowsLaterResponses第20行剩余占用断言失败。脚本在核心退出后结束，Files辅助构建安装、两设备原生单测和UI均未启动，不能视为失败修复已验收。

原始日志ZIP与结果ZIP字节不改，哈希见apple-12-summary.json。结果artifact仅包含空数组manifest，没有xcresult；“上传成功”不表示执行了测试。phase-excerpt只摘实际阶段、编译结论及失败，不替代原始日志。

## 下一轮的具体改动

- 保留缓存0占用、不可命中、容量恢复、后续可缓存以及用户原包保留的断言。增加新缓存、存入、清理和随后4秒等待的实际内存/磁盘占用与命中记录，不预先宣称是系统索引或异步延迟。
- 核心失败后继续已构建候选的独立两设备原生/UI取证；总体仍退出失败、禁止IPA。SDK编译失败仍立即停止，不用旧二进制。
- 目录取消/阅读下载接管场景经真实全站搜索打开未收藏copy4000作品，避免书架自动追更消耗受控第一请求。生产追更保持，取消、重试、不误跳及真实图片断言保持。

Apple文档仅承诺[移除全部缓存响应](https://developer.apple.com/documentation/foundation/urlcache/removeallcachedresponses())、[统计磁盘缓存占用](https://developer.apple.com/documentation/foundation/urlcache/currentdiskusage)以及[容量收缩](https://developer.apple.com/documentation/foundation/urlcache/diskcapacity)；当前尚无实际证据证明失败原因。不会直接删系统数据库或将占用改成假0。

## 本地验证边界

当前缓存专项9项/0失败、2.064秒、退出0；Linux实际记录fresh=0/0、stored=5266/5266、cleared=0/0且不可命中，不能据此推断Apple结果。78 Swift文件Release/DEBUG语法、构建驱动Bash语法退出0；不证明Apple类型、Files或UI已通过。Core生产代码未改，最近完整877项/2个Apple PDF跳过/0失败来自c55d4a3之前的同一生产实现，完整Apple仍以新运行实际结果为准。

命令、实际退出码、日志哈希和本轮三项代码输入SHA见validation.json。完整两设备74项UI、当前64页视觉与P5性能/旧数据/后台/Release仍未齐；不请求用户中间验收。

验证驱动另在可丢弃Linux容器用模拟编译器进行契约检查：核心失败后两目的设备仍执行，但整体退出1、不产IPA；SDK失败整体退出23且不执行UI。实际退出0，源夹具driver-contract-fixture.py与driver-contract.log保留。这是驱动契约检查，不是Apple或UI运行证据。
