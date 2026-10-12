# 当前执行状态

更新：2026-10-12。固定Android2.0.40/340/696e80a44ab36b19de6f630565df32978e55a19e；保留卷轴、普通、日漫三种独立模式，旧左右手删除。当前51站源、默认启用50，先非站源完整自验、最后真实网站。用户只负责总验收，开发上传/CI仅sermisellek2-spec/xx-comic-ios，阶段不打IPA。

阅读候选c377af6正在[CI38242082789](https://github.com/sermisellek2-spec/xx-comic-ios/actions/runs/38242082789)复验，reader-modes，package_ipa=false。原始CI25证实模式切换读取旧布局：逻辑第2页实际回第1页，卷轴图内偏移被压成0。候选修显式分页帧、恢复前实际布局、reload前保留位置，以及下一章高度不足时继续恢复。18项原阅读UI断言保持，新增1项UIKit模式reload/尺寸回归；当前93 Swift文件两配置仅语法通过，Apple运行结果未返回。

已完成CI25：Debug/Release成功，Mac Core932项/1缓存失败；双设备原生各29项/0失败，根底栏20pt图标、4pt间距与居中检查通过。阅读UI各18项/16通过/2失败，各10条断言；正常日漫横滑、跨章、第3页旋转及连续阅读10项通过。两个失败为模式续读和图内偏移，不能把整个日漫模式标为通过。[原件与数值诊断](review-evidence/2026-10-12-ci25-results/README.md)。

已完成CI26：Debug/Release成功，Mac Core934项/1原物理归零失败；双设备原生各29项/0失败，正文清除、重新打开、容量恢复和原文件保护通过。本轮没有UI。隔离探针已知正文4变0、正文文件和三张响应表清空；原始磁盘统计仍144016字节，原失败与isEmpty=false保留。[原件](review-evidence/2026-10-12-ci26-results/README.md)。

当前ComicCore268个输入沿用927项完整Linux结果：2个Apple PDF跳过、0失败，150.959秒。阅读候选未改变Core输入。Linux语法/核心结果不能代替Apple构建、UI、Files、PDF、图像、恢复与性能验收。[当前候选](review-evidence/2026-10-12-reader-layout-restore/README.md)。

P3阅读仍待验收；P5完整视觉、Files/恢复、当前全量UI与缓存反馈门槛仍未通过。已保留CI23同内容64场景真实对照及1032组件台账，4个场景人工复核不能代表全部视觉通过。完整UI仍保留93项/设备，下一次完整CI给两设备顺序执行留180分钟，不减少范围。P6真实站源关闭，没有最终IPA。

[阶段开发方案](../IOS_2_0_40_PHASED_DEVELOPMENT.md)、[功能矩阵](requirements.csv)、[差异台账](differences.md)、[完整门槛](NON_SOURCE_GATE.md)。原接续状态完整保存在[历史原文](review-evidence/2026-10-12-reader-layout-restore/historical-before-ci25-STATUS.md)，不作为当前输入通过证据。
