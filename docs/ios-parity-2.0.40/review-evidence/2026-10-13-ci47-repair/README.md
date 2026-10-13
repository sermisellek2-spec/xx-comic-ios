# CI47 原生用例编译修复

2026-10-13。[CI47](https://github.com/sermisellek2-spec/xx-comic-ios/actions/runs/38325901845) / 83ef152 实际失败。两种SDK与Apple932核心成功，但新FloatingImportBubbleTests第32行混合整数字面量/Double的XCTAssertEqual表达式触发Swift约束求解超时；两设备测试均在编译阶段取消，Native/UI未运行，未归档已验Release或IPA。

原本 `(200 - 16) / (852.0 - 54 - 20 - 16)` 拆成明确Double可用高度、期望比例，计算与0.0001精度保持。生产代码和ComicCore未改；Linux925/2 Apple PDF跳过/0失败的结果仍仅解释该核心输入，不重复无影响测试。受影响原生文件两配置语法实际退出0，下一同版本完整Apple复验待运行。

[具体原诊断](failure-diagnostics.json) · [实际运行失败/步骤](run-completed.json) · [本机输入/语法](syntax-proof.json) · [完整原日志ZIP哈希](logs-download.json)。完整原日志存于ios/build/ci47/original-logs.zip，不编辑或覆盖。
