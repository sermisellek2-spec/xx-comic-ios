# CI29 原件与实际结果

唯一仓库sermisellek2-spec/xx-comic-ios，[运行38266096867](https://github.com/sermisellek2-spec/xx-comic-ios/actions/runs/38266096867)，输入f5dcc5bcf16c2fa3c5d96ed557d7d91ab1f4c1da，reader-modes，整体失败，不打IPA。

Debug模拟器/Release设备SDK成功，两套实际AppIcon元数据、PNG、Assets.car验证成功。Mac Core实际935项、1项失败、125.234秒；失败仍为缓存清理返回memory=0/disk=144016未归零，原断言未改。双设备原生各30项和阅读UI各19项全部通过，包含普通/日漫手势、模式/旋转/重启、图内位置、旧按钮偏好兼容、跨章及控制条固定画布。19项影响范围不能代替完整100项UI、EPUB面板和当前视觉。

16份原生缓存记录确认两设备、两种构造方式的已知4个正文以及同目录重开均0命中，原始文件保护检查通过。iPad此前8条正文断言失败已在这个输入复验通过；记录仍如实保留144016索引占用，不能将其报告成0 B或原物理归零测试通过。当前后端关闭时机候选还需新Apple运行。

[summary.json](summary.json)包含失败原文、分类计数、16条缓存观察、产物和原件SHA。保留完整原始构建日志于[原日志ZIP](apple-build-test-original.zip)；Xcode原始结果10,258,755字节留在ios/build/ci29/xcresult-original.zip，SHA记录在summary中。附件汇总每设备20条包含1项原生AI和19项UI，不能当作20项UI；同样不按控制台恰好出现“19/30项”的行数计数，Core子套件可能同数。按实际套件及设备核验。

本运行不包含ccc文字面板或后续关于站源数/更新/历史反馈候选，不能冒充当前版本全部通过。真实站源继续暂停，非站源完整自验后再出一次总验收包。
