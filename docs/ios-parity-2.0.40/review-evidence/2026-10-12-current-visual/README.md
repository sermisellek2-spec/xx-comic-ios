# Android 当前共同视觉参考

2026-10-12。独立冻结副本，生产APK和527构建/源码输入不改；仅test APK提供共同数据和调用真实生产控件。没有真实网站调优。共同JSON/384×384原始PNG的SHA在每组manifest中。

此前android-golden-current包含手机/平板×横竖×浅深8种状态，8页/种共64张实际截图；真实旋转、尺寸、每张SHA、夹具消费，以及阅读原图/关闭对照/卷轴/控件展开状态严格核对。新增检查发现其View组件矩形为根视图坐标，弹窗无障碍矩形为屏幕坐标；窗口偏移未记录，不能直接拿旧组件坐标与iOS比较。当前保留这批原图/metadata作为历史，重新采集screen-viewport版本，新增真实屏幕矩形、窗口位置和实际应用内容宽度验证，避免只凭全屏尺寸宣称同宽。

当前采用android-golden-screen-viewport-3，完整采集退出0、64张实际PNG；每个场景的真实decor屏幕矩形与其全屏宽度一致、组件为屏幕坐标，全部SHA及原图/卷轴/关闭对照/展开控件核验。隔离Nexus9模拟器按8组真实逻辑尺寸与密度配置，避免旧Pixel模拟器的横屏缺口挤窄内容。冻结527输入和生产APK哈希再次全匹配。详见[实际结果](screen-coordinate-proof-3.json)及逐组manifest/provenance。

采集前的失败保留：第一次构建因进程SDK变量冲突失败；后续测试APK虽构建成功但注册的是原ReaderInstrumentation，screen-viewport第一尝试未取得任何参考图。最终通过独立Gradle init仅改测试runner，冻结Gradle/manifest不改；用于实际构建的init和五次原始日志保留。第一尝试不能算采集通过；受影响旧资料不删除。

阅读控件通过冻结生产setReaderFullscreen(false,false)展开，以匹配共同视觉姿态；收控件的真实滚动/翻页触发和固定画布仍单列P3（重新核对冻结源码后撤回初始自动隐藏推断），不能据此宣称交互通过。[Android坐标契约](https://developer.android.com/reference/android/view/View.html#getGlobalVisibleRect(android.graphics.Rect,android.graphics.Point))说明根坐标不等于屏幕坐标。新采集器加真实根窗口屏幕偏移，弹窗仍直接使用其屏幕矩形。手机实际密度3，平板2；逐组manifest使用各自实值。

保留早期数据：android-current-matrix横屏实际得到竖屏，拒绝作为完整矩阵；android-current-matrix-rotated尺寸正确，但增强请求/控件处于不同状态；android-golden-original是真原图但控件未展开。上述不继承为当前双方同状态通过。原始PNG不重绘、不裁切、不过滤；技术缩略总览只用于读图，存ignored build，不作为金标截图。

当前Android金标不是iOS验收通过。还须本次提交的Apple同宽截图、预声明系统区域/动态时间差异、真实叠图/差分及逐组件记录；不遮应用按钮、标题或文案。按用户2026-10-12纠正范围，日漫卡片与独立右向左模式保留；此前连带淘汰声明撤回，旧左右手设置仍移除。当前候选已恢复日漫，等待对应Apple运行，不能用旧图判为通过。

第二次screen-viewport-2虽采集退出0且几何/哈希有效，人工看图发现16张弹窗被系统首次全屏帮助遮挡，已拒绝作为当前金标。原图完整归档[原包](android-screen-viewport-2-rejected.zip)，SHA与拒绝清单见[拒绝记录](screen-viewport-2-overlay-rejection.json)。第三次按真实系统按钮关闭帮助后重采64张，全部活动窗口com.xxcomic、无帮助遮挡，不修改冻结生产界面。

五次原始构建日志保留[完整ZIP](component-coordinate-build-logs-original.zip)，成员SHA见[归档记录](build-log-archive-proof.json)。原Gradle输出含行末空格，原字节不改；未将原始输出的排版噪声改写成成功日志。当前第三组元数据按原字节入Git，避免Windows自动换行转换使跨机器SHA失效。
