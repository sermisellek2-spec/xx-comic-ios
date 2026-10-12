# 当前配置消费者审计接续

日期：2026-10-12。冻结Android `696e80a44ab36b19de6f630565df32978e55a19e` / 2.0.40 / 340；父提交 `b8be2d947e720c0527fb3ab280b4fbe1c1a30d0e`。本轮只修配置接线与兼容提示，使用注入的隔离响应，无真实网站请求。

本目录902项属于配置修复输入；随后按Apple证据修缓存统计时机，当前完整Core903项/2跳过/0失败、144.292秒，另存[原生/缓存接续](../2026-10-12-ci15-repair/README.md)。不覆盖或改写本目录的日志和输入SHA。

漫本的分类请求原先使用 `routes.latest`，忽略 `routes.category` 与 `filters.sort.latest`。冻结Android的 `latest → fetchCategory → categoryBody` 和 `category(Map) → categoryBody → fetchPost` 均消费分类路由；现按这两条路径接线。默认字段、直接筛选值和“全部”复位保持Android行为；原目录、阅读解析器没有改动。兼容旧分类名称的调用保留 `category.*` / `state.*` 映射，不把此接口测试冒充界面验收。

公共源的请求来自固定profile，原来导入四个旧平铺路径会成功保存却无人消费。现在保持原值并报告跳过，名称、域名、referer、开关和排序仍按既有支持处理。其他已核实无消费者的兼容路由改动也明确报告，不能因为字段出现在导出JSON里就认为它有效。完整51源的字段及界面验收仍未结束。

调用链人工核对范围如下；这张表是源码证据，表中各源不都具有实际请求回归。

| 范围 | 当前实际消费者 |
| --- | --- |
| gmh / mh18 | latest进入category模板；章节走目录地址或API，不使用独立latest/兼容chapter模板 |
| mh160 / mkzhan / hiperdex / jmcomic | 目录提供章节地址；漫客栈从章身份构造chapterApi；禁漫分类用categoryIndex和目录返回值 |
| manben | 最新及分类均POST到category；sort.latest实际消费；旧分类映射与界面直接筛选值分别处理 |
| manhuazhan / bbyin / cuimh / liumanhua | 分类辅助函数或网站返回的分类路径；催漫画明确不支持搜索；正文用目录地址 |
| copy4000 | apiDetail/apiChapters/apiChapter及主备用origin；兼容chapters/chapter网页模板不参与当前API请求 |
| dongmanla / hanman18 | 分类filter映射或latest/home；正文用目录返回地址 |
| 公共源 | profile的latest/search/分类模板和目录地址；旧平铺路径无消费者 |

漫画柜/悦看已有的不支持字段提示继续保留；HiperDEX章节模板统一进入同一兼容表。未知字段、非法类型/URL、未来版本、退役源和custom的原拒绝/跳过逻辑没有移除。当前目录的整包导出再导入必须保持51源、默认启用50、路由不增生，并且自己导出的默认兼容字段不产生错误警告。

实际记录：

| 原始日志 | 结果 |
| --- | --- |
| regression-before.log | 新增首4用例后，22项/67条失败（1条unexpected），退出1；生产输入仍为b8be2d9。原失败保留 |
| regression-fixed.log | 31项/2条失败，退出1；新整包回归实际暴露东漫拉默认字段误报和禁漫路径增生 |
| regression-roundtrip-fixed.log | 保留上述断言，31项/0失败，0.378秒，退出0 |
| core-full-current.log | 当前完整Linux902项/2个Apple PDF跳过/0失败，149.245秒，退出0 |

`core-validation.json` 保留完整命令、实际退出码、时间、原始日志SHA及当前Core生产/测试输入SHA。新增7项核心用例。UIKit未在本轮配置修复后实际运行；正在运行的Apple完整回归输入是父提交b8be2d9，不包含这些修改。Linux结果不能关闭CONFIG-02/03或P5。用户只负责最后总验收。
