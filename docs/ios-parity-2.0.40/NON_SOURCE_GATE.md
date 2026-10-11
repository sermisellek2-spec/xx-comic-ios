# 非站源完整验收门槛

更新：2026-10-11。**未通过。不进入真实站源阶段，不开放最终总验收。** 最新已运行快照c6363d7，当前又补宿主隔离/书架按钮/阅读增强偏好；旧a5aeec9 CI/IPA不能代替本批。

| 门槛 | 状态 | 未关闭事项 |
| --- | --- | --- |
| GATE-01 全入口与消费者 | 待核对 | 本批局部接线已修；新确认批量恢复未接resume、关联文件夹仍全量复制、同步错误假成功，见entry-consumer-audit.md；完整入口/配置消费者继续审计 |
| GATE-02 全应用8场景视觉 | 待验收 | Android设置8参考含元数据；当前iOS及其他页面共同内容/同宽截图、叠图和组件差分缺失 |
| GATE-03 正常/异常/取消/恢复 | 待验收 | Apple首个UI发现书架按钮不可单独访问；已修待重跑。完整设置/发现/详情/阅读/删除/目录/恢复仍未完成 |
| GATE-04 当前Apple/UI/图像/Files | 待验收 | c6363d7两配置Apple SDK构建、核心846项0失败及iPhone18原生项通过；新增修复待重跑，完整UI/iPad/Files未完成 |
| GATE-05 性能/旧数据/恢复/Release | 待验收 | 缓存/统计线程本地已修，仍缺Apple峰值/后台/Files/整套恢复和Release运行证据 |
| GATE-06 全非站源通过 | 待验收 | 以上必需项未齐，不得宣布PASS |

实际运行：冻结527文件/ZIP及51源默认50审计；独立Android702项、2跳过、0失败；前批Linux838项、2个Apple PDF跳过、0失败。最新c6363d7 Apple核心846项0失败/80.435秒、Debug/Release SDK构建成功、iPhone18原生项0失败/3.615秒；首个UI失败且该轮主动停止，未取得iPad或新IPA。当前新增修复本地偏好16项及64源码两配置语法通过，不能替代下一轮Apple结果。Linux注入协调/权限接口不证明Files持续授权。见[Apple证据](review-evidence/2026-10-11-apple-ci/README.md)。

SOURCE-01目录/ID/开关/排序属于P2前段；SOURCE-02~04真实网站最后P6。阶段报告、[requirements.csv](requirements.csv)、[差异台账](differences.md)和[本轮证据](review-evidence/2026-10-11-staged-development/README.md)共同记录，历史67全绿和零重要缺陷不继承。
