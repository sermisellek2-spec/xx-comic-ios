# XX Comic iOS

原生 UIKit + ComicCore Swift Package，iOS16+，支持iPhone/iPad。当前Android冻结基线为2.0.40/340，提交 `696e80a44ab36b19de6f630565df32978e55a19e`。iOS checkout里的app/是旧Android副本，不能用作当前基线。

**当前功能/视觉/交互尚未完整对齐，非站源门槛未通过。** 具体缺口、已作本地修正和证据边界见 [PARITY.md](PARITY.md) 与 [当前差异核对](../docs/comparisons/2026-10-11-ios-android-current-assessment.md)。

当前源目录51个=22专用+29公共，默认启用50，duya默认关闭；baozimh/mhua5仅保留旧身份与离线兼容。数量/顺序/默认开关静态及核心通过，生产注册Apple测试待验收；真实网站验收最后进行。

新仓库 [xx-comic-ios](https://github.com/sermisellek2-spec/xx-comic-ios) 的CI38104946234、代码a5aeec9已成功并产出未签名IPA。原额度限制已解决；该旧包实际没有应用图标资源。当前图标/淘汰设置、搜索/下载/封面及本批视觉、缓存/配置/统计、书架/阅读/本地删除/Files目录改动没有对应Apple产物。只用该仓库；指定账号正常Git凭据与写入权限已核验，Apple自验待运行，阶段及总验收均未开放。

[分阶段方案](../docs/IOS_2_0_40_PHASED_DEVELOPMENT.md)、[本批阶段证据](../docs/ios-parity-2.0.40/review-evidence/2026-10-11-staged-development/README.md)。

## Windows核心与基线核验

从本checkout根目录执行：

```powershell
pwsh -NoProfile -File docs/ios-parity-2.0.40/verify-baseline.ps1
python tools/audit-ios-source-catalog.py --output docs/ios-parity-2.0.40/review-evidence/2026-10-11-staged-development/source-catalog-proof.json
$comicCorePath = (Resolve-Path ios/ComicCore).Path
docker run --rm --mount "type=bind,source=$comicCorePath,target=/work" -w /work swift:5.10-jammy swift test -j 2
```

当前核心全量838项执行、2项Apple PDF跳过、0失败；独立反馈状态6项历史通过；63个原生/测试Swift文件两配置仅语法通过。最新文件协调/私有暂存发布/离线图片读取接线和下载相关49项记录见[接续证据](../docs/ios-parity-2.0.40/review-evidence/2026-10-11-download-files/README.md)。Linux核心或独立状态测试、Swift语法解析不替代Apple SDK类型检查、UIKit、CoreML、图像/PDF、WebKit、Files、后台调度和iPad验收。

## macOS/私有CI

安装Xcode与XcodeGen，用 `xcrun simctl list devices available` 获取真实iPhone和iPad模拟器UDID，再从checkout根目录运行：

```sh
IOS_TEST_DESTINATION='platform=iOS Simulator,id=实际iPhoneUDID' \
IOS_IPAD_DESTINATION='platform=iOS Simulator,id=实际iPadUDID' \
bash ios/scripts/build.sh
```

当前脚本按序接受两个目的设备，原生测试失败不打包。成功的未签名产物位于 `ios/build/XXComic-unsigned.ipa`，安装需用户自己的SideStore等工具签名。新包需解包核对CFBundleIcons、Assets.car/AppIcon资源、版本、SHA-256，并实际验收主屏图标。

本批未发布，指定账号Git凭据与私有仓库写入权限已实际核验，正在准备Apple开发验证提交。唯一远端 `github` 的workflow支持手动触发及 `codex/ios-port` 推送触发，只有上传当前代码并完成必需检查后才能取得对应版本的新证据。

## 进度与历史

[requirements.csv](../docs/ios-parity-2.0.40/requirements.csv)、[STATUS.md](../docs/ios-parity-2.0.40/STATUS.md)、[NON_SOURCE_GATE.md](../docs/ios-parity-2.0.40/NON_SOURCE_GATE.md) 和 [differences.md](../docs/ios-parity-2.0.40/differences.md) 是当前口径。旧逐源报告、2.0.29脚本和全绿声明只供追溯，更新前README保留为 [historical-README.md](../docs/ios-parity-2.0.40/review-evidence/2026-10-11-current-comparison/historical-README.md)。
