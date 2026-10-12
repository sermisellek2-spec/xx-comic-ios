# 漫画阅读范围调整与自验

2026-10-13，按用户明确指令移除文字阅读。本轮当前源码待Apple构建/UI，非站源门槛未通过，未生成总验收IPA。真实站源继续暂停，仅指定sermisellek2-spec/xx-comic-ios用于CI。

已删除文字阅读器、文字排版页/偏好消费者、WebView资源处理、文字假封面与自动跳转。新EPUB和Kindle导入拒绝纯文字及混排，不把书中正文静默丢弃；图片漫画、PDF和原漫画三模式保留。旧JSON文字位置只兼容解码/保存；旧原包和稳定身份保留，不提供文字阅读入口。Kindle默认也限定漫画，仅重建已有旧派生包时明确使用兼容转换。

当前UI声明93项/设备，其中7项真实文件的漫画EPUB/Kindle/拒绝/旧记录边界；没有以删除失败断言获得通过。原文字专属UI按范围撤销，二进制转换、取消、并发、路径保护及旧包恢复断言保留。

首轮Linux全量：917项执行、2个Apple PDF跳过、0失败，154.545秒，实际退出0（core-full-before-default-policy.log）。随后收紧Kindle默认策略并补2项真实记录测试；第一次编译发现测试辅助Data.write被错误加参数，已修复，失败原文保留（core-default-policy-compile-failure.log），当前新全量919项执行、2个Apple PDF跳过、0失败、154.815秒、实际退出0（core-full-final.log）；267个完整Core输入前后SHA一致，见validation.json。

当前88个原生/测试/Files宿主Swift文件，Release及DEBUG各语法解析退出0；build.sh bash -n退出0（native-syntax-final.log）。这不等于Apple类型检查。51当前源/50默认开启的静态核对结果保留，实站没有验收。

缓存原Mac物理占用144016字节及缓存/历史UI失败继续开放。当前公开容量/移除API候选、并行WebKit清理与隔离诊断日志待Apple实证；不扣除索引、不假报零。视觉字号、开关及安全区候选也待当前运行截图。

[范围原文](scope.json)、[当前完整核心输入](core-inputs.json)、[上一输入CI31原件](../2026-10-13-ci31-results/README.md)。[实际验证汇总](validation.json)与STATUS对应本轮最终输入。
