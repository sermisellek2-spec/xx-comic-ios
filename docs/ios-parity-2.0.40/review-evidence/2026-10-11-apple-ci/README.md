# 当前代码 Apple 开发验证

日期：2026-10-11。唯一仓库：`sermisellek2-spec/xx-comic-ios`，私有仓库，分支`codex/ios-port`。这是代理阶段自验，不是最终总验收或正式发布。

用户正常登录命令提示已保存账号凭据后，代理显式选择目标账号进行非交互Git访问，退出0，目标远端HEAD为a5aeec90a1d47b9670b859150cb89f78c9856fbb。API进一步确认账号sermisellek2-spec、仓库为私有、push权限为true；[auth-proof.json](auth-proof.json)记录过滤后的实际结果，不保存Token、Cookie或凭据助手原始输出。

认证缺项已关闭，无需用户重新认证。Windows没有Xcode，当前代码必须在指定仓库通过Apple SDK编译及iPhone/iPad原生运行；已取得三轮Apple实际结果，见下文；不能把认证成功或本地Linux测试记成Apple通过。

上传候选沿用上一批明确任务清单，排除四个原有凭据脚本和Android构建缓存。本批核验既有生产与测试输入未变化：代码输入SHA-256 `7318f82561ae4aa3dccb60d6a3e95c08bbfc8704cc3e14269165ebe51ab62824`，ComicCore输入`ec30b3b9b32ef78bef0fa9a27be49b34d5dac3c5c5bf9c982ce7c4d2a1cd9ab3`。对应Linux838项执行/2个Apple PDF跳过/0失败与63源码两配置语法证据保留在[前批目录](../2026-10-11-download-files/README.md)。

读取CI使用新的`tools/ios-ci.py`，仅调用指定仓库的只读API；凭据由正常Git Credential Manager提供并只驻留进程内存，产物跳转请求不携带认证头。不得运行或读取旧凭据脚本。

完整暂存差分检查返回2，原因仅为保留原始诊断日志的尾空格及历史STATUS末尾空行；源码与当前文档范围检查返回0。[pre-upload-check.json](pre-upload-check.json)逐条记录，不修改历史日志来伪装无诊断。所有历史日志按原字节纳入开发验证提交。

开发验证提交792b599已仅推送到指定仓库；[首轮CI38136187992](https://github.com/sermisellek2-spec/xx-comic-ios/actions/runs/38136187992)实际失败：Apple核心845项执行、8条失败，62.838秒；未进入UIKit构建，无新IPA。下载目录枚举采用原路径长度截取相对路径，无法可靠处理Darwin枚举URL形态，已改为同一规范根下的路径组件及归属校验，保留原8条失败涉及的断言与未知文件保护，并补一个真文件URL形式用例。相关50项Linux回归通过、脚本语法/工作差分通过；Darwin修复在次轮Apple核心通过；完整UI仍未通过。见[repair-1-summary.json](repair-1-summary.json)和原始失败日志。构建脚本前移Debug/Release SDK编译，完整核心和两设备原生/UI测试仍为打包前必需项。

修复提交c6363d7已仅推送指定仓库。[次轮38136705260](https://github.com/sermisellek2-spec/xx-comic-ios/actions/runs/38136705260)的实际结果：Debug模拟器SDK与Release设备SDK构建成功，Apple核心846项0失败/80.435秒，iPhone15 Pro iOS17.4原生18项0失败/3.615秒。包含51生产注册/配置2项、封面3项、反馈6项、离线解码1项和增强6项；CoreML实际输出neural 384→768、4tiles/2231.085ms。日志内前后驻留内存不是峰值，不关闭性能门槛。

首个UI测试失败，书架标题两个按钮未分别暴露。检查又发现原生XCTest宿主可能启动正式应用及统计；代理为补隔离停止该轮，结论是cancelled，iPad/完整UI未运行、没有新IPA，不能记为CI成功。旧宿主是否已发生产启动请求无法由现有日志确认。[repair-2-summary.json](repair-2-summary.json)、实际run JSON及原始日志保留证据。当前补Debug测试宿主/统计隔离及独立按钮访问，原UI断言保留，新增宿主测试。

入口审计还确认旧增强整数需按Android只接受0/1/2；本地相关16项回归0失败/退出0。初次极值断言失败日志保留：Foundation对Int.max的integer存取返回已发生改变，修为比较load前后真实NSNumber，全部极值/回退关闭断言保留。64个原生/测试文件Release/DEBUG语法通过，仅语法不能代替新增修复的Apple结果。LOCAL04/07/08确定缺实现见[入口审计](../../entry-consumer-audit.md)，继续P4开发而不是平台差异。

[第三轮38138407173](https://github.com/sermisellek2-spec/xx-comic-ios/actions/runs/38138407173)已实际完成，结论failure而非取消。9b1d4a2两配置SDK、Apple核心847/0失败/71.902秒、iPhone/iPad原生各19/0失败通过；测试宿主隔离验证通过。两设备UI各49项/51条失败，日志按断言条数统计不能当失败用例数；无IPA。完整原始日志ZIP及SHA保留于ios/build/apple-ci-38138407173；[筛选原日志](run-38138407173-summary.log)及[结果JSON](repair-3-summary.json)保留全部UI错误行和版本关联。

取得设置8真实参考及双设备CoreML实际输入/输出/指标。横屏原像素竖向但EXIF=8，按显示方向为横屏，原文件不变，[方向核验](settings-matrix/orientation-proof.json)通过；此前仅按原尺寸判断方向的人工判断已纠正。设置参考/cache状态不同且留白/字体/右值对齐仍有差异，完整视觉门槛不通过。

当前修复独立导航项、批量恢复/取消/失败再选择、同步实际反馈与书签回滚，详见[接续证据](../2026-10-11-import-recovery/README.md)。新的foundation-import范围仅做当前阶段原生自验，不生成/上传IPA；全部其他原测试保留，full范围仍需全部运行成功，P5及真实站源顺序不变。

[第四轮38147326917](https://github.com/sermisellek2-spec/xx-comic-ios/actions/runs/38147326917)实际failure。f4eaf93两配置SDK、Apple853项/0失败/71.174秒、两设备原生各19通过；部分范围UI各7执行/3条失败。我的书架/阅读偏好/未读/切列表及部分恢复重启通过，其他批量UI仍在本地标题失败。当前改应用内容区真实标题按钮；系统导航左项仅在有空间时显示见[Apple UINavigationItem](https://developer.apple.com/documentation/uikit/uinavigationitem)。[repair-4-summary.json](repair-4-summary.json)记录实际版本、范围、错误、条数和原日志SHA。

下一轮默认full包含全部UI，并导出实际失败PNG/逐用例状态；package_ipa显式开关默认false，只有最终全部自验后才启用。不生成IPA不改变完整测试门槛，不提前连接真实源。
