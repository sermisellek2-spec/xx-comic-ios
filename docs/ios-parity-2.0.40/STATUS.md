# 当前执行状态

更新：2026-10-13。Android冻结2.0.40 / 340 / `696e80a44ab36b19de6f630565df32978e55a19e`。用户仅最后总验收，上传及打包只用 `sermisellek2-spec/xx-comic-ios`。**当前非站源门槛未通过，尚无总验收IPA。**

按用户指令删除文字阅读/排版，保留图片漫画EPUB、PDF、Kindle；小说/图文混排新导入明确拒绝，旧JSON、历史、原包仅兼容，不误删。卷轴、普通、日漫RTL保留，旧左右手不恢复。真实站源继续暂停，不作为本次出包前置；当前51源、默认启用50（duya关）的目录和确定性流程仍在验收范围。

CI34父输入1990c84已完整成功：两SDK/图标/Release隔离，Apple Core929项零失败，iPhone及iPad各30原生和93UI全部通过，无跳过；130张实拍已保存。[完整原件与边界](review-evidence/2026-10-13-ci34-results/README.md)。该版本不包含随后设置与缓存修正，不能标当前交付通过。

CI37/ce0607c失败原件保持：手机directory正文/重开命中，平板实际Cookie清理超时。随后CI38/7f440e7影响复验实际成功：两SDK/图标/Release隔离，Apple929核心零失败，iPhone/iPad各32原生及6UI全部通过。两个后端正文与重开均零命中，已有Cookie实际删除，八设置清理前提与横屏安全区原断言通过。[CI38原件](review-evidence/2026-10-13-ci38-results/README.md)。这不是最终完整交付结果。

缓存保留后端/容量、8秒失败/重试、10秒UI及正文/重开/原包/后来缓存断言。真实框架索引仍如实显示，没有伪造0或直接删数据库。当前Linux完整Core922项/2个Apple PDF跳过/0失败/148.348秒。Core生产此后未改。

逐入口核对发现分卷追加/排序/撤销、外部文件夹实际变更、大目录快滚、双指缩放以及进度取消的用户闭环覆盖不足，正在补验。分卷页同时改为接近冻结安卓的底部卡片列表和后台文件操作，追加可取消，确认移除不依赖已关闭页面。CI39/aa53678的分卷/同步影响已失败，原件保留并修复中；随后逐需求反查修换源严格同名/取消/失败原记录保护，补阅读换源返回、日志与实际队列闭环。最新声明36原生/111UI，95Swift两配置仅语法通过，Apple影响与最终full待验。[补验范围与边界](review-evidence/2026-10-13-volume-sync-coverage/README.md)。

父输入64页同内容侧图已逐组件检查；8设置侧图另已查看。布局/文字/控件未发现重要缺失；iPhone横屏设置分组标题未避开安全区，当前已修并在原八场景检查中补实际横向对齐约束，已在CI38八设置实拍确认；这些父图仍不代最新交付版。所有旧图均标父输入，不算当前视觉通过。[64页审查](review-evidence/2026-10-13-current-visual/ci33-comparison/manual-component-review.json)、[设置审查](review-evidence/2026-10-13-current-visual/settings-ci36-comparison/manual-component-review.json)、[安全区修正](review-evidence/2026-10-13-settings-safe-area/README.md)。

通过当前影响复验后自动运行同版本full，复核当前64页、8设置及主屏图标；全部门槛实际通过后，使用成功full保存的Release原字节组装总验收IPA，核对图标/版本/完整资源字节与SHA，用户自行签名安装。打包工具只做语法核验，尚未实际归档/打包，不要求用户中途试包。

[阶段方案](../IOS_2_0_40_PHASED_DEVELOPMENT.md)、[需求矩阵](requirements.csv)、[差异台账](differences.md)、[完整门槛](NON_SOURCE_GATE.md)。此前状态原文与失败均保留为历史证据；详见本轮目录的historical-STATUS-before-ci37.md。

[换源/日志/队列收尾](review-evidence/2026-10-13-final-user-flows/README.md) · [CI38八设置人工对照](review-evidence/2026-10-13-current-visual/settings-ci38-comparison/manual-component-review.json)。

[验证超时/重试/返回](review-evidence/2026-10-13-verification-flow/README.md)：新增本机HTTP确定性交互用例，已在CI41双设备通过；CI40仍按23e9e56原输入验23UI，不包括该接续。

分组接续D126：全部51/disabled选源、表单实际错误和关闭后呈现已修，2UI新增仅语法通过；[边界](review-evidence/2026-10-13-source-group-catalog/README.md)。

[CI41验证交互实际成功](review-evidence/2026-10-13-ci41-results/README.md)：双设备超时/重试/完成返回及复位重启已实际通过，仅影响范围。当前分组接续与[模型许可校正](review-evidence/2026-10-13-model-provenance/README.md)仍须最终同版本完整复验。

CI39恢复影响与CI40收尾影响失败原件已完整保存。CI40三失败方法已定位并本地修正：下载空态文本已绘制但容器零尺寸导致AX不可达，日志复制改为可读且不阻塞导出的页内反馈，系统分享改查真实关闭控制；换源用例补实际收起工具栏的前提，原第2页/像素/分组/重启断言不变。新增实际剪贴板脱敏原生断言；95Swift两配置仅语法通过，修复Apple复验待运行。[原失败与修正边界](review-evidence/2026-10-13-ci40-repair/README.md)

[CI42分组管理实际通过](review-evidence/2026-10-13-ci42-results/README.md)：双设备35Native/7UI及Apple929核心零失败，不代当前full。CI39原Files错匹配、fixture屏幕倍率、目录加载AX与异步定位前提已本地修正，保留原文件/章节/像素/重启断言；新增范围包括配置Files驱动回归，36Native/36UI待Apple复验。[原失败与边界](review-evidence/2026-10-13-ci39-repair/README.md)。

逐入口复查D131：阅读目录正逆序原未保存，现接同一详情偏好并补重开/详情/重启的实际顺序/当前章检查；95Swift仅语法通过，仍待Apple。[原安卓证据和改动](review-evidence/2026-10-13-directory-order/README.md)。
