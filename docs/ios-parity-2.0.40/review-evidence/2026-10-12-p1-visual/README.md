# 当前P1视觉与用户闭环修复证据

更新：2026-10-12。当前候选父提交b9f368d，本地改动尚未通过Apple。仅指定sermisellek2-spec仓库做开发验收；未生成或发布IPA，不开放总验收/真实网站。

第九轮实际failure，见apple-9-summary.json与原始摘录：Debug/Release及Files辅助目标构建成功，AppleCore876/0失败/119.260秒；辅助应用安装报缺合法CFBundleVersion，Native/UI未执行，API产物为空。不能继承第八轮或说Files已通过。原始日志ZIP SHA保留，未修改原始包。

本地修改：书架一次续读与圆封面/历史布局、冻结网格密度；详情透明返回导航/封面/信息区/标签/目录卡片/底部动作；阅读设置全宽底部面板、图标卡片/整行开关/完整说明/拖动关闭、增强子项；删除当前设置没有的翻页方式入口并保留旧偏好兼容。两端同内容提供器首次初始化，重启不覆盖用户设置或阅读记录；固定共同排序时间。独立Files辅助目标补1.0/1版本及安装前核验，不进入产品scheme。

新行为用例：书架一次续读及返回；阅读模式/主题/开关重启；增强开关/模式/对照/回原图；两设备主屏图标/点击并留实际截图位置。主VisualMatrix严格neural断言保留，另外截原图/原图设置，并留实际元素几何/文案。上述Apple用例本批尚未运行。

native-syntax-candidate.log为当前候选76个源码两配置语法实际退出0，不是Apple类型或UIKit验收。Python AST、YAML及辅助目标版本/生产scheme隔离检查通过，git diff --check退出0。ComicCore生产和核心用例未改变，869执行/2个Apple PDF跳过/0失败的上批Linux全量仍有效，没有无理由重跑。

Android独立冻结输入527文件与原APK SHA再次核验。android-current-matrix早期横屏文件实际竖屏，保留为拒绝组；android-current-matrix-rotated为尺寸正确64图，但增强请求处于设备检测状态。android-golden-original以显式关闭增强且关闭对照重采；android-golden-current再按真实生产动作展开控件，并严格核对controlsVisible；真实图/manifest/设备及每图SHA保留。iOS当前共同原图金标/叠图/组件差分仍待完成，不能记视觉通过。

历史P1文字保存在historical-P1-before-current-visual.md，不作为当前结果。候选输入SHA记录另附；当前阶段仍未通过。
