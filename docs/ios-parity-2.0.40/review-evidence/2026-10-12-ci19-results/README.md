# 第19轮实际Apple结果

输入`c5aa922016e867d58d8d76cc8f681e5981fa3cbe`，整体failure，非站源阶段未通过，没有IPA。

第19轮编译修复已实际通过两SDK及双设备25项原生。UI38项/设备各32通过、6失败用例；iPhone11条/iPad10条失败记录。分组7项、CurrentParity12、ExternalFiles3双设备通过；iPhone站源草稿确认与双设备分类源可达仍失败，iPad文件取消失败，设置参考4项/设备缓存0断言失败。

本轮不含独立日漫恢复。

Mac Core923项/1失败/101.375秒，缓存实际保留36864字节；不能伪报0。附件290件逐项SHA核验，原始日志和失败图/树完整保留；原始视觉/增强包SHA见apple-summary。测试通过数为用例，失败断言条数分开记录。

[原CI](https://github.com/sermisellek2-spec/xx-comic-ios/actions/runs/38215339295)。后续修复和运行必须分输入记录，不继承旧结果为当前通过。
