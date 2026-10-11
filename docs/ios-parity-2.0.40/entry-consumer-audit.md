# 非站源入口与实际消费者审计

日期：2026-10-11。冻结Android696e80a；iOS检查9b1d4a2及当前修复。只核对确定性流程，不调真实网站。下列缺项进入P4开发，不能归为iOS平台限制。

| 需求 | 已确认实际调用链 | 结论 / 下一步 |
| --- | --- | --- |
| LOCAL-04 批量取消/重启恢复 | 书架checkPendingBatchSession已有“选择文件恢复”，但调用pickBatchImport→beginBatchImport→worker.execute→session.create；已有未完成会话时create抛unfinishedBatch。服务resumeSession没有UI调用者，跨启动原URL也不等于授权 | 发现时缺实现，当前已补恢复原会话/稳定身份、重选授权匹配/歧义与失败重试、取消持久化；核心通过，4新UI待Apple |
| LOCAL-07 文件夹直接索引与重新授权 | frozen local/LocalImporter.java直接索引原文件夹；iOS linkFolder→importFolderCoordinated→prepareFolderFiles复制全部图片并做全内容指纹，虽UI称“关联并索引”。书签存储已存在，但关联文件夹无重授权入口 | 待实现。用合法持续授权索引原文件并在读图时协调访问；区别拥有副本和外部索引，增加失权后重选并验证同一文件夹的入口 |
| LOCAL-08 同步与失败反馈 | syncAllFoldersTapped忽略结果中的error后提示全部完成；解除关联try?后总显示成功；FolderBookmarkStore.save/remove先改内存再落盘，无失败回滚 | 待实现。逐项汇总失败并提供重试，解除关联失败保留记录/反馈，持久化原子成功后发布内存状态；验证新增/删除/改名与前后台触发 |
| READER-09 增强旧偏好 | 冻结MainActivity仅接受1/2增强模式，其余为关闭；iOS原来将原始整数传给设置分段控件 | 已本地修复，待Apple回归。读取规范值且不改写旧原始数据，正常0/1/2落盘；16项相关Linux回归通过 |
| VIS-03/SHELF-01 书架标题按钮 | c6363d7 Apple UI实际仅看到合并的无名按钮，不能独立找到“我的书架” | 前次容器修复实际仍失败；当前改标准独立导航项，原UI断言保留，待当前Apple运行 |
| BASE-04 测试隔离 | UI --ui-testing已有隔离；原生XCTest宿主未带此参数，可能启动正式书架/统计 | 已本地补Debug测试宿主及上报双层隔离，Release正常行为保留；新增原生宿主断言。不能断言旧轮未曾发送生产启动请求 |

源码定位：ios/XXComic/ComicGridViewController.swift、LocalStorageViewController.swift；ios/ComicCore/Sources/ComicCore/BatchImportWorker.swift、BatchImportSession.swift、LocalFolderSync.swift、FolderBookmarkStore.swift、LocalLibrary.swift、LocalImportPreparation.swift。冻结Android通过Git对象/独立参考副本读取，不能取iOS checkout旧app副本。

本表仅是已发现的明确缺项及修复，尚未代表全入口审计完成。功能矩阵仍未通过；共同fixture、全应用视觉与生命周期按阶段方案继续。

最新接续：9b1d4a2第三轮实际完成为failure，SDK两配置/Apple核心847及两设备原生各19通过；UI各49项/51条失败，无新IPA。设置8参考真实取得，横屏按EXIF显示方向核验通过；缓存状态不同，完整视觉门槛未过。书架改独立导航项，LOCAL04恢复/取消/重试与LOCAL08失败反馈/书签回滚已接，当前Linux全量846项/2跳过/0失败，66源码仅语法通过；新修复待Apple阶段范围运行。目录直接索引/重授权仍待实现，非站源门槛未通过。见[新恢复证据](review-evidence/2026-10-11-import-recovery/README.md)及[第三轮实际结果](review-evidence/2026-10-11-apple-ci/repair-3-summary.json)。
