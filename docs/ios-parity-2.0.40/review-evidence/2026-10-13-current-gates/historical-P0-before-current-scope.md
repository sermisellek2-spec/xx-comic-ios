# P0 方案、冻结基线与验收通路

日期：2026-10-11。状态：部分核验完成，当前Apple基准待验收，完整P0未通过。

固定Android基线696e80a（2.0.40/340），iOS工作树起点1e2287c。覆盖BASE-01~05，先写[完整方案](../../IOS_2_0_40_PHASED_DEVELOPMENT.md)，再实施本批P1~P4相互独立的修正；不会将这些本地修正当作阶段通过。

Android冻结包提取到独立.reference/android-2.0.40，不使用iOS旧app副本。实际运行testDebugUnitTest assembleDebug成功退出0；安装于专用API34模拟器，启动前关闭统计并启用飞行模式，没有调用真实站源。取得设置页iPhone/平板逻辑尺寸×横竖屏×浅深色8张真实参考，保留APK哈希、字体、尺寸、主题、旋转、步骤、UI文本边界和图片SHA。首次尺寸切换回到书架的4张失败采集也保留；修复逐配置导航后8场景实际成功。

iOS新加空书架/51源/统计关闭的设置参考用例，与Android该页内容状态一致；当前尚未在Apple运行，不能当作跨端金标。其他页面共同内容提供器、逻辑宽度对齐和8场景叠图仍未完成。原已有全页面fixture及测试保留，Release无矩阵fixture。

唯一CI/打包仓库sermisellek2-spec/xx-comic-ios已写入workflow条件；已通过正常Git凭据显式选择sermisellek2-spec账号，实际核验私有仓库与写入权限，认证缺项关闭，详见[认证证据](../review-evidence/2026-10-11-apple-ci/auth-proof.json)。不向旧仓库上传，不读取旧凭据脚本。c6363d7实际SDK Debug/Release构建、核心846项和iPhone18项原生通过；首UI失败后为补宿主隔离停止。当前新增修复、完整UI/iPad及新IPA仍待验收，旧a5aeec9不可继承。

实际命令、输入哈希、失败及修复见[本轮证据](../review-evidence/2026-10-11-staged-development/README.md)。BASE-02完整入口/默认值、BASE-03共同fixture、BASE-04 Apple基准、BASE-05跨端视觉仍需完成。
