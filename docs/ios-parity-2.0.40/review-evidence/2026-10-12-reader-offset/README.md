# 三模式同页图内位置与站源滚动接续

父输入ca68ef8的[阅读CI38230280027](https://github.com/sermisellek2-spec/xx-comic-ios/actions/runs/38230280027)仍运行，包含双轴定位、pending恢复和日漫旋转UI，不包含本次图内偏移修正。

冻结Android MainActivity.java 9100~9106实际保留同页ReaderPosition，只有换页才重建offset=0。当前iOS单页currentPosition此前始终生成offset=0。新候选按章加载保留实际页锚点；普通和日漫仍读同一图片时保留卷轴偏移，实际换页、缩短目录或链接图片消失时重建位置；链接重排仍按稳定图片ID跟踪。正常翻页方向及章序不变，旧左右手继续忽略。

新增3个核心回归覆盖同页往返、实际换页/空目录/缩短目录、链接重排/图片删除。12项ReadingRules影响回归退出0；最终完整Linux925项、2个Apple PDF跳过、0失败，147.408秒、命令退出0。首次完整925项0失败也保留；随后补边界检查并重跑，两个输入与日志分别记录，不覆盖原证据。

原始编译器诊断含尾空格，首次暂存格式检查因此失败；两份filter原log保留全部字节和SHA，仅为该原件声明尾空格格式例外。生产源码、测试断言及其他文档的格式检查不放宽。

新增真实UI操作：慢速滚入图内，切普通/日漫，退出后重启，再回卷轴，断言同章页、实际图片Y及高度。使用[Apple坐标拖动API](https://developer.apple.com/documentation/xcuiautomation/xcuicoordinate/press%28forduration%3Athendragto%3Awithvelocity%3Athenholdforduration%3A%29)，没有测试设置位置的生产后门。该UI尚未Apple执行，不能因核心通过记为界面通过。

CI22确认站源滚动仍失败。新候选把已有SourceOptionScrollView接到实际filter.options，保留原3项SourceDrawer UI断言。93原生Swift文件Release/DEBUG语法各退出0；这是语法检查，Apple类型检查/构建/运行仍待执行。

本候选计划原生29、阅读18、配置52项每设备，数量最终以Apple原始结果为准。当前目标不变：51源/默认50，非站源门槛false，只用sermisellek2-spec开发CI，package_ipa=false，无阶段IPA。
