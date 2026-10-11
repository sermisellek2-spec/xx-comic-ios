# 非站源完整验收门槛

最新第五轮e29824a完整范围CI在Debug SDK编译失败：SettingsViewController的leastNormalMagnitude类型歧义；Release、核心、两设备原生/UI均未运行，不能继承第四轮结果为该版本通过。已显式改为CGFloat，并补失败PNG/逐用例JSON上传路径，接下来重跑完整Apple自验。package_ipa仍为false，不生成IPA；非站源及真实51源完整门槛仍未通过。 [第五轮实际记录](review-evidence/2026-10-11-apple-ci/repair-5-summary.json)。下文历史结果仅对应各自提交。

更新：2026-10-11。**未通过。不进入真实站源阶段，不开放最终总验收。** 此前完整UI快照9b1d4a2，最新部分范围f4eaf93仍失败；当前完整UI待Apple复验，旧成功IPA不能代替。

| 门槛 | 状态 | 未关闭事项 |
| --- | --- | --- |
| GATE-01 全入口与消费者 | 待核对 | 批量恢复已接原会话；直接索引/重新授权、同步完整生命周期及全配置消费者仍未完成 |
| GATE-02 全应用8场景视觉 | 待验收 | 双方设置8参考取得，iOS方向按EXIF正确；缓存状态不同且间距/文字对齐有差异。其他页面共同内容/宽度、叠图与逐组件记录仍缺 |
| GATE-03 正常/异常/取消/恢复 | 待验收 | 第三轮书架访问、下载目录相关及空结果源tab仍失败；当前标准导航项与4项批量恢复UI待复验，完整闭环未通过 |
| GATE-04 当前Apple/UI/图像/Files | 待验收 | 9b1d4a2两配置SDK、核心847及两设备原生各19通过；完整UI各49执行/51条失败；新修复及Files/后台未完整验收 |
| GATE-05 性能/旧数据/恢复/Release | 待验收 | 缓存/统计线程与恢复本地回归已修，仍缺Apple峰值/后台/Files/整套恢复和Release运行证据 |
| GATE-06 全非站源通过 | 待验收 | 必需项未齐，不得宣布PASS |

实际运行见[第三轮结果](review-evidence/2026-10-11-apple-ci/repair-3-summary.json)和[当前新增修复证据](review-evidence/2026-10-11-import-recovery/README.md)。当前Linux846项执行、2个Apple PDF跳过、0失败，以及66源码两配置语法通过不能替代新增原生验收。阶段foundation-import只验证当前导航/书架/导入范围，不生成IPA；full仍包含所有原生/UI用例，最终还需全部视觉、Files和恢复等检查。

SOURCE-01目录/ID/开关/排序属于P2前段；SOURCE-02~04真实网站最后P6。完整范围通过之前，sources.csv当前51源均后置；历史全绿不继承。
