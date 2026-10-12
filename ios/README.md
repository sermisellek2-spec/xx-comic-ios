# XX Comic iOS

最新接续（2026-10-12）：第19轮两SDK及25原生/设备通过，但整体失败；第20轮日漫两SDK通过，27原生/设备1真实页排列失败、16阅读UI/设备2日漫失败。当前显式页帧/查询、站源触摸滚动/顶部宽度、Files侧栏取消及样式修复，90文件仅语法通过，尚待Apple复验。Core266输入与Linux922项/2个Apple PDF跳过/0失败不变；缓存Mac929项仍1失败。当前以STATUS为准，下列早期数字和“正在运行”是对应输入历史，不继承为当前通过。

当前状态以[STATUS](../docs/ios-parity-2.0.40/STATUS.md)为准：第17轮SDK及两设备原生通过但Core/UI仍失败；第18轮编译失败已修，第19轮正在复验。最新本地保留卷轴/普通/日漫三模式，删除旧左右手设置；完整Linux922项/2个Apple PDF跳过/0失败，Apple/UI尚待当前输入复验。非站源门槛未过，不生成IPA；下方旧版本数字是历史记录。

原生 UIKit + ComicCore Swift Package，iOS16+，支持iPhone/iPad。当前Android冻结基线为2.0.40/340，提交 `696e80a44ab36b19de6f630565df32978e55a19e`。iOS checkout里的app/是旧Android副本，不能用作当前基线。

**当前功能/视觉/交互尚未完整对齐，非站源门槛未通过。** 具体缺口、已作本地修正和证据边界见 [PARITY.md](PARITY.md) 与 [当前差异核对](../docs/comparisons/2026-10-11-ios-android-current-assessment.md)。

当前源目录51个=22专用+29公共，默认启用50，duya默认关闭；baozimh/mhua5仅保留旧身份与离线兼容。数量/顺序/默认开关静态及核心通过，生产注册两设备原生测试通过，完整目录管理UI待验收；真实网站验收最后进行。

新仓库 [xx-comic-ios](https://github.com/sermisellek2-spec/xx-comic-ios) 的CI38104946234、代码a5aeec9已成功并产出未签名IPA。原额度限制已解决；该旧包实际没有应用图标资源。当前图标/淘汰设置、搜索/下载/封面及本批视觉、缓存/配置/统计、书架/阅读/本地删除/Files目录改动没有对应Apple产物。只用该仓库；指定账号正常Git凭据与写入权限已核验，9b1d4a2两配置SDK、核心847及两设备原生各19通过，完整UI仍失败；当前标准导航/批量恢复等修复待复验，完整阶段及总验收未开放。

[分阶段方案](../docs/IOS_2_0_40_PHASED_DEVELOPMENT.md)、[本批阶段证据](../docs/ios-parity-2.0.40/review-evidence/2026-10-11-staged-development/README.md)。

## Windows核心与基线核验

从本checkout根目录执行：

```powershell
pwsh -NoProfile -File docs/ios-parity-2.0.40/verify-baseline.ps1
python tools/audit-ios-source-catalog.py --output docs/ios-parity-2.0.40/review-evidence/2026-10-11-staged-development/source-catalog-proof.json
$comicCorePath = (Resolve-Path ios/ComicCore).Path
docker run --rm --mount "type=bind,source=$comicCorePath,target=/work" -w /work swift:5.10-jammy swift test -j 2
```

当前Linux核心全量846项执行、2项Apple PDF跳过、0失败；66个原生/测试Swift文件两配置仅语法通过。最新恢复/同步修复见[接续恢复证据](../docs/ios-parity-2.0.40/review-evidence/2026-10-11-import-recovery/README.md)。最新文件协调/私有暂存发布/离线图片读取接线和下载相关49项记录见[接续证据](../docs/ios-parity-2.0.40/review-evidence/2026-10-11-download-files/README.md)。Linux核心或独立状态测试、Swift语法解析不替代Apple SDK类型检查、UIKit、CoreML、图像/PDF、WebKit、Files、后台调度和iPad验收。

## macOS/指定仓库CI

安装Xcode与XcodeGen，用 `xcrun simctl list devices available` 获取真实iPhone和iPad模拟器UDID，再从checkout根目录运行：

```sh
IOS_TEST_DESTINATION='platform=iOS Simulator,id=实际iPhoneUDID' \
IOS_IPAD_DESTINATION='platform=iOS Simulator,id=实际iPadUDID' \
bash ios/scripts/build.sh
```

当前脚本按序接受两个目的设备，原生测试失败不打包。成功的未签名产物位于 `ios/build/XXComic-unsigned.ipa`，安装需用户自己的SideStore等工具签名。新包需解包核对CFBundleIcons、Assets.car/AppIcon资源、版本、SHA-256，并实际验收主屏图标。

本批未发布，指定账号Git凭据及仓库写入权限已实际核验，正在准备Apple开发验证提交。唯一远端 `github` 的workflow支持手动触发及 `codex/ios-port` 推送触发，只有上传当前代码并完成必需检查后才能取得对应版本的新证据。

## 进度与历史

[requirements.csv](../docs/ios-parity-2.0.40/requirements.csv)、[STATUS.md](../docs/ios-parity-2.0.40/STATUS.md)、[NON_SOURCE_GATE.md](../docs/ios-parity-2.0.40/NON_SOURCE_GATE.md) 和 [differences.md](../docs/ios-parity-2.0.40/differences.md) 是当前口径。旧逐源报告、2.0.29脚本和全绿声明只供追溯，更新前README保留为 [historical-README.md](../docs/ios-parity-2.0.40/review-evidence/2026-10-11-current-comparison/historical-README.md)。

当前未提交候选补直接索引/重新授权/稳定页与末页续读、旧复制记录迁移及自动同步生命周期；Linux最终全量858项/2个Apple PDF跳过/0失败，68源码两配置仅语法通过，候选Apple未运行。第七轮e2f53b5正在完整自验；D44旧孤儿恢复持久归属、真实外部Files/视觉/性能仍未完成，非站源门槛未通过。
