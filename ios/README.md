# XX Comic iOS

> 2026-10-10：当前目标已改为Android2.0.40完整复刻，按“全部非站源功能/视觉/交互自验通过，再逐一接真实站源”执行。以下2.0.29状态说明为历史；先读根AGENTS.md、[新执行方案](../docs/IOS_2_0_40_GEMINI_PLAN.md)和[当前追踪](../docs/ios-parity-2.0.40/STATUS.md)。历史“未实现/未经Xcode验证”不代表当前源码状态，须实际核对。

原生 iOS 移植进行中，Android 行为基准为 **2.0.29 / 229**。本目录不是完整可用的漫画客户端。

## 当前阶段

- 已建立 Swift 核心测试、UIKit 工程配置和手动 macOS 构建流程。
- 已接入13/18个安卓默认站源、书架/历史存储和在线阅读流程；逐站状态见 `PARITY.md`。
- 阅读器已编写条漫/单页、缩放、位置恢复、白边与墨水屏处理；UIKit尚未经过Xcode验证。
- 本地图片与图片文件夹已接入导入/书架/阅读，128MiB单图边界对齐安卓；其他文件格式/电子书/PDF、下载和完整视觉仍未完成。
- 具体实际验证结果见 `VALIDATION.md`；未取得 Xcode 输出前不能称为 iOS 构建通过。

## Windows + Docker 核心测试

在仓库根目录的 PowerShell 中执行：

```powershell
$comicCorePath = (Resolve-Path ios/ComicCore).Path
docker run --rm --mount "type=bind,source=$comicCorePath,target=/work" -w /work swift:5.10-jammy swift test
```

Docker 只验证平台无关逻辑，不运行 UIKit、iOS 模拟器或 IPA 构建。

## macOS 构建

安装 Xcode 和 XcodeGen 后，在仓库根目录执行：

```sh
bash ios/scripts/build.sh
```

需要执行 UI 测试时，通过 `xcrun simctl list devices available` 选择 iPhone 模拟器，然后指定：

```sh
IOS_TEST_DESTINATION='platform=iOS Simulator,id=设备UDID' bash ios/scripts/build.sh
```

输出 `ios/build/XXComic-unsigned.ipa`，尚未签名，不能点开直接安装；测试用户需使用自己的账号通过侧载工具签名。

## GitHub 免费账户与构建

1. 在 https://github.com/signup 注册免费个人账户。
2. 在 https://github.com/new 创建私有仓库，避免未经决定公开 Android 源码。
3. 将项目上传后，Actions → iOS manual build → Run workflow。

流程仅手动触发，使用标准 macOS 运行器，单次最多 30 分钟，工件保留 7 天。私有仓库仍消耗账户的 Actions 免费额度；不保证无限免费，不需要在此配置苹果账号密码或开发者证书。

目前工作区的远端是 Gitee，尚未连接 GitHub 或运行云端构建。

## 基准检查

```sh
node ios/scripts/android-baseline.mjs --check
```

`android-baseline.json` 只记录 Android 文件相对路径、哈希和版本，不包含用户设备数据或账号信息。检查失败时逐项评估 Android 变化，不直接覆盖基准。
