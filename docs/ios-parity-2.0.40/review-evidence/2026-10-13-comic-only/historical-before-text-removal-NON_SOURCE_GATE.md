# 非站源完整验收门槛

2026-10-12，**未通过**。固定Android2.0.40/340/696e80a。用户只负责最后总验收；代理自主完成阶段修复和自验。

真实站源验收按用户最新指令暂停，由用户后续判断需修复哪些站源，不作为本次出包前置，也不自动恢复。当前51源、默认开启50（duya关闭）的目录、配置和确定性发现/搜索/下载流程仍须对齐。全部非站源自验完成后，仅在 sermisellek2-spec/xx-comic-ios 出总验收包。

ed3完整CI28 [38259663957](https://github.com/sermisellek2-spec/xx-comic-ios/actions/runs/38259663957)运行中，保留原93项UI/设备。部分原日志确认Debug/Release构建及两套实际产物图标元数据、PNG、Assets.car通过，完整Core、原生、UI结果尚未取得。部分日志有10MiB截断，不能当作最终结果或用于推断后续通过。

当前f5另修旧按钮偏好禁用单页交互，原有全部断言保留，新增后94项UI/设备。阅读影响CI29 [38266096867](https://github.com/sermisellek2-spec/xx-comic-ios/actions/runs/38266096867)运行中，不生成IPA。93原生文件Release/DEBUG语法通过；269个Core输入与已实际运行的Linux928项/2 Apple PDF跳过/0失败完全一致。Linux结果不能代替Apple。

文字排版设置原系统大列表已替换为冻结Android的底部卡片，字号、行距、背景和翻页消费者/保存保留；新增主题×方向实际操作及截图用例。当前完整95项UI/设备，93原生两配置与Bash语法通过，269 Core输入不变。Apple实际运行及文字面板视觉仍待验收。[候选证据](review-evidence/2026-10-12-text-settings-panel/README.md)。

最新接续：CI29输入f5两SDK及实际图标检查成功，双设备原生各30项、阅读UI各19项全通过，Mac Core935项/1项物理缓存归零失败（144016字节）。[原件](review-evidence/2026-10-12-ci29-results/README.md)。当前修关于53误计为51、更新重试弹窗及历史/改名写入失败反馈；公开容量API在删除稳定后释放后端，原统计/容量/正文/重开断言保留。Linux完整928/2 Apple PDF跳过/0失败，159.624秒；完整100项UI/设备，当前Apple与视觉未通过。[候选](review-evidence/2026-10-12-settings-and-cache/README.md)。真实源继续暂停。

| 门槛 | 状态 | 当前需要关闭的事项 |
| --- | --- | --- |
| GATE-01 全入口与消费者 | 待核对 | 11设置入口、阅读默认值/旧输入消费者及51/50目录已源码核对；全应用入口、配置与数据生命周期仍需完整对应当前运行结果 |
| GATE-02 全应用8场景视觉 | 待验收 | 64张冻结Android金标及CI23同内容对照保留；当前64张实拍、1032组件逐项问题、图标和文本/颜色/布局检查未闭合 |
| GATE-03 正常/异常/取消/恢复 | 待验收 | 当前全量UI、阅读迟到尺寸/模式/重启、旧输入兼容、缓存实际反馈、Files/下载/导入恢复待结果 |
| GATE-04 当前Apple/UI/图像/Files | 待验收 | 当前完整Core、两设备全部原生/UI、PDF/CoreML/WebKit/真实外部Files检查必须实际运行；CI28父输入不能覆盖f5修正 |
| GATE-05 性能/旧数据/恢复/Release | 待验收 | 记录当前耗时、真实内存观察、并发/文件/权限失败和恢复；最终Release无夹具/测试端点。模拟器不能证明真机峰值或系统后台配额 |
| GATE-06 全非站源通过 | 待验收 | 所有必需项来自交付代码，无开放重要缺陷；未测、失败或平台缺项不记通过 |

CI27的原失败仍保留：Mac Core实际缓存物理归零断言失败，iPad已知正文与同目录重开仍命中，iPhone三次第3页恢复失败。正文缺陷不能解释为索引字节。当前活动磁盘后端与迟到图片锚点修正必须复验；原物理归零断言、正文不可命中、容量恢复、后续可缓存与原包保护检查不删、不放宽。

当前状态以[STATUS](STATUS.md)、[功能矩阵](requirements.csv)、[差异台账](differences.md)及实际原件为准。尚无总验收IPA。[CI27原件](review-evidence/2026-10-12-ci27-results/README.md)、[ed3证据](review-evidence/2026-10-12-reader-late-image-cache-active/README.md)、[f5修正与审计](review-evidence/2026-10-12-current-reader-input-compatibility/README.md)。

旧门槛整页按原字节保存在[历史原文](review-evidence/2026-10-12-current-reader-input-compatibility/historical-NON_SOURCE_GATE.md-before-scope-cleanup.md)，哈希见[归档记录](review-evidence/2026-10-12-current-reader-input-compatibility/historical-documents.json)。其中旧“正在运行”、用例数量及站源自动推进规则不覆盖当前范围。
