# 进度条几何与iOS缓存取证接续

日期：2026-10-12。父提交b8be2d9。完整Apple回归38190082897仍在运行，本目录不把未取得的界面/视觉记为通过。

缓存探针还证明返回值取样过早：两种构造均返回36864字节，而恢复容量后实际立即占144016字节。新增可控容量记账回归先实际失败（1项/2断言），原日志cache-accounting-before.log保留。生产清理在正常结束先恢复容量再统计，异常结束仍通过defer恢复；容量只恢复一次，所有旧物理归零/迟到响应/取消/并发/原包断言保留。

此修改后实际完整Linux903项/2个Apple PDF跳过/0失败，144.292秒，退出0；core-full-after-cache-accounting.log及core-validation-after-cache-accounting.json记录原始日志、命令与全部Core输入SHA。这是当前Core结果，配置专项中的902项是它的上一输入。尚未运行此修正的Apple检查，不能据此关闭D51。

独立诊断38190616735实际确认：iPhone和iPad的ReaderSeekGeometry各仍失败1条包含断言；原来的无障碍断言已通过。父视图273×40，slider实际frame为(-2,4,277,33)，左右各超出2pt。真实宿主窗口、原日志和全部原断言保留，不能改断言让超出区域通过。

当前生产约束按slider的真实alignmentRectInsets补偿，使完整触控frame落在父视图内；原包含/触控/无障碍断言不变，并补末页拇指的实际hitTest。依据[Apple UIView对齐矩形说明](https://developer.apple.com/documentation/uikit/uiview/alignmentrectinsets)，Auto Layout对齐内容矩形而不一定是frame，因此用控件返回值，不写死2pt。实际修复效果仍待Apple复验。

CacheMaintenanceNativeTests新增一项隔离原生用例，使用四个明确拥有的响应，覆盖2048字节/256KiB、旧diskPath/新directory构造、同目录另建实例后的响应不可命中、实际统计不减常数、容量与原包保护；零网络，观测和清理使用URLCache API，不直接写或删除数据库；结束后清除自建夹具目录。该用例不证明跨进程重启，也不取代Mac中仍失败的物理归零检查。

当前84个Swift文件（应用/原生/UI83，Files helper1）分别在Release与DEBUG解析，四次实际退出0；详细命令、输入SHA和日志见syntax-validation.json、native-syntax-current.log。此检查只是Linux语法解析。新增原生用例使计划变为25项原生/设备，UI76项保持不变。当前Core903及上一配置输入902均不能与父输入的Apple Core902混淆。
