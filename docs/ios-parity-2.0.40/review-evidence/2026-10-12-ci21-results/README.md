# 第21轮实际Apple阅读结果

指定仓库sermisellek2-spec/xx-comic-ios，5e2eb9d，reader-modes，package_ipa=false。整体failure，不能记为日漫或完整阶段通过。

Debug/Release两SDK均通过。Mac ComicCore实际929项、1缓存失败、164.292秒；剩余disk36864，原归零断言不改。两设备各27项原生、0失败，日漫首末真实反向帧/seek/ resize两项各通过，已修复CI20页排列失败。

UI每设备16项、15通过、1失败用例；失败为testMangaTapsModeSwitchAndRelaunchPreserveTheCurrentLogicalPage，每设备4条失败断言。日漫默认左右滑动/一次翻页/跨章专用用例通过；模式返回与续读用例仍失败：普通第3页切卷轴时曾确认第3页，随后切日漫退回第1页，退出重启仍是第1页。不能把这一个失败拆成全用例通过。

10份原始附件逐个SHA匹配。原始日志ZIP与过滤API、原样manifest/tests、失败图/层级ZIP保留；原始视觉与AI ZIP在ios/build/apple-reader-ci-38223265455。完整xcresult产物11736653787在原CI保留，本次尚未下载，不声明本地已有完整xcresult。

实际SDK17.5/iOS17.5环境目录已保留在root-navigation证据中。此轮没有根底栏/面板候选、没有新增日漫旋转UI用例，不证明后续输入已通过。接续修复两个轴的页定位和布局恢复前pending位置的生命周期，见reader-mode-recovery；该修复尚待原生/全部17阅读UI实际运行。
