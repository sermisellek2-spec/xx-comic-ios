# 非站源完整验收门槛

2026-10-13，**未通过**。固定Android2.0.40/340/696e80a；用户只负责最后总验收，代理自主开发、修复及阶段自验。

文字阅读/排版按用户要求移除，READER-13保留为范围排除；图片漫画EPUB/PDF/Kindle及明确拒绝小说/混排、旧JSON/原包保护仍在范围。真实站源验收继续暂停，不作为本次总包前置，门槛通过后也不自动恢复。当前目录51源/默认启用50及开关、配置、确定性搜索/验证/换源/下载流程仍自验。

| 门槛 | 状态 | 当前必需项 |
| --- | --- | --- |
| GATE-01 全入口/消费者 | 待核对 | 逐需求对应冻结入口、当前生产消费者与实际检查，不能用父93UI成功推定全部通过；已补分卷、同步、大目录、双指和进度取消，已修换源重要问题并补日志/队列/验证闭环；实际消费者证据映射仍须关闭 |
| GATE-02 视觉 | 待验收 | 当前交付版本64同内容场景、8设置、主屏图标及分卷8状态实拍；逐组件/叠图/差分，无遮挡缺项 |
| GATE-03 交互/恢复 | 待验收 | 当前全部UI双设备运行，正常、异常、重试、取消、重启/授权恢复、返回路径；新增影响范围CI39正在运行 |
| GATE-04 Apple原生 | 待验收 | 最终同版本Debug/Release SDK、完整Apple Core、双设备全部Native/UI及PDF/CoreML/WebKit/外部Files；Linux解析不代实际运行 |
| GATE-05 质量/Release | 待验收 | 实际耗时/内存及后台恢复、旧库/原文件保护、Release无fixture；模拟器与真机边界明示 |
| GATE-06 同版本交付 | 待验收 | 必需项实际全过且无重要未解决缺陷，保存同SHA已验Release原件；人工视觉通过后仅指定仓库同字节组包，核验IPA哈希/图标/未签名安装方式 |

已确认的最近运行：CI34/1990c84父full成功，Apple929核心、各设备30Native/93UI，两SDK及130实拍；不含后续缓存与新增闭环。CI38/7f440e7影响范围实际成功：Apple929核心、各设备32Native/6UI、两SDK/图标/Release隔离，8设置实拍逐张人工检查无重要视觉缺陷。URLCache两后端正文清除及同目录重开无命中，真实WebKit Cookie/重复清理完成；144016B框架索引如实保留。

当前35Native/111UI声明及94Swift两配置语法解析通过。CI39/aa53678分卷同步、CI40/23e9e56换源日志队列仅影响范围，仍在运行；本轮验证超时/重试/返回新增尚未Apple运行。各范围不生成中间IPA，不代最终full；未运行项保持待验。

历史缓存失败CI35/36/37原件及先前门槛原文保留，已由CI38影响复验关闭的正文残留/清理超时不能继续列为当前未修问题，也不能据此代最终版本通过。

[当前状态](STATUS.md) · [CI34原件](review-evidence/2026-10-13-ci34-results/README.md) · [CI38原件](review-evidence/2026-10-13-ci38-results/README.md) · [当前新增范围](review-evidence/2026-10-13-volume-sync-coverage/README.md) · [本页历史原文](review-evidence/2026-10-13-volume-sync-coverage/historical-before-current-gate.md)。

分组接续D126：全部51/disabled选源、表单实际错误和关闭后呈现已修，2UI新增仅语法通过；[边界](review-evidence/2026-10-13-source-group-catalog/README.md)。
