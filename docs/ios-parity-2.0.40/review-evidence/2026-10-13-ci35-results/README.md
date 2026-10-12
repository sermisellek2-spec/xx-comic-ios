# 设置参考复验原件

CI35（38293643264）实际输入1006ec672def792f7659f1d1fc1777c4272bc411，settings-reference范围，不生成IPA。两SDK、实际图标和Release隔离通过；Apple Core929项0失败/167.340秒。手机30原生全部通过，iPad30原生有1用例8条失败断言：diskPath缓存正文清理后及同路径重开各4项仍命中，不能把真实残留当成系统管理文件。

每设备6项UI：手机2通过、4失败用例/8断言，iPad3通过、3失败用例/6断言。历史取消、清空、重启保留收藏两设备通过；其余失败集中在清理反馈10秒未完成、按钮仍禁用。3张设置参考已实际拍出，其余未到拍摄点，不能当作8张完整视觉验收。

summary.json包含原始完整Actions日志ZIP、解出的未改动构建日志、visual ZIP及xcresult ZIP的本机路径、大小和SHA。完整xcresult归档已下载，内部两个tar.gz的原manifest也实际读取；未在Windows解析Apple结果对象，不称完整诊断分析已通过。原失败树/截图位于ios/build/ci35/visual-extracted，保留原件。

后续候选减少URLCache异步数据库反复清理和磁盘后端重置，并为无已加载页面的WebKit清理保持上下文及超时失败出口。原正文/重开断言及10秒UI完成检查保持，必须重新在Apple运行；本记录永远保留为失败历史。
