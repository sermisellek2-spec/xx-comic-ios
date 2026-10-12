# 当前执行状态

更新：2026-10-13。Android固定2.0.40/340/696e80a44ab36b19de6f630565df32978e55a19e；iOS在codex/ios-port。用户只做最后总验收，开发上传/打包仅sermisellek2-spec/xx-comic-ios。**非站源完整门槛尚未通过，尚无当前总验收IPA。**

用户最新范围：移除文字阅读及排版功能。当前已删除专属页面、设置、偏好消费者、资源处理与自动跳转；保留图片漫画EPUB/PDF/Kindle。小说、图文混排新导入明确拒绝，旧JSON/历史/原包保留兼容。READER-13记为“用户移除”，不计入当前功能门槛。[范围与证据](review-evidence/2026-10-13-comic-only/README.md)。卷轴、普通、日漫RTL继续保留，旧左右手不恢复。

真实站源验收继续暂停，后续由用户判断需修哪些源，不自动恢复，不作为本次出包前置。51当前源、默认开启50（duya关闭）的目录/顺序/开关和确定性发现、搜索、验证、换源、配置及下载流程仍须自验。

本轮首个Linux全量917项执行/2个Apple PDF跳过/0失败、154.545秒、实际退出0。之后Kindle默认策略再收紧并增加2项真实输入测试，当前最新Linux全量919项/2个Apple PDF跳过/0失败、154.815秒、实际退出0，267个完整Core输入前后SHA一致。88个原生Swift文件Release/DEBUG仅语法解析通过，Bash语法通过。当前完整UI声明93项/设备，Apple运行及视觉待验收。

上一输入9991044的CI31已完整失败：两SDK、实际图标及Release隔离通过；Mac Core935项/1物理缓存归零失败（144016字节）；双设备原生各30通过；每设备15UI中9通过/6用例失败，涉及缓存清理反馈、历史初始展示和4项设置参考。[实际结果](review-evidence/2026-10-13-ci31-results/README.md)。当前文字删除、缓存API/并行清理、历史日志、字号/开关/安全区候选尚未Apple运行，不以父输入结果替代。

下一步：仅指定仓库跑当前两SDK/完整Core/原生及漫画边界、缓存/历史影响UI；根据真实失败继续修复。然后跑当前完整93UI/设备、64场景视觉及Files/恢复/图像检查，闭合所有非站源门槛后再打最终包。真实网站仍暂停，中途不要求用户试包。

[阶段方案](../IOS_2_0_40_PHASED_DEVELOPMENT.md)、[功能矩阵](requirements.csv)、[差异](differences.md)、[完整门槛](NON_SOURCE_GATE.md)。旧文字范围及当时执行数字的整页原件见[历史记录](review-evidence/2026-10-13-comic-only/historical-before-text-removal-STATUS.md)，不覆盖当前范围。
