# 文件型站源的当前版本范围核对

固定Android 696e80a/2.0.40。直接从不可变Git对象检查source包及DownloadSources正式构造工厂：source包中FileSourceCapability只出现在其接口声明，没有当前源实现。MainActivity及DownloadViews虽然保留instanceof条件分支、下载协议和工作者，但当前51个注册源不会进入这一可选分支。因此不能把iOS没有文件型站源入口当成当前版本功能缺失，也不应为了旧计划新增不可达入口。

DOWNLOAD-06稳定ID保留用于追溯，改记范围核对，旧功能完整/缺失断言撤回。现有内部协议与旧记录兼容保留，不作为当前新增入口。LOCAL-01~08的ZIP/EPUB/PDF/Kindle文件导入、批量/卷管理、合法授权和阅读仍在当前功能范围。

[冻结源码证据](../review-evidence/2026-10-11-staged-development/file-source-scope-proof.json)。这项静态范围核对不是任何真实网站可用性测试，也不关闭其余下载队列/Files/后台/恢复门槛。
