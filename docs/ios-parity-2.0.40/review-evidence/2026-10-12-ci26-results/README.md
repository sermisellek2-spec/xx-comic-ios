# 第26轮 Apple 缓存复验

[实际运行38238544096](https://github.com/sermisellek2-spec/xx-comic-ios/actions/runs/38238544096)，输入e5a8fa558373f2a815d5a1ed095e6d1aab7ede31；cache-diagnostics，package_ipa=false，结论failure。

Debug/Release构建成功。Mac Core934项、1项原物理归零断言失败，136.886秒：memory=0、disk=144016。iPhone15 Pro和iPad Pro11(M4)原生各29项、0失败，包括正文删除、重新打开、容量恢复、原文件保留及清理前后计数等式。没有运行UI；原件tests.json仅记录带保留附件的1项原生AI用例，不能冒充完整原生或UI清单。

隔离Mac缓存探针没有网络请求，也没有修改/删除缓存数据库。两种初始化方式各先写4份262144字节已知响应，再调用生产清理：已知响应命中4变0、正文文件1048576字节变0、三张响应表行数变0。清理后及4次延迟观测仍实际占144016字节，为Cache.db、共享内存和WAL；原返回isEmpty=false完整保留。只读拷贝快照不是原子数据库快照，不把它扩展为生产缓存全部验收。

`cache-probe.json`及`cache-original.zip`是原产物，`apple-summary.json`、原始logs ZIP、tests/manifest及6份模拟器目录文件保留。新正文清理修正已有双设备证据，但缓存物理归零与设置UI门槛尚未通过，不能改期望、伪报0或打包绕过。

本轮不包含c377af6阅读布局恢复候选。当前Linux Core927项/2个Apple PDF跳过/0失败与Mac934项/1失败是不同平台执行范围，均按原件记录。
