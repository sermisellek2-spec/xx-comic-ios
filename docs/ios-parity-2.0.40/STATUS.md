# 当前执行状态

更新：2026-10-13。Android冻结2.0.40 / 340 / `696e80a44ab36b19de6f630565df32978e55a19e`。用户仅最后总验收，上传及打包只用 `sermisellek2-spec/xx-comic-ios`。**当前非站源门槛未通过，尚无总验收IPA。**

按用户指令删除文字阅读/排版，保留图片漫画EPUB、PDF、Kindle；小说/图文混排新导入明确拒绝，旧JSON、历史、原包仅兼容，不误删。卷轴、普通、日漫RTL保留，旧左右手不恢复。真实站源继续暂停，不作为本次出包前置；当前51源、默认启用50（duya关）的目录和确定性流程仍在验收范围。

CI34父输入1990c84已完整成功：两SDK/图标/Release隔离，Apple Core929项零失败，iPhone及iPad各30原生和93UI全部通过，无跳过；130张实拍已保存。[完整原件与边界](review-evidence/2026-10-13-ci34-results/README.md)。该版本不包含随后设置与缓存修正，不能标当前交付通过。

最新CI37/ce0607c影响复验失败：Core929零失败、两SDK/图标/隔离通过；每设备32原生各有1失败用例，手机directory旧正文及重开仍命中，平板真实Cookie清理超时。两设备6UI各4通过、2设置参考的清理前提失败。[CI37原件](review-evidence/2026-10-13-ci37-results/README.md)。CI35/36失败原件保持，不把实际正文残留当作系统索引。

当前候选保留URLCache后端/容量，以两个公开清理接口清理实际响应；WebKit先完成无网络本地页初始化，再等待实际全数据清理回调。保留8秒失败/重试、10秒UI、正文/重开/原包/后来缓存能力断言。13项核心影响0失败，90Swift两配置仅语法解析通过；当前Linux完整Core922项/2个Apple PDF跳过/0失败/148.348秒，实际退出0且输入SHA不变；当前Apple复验待上传运行。[候选及本机记录](review-evidence/2026-10-13-cache-local-document/README.md)。

父输入64页同内容侧图已逐组件检查；8设置侧图另已查看。布局/文字/控件未发现重要缺失；iPhone横屏设置分组标题未避开安全区，当前已修并在原八场景检查中补实际横向对齐约束，须当前Apple实拍确认。所有旧图均标父输入，不算当前视觉通过。[64页审查](review-evidence/2026-10-13-current-visual/ci33-comparison/manual-component-review.json)、[设置审查](review-evidence/2026-10-13-current-visual/settings-ci36-comparison/manual-component-review.json)、[安全区修正](review-evidence/2026-10-13-settings-safe-area/README.md)。

通过当前影响复验后自动运行同版本full，复核当前64页、8设置及主屏图标；全部门槛实际通过后，使用成功full保存的Release原字节组装总验收IPA，核对图标/版本/完整资源字节与SHA，用户自行签名安装。打包工具只做语法核验，尚未实际归档/打包，不要求用户中途试包。

[阶段方案](../IOS_2_0_40_PHASED_DEVELOPMENT.md)、[需求矩阵](requirements.csv)、[差异台账](differences.md)、[完整门槛](NON_SOURCE_GATE.md)。此前状态原文与失败均保留为历史证据；详见本轮目录的historical-STATUS-before-ci37.md。
