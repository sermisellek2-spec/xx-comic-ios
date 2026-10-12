# CI36 设置与缓存复验原件

指定仓库 [38298237394](https://github.com/sermisellek2-spec/xx-comic-ios/actions/runs/38298237394)，输入52ea72e61aceae8d8976f863d06c111b94d9d7a9，settings-reference，实际结论failure，不生成IPA。

两SDK构建、实际图标资源和Release无fixture隔离通过；Apple核心929项执行、0失败、128.368秒。iPhone/iPad各31项原生检查全部通过，含HTTP正文清除/原路径重开及未使用WebKit连续清理。手机6项UI中5通过、1失败用例/2断言；平板6项中4通过、2失败用例/4断言。失败仍是清理UI未在10秒内成功，出现“请重试”；不能把重试提示当清理成功。历史清空/取消/重启保留收藏双设备通过。

虽然实际导出了8张设置原图，3项拍摄用例的清理前提失败，8张不能自动记视觉通过。Windows已收完整xcresult ZIP，并仅检查归档成员/原始字节中的显式CACHE_UI标记（未发现），未用Apple工具解码，不称完成框架错误诊断。当前继续修复记录读取/删除路径，不改原正文、重开或10秒UI断言。

精确运行结果、原件大小/哈希见summary.json；截图、原始日志与xcresult保留在ios/build/ci36，源网站0联网验收。所有失败原件保留，不将父输入结果覆盖为当前通过。
