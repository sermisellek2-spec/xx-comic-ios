# 当前执行状态

更新：2026-10-12。固定Android2.0.40/340/696e80a44ab36b19de6f630565df32978e55a19e；保留卷轴、普通、日漫三种独立模式，旧左右手删除。51当前源、默认启用50。用户只负责总验收；开发上传和打包仅sermisellek2-spec/xx-comic-ios。

**用户最新范围：暂停真实站源验收，后续用户自行判断需要修复的站源。** 目录、开关、配置、源分组和使用fixture的发现/搜索/详情/下载仍属于非站源对齐。非站源完整自验后直接准备总验收包，不以真实网站逐项验收作为出包前置；P6保持暂停，不自动恢复。[范围原文与交付顺序](review-evidence/2026-10-12-reader-late-image-cache-active/scope-update.json)。

最新接续：CI29输入f5两SDK及实际图标检查成功，双设备原生各30项、阅读UI各19项全通过，Mac Core935项/1项物理缓存归零失败（144016字节）。[原件](review-evidence/2026-10-12-ci29-results/README.md)。当前修关于53误计为51、更新重试弹窗及历史/改名写入失败反馈；公开容量API在删除稳定后释放后端，原统计/容量/正文/重开断言保留。Linux完整928/2 Apple PDF跳过/0失败，159.624秒；完整100项UI/设备，当前Apple与视觉未通过。[候选](review-evidence/2026-10-12-settings-and-cache/README.md)。真实源继续暂停。

CI27已结束：[38242082789](https://github.com/sermisellek2-spec/xx-comic-ios/actions/runs/38242082789)，输入c377，reader-modes，未打IPA。Debug/Release成功；Mac Core934项/1物理归零失败，memory0/disk144016如实保留。iPhone原生30通过、阅读UI17通过/1失败（6条断言）；iPad原生29通过/1失败（8条缓存正文/重开断言）、阅读UI18全通过。两设备4项阅读几何和图内偏移往返UI通过，但完整模式恢复仍未关闭。[原件与诊断](review-evidence/2026-10-12-ci27-results/README.md)。

ed3修正保留图片解码后的目标位置，等待续章补足卷轴高度；缓存保持原磁盘后端活动。新增回归修正前1用例/3条断言失败，修正后13项影响检查通过。269个Core输入完整Linux928项/2个Apple PDF跳过/0失败，156.562秒。完整Apple CI28已结束，输入ed3：Mac935/1物理归零失败；双设备原生各30通过，UI各93项/6用例失败（10条断言），涉及缓存/设置参考及源选择驱动。完整原件和全部附件SHA见[CI28](review-evidence/2026-10-13-ci28-results/README.md)；原断言保留，当前候选待复验。[该输入](review-evidence/2026-10-12-reader-late-image-cache-active/README.md)。

本轮消费者核对确认旧按钮输入偏好会禁用iOS单页翻页，而底栏仅切章。当前普通/日漫采用现行点按和横滑，保留旧数据，不恢复旧输入方式入口。新增真实偏好→普通/日漫→重启UI回归，当前94项UI；93原生文件两配置仅语法通过。Core269输入未变，不重复全量核心检查；当前兼容修正尚未Apple运行，父输入CI28不能代替。[修正与审计](review-evidence/2026-10-12-current-reader-input-compatibility/README.md)。

文字排版设置原系统大列表已替换为冻结Android的底部卡片，字号、行距、背景和翻页消费者/保存保留；新增主题×方向实际操作及截图用例。当前完整95项UI/设备，93原生两配置与Bash语法通过，269 Core输入不变。Apple实际运行及文字面板视觉仍待验收。[候选证据](review-evidence/2026-10-12-text-settings-panel/README.md)。

CI26双设备正文清除通过是对应输入的历史结果；CI27出现iPad正文残留，稳定性尚未通过，不以索引字节解释正文缺陷。原物理零字节断言保持，未隐藏失败。Core、Apple、UI、Files、图像、恢复、性能和视觉分别记录，Linux结果不能代替Apple运行。

P3阅读仍待验收；P5当前完整UI、64场景视觉、Files/恢复、性能与缓存反馈门槛未通过。CI23同内容64场景真实对照及1032组件台账已保留，参考场景人工检查不能代表当前版本全部视觉通过。原93项完整UI均保留，新增后当前100项/设备；Apple运行180分钟上限，不减少范围。尚无总验收IPA。

[阶段开发方案](../IOS_2_0_40_PHASED_DEVELOPMENT.md)、[功能矩阵](requirements.csv)、[差异台账](differences.md)、[完整门槛](NON_SOURCE_GATE.md)。历史记录与旧失败保留，不作为当前输入通过证据。
