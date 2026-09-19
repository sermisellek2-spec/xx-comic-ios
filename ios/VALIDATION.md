# 首阶段验证记录

日期：2026-09-19。工作区 `.worktrees/ios-port`，分支 `codex/ios-port`。

## 实际执行

| 检查 | 结果 | 能证明的范围 |
| --- | --- | --- |
| Docker Swift 5.10 `swift test` | 15 项通过，0 失败 | 核心 Swift 在 Linux 编译、阅读位置/方向/历史、精确搜索与异步隔离、设置持久化 |
| `swiftc -frontend -parse XXComic/*.swift XXComicUITests/*.swift` | 通过 | Swift 语法，不包含 UIKit 类型检查和链接 |
| `bash -n ios/scripts/build.sh` | 通过 | shell 语法，不代表 Xcode 构建运行成功 |
| `node ios/scripts/android-baseline.mjs --check` | 254 个文件一致 | Android 基准与独立工作区一致 |
| 独立代码审查 | 修复重复执行 UI 测试结果目录冲突 | 首阶段代码检查，未替代设备验证 |

首次测试在核心 target 为空时失败，属于缺失实现导致的构建失败，不将其称为所有行为测试都完成了断言级 red-green。后续翻页数值映射、旧按钮模式回退测试均实际出现断言失败，修复后通过。

## 尚未执行

- XcodeGen 工程生成、Xcode 模拟器/设备编译、UIKit 类型检查。
- iOS 模拟器 UI 测试；已编写导航与设置重启后保存测试，但未运行。
- IPA 签名、用户 iPhone 安装、视觉/手势/性能验收。
- GitHub Actions 云端运行；当前只有 Gitee 远端，用户正在准备 GitHub 账户。

## 全量移植状态

- 已实现并测试：阅读位置数学规则、物理方向、历史安全提示、严格标题置顶、站源顺序、搜索代次隔离与选择、阅读设置存取。
- 已编写但未经过 iOS 编译：应用入口、书架/发现/设置开发预览、阅读设置界面、云端构建配置。
- 未接入：实际在线站源及验证会话、漫画阅读器、收藏/历史页面、本地导入/电子书/PDF、下载和恢复、全局按时间主题、原版完整视觉及素材。

当前不能称为 1:1 复刻完成，也没有可供用户安装的已验证 IPA。
