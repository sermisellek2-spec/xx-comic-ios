# 当前逐组件修正与环境候选

基于冻结Android696e80a及第17轮852真实iOS输入。`ci17-component-review.json`登记32组手机真实对照的SHA和开放差异；旧图不证明后续候选通过，iPad32组因尺寸不符仍拒绝。没有隐藏应用内容或拉伸原图。选中文字、当前章、目录卡片、收藏像素、状态栏、安全区及站源说明的生产修复属于63c2af2之后的新输入，尚未取得当前Apple截图。

当前90个原生Swift文件（前两次89文件仅语法记录已保留）Release/DEBUG仅语法各退出0，build.sh bash语法退出0；Core输入未改变，922项/2个Apple PDF跳过/0失败仍对应日漫提交。完整Core的Mac缓存失败不能继承Linux通过关闭。

模拟器选择修正基于原日志：Xcode15.4/SDK17.5，设备iPhone15 Pro和M4 iPad均实际运行17.4。当前选择与SDK主次版本匹配并保存完整原目录；6项合成目录检查通过，实际Apple目录尚未运行。不预先断定iPad尺寸的全部原因。Apple官方[Xcode15.4说明](https://developer.apple.com/documentation/xcode-release-notes/xcode-15_4-release-notes)确认SDK17.5；真实新窗口/场景/截图仍必须同时验证。

收藏原图保持冻结1254×1254 PNG不改；使用[Apple后台缩略API](https://developer.apple.com/documentation/uikit/uiimage/preparethumbnail(of:completionhandler:))按44pt×屏幕密度准备，代次保护页面离开/收藏切换，UI回主线程。

后续configuration-files保留原测试并增加阅读固定画布两项和底栏两项，计划27原生/46 UI每设备；必须以真实结果核对实际数量，不以计划计通过。第19轮c5只覆盖其输入、第20轮63覆盖日漫，不包含本候选。所有CI仅指定仓库，package_ipa=false。

开放项：缓存物理归零、横屏根底栏纵排、横屏设置面板高度、完整组件量测与iPad尺寸。当前阶段未通过，P6关闭，无阶段安装包。

第19/20轮已结束，原始结果在各ci19/ci20-results目录，均整体failure。第20轮证明原RTL语义布局无效，接续改成显式反向单页帧/查询，原核心和UI断言不改；真实原生fixture改为配置生产方向属性。第19轮原图/树证明站源网格没移动、手机换源按钮消失、iPad取消在系统侧栏，当前修滚动取消/固定宽度及驱动真实定位。当前90文件两配置仅语法通过，后续Apple尚未运行。
