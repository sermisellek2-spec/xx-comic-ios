# Android 当前共同视觉参考

2026-10-12。独立冻结副本，生产APK和527构建/源码输入不改；仅test APK提供共同数据和调用真实生产控件。没有真实网站调优。共同JSON/384×384原始PNG的SHA在每组manifest中。

当前采用android-golden-current：手机/平板×横竖×浅深8种状态，8页/种共64张实际截图；真实旋转、尺寸、每张SHA、夹具消费，以及阅读原图/关闭对照/卷轴/控件展开状态均严格核对。每组manifest留实际组件几何/文字/字体（弹窗附实际无障碍树）与readerState；provenance留设备、APK/test APK/提供器SHA和步骤。阅读控件通过冻结生产setReaderFullscreen(false,false)展开，以匹配共同视觉姿态；初始自动收控件行为仍单列P3，不能据此宣称交互通过。

保留早期数据：android-current-matrix横屏实际得到竖屏，拒绝作为完整矩阵；android-current-matrix-rotated尺寸正确，但增强请求/控件处于不同状态；android-golden-original是真原图但控件未展开。上述不继承为当前双方同状态通过。原始PNG不重绘、不裁切、不过滤；技术缩略总览只用于读图，存ignored build，不作为金标截图。

当前Android金标不是iOS验收通过。还须本次提交的Apple同宽截图、预声明系统区域/动态时间差异、真实叠图/差分及逐组件记录；不遮应用按钮、标题或文案。冻结Android日漫卡片因用户要求删除左右手映射而成为已声明的淘汰差异。
