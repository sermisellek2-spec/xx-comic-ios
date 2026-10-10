# Android2.0.40冻结参考

- 发布提交：`696e80a44ab36b19de6f630565df32978e55a19e`。
- 版本：2.0.40 / 340。
- 归档：`android-2.0.40-reference.zip`，共527个文件，约31.64MiB。
- SHA-256：`4a565a34f4f169f651c8e4222ea1a8fb3d5b0cd529de04e4322e53a0b72cf3bb`。
- `manifest.json`记录范围、起点版本和每个文件的SHA-256。

归档来自git archive，包含发布提交中已跟踪的app/src、app/build.gradle、根Gradle输入及wrapper；无本机build缓存、用户书库或Cookie。相关资源/模型/许可文件随app/src包含。参考编译产生的缓存放在解包副本，不修改冻结包。

**完整参考包和manifest放在iOS checkout：**
`F:/softForCode/codex-project/xx-comic/.worktrees/ios-port/docs/ios-parity-2.0.40/baseline/`。
外层Android目录仅镜像交接文本/manifest，没有重复存放31MiB包。跨机器接手请携带完整iOS checkout的本次资料。

校验命令（在iOS checkout根）：

```powershell
pwsh -NoProfile -File docs/ios-parity-2.0.40/verify-baseline.ps1
```

校验归档整体、文件集合和逐文件内容后，再解包到独立参考目录。不能使用iOS checkout旧app/或2.0.29的android-baseline脚本替代本包。解包目录不加入iOS编译输入。
