# 缓存停用与重新启用边界修复候选

父输入d0e0d38；CI24的iPhone diskPath离线用例在清理及重开后仍有四份已知正文命中，先保留实际失败。新加两类可重复边界：停用存储后旧后端不可見、重新启用时发布待写响应。旧生产代码影响回归执行2项/4条失败断言，原日志和输入SHA保存，不当作Apple原生复现。

生产清理现在先清活动后端，再停用存储并等待，恢复原容量后再次调用归属API清理并等待实际计数稳定。没有删除缓存数据库或库根，没有伪报0。原isEmpty、物理计数及所有旧失败断言不改，剩余索引与实际正文分别记录，不继承Linux为原生通过。

新增边界加原缓存/取消/并发/文件保护影响回归12项/0失败。当前Linux全量927项/2个Apple PDF平台跳过/0失败，150.959秒，实际退出0；精确268个输入见core-full-result.json。93个原生Swift文件Release/DEBUG语法各退出0；Apple类型检查/原生/UI未验证本候选。

原生取证修两处契约：Apple的diskPath参数在iOS是默认Caches目录下的子目录名，此前测试传绝对临时路径，未枚举到实际后端文件。现创建唯一自有Caches子目录并传相对名字，directory方式仍精确URL。返回使用量的原等式断言放在诊断lookup之前，避免lookup重开索引改变取样；正文缺失、重开缺失、容量恢复和原文件不变断言全部保留。

[Apple初始化契约](https://developer.apple.com/documentation/foundation/urlcache/init(memorycapacity:diskcapacity:diskpath:))、[diskCapacity](https://developer.apple.com/documentation/foundation/urlcache/diskcapacity)、[removeAllCachedResponses](https://developer.apple.com/documentation/foundation/urlcache/removeallcachedresponses())仅支持API行为，不能替代真实验收。冻结Android清理后保留收藏摘要/详情，统计含持久化JSON长度；原版也未承诺所有元数据物理0，摘录独立归档。当前Mac原零字节失败和设置反馈仍未解决，没有因修改期望关闭门槛。

只允许指定sermisellek2-spec仓库开发CI，package_ipa=false；后续实际结果另记，不打阶段包，不要求用户试包。
