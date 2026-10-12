# 第24轮阅读验收原件

输入 `ca68ef87364986f1bdbcf26a29d5d01dde8b4bb3`，指定仓库 [Actions 38230280027](https://github.com/sermisellek2-spec/xx-comic-ios/actions/runs/38230280027)，实际结论 failure，未生成IPA。

Debug、Release编译成功；Mac Core929项/1缓存失败，136.844秒。原生各29项：iPhone27通过/2失败用例/34条断言，iPad28通过/1失败用例/36条断言。日漫首末帧、resize和卷轴切水平双轴恢复三项均双设备通过；根底栏几何仍失败。

阅读UI各17项/16通过/1失败用例/8条断言。默认日漫横滑、跨章及新增第3页横屏再回竖屏实际通过。模式切换用例仍失败：普通页2右点后保持页2；切卷轴仍页2，切日漫和重启变页1。不能把双轴/pending候选标为已解决，也不降低原页3断言。

缓存出现更严重的iPhone原生失败：diskPath清理后四个已知响应正文仍可读，重开仍有命中；不是仅索引占用。原始 `CACHE_NATIVE_PROBE` 保存为JSON，物理计数和保留正文都待修；iPad该用例通过不能覆盖iPhone失败。

本目录保存原始日志ZIP、下载字节数/SHA、原始测试/截图清单及六份模拟器目录。10个附件SHA逐个核对；真实失败图在 `ios/build/ci24-v/`，未下载xcresult ZIP。6a7804e同图偏移修正及后续诊断不包含在本输入，Apple仍待运行。
