# 第22轮配置、Files及视觉实际结果

输入5e2eb9da3b5236c19bac906165db7563cc6045eb，[CI38223827364](https://github.com/sermisellek2-spec/xx-comic-ios/actions/runs/38223827364)，configuration-files、package_ipa=false。2026-10-12 09:42:56 UTC结束，结论failure；不是本轮位置恢复/根导航候选的通过证据。

Debug、Release和FilesFixtureHost构建成功；Mac Core929项、1缓存失败、136.494秒，实际磁盘36864字节。双设备27原生均0失败；UI各46项、40通过、6失败用例、13条断言。失败为日漫返回/续读、催漫画按钮不可达、四个设置空缓存场景。原0 B及页码断言保留。分组7、搜索/详情/下载12、ExternalFiles3、SourceConfigFiles5及阅读画布2均双设备通过；其他通过项逐条见原tests.json。

原SDK17.5、两设备实际iOS17.5；五个原环境输入SHA均核对。原件290条附件SHA全部核对，原始日志ZIP、失败图/树ZIP及原manifest/tests保存。386559257字节xcresult仍在CI产物11739245101，未声称已下载到本机。完整视觉及AI原ZIP保存在ios/build，下载记录保存其SHA。

冻结Android screen-viewport-3与此次原图生成64/64同内容、同逻辑窗口对照，命令退出0，没有缺图/尺寸拒绝；逐组件仍待检查，视觉门槛false。结果在../2026-10-12-current-visual/ci22-comparison/comparison.json；不能用5e2的图验证后续根底栏及设置高度修正。

实际读取催漫画失败图/树：站源位于滚动窗口下方，而拖动后窗口仍在首行。源码确认SourceOptionScrollView接在历史及横向分组上，filter.options仍为普通UIScrollView。新候选补实际容器接线，原可达/选择/搜索断言不变。日漫D99修正另在ca68ef8的CI38230280027复验。

非站源门槛未通过，不进入真实网站，不生成IPA。
