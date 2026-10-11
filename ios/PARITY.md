# Android 2.0.40 → iOS 当前对照状态

冻结基线696e80a44ab36b19de6f630565df32978e55a19e、2.0.40/340。iOS为1e2287c基础本地未提交工作树。**尚未完整1:1，非站源门槛未通过。**

先写[阶段方案](../docs/IOS_2_0_40_PHASED_DEVELOPMENT.md)，再实施P1~P4。本批已修导航/设置/书架及详情层级、发现收放/未读锚点、阅读88控制条、缓存/配置/统计/更新消费者、整本删除撤销、Files目录/持续书签/真实路径映射；接续补文件协调/私有暂存发布/权限反馈与离线图片读取器。以前的搜索/目录下载/封面/图标/淘汰左右手修正保留。当前核心全量838执行、2个Apple PDF跳过、0失败；独立反馈6项历史结果；63原生/测试源码两配置仅语法通过。当前Apple/UIKit/Files/CoreML/视觉和新IPA均未验收，不能把本地已改记成阶段通过。

当前51源=22专用+29公共，默认50且duya关闭，haoman排除；baozimh/mhua5仅旧记录兼容。数量/名称/顺序/默认状态静态及核心通过，生产注册与真实网站未验收。全部非站源通过后才逐一真实网站。

只用sermisellek2-spec/xx-comic-ios打包和开发验证。旧a5aeec9 CI38104946234成功但IPA实际缺图标且不含本批代码；Windows无Xcode；指定账号正常Git凭据与私有仓库写入权限已核验，准备由代理运行当前CI。用户只做最终总验收，缺项集中于[USER_ITEMS](../docs/ios-parity-2.0.40/USER_ITEMS.md)。

- [当前差异及运行参考图](../docs/comparisons/2026-10-11-ios-android-current-assessment.md)
- [需求矩阵](../docs/ios-parity-2.0.40/requirements.csv)、[状态](../docs/ios-parity-2.0.40/STATUS.md)、[非站源门槛](../docs/ios-parity-2.0.40/NON_SOURCE_GATE.md)
- [阶段报告](../docs/ios-parity-2.0.40/stages/)、[实际验证和输入哈希](../docs/ios-parity-2.0.40/review-evidence/2026-10-11-staged-development/README.md)
- [历史对照](../docs/ios-parity-2.0.40/review-evidence/2026-10-11-current-comparison/historical-PARITY.md)，不作为当前PASS。
