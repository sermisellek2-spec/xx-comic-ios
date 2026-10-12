# 模型许可与描述校正

2026-10-13。实际模型来自冻结Android realesr-animevideov3-x2训练权重，现有转换保留原图与权重，不是50K随机小模型。本轮只修正旧许可文件与模型metadata中的错误BSD/旧尺寸/旧包体描述。

冻结包REAL-ESRGAN-LICENSE.txt及README明确MIT，保留Xintao Wang版权与完整条款。模型metadata改MIT；训练网络序列化字节与SHA执行前后完全相同，输入256×256、输出512×512不变；资源约2.49MB。没有新增依赖、重新生成网络或联网处理漫画。

[metadata-proof.json](metadata-proof.json)记录原/新整个模型哈希与网络不变断言。Windows只有Protobuf读取/写入成功，CoreML原生加载模块不可用的输出如实保留；不算Apple编译或推理验收。最终同版本full须编译模型并重跑全部实际推理/回退/取消/复用用例。

旧许可描述保存于historical-license-before-fix.txt，不作为当前许可说明。
