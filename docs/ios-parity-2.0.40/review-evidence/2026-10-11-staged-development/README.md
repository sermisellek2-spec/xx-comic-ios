# 2026-10-11 分阶段开发证据

当前Android基线696e80a/2.0.40/340；iOS基于1e2287c未提交工作树。先完整写阶段方案，再实施P1~P4本批局部闭环。所有阶段仍有必需未跑项，非站源门槛未通过，没有新IPA。

当前源码输入SHA256：`e585a92ff10bc5342b715abe58708e4f92ad7f31fcfade0e119c4347ef33e6c0`；核心输入：`16358cbb1d923aa44898328c19be725157738dd62f7178c83c0a46dd162bae1d`。逐文件/工具链镜像记录见[inputs-sha256.json](inputs-sha256.json)，实际命令/退出码及未运行项见[validation-summary.json](validation-summary.json)。测试结束后未再修改核心或原生源码。

| 检查 | 实际结果 | 原始依据 |
| --- | --- | --- |
| 基线/目录 | 527文件及ZIP匹配；51当前=22+29，默认50且duya关闭，退出0 | baseline-verification.log、source-catalog-proof.json |
| Android独立参考构建 | testDebugUnitTest assembleDebug成功，702项/2跳过/0失败错误 | android-reference-build.log、android-reference-build-proof.json |
| 最终当前核心全量 | 827执行、2个Apple PDF跳过、0失败，134.734秒，退出0 | core-full-test.log |
| 下载位置/删除/运行器回归 | 21项、0失败，退出0；后续链接/文件类型保护包含于最终全量 | download-cancellation-tests.log |
| 独立详情反馈 | 6项、0失败，退出0，测试同一源文件，未运行UIKit | detail-feedback-tests.log |
| 原生/测试语法 | 62 Swift文件，Release与DEBUG退出0，未用Apple SDK | native-syntax.log |
| Git/元数据 | diff check退出0；截图SHA/方向、74稳定ID、51/50与任务范围核对通过 | git-diff-check.log、metadata-verification.json |

cache-config-tests、source-import-tests、bookshelf-update-tests、statistics-discovery-tests、local-deletion-tests等保存本批影响范围回归；core-full-test-before-*保留815/823/826旧快照，不能冒充当前输入。初始缓存测试调用缺try、目录URL fixture缺目录标志、尺寸切换回到书架的采集失败分别保留，定位后修复，没有降断言或删失败用例。

Android设置8张实际图及XML/尺寸/字体/主题/版本/步骤/SHA见[android-settings-matrix](android-settings-matrix/android-settings-manifest.json)。首次失败的4张保留在android-settings，未混入成功8场景。专用模拟器启动前禁用统计并启用飞行模式，没有真实网站验收；平板尺寸覆盖不是实体设备。当前iOS还没有对应运行图，不能算视觉门槛或对齐率。

范围核对：[file-source-scope-proof.json](file-source-scope-proof.json)直接读冻结Git对象，当前源包仅声明可选文件能力，没有具体实现，不新增该不可达旧入口；本地电子书导入继续在范围。目录数量通过也不证明站点可用。

必须补齐的开发：完整入口/默认值与配置消费、共同内容/逻辑宽度，以及文件提供器协调I/O和完整恢复。Apple对目录访问要求作用域、协调读写及书签恢复，当前直接路径的Linux注入权限测试不能代替这项：[Apple目录访问文档](https://developer.apple.com/documentation/uikit/providing-access-to-directories)。

当前Apple类型/原生UI/8场景视觉、Files真实授权/重启、PDF/WebKit/CoreML、后台/恢复/峰值性能、新IPA资源/主屏及51真实站源均未完成；所有未跑项明确列在JSON中。唯一仓库sermisellek2-spec/xx-comic-ios；本机Git和浏览器无可用认证，Windows无Xcode，无新上传或触发，见[ci-access-summary.json](ci-access-summary.json)。只需正常仓库认证这一个外部执行条件，不要求用户阶段试包或选择实现。

任务文件候选列表见[task-file-manifest.json](task-file-manifest.json)，未暂存/提交。四个旧凭据脚本只记录排除名称，未读取或执行；Android原工作区构建缓存未修改/清理/暂存。旧成功IPA与旧审查仍保留在上一批证据目录，不算本批通过。
