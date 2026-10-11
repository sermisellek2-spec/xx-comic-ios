# 当前代码 Apple 开发验证

日期：2026-10-11。唯一仓库：`sermisellek2-spec/xx-comic-ios`，私有仓库，分支`codex/ios-port`。这是代理阶段自验，不是最终总验收或正式发布。

用户正常登录命令提示已保存账号凭据后，代理显式选择目标账号进行非交互Git访问，退出0，目标远端HEAD为a5aeec90a1d47b9670b859150cb89f78c9856fbb。API进一步确认账号sermisellek2-spec、仓库为私有、push权限为true；[auth-proof.json](auth-proof.json)记录过滤后的实际结果，不保存Token、Cookie或凭据助手原始输出。

认证缺项已关闭，无需用户重新认证。Windows没有Xcode，当前代码必须在指定仓库通过Apple SDK编译及iPhone/iPad原生运行；CI结果尚未取得，不能把认证成功或本地Linux测试记成Apple通过。

上传候选沿用上一批明确任务清单，排除四个原有凭据脚本和Android构建缓存。本批核验既有生产与测试输入未变化：代码输入SHA-256 `7318f82561ae4aa3dccb60d6a3e95c08bbfc8704cc3e14269165ebe51ab62824`，ComicCore输入`ec30b3b9b32ef78bef0fa9a27be49b34d5dac3c5c5bf9c982ce7c4d2a1cd9ab3`。对应Linux838项执行/2个Apple PDF跳过/0失败与63源码两配置语法证据保留在[前批目录](../2026-10-11-download-files/README.md)。

读取CI使用新的`tools/ios-ci.py`，仅调用指定仓库的只读API；凭据由正常Git Credential Manager提供并只驻留进程内存，产物跳转请求不携带认证头。不得运行或读取旧凭据脚本。

完整暂存差分检查返回2，原因仅为保留原始诊断日志的尾空格及历史STATUS末尾空行；源码与当前文档范围检查返回0。[pre-upload-check.json](pre-upload-check.json)逐条记录，不修改历史日志来伪装无诊断。所有历史日志按原字节纳入开发验证提交。
