# Android 2.0.40 → iOS 当前对照状态

最新完成的Apple运行是第八轮b69517c：SDK/Core875/两设备原生各20通过，UI各57执行仍有7/9个失败用例。当前修复与真实Files/共同夹具待Apple；非站源完整门槛未过，不生成IPA。当前状态以docs/ios-parity-2.0.40/STATUS.md为准；下文早期版本数字为历史记录。

冻结基线696e80a44ab36b19de6f630565df32978e55a19e、2.0.40/340。iOS最新已运行快照9b1d4a2，完整UI仍失败；当前标准导航/批量恢复/同步反馈修复待Apple回归。**尚未完整1:1，非站源门槛未通过。**

先写[阶段方案](../docs/IOS_2_0_40_PHASED_DEVELOPMENT.md)，再实施P1~P4。本批已修导航/设置/书架及详情层级、发现收放/未读锚点、阅读88控制条、缓存/配置/统计/更新消费者、整本删除撤销、Files目录/持续书签/真实路径映射；接续补文件协调/私有暂存发布/权限反馈与离线图片读取器。以前的搜索/目录下载/封面/图标/淘汰左右手修正保留。当前Linux全量846执行、2个Apple PDF跳过、0失败；66原生/测试源码两配置仅语法通过。9b1d4a2两配置Apple SDK、核心847与两设备原生各19已运行通过（含真实CoreML）；完整UI各49执行/51条失败，设置8参考取得但状态/视觉仍有差异。Files/性能及新IPA未验收，不能把局部结果记为阶段通过。

当前51源=22专用+29公共，默认50且duya关闭，haoman排除；baozimh/mhua5仅旧记录兼容。数量/名称/顺序/默认状态静态及核心通过，生产注册与真实网站未验收。全部非站源通过后才逐一真实网站。

只用sermisellek2-spec/xx-comic-ios打包和开发验证。旧a5aeec9 CI38104946234成功但IPA实际缺图标且不含本批代码；Windows无Xcode；指定账号正常Git凭据与仓库写入权限已核验，代理已运行三轮Apple CI并继续修失败，最新结果见docs/ios-parity-2.0.40/review-evidence/2026-10-11-apple-ci/。用户只做最终总验收，缺项集中于[USER_ITEMS](../docs/ios-parity-2.0.40/USER_ITEMS.md)。

- [当前差异及运行参考图](../docs/comparisons/2026-10-11-ios-android-current-assessment.md)
- [需求矩阵](../docs/ios-parity-2.0.40/requirements.csv)、[状态](../docs/ios-parity-2.0.40/STATUS.md)、[非站源门槛](../docs/ios-parity-2.0.40/NON_SOURCE_GATE.md)
- [阶段报告](../docs/ios-parity-2.0.40/stages/)、[实际验证和输入哈希](../docs/ios-parity-2.0.40/review-evidence/2026-10-11-staged-development/README.md)
- [历史对照](../docs/ios-parity-2.0.40/review-evidence/2026-10-11-current-comparison/historical-PARITY.md)，不作为当前PASS。

当前未提交候选补直接索引/重新授权/稳定页与末页续读、旧复制记录迁移及自动同步生命周期；Linux最终全量858项/2个Apple PDF跳过/0失败，68源码两配置仅语法通过，候选Apple未运行。第七轮e2f53b5正在完整自验；D44旧孤儿恢复持久归属、真实外部Files/视觉/性能仍未完成，非站源门槛未通过。
