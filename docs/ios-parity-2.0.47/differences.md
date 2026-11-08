# iOS 2.0.47 平台差异与设计确认台账

本文件记录 Android `2.0.47` (`versionCode 347`) 与 iOS `2.0.47` (`CURRENT_PROJECT_VERSION 347`) 之间经用户确认或由系统机制决定的合法平台差异。未列入本台账的功能均按同用户结果在 iOS 完整实现。

## 1. 经用户明确确认的设计决策（2026-11-08）

| 编号 | 对应需求 | 差异说明 | 用户结果与替代保障 |
| --- | --- | --- | --- |
| DIFF-2047-01 | `N2` / `D-A6` 音量键翻页 | **iOS 不实现音量键翻页**。iOS 无公开物理音量键拦截 API，强行 KVO `AVAudioSession.outputVolume` 并重置 `MPVolumeView` 会造成系统音量 HUD 闪动、后台音频打断及误触风险。 | 保留单页点击区域翻页、横滑翻页、卷轴上下滑动及底栏上下章切换。 |
| DIFF-2047-02 | `D-B1` / `D-B2` / `D-B5` / `D-B6` / `D-B7` 居中弹窗 | **保留 iOS 系统 `UIAlertController`**。系统原生弹窗已天然具备左取消右确认、`.destructive` 危险红、首帧稳定、超长消息自动滚动与输入框自动弹键盘能力。 | 顶部/底部轻量操作反馈统一收拢至自定义窗口级 Rem 提示胶丸（`V3` / `D-B3`），按成功/警告/异常匹配语义插画。 |
| DIFF-2047-03 | `B11` / `B12` / `D-A7(外链)` / `D-C4(文字设置)` | **不包含文字型 EPUB / MOBI 电子书阅读器**。沿用 `2.0.40` 差异台账 `D105` / `D112`（2026-10-13 用户指令移除文字阅读排版）。 | 纯图片漫画 EPUB / Kindle 保持后台线程解码、进度记忆与失败重试。 |

## 2. 系统机制等价实现差异

| 编号 | 对应需求 | Android 机制 | iOS 等价机制 |
| --- | --- | --- | --- |
| DIFF-2047-04 | `N1` 屏幕常亮 | `WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON` + 无操作超时清理 | `UIApplication.shared.isIdleTimerDisabled` + 阅读器内触摸刷新计时器；退出阅读器、进入后台或超时后立即恢复 `false`。 |
| DIFF-2047-05 | `N3` 窗口亮度与超暗遮罩 | `WindowManager.LayoutParams.screenBrightness` + 暗色遮罩 View | 进入阅读器记录系统 `UIScreen.main.brightness`，自定义亮度时实时调节并在退出/失活/进后台时恢复原值；低于硬件背光下限时叠加 `isUserInteractionEnabled = false` 的暗色护眼遮罩层。 |
| DIFF-2047-06 | `D-A2` / `D-A3` 导入进度与外部目录重授权 | 模态进度弹窗防误触取消；SAF 权限失效单例弹窗 | iOS 采用书架顶部非模态常驻导入进度条（天然支持边导入边浏览、不因点空白误取消）；外部 Files 书签失效在本地存储管理行内展示明确重授权按钮，不在阅读器并发叠弹窗。 |
| DIFF-2047-07 | `P43-UPDATE` 应用内更新 | APK 下载优先走 CDN 回退源站并调起安装 | iOS 不支持应用内直接静默/调起未签名 IPA 自升级；设置页检查更新读取远端清单并引导复制/打开官网最新 IPA 下载与重签指引。 |
| DIFF-2047-08 | `D-C8` 下载选章抽屉关闭 | Android 移除底部独立关闭按钮，统一由顶栏/下滑关闭 | iOS `.pageSheet` 在 iPad 无系统下拉关闭手势且需兼顾无障碍关闭动作，保留 `download.close` 关闭入口以保证 iPhone/iPad 一致可关闭。 |
