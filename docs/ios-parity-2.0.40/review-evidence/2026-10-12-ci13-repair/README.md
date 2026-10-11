# 第十三轮完整 Apple 结果与接续修复

日期：2026-10-12。[实际运行](https://github.com/sermisellek2-spec/xx-comic-ios/actions/runs/38178699287)，输入 `49446de7480c2405bcfaae4b2f389223d6e69998`，结论 failure，未生成 IPA。该轮不含后续下载调度、记录保护、配置消费者修复。

Debug/Release SDK 构建成功，独立 Files 辅助应用构建和两设备安装成功。Apple 核心884项/1失败，140.718秒；iPhone/iPad 原生各20项/0失败。两设备完整 UI 均跑完74项：iPhone14个失败用例/21条失败断言，1981.060秒；iPad13个/18条，2144.155秒。原始失败没有删除，详细结果与ZIP哈希见 `apple-13-summary.json`；原始完整构建/测试日志与原始日志ZIP在本目录，完整xcresult和视觉ZIP另保留在 `ios/build/apple-ci-38178699287/`。

缓存失败继续保留。实际探针：新实例 memory=0/disk=81920；保存响应 memory=4096/disk=81920；清理返回 memory=0/disk=36864，原请求已不能命中；此后8次等待仍 memory=0/disk=144016、不能命中，之后可重新缓存。原包字节与容量断言通过。单凭原请求不能命中不能推定全部占用是索引；生产不改成假0，不删框架私有数据库，不放宽原失败断言。Apple [currentDiskUsage](https://developer.apple.com/documentation/foundation/urlcache/currentdiskusage)描述磁盘占用，[removeAllCachedResponses](https://developer.apple.com/documentation/foundation/urlcache/removeallcachedresponses())描述删除缓存响应；当前还需归属与实际存储实证。

原始运行取得两设备完整视觉截图。对冻结安卓 screen-viewport-3 可准备32/64个对照；iPad应用窗口实际803.6727×1150.5818，与安卓834×1210不一致，32个尚不能比较。保留原图，不裁切应用或拉伸单轴来凑对照。完整清单见 `visual-comparison.json`，派生图在 `../2026-10-12-current-visual/ci13-comparison/`；逐组件检查仍未完成，不是视觉通过。

接续修复及边界：

- 阅读进度条外层在居中 stack 中高度为0，虽然画在屏幕上，却丢失触摸和无障碍。补真实固有高度，新增原生拇指命中/父层包含/无障碍回归；原有拖动与位置断言保留。
- 目录行补完整章节标签及选中语义，原有按章选择/末章状态断言保留。单击等双击识别失败的控制条切换增加有界同步，原隐藏/固定画布断言保留，是否关闭原问题仍待Apple。
- 书架锚点现在包含顶部部分可见的首本，恢复时仍限制偏移保证可点击；原先“验收漫画19”切换后丢失的断言不改。
- iPad窗口改由真实 UIWindowScene 创建，复用单场景环境/任务/界面，前后台回调接回下载、阅读和统计；保留动态尺寸支持，补完整iPad方向声明。原始缩放窗口是实证，场景迁移的实际效果仍需Apple截图验证。[Apple场景生命周期](https://developer.apple.com/documentation/uikit/transitioning-to-the-uikit-scene-based-life-cycle)供实现参照。
- Files辅助应用改显式、带类型的Info.plist；原版本记录有构建/安装，但目录提供器显示空。下一轮检查编译产物的共享/原位打开布尔值，再运行真实Files选择；源plist检查不能证明系统注册成功。

接续当前83个Swift文件两配置仅语法通过，shell语法与两个plist声明检查退出0；新增原生和当前UI尚未Apple运行。ComicCore未改，沿用 `a41b28a` 的895项/2个Apple PDF跳过/0失败完整结果，不能替代当前UIKit检查。

下一轮推送默认为 `recovery-regression`：SDK两配置、Apple全Core、全部24项原生，以及书架3/外部Files3/连续阅读10/下载生命周期2，共18项UI每设备。核心失败仍保留并使总体失败；局部范围永不生成IPA。后续用完整 full 范围执行76项UI/设备及全部视觉，不把18项结果当阶段通过。仍不对接真实站源，用户只负责最终总验收。
