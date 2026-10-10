# XX Comic iOS

> 2026-10-11：当前修复与交付状态以 [`REPAIR_DELIVERY_2026-10-11.md`](../docs/ios-parity-2.0.40/REPAIR_DELIVERY_2026-10-11.md) 为准。已修复阅读器任务生命周期、模型通道重排、换源取消入口、详情布局和 CI 失败门槛；运行验收 `38069643191`（代码 `7162e15`）核心 776 项、双设备各 28 项通过；最后 Release 隔离修复为 `8bf6bfa`，新 CI `38071472048` 因账号账单/消费上限未启动，暂无新 IPA。下方 2026-10-10 的范围和站源结果作为历史记录保留，不代表本轮重测，也不能证明 Android 同内容视觉 1:1 全部通过。

原生 iOS 客户端（UIKit + `ComicCore` Swift Package，最低支持 iOS 16.0，适配 iPhone 与 iPad 横竖屏及浅/深色主题），Android 对照冻结基线为 **2.0.40 / versionCode 340**（commit `696e80a44ab36b19de6f630565df32978e55a19e`）。

## 历史实现范围（2026-10-10）

- **非站源功能、视觉与交互（P0~P5）**：已完成设计 Token（`Palette`）、动态列数（`CoverLayoutHelper`）、原版蕾姆素材与矢量图标、在线/本地双书架与分组管理、追更红点、多源并发搜索与严格同名置顶/防抢页、双段分类筛选抽屉、书架/详情/阅读器三处无损换源、条漫/普通单页/日漫翻页与卷轴防误触、进度预览气泡、目录双段抽屉與 44pt 独立快滚导轨、本地 2 倍 AI 超分/普通增强与原图长按对照、本地全格式（图片/文件夹/ZIP/CBZ/EPUB/PDF/Kindle MOBI/AZW）导入与分卷/墓碑恢复、文件夹安全书签直接索引与前后台自动同步、图片与大文件断点续传下载及离线修复、设置/缓存/脱敏日志/版本更新/可选匿名统计。详见 [`NON_SOURCE_GATE.md`](../docs/ios-parity-2.0.40/NON_SOURCE_GATE.md)。
- **真实站源全目录（P6）**：已按 2.0.40 规范顺序完整接入 **22 个专用站源 + 29 个公共配置驱动站源（共 51 个活跃站源）** 及 **2 个退役站源（`baozimh`、`manhuawu` 仅保留历史与离线阅读）**；支持 `xx-comic.sources` v2 动态 `routes`/`filters`/`baseUrl`/`referer`/`custom` 导入导出与消费。48 个活跃源通过实网全链路验证，1 个源（`duya`）按原版默认关闭，2 个源（`manhuazhan` CF 521、`xiuxiu` HTTP 403）受外部源站故障阻塞。逐源报告见 [`docs/ios-parity-2.0.40/sources/`](../docs/ios-parity-2.0.40/sources/)。
- **验证状态与平台边界**：Windows + Docker (`swift:5.10-jammy`) 下 `ComicCore` **760 项核心测试全部通过**（2 项 Apple PDFKit 条件测试在 Linux 跳过，0 失败），UIKit 与 UITests 全文件 Swift 语法前端解析 0 错误，527 个 Android 2.0.40 基准文件 SHA-256 校验通过。因当前开发主机为 Windows，macOS Xcode 原生编译、iOS 模拟器 UI 自动化与未签名 IPA 打包需在 macOS 或 GitHub Actions (`ios.yml`) 运行后产出。

## Windows + Docker 核心测试与基线校验

在仓库根目录的 PowerShell 中执行：

```powershell
pwsh -NoProfile -File docs/ios-parity-2.0.40/verify-baseline.ps1
$comicCorePath = (Resolve-Path ios/ComicCore).Path
docker run --rm --mount "type=bind,source=$comicCorePath,target=/work" -w /work swift:5.10-jammy swift test -j 2
```

Docker 验证跨平台核心逻辑、持久化、文件解析与网络协议，不替代 macOS Xcode 编译、UIKit 模拟器运行或 IPA 打包。

## macOS 构建

安装 Xcode 和 XcodeGen 后，用 `xcrun simctl list devices available` 选择实际模拟器 UDID。在仓库根目录执行双设备验收：

```sh
IOS_TEST_DESTINATION='platform=iOS Simulator,id=实际iPhoneUDID' \
IOS_IPAD_DESTINATION='platform=iOS Simulator,id=实际iPadUDID' \
bash ios/scripts/build.sh
```

脚本必须收到实际目的设备；原生测试失败则退出，不执行 Release 打包。CI 必须找到 iPhone 和 iPad。成功输出 `ios/build/XXComic-unsigned.ipa`，尚未签名，需通过用户自己的 SideStore 等侧载工具签名安装。

## 私有 CI 构建

已有 GitHub 私有远端 `github`，workflow `ios.yml` 支持手动触发及 `codex/ios-port` 推送触发。使用 macOS-14 / Xcode，单次上限 60 分钟，逐个执行双设备测试，工件保留 7 天。构建不需要 Apple 账号或签名证书；用户安装时由 SideStore 签名。

## 基准检查

- **Android 2.0.40 / 340 冻结基线校验（当前目标）**：
  ```powershell
  pwsh -NoProfile -File docs/ios-parity-2.0.40/verify-baseline.ps1
  ```
  校验 `docs/ios-parity-2.0.40/baseline/android-2.0.40-reference.zip` 与 `manifest.json`（发布提交 `696e80a44ab36b19de6f630565df32978e55a19e`，527 个文件逐一 SHA-256 核对）。
- **历史 2.0.29 工作区副本检查（仅历史参考）**：
  ```sh
  node ios/scripts/android-baseline.mjs --check
  ```
  `ios/android-baseline.json` 对应早期 2.0.29 副本，不用于当前 2.0.40 验收。
