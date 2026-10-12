# 迟到图片尺寸恢复、活动磁盘缓存与出包图标核验

2026-10-12 接续 CI27 的实际失败。保留卷轴、普通、日漫三种独立模式及旧左右手删除。用户已暂停真实站源验收，非站源完整自验后使用 sermisellek2-spec 仓库出总验收包；51当前源、50默认启用仍需对齐。

阅读器在图片解码后发现目标位置被内容高度压缩时，即使之前的 pending 已恢复，也重新保存目标章内位置；续章追加后恢复，用户主动拖动/seek仍可取消等待。原页码、往返图片Y、旋转与重启断言均保留。CI27的匹配原附件证明了这个完成顺序，修正后的Apple/UI尚未运行。

缓存新增行为模型先复现后端切换导致的正文回归：修正前1用例、3条断言失败，退出1；保持磁盘后端活动后，13项缓存影响回归退出0。模型不代表Apple私有实现，真实原生已知正文及重开检查仍须复验。原物理字节断言、实际usage与容量检查均保留，不减去索引字节。

| 本地实际检查 | 结果与边界 |
| --- | --- |
| Linux ComicCore 全量 | 928项、2个Apple PDF跳过、0失败，156.562秒，退出0；269个输入SHA在verification.json |
| Swift原生语法 | 93文件，Release/DEBUG分别退出0；不是Apple类型检查或UI运行 |
| 构建脚本/证据工具 | bash-n退出0；Python AST及workflow YAML解析通过，完整UI超时180分钟 |
| 图标核验工具契约 | 4个控制夹具案例通过；旧真实IPA缺phone/pad图标及Assets.car，按预期拒绝，退出1 |
| 当前Xcode图标产物 | 待Apple；新增Debug/Release实际Info.plist、AppIcon PNG及Assets.car检查，失败保留且继续收集独立UI证据 |

图标的控制夹具不属于构建证据。原旧IPA的SHA为 `cb18338e00e8cf9b7bb1dab1a4c639a67936ece8db1541c25b56e29aec5c984d`，它不包含当前修正。新增产物核验不证明签名、真机安装或主屏显示。

[完整输入与命令](verification.json)、[修正前失败](cache-backend-before-fix.json)、[缓存影响结果](cache-impact-after-fix.json)、[图标工具边界](app-icon-verifier-contract.json)。阶段与总验收包仍待完整Apple/UI、视觉、恢复和性能检查；不把本地通过扩为全部功能通过。
