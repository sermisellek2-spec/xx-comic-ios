# 验证界面超时、重试与完成返回

2026-10-13。真实站源继续暂停，本轮仅验证非站源交互。生产验证地址、信任规则、120秒请求时限、Cookie消费与后台重置语义保持。

原有UI只验关闭和重开，不能证明成功、超时及重试。新增显式Debug驱动：第一轮使用实际单调时钟超时处理器；重试通过本机HTTP服务取得真实200漫画目录响应，再进入生产Cookie同步屏障、完成令牌、管理状态更新、窗口关闭和返回流程。复位后重启，管理页仍为未验证。未使用真实网站，也不宣称Cloudflare、TLS或真实Cookie验证成功；这些仍后置。

驱动必须同时指定`--ui-testing`、`--verification-fixtures`和`--verification-timeout-then-local-response`，Release不编译。新增二进制隔离标记。首轮期限仅在上述Debug驱动缩短，重试用正常生产时限。没有改成成功布尔值预填，没有改变现有关闭/重开断言。

当前声明35原生/109UI，包含2个验证UI；[清单](test-declaration.json)仅为源码声明。93个Swift输入两配置语法检查退出0，输入哈希执行前后不变；[记录](native-syntax-proof.json)不代Apple类型检查或运行。Python AST与Bash语法退出0。ComicCore生产未改。

新增`verification-ui`影响范围：两SDK、图标、Release隔离、完整Apple Core、每设备全部原生及2个验证UI；不得出IPA。该范围与最终同版本full尚待实际运行。CI39分卷/同步、CI40换源/日志/队列仍在运行，CI40不包含本轮新增验证用例。
